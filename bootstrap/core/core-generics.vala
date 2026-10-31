// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
public class CoreGenericCapabilityRequirement : CoreNode {
	private WeakRef parameter;
	public CoreTypeParameter? type_parameter { owned get { return (CoreTypeParameter?) parameter.get (); } }
	public GenericCapabilityIdentity capability { get; private set; }
	internal CoreGenericCapabilityRequirement (SourceSpan span, CoreTypeParameter parameter, GenericCapabilityIdentity capability) {
		base (span);
		this.parameter = WeakRef (parameter);
		this.capability = capability;
	}
}

public class CoreGenericCapabilityOperation : CoreValue {
	public GenericOperationKind operator_kind { get; private set; }
	public CoreTypeParameter type_parameter { get; private set; }
	public GenericCapabilityIdentity capability { get; private set; }
	public CoreValue left { get; private set; }
	public CoreValue? right { get; private set; }
	internal CoreGenericCapabilityOperation (SourceSpan span, SemanticType result, GenericOperationKind kind, CoreTypeParameter parameter, GenericCapabilityIdentity capability, CoreValue left, CoreValue? right = null) {
		base (span, result);
		this.operator_kind = kind;
		this.type_parameter = parameter;
		this.capability = capability;
		this.left = left;
		this.right = right;
	}
}

// Select existing concrete operations; their accepted scalar/BIT semantics own
// overflow, IEEE behavior, signedness and shift guards. No source rechecking.
public class CoreGenericOperationResolver : Object {
	public static CoreValue concretize(CoreGenericCapabilityOperation operation, SemanticType concrete, SemanticType result, CoreValue left, CoreValue? right) throws CoreError {
		var kind = operation.operator_kind;
		if (!kind.valid () || kind.capability () != operation.capability || !GenericArgumentTypes.supports (concrete) || !GenericCapabilityAuthority.satisfies (concrete, operation.capability) || left.semantic_type != concrete) {
			throw new CoreError.INVALID_IR ("invalid concrete capability operation substitution");
		}
		if (kind == GenericOperationKind.BIT_NOT) {
			if (right != null || !PrefixOperator.BIT_NOT.accepts (concrete, result)) {
				throw new CoreError.INVALID_IR ("invalid concrete Bitwise complement shape");
			}
			return new CorePrefixValue (operation.span, result, PrefixOperator.BIT_NOT, left);
		}
		if (right == null) {
			throw new CoreError.INVALID_IR ("missing concrete capability RHS");
		}
		if (kind.is_shift ()) {
			var shift = kind == GenericOperationKind.SHIFT_LEFT ? IntegerShiftKind.LEFT : IntegerShiftKind.RIGHT;
			if (!shift.accepts (concrete, right.semantic_type, result)) {
				throw new CoreError.INVALID_IR ("invalid concrete Shift shape");
			}
			return new CoreIntegerShiftValue (operation.span, result, shift, left, right);
		}
		var binary = kind.binary_operator ();
		if (!binary.accepts (concrete, right.semantic_type, result)) {
			throw new CoreError.INVALID_IR ("invalid concrete capability binary shape");
		}
		return new CoreBinaryValue (operation.span, result, binary, left, right);
	}
}

public class CoreTypeParameter : CoreNode {
	public GenericTransportMode transport_mode { get { return semantic_type.transport_mode; } }
	public GenericArray<CoreGenericCapabilityRequirement> capability_requirements { get; private set; default = new GenericArray<CoreGenericCapabilityRequirement> (); }
	public TypeParameterType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	internal CoreTypeParameter (SourceSpan span, TypeParameterType type, int ordinal) {
		base (span);
		this.semantic_type = type;
		this.ordinal = ordinal;
	}
}

// Stable origin identity has no body or upstream backlink. Concrete instances
// retain this token even after the parameterized definition graph is released.
public class CoreGenericIdentity : CoreNode {
	public int ordinal { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	internal CoreGenericIdentity (SourceSpan span, string name, int ordinal) {
		base (span);
		this.identifier = name;
		this.ordinal = ordinal;
	}
}

public class CoreGenericFunction : CoreFunction {
	public GenericSliceObligations element_obligations { get; private set; default = new GenericSliceObligations (); }
	public GenericArray<CoreGenericCapabilityRequirement> capability_requirements { get; private set; default = new GenericArray<CoreGenericCapabilityRequirement> (); }
	public CoreGenericIdentity identity { get; private set; }
	public GenericArray<CoreTypeParameter> type_parameters { get; private set; }
	internal CoreGenericFunction (SourceSpan span, SourceSpan name_span, string name, SemanticType result, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body, CoreCleanupContract? cleanup, GenericArray<CoreTypeParameter> type_parameters, int ordinal) {
		base (span, name_span, name, result, parameters, locals, body, cleanup);
		this.type_parameters = type_parameters;
		this.identity = new CoreGenericIdentity (span, name, ordinal);
	}
	public void verify_capability_arguments(GenericArray<SemanticType> arguments, CopyabilityFields? fields = null, CopyabilityPremise? premise = null, CopyabilityPremise? element_premise = null) throws CoreError {
		if (arguments.length != type_parameters.length) {
			throw new CoreError.INVALID_IR ("generic type-argument arity mismatch");
		}
		for (int i = 0; i < arguments.length; i++) {
			if (!GenericArgumentTypes.accepts (type_parameters[i].semantic_type, arguments[i], fields, premise)) {
				throw new CoreError.INVALID_IR ("type argument does not satisfy the exact generic transport mode%s", type_parameters[i].transport_mode == GenericTransportMode.PLAIN_COPY ? "; plain-copy proof requires complete fields within type-application depth 256" : "");
			}
		}
		for (int i = 0; i < arguments.length; i++) {
			if (element_obligations.contains (type_parameters[i].semantic_type) && !GenericSliceObligations.accepts (arguments[i], fields, element_premise)) {
				throw new CoreError.INVALID_IR ("type argument does not satisfy the signature-derived mutable slice element-storage obligation");
			}
		}
		foreach (var requirement in capability_requirements) {
			var parameter = requirement.type_parameter;
			if (parameter == null || parameter.ordinal < 0 || parameter.ordinal >= arguments.length || type_parameters[parameter.ordinal] != parameter || !GenericCapabilityAuthority.satisfies (arguments[parameter.ordinal], requirement.capability)) {
				throw new CoreError.INVALID_IR ("unsatisfied exact generic capability requirement");
			}
		}
	}
	public TypeSubstitution substitution(GenericArray<SemanticType> arguments) throws CoreError {
		if (arguments.length != type_parameters.length) {
			throw new CoreError.INVALID_IR ("generic type-argument arity mismatch");
		}
		var result = new TypeSubstitution ();
		for (int i = 0; i < arguments.length; i++) {
			result.bind (type_parameters[i].semantic_type, arguments[i]);
		}
		return result;
	}
}

public class CoreGenericCall : CoreCallValue {
	public GenericArray<CoreGenericCapabilityRequirement> target_requirements { get; private set; }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	internal CoreGenericCall (SourceSpan span, SemanticType result, CoreGenericFunction target, GenericArray<SemanticType> type_arguments, GenericArray<CoreValue> arguments) {
		base (span, result, target, arguments);
		this.type_arguments = type_arguments;
		this.target_requirements = new GenericArray<CoreGenericCapabilityRequirement> ();
		foreach (var requirement in target.capability_requirements) {
			this.target_requirements.add (requirement);
		}
	}
}

public class CoreGenericCallStatement : CoreCallStatement {
	public GenericArray<CoreGenericCapabilityRequirement> target_requirements { get; private set; }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	internal CoreGenericCallStatement (SourceSpan span, CoreGenericFunction target, GenericArray<SemanticType> type_arguments, GenericArray<CoreValue> arguments) {
		base (span, target, arguments);
		this.type_arguments = type_arguments;
		this.target_requirements = new GenericArray<CoreGenericCapabilityRequirement> ();
		foreach (var requirement in target.capability_requirements) {
			this.target_requirements.add (requirement);
		}
	}
}

internal class CoreResultOriginRequest : Object {
	internal CoreFunction function;
	internal TypeArgumentVector arguments;
	internal TypeSubstitution substitution;
	internal GenericResultOrigins equation = new GenericResultOrigins ();
	internal bool solved;
	internal CoreResultOriginRequest (CoreFunction function, GenericArray<SemanticType> arguments) throws CoreError {
		this.function = function;
		this.arguments = new TypeArgumentVector (arguments);
		this.substitution = (function is CoreGenericFunction) ? ((CoreGenericFunction) function).substitution (arguments) : new TypeSubstitution ();
	}
}

// A member header carries nominal binding authority, not an implementation.
// Project its actual closed target before choosing result storage.
internal class CoreResultOriginProjection : Object {
	private CoreProgram program;
	private GenericArray<CoreResultOriginRequest> requests = new GenericArray<CoreResultOriginRequest> ();
	private HashTable<GenericRequestKey, CoreResultOriginRequest> registry = new HashTable<GenericRequestKey, CoreResultOriginRequest> (GenericRequestKey.hash, GenericRequestKey.equal);
	internal CoreResultOriginProjection (CoreProgram program) {
		this.program = program;
	}

	internal CoreResultOriginRequest request(CoreFunction function, GenericArray<SemanticType> arguments) throws CoreError {
		var vector = new TypeArgumentVector (arguments);
		var key = new GenericRequestKey (function, vector);
		var prior = registry.lookup (key);
		if (prior != null) {
			return prior;
		}
		if (requests.length >= GenericResourceLimits.CLOSED_INSTANCES) {
			throw new CoreError.INVALID_IR ("result-origin projection exceeded the closed-instance budget");
		}
		foreach (var argument in arguments) {
			if (!GenericResourceLimits.admits_type (argument)) {
				throw new CoreError.INVALID_IR ("result-origin projection exceeded the type-depth budget");
			}
		}
		var result = new CoreResultOriginRequest (function, arguments);
		requests.add (result);
		registry.insert (key, result);
		return result;
	}

	internal CoreFunction? member(CoreFunction original, TypeSubstitution substitution) throws CoreError {
		var receiver = original.implicit_receiver;
		if (receiver == null) {
			return original;
		}
		CoreFunction? result = null;
		foreach (var owner in program.native_instances ()) {
			if (!substitution.matches (receiver.contract.instance_type, owner.semantic_type)) {
				continue;
			}
			if (original is CoreMethod) {
				var method = (CoreMethod) original;
				foreach (var candidate in owner.methods) {
					var binding = method.generic_method_instance;
					var key = candidate.generic_method_instance;
					bool matches;
					if (binding == null) {
						matches = key == null && candidate.member_ordinal == method.member_ordinal && candidate.name == method.name;
					} else {
						matches = key != null && key.member == binding.member && key.arguments.length == binding.arguments.length;
						for (int a = 0; matches && a < binding.arguments.length; a++) {
							matches = substitution.matches (binding.arguments.at (a), key.arguments.at (a));
						}
					}
					if (!matches) {
						continue;
					}
					if (result != null && result != candidate) {
						throw new CoreError.INVALID_IR ("result-origin projection requires one exact closed member target");
					}
					result = candidate;
				}
			} else if (original is CorePropertyAccessor) {
				var property = ((CorePropertyAccessor) original).property_member;
				foreach (var candidate in owner.properties) {
					if (candidate.ordinal != property.ordinal || candidate.name != property.name) {
						continue;
					}
					CoreFunction? target = (original is CorePropertyGetter) ? (CoreFunction) candidate.getter : candidate.setter;
					if (result != null && result != target) {
						throw new CoreError.INVALID_IR ("result-origin projection requires one exact closed property target");
					}
					result = target;
				}
			}
		}
		return result;
	}

	internal GenericResultOrigins project(CoreGenericFunction function, GenericArray<SemanticType> arguments) throws CoreError {
		var root = request (function, arguments);
		if (root.solved) {
			return root.equation;
		}
		bool changed = false;
		do {
			changed = false;
			uint before = requests.length;
			for (int i = 0; i < requests.length; i++) {
				var current = requests[i];
				if (current.solved) {
					continue;
				}
				var equation = CoreGenericResultOrigins.projected (current.function, this, current.substitution);
				if (!current.equation.same (equation)) {
					current.equation = equation;
					changed = true;
				}
			}
			changed |= requests.length != before;
		} while (changed);
		foreach (var current in requests) {
			current.solved = (current.equation.domains & GenericResultOrigins.UNKNOWN) == 0;
		}
		return root.equation;
	}
}

// Reconstruct the result equation from this stage's own definitions. Calls
// compose equations by parameter ordinal; signatures of owned code values
// establish heap-origin Class results independently of all actual inputs.
internal class CoreGenericResultOrigins : Object {
	private CoreFunction function;
	private HashTable<CoreGenericFunction, GenericResultOrigins>? equations;
	private HashTable<CoreFunction, GenericResultOrigins>? concrete_equations;
	private CoreResultOriginProjection? projection;
	private TypeSubstitution? substitution;
	private HashTable<CoreOwnedLocal, GenericResultOrigins> locals = new HashTable<CoreOwnedLocal, GenericResultOrigins> (direct_hash, direct_equal);
	private HashTable<CoreBlock, bool> visited = new HashTable<CoreBlock, bool> (direct_hash, direct_equal);
	private GenericResultOrigins result = new GenericResultOrigins ();

	private CoreGenericResultOrigins (CoreFunction function, HashTable<CoreGenericFunction, GenericResultOrigins>? equations, CoreResultOriginProjection? projection = null, TypeSubstitution? substitution = null, HashTable<CoreFunction, GenericResultOrigins>? concrete_equations = null) {
		this.projection = projection;
		this.concrete_equations = concrete_equations;
		this.substitution = substitution;
		this.function = function;
		this.equations = equations;
	}
	private GenericResultOrigins owner(CoreOwnedLocal owned) throws CoreError {
		if (!function.owned_locals.find (owned)) {
			throw new CoreError.INVALID_IR ("owned T result analysis requires incoming owner provenance or a local owned by the exact function");
		}
		var prior = locals.lookup (owned);
		if (prior != null) {
			return prior;
		}
		var parameter = owned.place.incoming_parameter;
		if (parameter != null && parameter.heap_object) {
			return new GenericResultOrigins (GenericResultOrigins.HEAP);
		}
		return parameter == null ? new GenericResultOrigins (owned.cleanup.is_heap_object ? GenericResultOrigins.HEAP : GenericResultOrigins.CALLER)
		        : new GenericResultOrigins (0, new int[] { parameter.ordinal });
	}
	private GenericResultOrigins value(CoreValue? expression) throws CoreError {
		if (expression == null || expression is CoreNullPointerValue) {
			return new GenericResultOrigins ();
		}
		var argument = expression as CoreOwnedArgumentValue;
		if (argument != null) {
			return argument.source == null ? value(argument.producer) : owner (argument.source);
		}
		var invocation = expression as CoreInvocation;
		if (invocation != null && invocation.result_cleanup () != null) {
			return new GenericResultOrigins (GenericResultOrigins.HEAP);
		}
		var call = expression as CoreCallValue;
		if (call != null) {
			var generic = call.target as CoreGenericFunction;
			if (generic != null && (generic.return_type is TypeParameterType || generic.return_type is ClassType)) {
				GenericResultOrigins? equation;
				if (projection != null && call is CoreGenericCall) {
					equation = projection.request (generic, substitution.apply_arguments (((CoreGenericCall) call).type_arguments)).equation;
				} else {
					equation = equations == null ? null : equations.lookup (generic);
				}
				if (equation == null) {
					return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
				}
				var arguments = new GenericArray<GenericResultOrigins> ();
				foreach (var operand in call.arguments) {
					arguments.add (value (operand));
				}
				return equation.compose (arguments);
			}
			var target = projection == null ? call.target : projection.member (call.target, substitution);
			if (projection == null && target != null && target.implicit_receiver != null) {
				var method = target as CoreMethod;
				if (target.implicit_receiver.contract.instance_type.is_parameterized () || method != null && method.generic_method_instance != null && !method.generic_method_instance.arguments.closed ()) {
					return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
				}
			}
			if (target != null && target.return_type is ClassType && target.owned_cleanup != null) {
				if (target.dispatch_kind != ClassDispatchKind.DIRECT) {
					return new GenericResultOrigins (target.heap_result ? GenericResultOrigins.HEAP : GenericResultOrigins.CALLER);
				}
				var equation = projection != null && target.native_declaration == null
				        ? projection.request(target, new GenericArray<SemanticType> ()).equation
				        : concrete_equations == null ? null : concrete_equations.lookup (target);
				if (equation != null) {
					var arguments = new GenericArray<GenericResultOrigins> ();
					foreach (var operand in call.arguments) {
						arguments.add (value (operand));
					}
					return equation.compose (arguments);
				}
				return new GenericResultOrigins (target.heap_result ? GenericResultOrigins.HEAP : GenericResultOrigins.CALLER);
			}
		}
		if (expression is CoreOwnedObjectResultConstruction) {
			return new GenericResultOrigins (GenericResultOrigins.CALLER);
		}
		return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
	}
	private void block(CoreBlock body) throws CoreError {
		if (visited.contains (body)) {
			return;
		}
		visited.insert (body, true);
		foreach (var statement in body.statements) {
			if (statement is CoreOwnershipReturn) {
				var returned = (CoreOwnershipReturn) statement;
				result = result.union (returned.source == null ? value (returned.producer) : owner (returned.source));
			} else if (statement is CoreOwnershipTransfer) {
				var transfer = (CoreOwnershipTransfer) statement;
				var prior = locals.lookup (transfer.destination) ?? new GenericResultOrigins ();
				locals.insert (transfer.destination, prior.union (owner (transfer.source)));
			} else if (statement is CoreInitialize) {
				var initialization = (CoreInitialize) statement;
				if (!(statement is CoreAcquireParameter) && initialization.acquisition != null) {
					locals.insert (initialization.acquisition, value (initialization.value));
				}
			} else if (statement is CoreScope) {
				block (((CoreScope) statement).body);
			} else if (statement is CoreIf) {
				var branch = (CoreIf) statement;
				var constant = branch.condition as CoreBooleanValue;
				if (constant == null || constant.literal == BooleanLiteral.TRUE) {
					block (branch.then_block);
				}
				if ((constant == null || constant.literal == BooleanLiteral.FALSE) && branch.else_block != null) {
					block (branch.else_block);
				}
			} else if (statement is CoreWhile) {
				var loop = (CoreWhile) statement;
				var constant = loop.condition as CoreBooleanValue;
				if (constant == null || constant.literal == BooleanLiteral.TRUE) {
					block (loop.body);
					if (loop.step != null) {
						block (loop.step);
					}
				}
			} else if (statement is CoreTry) {
				var guarded = (CoreTry) statement;
				block (guarded.body);
				foreach (var caught in guarded.catches) {
					block (caught.body);
				}
			} else if (statement is CoreEnumMatch) {
				foreach (var arm in ((CoreEnumMatch) statement).arms) {
					block (arm.body);
				}
			}
		}
	}
	internal static GenericResultOrigins projected(CoreFunction function, CoreResultOriginProjection projection, TypeSubstitution substitution) throws CoreError {
		var analysis = new CoreGenericResultOrigins (function, null, projection, substitution);
		analysis.block (function.body);
		return analysis.result;
	}
	internal static HashTable<CoreOwnedLocal, GenericResultOrigins> projected_locals(CoreGenericFunction function, CoreResultOriginProjection projection, TypeSubstitution substitution) throws CoreError {
		var analysis = new CoreGenericResultOrigins (function, null, projection, substitution);
		analysis.block (function.body);
		return analysis.locals;
	}
	internal static HashTable<CoreGenericFunction, GenericResultOrigins> derive(CoreProgram program) throws CoreError {
		var equations = new HashTable<CoreGenericFunction, GenericResultOrigins> (direct_hash, direct_equal);
		foreach (var function in program.generic_functions) {
			equations.insert (function, new GenericResultOrigins ());
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var function in program.generic_functions) {
				if (function.owned_cleanup == null || !(function.return_type is TypeParameterType || function.return_type is ClassType)) {
					continue;
				}
				var analysis = new CoreGenericResultOrigins (function, equations);
				analysis.block (function.body);
				if (!equations.lookup (function).same (analysis.result)) {
					equations.insert (function, analysis.result);
					changed = true;
				}
			}
		} while (changed);
		return equations;
	}
	internal static HashTable<CoreFunction, GenericResultOrigins> concrete_results(CoreProgram program) throws CoreError {
		var equations = new HashTable<CoreFunction, GenericResultOrigins> (direct_hash, direct_equal);
		foreach (var function in program.all_definitions ()) {
			if (function.return_type is ClassType && function.owned_cleanup != null && !function.heap_result && function.native_declaration == null) {
				equations.insert (function, new GenericResultOrigins ());
			}
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var function in equations.get_keys ()) {
				var analysis = new CoreGenericResultOrigins (function, null, null, null, equations);
				analysis.block (function.body);
				if (!equations.lookup (function).same (analysis.result)) {
					equations.insert (function, analysis.result);
					changed = true;
				}
			}
		} while (changed);
		return equations;
	}
	internal static HashTable<CoreOwnedLocal, GenericResultOrigins> concrete_locals(CoreFunction function, HashTable<CoreFunction, GenericResultOrigins> equations) throws CoreError {
		var analysis = new CoreGenericResultOrigins (function, null, null, null, equations);
		analysis.block (function.body);
		return analysis.locals;
	}
	internal static bool[] heap_arguments(GenericArray<CoreValue> arguments) {
		var heaps = new bool[arguments.length];
		for (int i = 0; i < arguments.length; i++) {
			var argument = arguments[i] as CoreOwnedArgumentValue;
			heaps[i] = argument != null && (argument.source == null ? argument.cleanup.is_heap_object : argument.source.cleanup.is_heap_object);
		}
		return heaps;
	}
}

public enum GenericInstanceState {
	IN_PROGRESS, COMPLETE
}

public class GenericInstanceCaller : Object {
	private WeakRef callable;
	public CoreFunction? function { owned get { return (CoreFunction?) callable.get (); } }
	private string identifier;
	public string label { get { return identifier; } }
	internal GenericInstanceCaller (CoreFunction function, string label) {
		this.callable = WeakRef (function);
		this.identifier = label;
	}
}

public class GenericFunctionInstance : Object {
	private WeakRef definition;
	private GenericArray<SemanticType> canonical_arguments = new GenericArray<SemanticType> ();
	private int[] consuming_parameters;
	private int[] exact_parameters;
	private int[] declared_heap_parameters;
	private bool parameter_result;
	public int heap_owned_parameter { get; private set; }
	public GenericStorageVector storage { get; private set; }
	public bool heap_result { get; private set; }
	// Definition-owned local shape, separate from the canonical allocation-domain
	// key. Concrete verification must reconstruct its actual transfer again.
	public int local_owned_parameter { get; private set; default = -1; }
	public CoreGenericFunction? origin_definition { owned get { return (CoreGenericFunction?) definition.get (); } }
	public CoreGenericIdentity origin { get; private set; }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	public int ordinal { get; private set; }
	public GenericInstanceState state { get; internal set; default = GenericInstanceState.IN_PROGRESS; }
	public GenericArray<GenericInstanceCaller> callers { get; private set; default = new GenericArray<GenericInstanceCaller> (); }
	public uint requests { get; internal set; default = 0; }
	internal GenericFunctionInstance (CoreGenericFunction definition, GenericArray<SemanticType> arguments, int ordinal, int heap_owned_parameter = -1, bool heap_result = false, GenericStorageVector? storage = null) {
		this.definition = WeakRef (definition);
		this.storage = storage ?? new GenericStorageVector.single (heap_owned_parameter);
		this.heap_owned_parameter = this.storage.count == 1 ? this.storage.parameter (0) : -1;
		this.heap_result = heap_result;
		parameter_result = definition.owned_cleanup != null && (definition.return_type is TypeParameterType || definition.return_type is ClassType);
		foreach (var parameter in definition.parameters) {
			if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !(parameter.semantic_type is TypeParameterType || parameter.semantic_type is ClassType)) {
				continue;
			}
			consuming_parameters += parameter.ordinal;
			if (parameter.semantic_type is TypeParameterType) {
				exact_parameters += parameter.ordinal;
			}
			if (parameter.heap_object) {
				declared_heap_parameters += parameter.ordinal;
			}
		}
		// Retain the old optional single-transfer annotation only where exact.
		// General local ownership is derived from the actual transfer graph.
		if (definition.owned_locals.length == 2) {
			foreach (var statement in definition.body.statements) {
				var transfer = statement as CoreOwnershipTransfer;
				var parameter = transfer == null ? null : transfer.source.place.incoming_parameter;
				if (parameter != null && parameter.semantic_type is TypeParameterType && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER
				    && transfer.destination.place.incoming_parameter == null && transfer.destination.place.semantic_type == parameter.semantic_type) {
					local_owned_parameter = parameter.ordinal;
				}
			}
		}
		this.origin = definition.identity;
		this.ordinal = ordinal;
		this.type_arguments = new GenericArray<SemanticType> (arguments.length);
		canonical_arguments = new GenericArray<SemanticType> (arguments.length);
		foreach (var type in arguments) {
			type_arguments.add (type);
			canonical_arguments.add (type);
		}
	}
	public bool has_canonical_key() {
		if (type_arguments.length != canonical_arguments.length) {
			return false;
		}
		for (int i = 0; i < type_arguments.length; i++) {
			if (type_arguments[i] != canonical_arguments[i]) {
				return false;
			}
		}
		return true;
	}
	public bool owns_parameter(int ordinal) {
		foreach (var parameter in consuming_parameters) {
			if (parameter == ordinal) {
				return true;
			}
		}
		return false;
	}
	public bool requires_exact_source(int ordinal) {
		foreach (var parameter in exact_parameters) {
			if (parameter == ordinal) {
				return true;
			}
		}
		return false;
	}
	private bool declared_heap(int ordinal) {
		foreach (var parameter in declared_heap_parameters) {
			if (parameter == ordinal) {
				return true;
			}
		}
		return false;
	}
	public string symbol_name() {
		return "astra.gen.%d.%d".printf (origin.ordinal, ordinal);
	}
	public bool matches(CoreGenericIdentity definition, GenericArray<SemanticType> arguments, int heap_owned_parameter = -1, GenericStorageVector? storage = null) {
		var expected = storage ?? new GenericStorageVector.single (heap_owned_parameter);
		if (!has_canonical_key () || origin != definition || type_arguments.length != arguments.length || !this.storage.same (expected)) {
			return false;
		}
		for (int i = 0; i < arguments.length; i++) {
			if (type_arguments[i] != arguments[i]) {
				return false;
			}
		}
		return true;
	}
	public bool has_storage_domain(CoreFunction function) {
		if (!storage.valid ((int) function.parameters.length)) {
			return false;
		}
		if (parameter_result && function.return_type is ClassType) {
			if (function.owned_cleanup == null) {
				return false;
			}
			if (function.heap_result != heap_result || function.owned_cleanup.is_heap_object != heap_result || (function.result_storage != null) == heap_result) {
				return false;
			}
		}
		for (int p = 0; p < storage.count; p++) {
			if (!owns_parameter (storage.parameter (p))) {
				return false;
			}
		}
		foreach (var ordinal in consuming_parameters) {
			if (ordinal < 0 || ordinal >= function.parameters.length) {
				return false;
			}
			var parameter = function.parameters[ordinal];
			bool heap = storage.is_heap (ordinal) || declared_heap (ordinal);
			if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || parameter.heap_object != heap || (heap && !(parameter.semantic_type is ClassType))) {
				return false;
			}
		}
		return true;
	}
}
}
