// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Foreign;

namespace Astra.Semantic {
public class SemanticResult : Object {
	public CheckedProgram? program { get; private set; }
	public Diagnostic? diagnostic { get; private set; }

	internal SemanticResult (CheckedProgram? program, Diagnostic? diagnostic) {
		assert ((program == null) != (diagnostic == null));
		this.program = program;
		this.diagnostic = diagnostic;
	}
}

// Visibility is lexical; the function-wide local array owns declaration order.

private class ModuleBinding : Object {
	internal string name;
	internal string space;
	internal bool restricted;
	internal ModuleBinding (string name, string space, bool restricted) {
		this.name = name;
		this.space = space;
		this.restricted = restricted;
	}
}

private class ValueScope : Object {
	private ValueScope? parent;
	public LexicalRegion region { get; private set; }
	private HashTable<string, Symbol> values = new HashTable<string, Symbol> (str_hash, str_equal);

	public ValueScope (ValueScope? parent, LexicalRegion region) {
		this.parent = parent;
		this.region = region;
	}

	public Symbol? lookup(string name) {
		var symbol = values.lookup (name);
		return symbol != null || parent == null ? symbol : parent.lookup (name);
	}

	public void insert(string name, Symbol symbol) {
		values.insert (name, symbol);
	}
}

private enum OwnershipUse {
	UNMANAGED,
	ACQUIRE,
	NULL_COMPARISON,
	BUFFER_VIEW,
	RECEIVER_BORROW
}
// Declaration-phase constraints establish one allocation domain per owned
// signature. They do not grant ownership: ordinary checking still proves
// every acquisition, move, extent, exact type and cleanup independently.
private class ObjectOriginConstraint : Object {
	internal ClassSymbol object_class;
	internal int domains;
	internal int intrinsic_domains;
	internal bool requires_heap;
	internal GenericArray<ObjectOriginConstraint> inputs = new GenericArray<ObjectOriginConstraint> ();
	internal ObjectOriginConstraint (ClassSymbol object_class, int domains = 0) {
		this.object_class = object_class;
		this.intrinsic_domains = domains;
		this.domains = domains;
	}
	internal void include(ObjectOriginConstraint? input) {
		if (input != null && !inputs.find (input)) {
			inputs.add (input);
		}
	}
}

public class SemanticAnalyzer : Object {
	private HashTable<SemanticType, string> c_class_prefixes = new HashTable<SemanticType, string> (direct_hash, direct_equal);
	private HashTable<SemanticType, ForeignValueKind> c_class_kinds = new HashTable<SemanticType, ForeignValueKind> (direct_hash, direct_equal);
	private HashTable<SemanticType, bool> c_class_shared = new HashTable<SemanticType, bool> (direct_hash, direct_equal);
	private HashTable<string, FunctionSymbol> imported_getters = new HashTable<string, FunctionSymbol> (str_hash, str_equal);
	private HashTable<string, FunctionSymbol> imported_setters = new HashTable<string, FunctionSymbol> (str_hash, str_equal);
	private bool imported_c_root(SemanticType type, out string prefix, out bool shared, out ForeignValueKind kind) {
		kind = c_class_kinds.contains (type) ? c_class_kinds.lookup (type) : ForeignValueKind.NATIVE_OBJECT;
		prefix = c_class_prefixes.lookup (type) ?? "";
		shared = c_class_shared.contains (type);
		return type is HandleType && prefix != "";
	}
	private HashTable<LocalSymbol, GenericArray<CheckedFieldPlace>> record_flow_fields = new HashTable<LocalSymbol, GenericArray<CheckedFieldPlace>> (direct_hash, direct_equal);
	private bool aggregate_owner_flow_needed;
	private void begin_ownership_flow(FunctionSymbol symbol) {
		record_flow_fields.remove_all ();
		var method = symbol as MethodSymbol;
		var accessor = symbol as PropertyAccessorSymbol;
		var owner = method != null ? method.declaring_type : accessor == null ? null : accessor.property_symbol.declaring_type;
		bool declaration_only = owner != null && owner.semantic_type is ClassType && ((ClassType) owner.semantic_type).is_interface;
		string context = (symbol is GenericFunctionSymbol) ? "generic definition checking" : "ownership checking in '%s'".printf (symbol.name);
		generic_owner_flow = !declaration_only && (aggregate_owner_flow_needed || symbol is GenericFunctionSymbol) ? new SemanticOwnershipFlow (symbol.span, context) : null;
	}
	private bool verify_ownership_flow(CheckedBlockStatement? body, FunctionSymbol symbol) {
		if (body == null) {
			return false;
		}
		if (generic_owner_flow != null && !generic_owner_flow.verify (symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) {
			fail (generic_owner_flow.diagnostic.span, generic_owner_flow.diagnostic.message);
			return false;
		}
		return true;
	}
	private HashTable<string, AsyncRuntimeIdentity> async_runtimes = new HashTable<string, AsyncRuntimeIdentity> (str_hash, str_equal);
	private AsyncRuntimeIdentity? runtime_for(SourceSpan span) {
		return async_runtimes.lookup (source_namespace (span)) ?? async_runtimes.lookup ("");
	}
	private GenericArray<ConstantSymbol> constants = new GenericArray<ConstantSymbol> ();
	private HashTable<ConstantSymbol, int> constant_indices = new HashTable<ConstantSymbol, int> (direct_hash, direct_equal);
	private ValueScope? constant_scope;
	private CallExpressionSyntax? direct_await_creation;
	private ExpressionSyntax? direct_loan_argument;
	private HashTable<LocalSymbol, bool> exposed_suspension_arrays = new HashTable<LocalSymbol, bool> (direct_hash, direct_equal);
	private GenericArray<LocalSymbol> scoped_contexts = new GenericArray<LocalSymbol> ();
	private GenericArray<LocalSymbol> pending_scoped_backings = new GenericArray<LocalSymbol> ();
	private GenericArray<CheckedSuspensionLoan> suspension_loans = new GenericArray<CheckedSuspensionLoan> ();
	private bool checking_constant;
	private HashTable<string, CForeignCleanupContract> cleanups = new HashTable<string, CForeignCleanupContract> (str_hash, str_equal);
	private HashTable<string, SemanticType> named_types = new HashTable<string, SemanticType> (str_hash, str_equal);
	private HashTable<SemanticType, HandleSymbol> handle_types = new HashTable<SemanticType, HandleSymbol> (direct_hash, direct_equal);
	private GenericArray<HandleSymbol>? shared_handle_inventory;
	private GenericArray<LocalSymbol> shared_borrow_guards = new GenericArray<LocalSymbol> ();
	private BuiltinTypes types = new BuiltinTypes ();
	private HashTable<EnumType, EnumDefinition> enum_definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private GenericArray<EnumDefinition> ordered_enums = new GenericArray<EnumDefinition> ();
	private HashTable<EnumType, GenericArray<TypeParameterSymbol>> enum_parameters = new HashTable<EnumType, GenericArray<TypeParameterSymbol>> (direct_hash, direct_equal);
	private bool collecting_enum_premises;
	private bool enum_buffer_capture;
	private bool enum_scalar_capture;
	private GenericArray<LocalSymbol> enum_reservations = new GenericArray<LocalSymbol> ();
	private GenericArray<LocalSymbol> enum_inspections = new GenericArray<LocalSymbol> ();
	private GenericSliceObligations element_obligations = new GenericSliceObligations ();
	private GenericCapabilityNamespace capability_names = new GenericCapabilityNamespace ();
	private HashTable<string, TypeParameterSymbol> lexical_types = new HashTable<string, TypeParameterSymbol> (str_hash, str_equal);
	private HashTable<string, GenericStructSymbol> generic_struct_names = new HashTable<string, GenericStructSymbol> (str_hash, str_equal);
	private HashTable<GenericStructSymbol, StructDeclarationSyntax> owning_record_syntax = new HashTable<GenericStructSymbol, StructDeclarationSyntax> (direct_hash, direct_equal);
	private HashTable<GenericStructApplicationType, bool> active_owning_records = new HashTable<GenericStructApplicationType, bool> (direct_hash, direct_equal);
	private int next_owned_record_ordinal;
	private GenericArray<CheckedGenericStruct> generic_structs = new GenericArray<CheckedGenericStruct> ();
	private HashTable<string, ExactClassTemplate> generic_class_names = new HashTable<string, ExactClassTemplate> (str_hash, str_equal);
	private GenericArray<ExactClassTemplate> generic_classes = new GenericArray<ExactClassTemplate> ();
	private GenericArray<NativeInstanceDeclarationSyntax> instance_syntax = new GenericArray<NativeInstanceDeclarationSyntax> ();
	private GenericArray<NativeInstanceSymbol>? class_requests;
	private GenericArray<NativeInstanceDeclarationSyntax>? class_request_syntax;
	private bool class_declarations_ready;
	private bool draining_class_declarations;
	private int class_field_cursor;
	private int class_member_cursor;
	private HashTable<NativeInstanceSymbol, bool> collected_instance_fields = new HashTable<NativeInstanceSymbol, bool> (direct_hash, direct_equal);
	private HashTable<NativeInstanceSymbol, bool> collected_instance_members = new HashTable<NativeInstanceSymbol, bool> (direct_hash, direct_equal);
	private HashTable<ClassSymbol, bool> completed_class_dispatch = new HashTable<ClassSymbol, bool> (direct_hash, direct_equal);
	private int next_class_ordinal;
	private int class_request_depth;
	private ClassSymbol? specializing_class;
	private ClassMethodInstance? specializing_method;
	private string[] method_type_parameters = {};
	private uint closed_method_count;
	private uint closed_class_count;
	private uint closed_enum_count;
	private HashTable<MethodSymbol, bool> checked_methods = new HashTable<MethodSymbol, bool> (direct_hash, direct_equal);
	private HashTable<MethodSymbol, FunctionDeclarationSyntax> method_syntax = new HashTable<MethodSymbol, FunctionDeclarationSyntax> (direct_hash, direct_equal);
	private HashTable<string, DirectCallableSymbol> function_names = new HashTable<string, DirectCallableSymbol> (str_hash, str_equal);
	private HashTable<string, NativeInstanceSymbol> instance_names = new HashTable<string, NativeInstanceSymbol> (str_hash, str_equal);
	private HashTable<ConstructorSymbol, LifecycleDeclarationSyntax> constructor_initializers = new HashTable<ConstructorSymbol, LifecycleDeclarationSyntax> (direct_hash, direct_equal);
	private LifecycleSymbol? checking_lifecycle;
	private FunctionSymbol? checking_function;
	private ClassSymbol? exception_root;
	private GenericArray<ExceptionHandlerScope> exception_handlers = new GenericArray<ExceptionHandlerScope> ();
	private GenericArray<LocalSymbol> caught_exceptions = new GenericArray<LocalSymbol> ();
	private HashTable<LocalSymbol, GenericArray<ClassType>> caught_effects = new HashTable<LocalSymbol, GenericArray<ClassType>> (direct_hash, direct_equal);
	private HashTable<SemanticType, NativeInstanceSymbol> instance_types = new HashTable<SemanticType, NativeInstanceSymbol> (direct_hash, direct_equal);
	private Diagnostic? diagnostic;
	private GenericArray<LocalSymbol> active_object_receivers = new GenericArray<LocalSymbol> ();
	private GenericArray<CheckedLoopTarget> active_loops = new GenericArray<CheckedLoopTarget> ();
	private uint foreach_depth;
	private GenericArray<LocalSymbol> sequence_sources = new GenericArray<LocalSymbol> ();
	private GenericArray<CheckedWithContract> active_with = new GenericArray<CheckedWithContract> ();
	private ReadonlyInspection readonly_inspection = new ReadonlyInspection ();
	private GenericArray<FunctionSymbol> nonnull_definitions = new GenericArray<FunctionSymbol> ();
	private GenericArray<SemanticType> allocation_containers = new GenericArray<SemanticType> ();
	private GenericArray<SemanticType> pending_lazy_borrows = new GenericArray<SemanticType> ();
	private GenericArray<SemanticType> pending_field_borrows = new GenericArray<SemanticType> ();
	private GenericArray<LocalSymbol> pending_record_borrows = new GenericArray<LocalSymbol> ();
	private GenericArray<LocalSymbol> pending_callable_borrows = new GenericArray<LocalSymbol> ();
	private GenericArray<LocalSymbol> pending_callable_transfers = new GenericArray<LocalSymbol> ();
	private GenericArray<SemanticType>? child_edges(SemanticType type) {
		var result = new GenericArray<SemanticType> ();
		var record = instance_for (type) as StructSymbol;
		if (record != null) {
			foreach (var field in record.fields) {
				if (field.owns_child || field.semantic_type is StructType) {
					result.add (field.semantic_type);
				}
			}
			return result;
		}
		var owner = instance_for (type) as ClassSymbol;
		for (var current = owner; current != null; current = current.parent_class) {
			foreach (var property in current.properties) {
				if (property.is_owned_lazy) {
					result.add (property.semantic_type);
				}
			}
			foreach (var field in current.fields) {
				if (field.owns_child || field.owns_record) {
					result.add (field.semantic_type);
				} else if (field.semantic_type is OwnerSlotsType) {
					result.add (((OwnerSlotsType) field.semantic_type).element);
				}
			}
		}
		return result;
	}
	private GenericArray<SemanticType>? possible_child_edges(SemanticType type) {
		var result = child_edges (type);
		var owner = type as ClassType;
		if (owner != null) {
			foreach (var instance in instance_types.get_values ()) {
				var candidate = instance.semantic_type as ClassType;
				if (candidate != null && candidate != owner && candidate.derives_from (owner)) {
					foreach (var child in child_edges (candidate)) {
						result.add (child);
					}
				}
			}
		}
		return result;
	}
	private bool field_overlap(SemanticType candidate, SemanticType backing) {
		return OwnedChildComposition.may_invalidate (candidate, backing, possible_child_edges);
	}
	private HashTable<CallExpressionSyntax, GenericCallContext> generic_call_contexts = new HashTable<CallExpressionSyntax, GenericCallContext> (direct_hash, direct_equal);
	private HashTable<CheckedOwnedArgument, GenericFunctionSymbol> heap_generic_requests = new HashTable<CheckedOwnedArgument, GenericFunctionSymbol> (direct_hash, direct_equal);
	private GenericArray<CheckedOwnedArgument> lexical_generic_order = new GenericArray<CheckedOwnedArgument> ();
	private HashTable<CheckedOwnedArgument, GenericFunctionSymbol> lexical_generic_requests = new HashTable<CheckedOwnedArgument, GenericFunctionSymbol> (direct_hash, direct_equal);
	private GenericArray<CheckedOwnedArgument> heap_generic_order = new GenericArray<CheckedOwnedArgument> ();
	private HashTable<GenericFunctionSymbol, GenericOwnerTransferScope> heap_consumer_scopes = new HashTable<GenericFunctionSymbol, GenericOwnerTransferScope> (direct_hash, direct_equal);
	private HashTable<GenericFunctionSymbol, GenericOwnershipFlow> storage_flows = new HashTable<GenericFunctionSymbol, GenericOwnershipFlow> (direct_hash, direct_equal);
	private FieldInitializationState? field_state;
	private bool element_fields_complete;
	private bool slots_field_type_context;
	private HashTable<CheckedLoopTarget, CheckedLoopTarget> constructor_breaks = new HashTable<CheckedLoopTarget, CheckedLoopTarget> (direct_hash, direct_equal);
	private int next_loop_ordinal = 0;
	private int next_object_ordinal = 0;
	private int next_region_ordinal = 0;
	private HashTable<Object, ObjectOriginConstraint> signature_origins = new HashTable<Object, ObjectOriginConstraint> (direct_hash, direct_equal);
	private GenericArray<ObjectOriginConstraint> origin_constraints = new GenericArray<ObjectOriginConstraint> ();
	private GenericArray<ClassSymbol> class_applications = new GenericArray<ClassSymbol> ();
	private GenericArray<GenericClassFunctionRequest> class_function_requests = new GenericArray<GenericClassFunctionRequest> ();
	private GenericArray<GenericClassFunctionRequest> closed_class_function_requests = new GenericArray<GenericClassFunctionRequest> ();
	private HashTable<GenericRequestKey, bool> closed_class_function_keys = new HashTable<GenericRequestKey, bool> (GenericRequestKey.hash, GenericRequestKey.equal);
	private GenericArray<GenericClassMethodRequest> class_method_requests = new GenericArray<GenericClassMethodRequest> ();
	private GenericArray<MethodSymbol> method_applications = new GenericArray<MethodSymbol> ();

	private bool close_class_function_request(GenericFunctionSymbol target, TypeArgumentVector arguments) {
		foreach (var argument in arguments.copy_values ()) {
			if (!GenericResourceLimits.admits_type (argument)) {
				fail (target.span, "generic materialization limit exceeded: type-expression depth %d while requesting '%s'".printf (GenericResourceLimits.TYPE_DEPTH, target.name));
				return false;
			}
		}
		var key = new GenericRequestKey (target, arguments);
		if (closed_class_function_keys.contains (key)) {
			return true;
		}
		if (closed_class_function_requests.length >= GenericResourceLimits.CLOSED_INSTANCES) {
			fail (target.span, "generic materialization limit exceeded: at most %u closed declaration requests while requesting '%s'".printf (GenericResourceLimits.CLOSED_INSTANCES, target.name));
			return false;
		}
		closed_class_function_requests.add (new GenericClassFunctionRequest (target, null, arguments));
		closed_class_function_keys.insert (key, true);
		return true;
	}

	private bool expand_class_applications() {
		bool origins_changed = false;
		var edges = new HashTable<GenericFunctionSymbol, GenericArray<GenericClassFunctionRequest>> (direct_hash, direct_equal);
		foreach (var request in class_function_requests) {
			if (request.arguments.closed () && !close_class_function_request (request.target, request.arguments)) {
				return false;
			}
			if (request.caller != null) {
				var bucket = edges.lookup (request.caller);
				if (bucket == null) {
					bucket = new GenericArray<GenericClassFunctionRequest> ();
					edges.insert (request.caller, bucket);
				}
				bucket.add (request);
			}
		}
		for (int i = 0; i < closed_class_function_requests.length; i++) {
			var request = closed_class_function_requests[i];
			var substitution = new TypeSubstitution ((element) => types.slice_of (element), types.substitute_function, substitute_class, substitute_closure);
			for (int t = 0; t < request.arguments.length; t++) {
				substitution.bind (request.target.type_parameters[t].semantic_type, request.arguments.at (t));
			}
			var outgoing = edges.lookup (request.target);
			if (outgoing != null) {
				foreach (var edge in outgoing) {
					var arguments = new TypeArgumentVector (substitution.apply_arguments (edge.arguments.copy_values ()));
					if (arguments.closed () && !close_class_function_request (edge.target, arguments)) {
						return false;
					}
				}
			}
			// Unrelated lexical parameters retain identity under substitution,
			// so only dependencies of this demanded function become closed.
			for (int a = 0; a < class_applications.length; a++) {
				substitution.apply (class_applications[a].semantic_type);
			}
			for (int m = 0; m < class_method_requests.length; m++) {
				var edge = class_method_requests[m];
				if (edge.caller != request.target) {
					continue;
				}
				var binding = edge.header.generic_method_instance;
				var owner_type = substitution.apply (edge.header.declaring_type.semantic_type);
				var arguments = new TypeArgumentVector (substitution.apply_arguments (binding.arguments.copy_values ()));
				if (owner_type.is_parameterized () || !arguments.closed ()) {
					continue;
				}
				var owner = instance_for (owner_type) as ClassSymbol;
				if (owner == null) {
					return false;
				}
				var method = request_class_method (owner, binding.member, arguments, edge.header.span);
				if (method == null) {
					return false;
				}
				for (int p = 0; p < edge.header.parameters.length; p++) {
					var symbolic = edge.header.parameters[p];
					var parameter = method.parameters[p];
					if (symbolic.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !ownable_parameter (symbolic.semantic_type) || !(parameter.semantic_type is ClassType)) {
						continue;
					}
					var origin = signature_origins.lookup (parameter);
					if (origin != null && !origin.requires_heap) {
						origin.requires_heap = true;
						origins_changed = true;
					}
				}
			}
			if (diagnostic != null) {
				return false;
			}
		}
		return !origins_changed || origin_program == null || resolve_object_origins (origin_program, origin_declarations, class_requests);
	}
	private GenericArray<FunctionSymbol> origin_functions = new GenericArray<FunctionSymbol> ();
	private GenericArray<BlockStatementSyntax> origin_bodies = new GenericArray<BlockStatementSyntax> ();
	private HashTable<FunctionSymbol, bool> queued_origin_functions = new HashTable<FunctionSymbol, bool> (direct_hash, direct_equal);
	private int origin_body_cursor;
	private SyntaxProgram? origin_program;
	private GenericArray<DirectCallableSymbol>? origin_declarations;
	private bool draining_object_origins;
	private FunctionSymbol? origin_function;
	private HashTable<string, SemanticType> origin_record_types = new HashTable<string, SemanticType> (str_hash, str_equal);
	private HashTable<ExpressionSyntax, SemanticType> origin_record_results = new HashTable<ExpressionSyntax, SemanticType> (direct_hash, direct_equal);
	private SemanticType? origin_record_type(ExpressionSyntax expression) {
		while (expression is ParenthesizedExpressionSyntax) {
			expression = ((ParenthesizedExpressionSyntax) expression).expression;
		}
		var move = expression as MoveExpressionSyntax;
		if (expression is NameExpressionSyntax) {
			return origin_record_types.lookup (((NameExpressionSyntax) expression).identifier.spelling ());
		}
		if (move != null && move.fields.length == 0) {
			return origin_record_types.lookup (move.source.spelling ());
		}
		return origin_record_results.lookup (expression);
	}
	private ObjectOriginConstraint origin_constraint(ClassSymbol owner, int domains = 0) {
		var node = new ObjectOriginConstraint (owner, domains);
		origin_constraints.add (node);
		return node;
	}
	private void origin_arguments(GenericArray<ExpressionSyntax> arguments, DirectCallableSymbol? target, HashTable<string, ObjectOriginConstraint> bindings, CallableSignature? indirect = null, int first = 0) {
		for (int i = 0; i < arguments.length; i++) {
			var incoming = origin_expression (arguments[i], bindings);
			if (target != null && i < target.parameters.length) {
				var parameter = signature_origins.lookup (target.parameters[i]);
				if (parameter != null && !(target is GenericFunctionSymbol && target.parameters[i].pointer_contract == PointerParameterContract.OWNED_TRANSFER && target.parameters[i].semantic_type is ClassType)) {
					parameter.include (incoming);
				}
			}
			if (incoming != null && indirect != null && i >= first && i - first < indirect.parameter_types.length && CallableRecordGroups.heap_parameter (indirect, i - first)) {
				incoming.requires_heap = true;
			}
		}
	}
	private SemanticType? origin_receiver_type(ExpressionSyntax syntax, HashTable<string, ObjectOriginConstraint> bindings) {
		if (syntax is ParenthesizedExpressionSyntax) {
			return origin_receiver_type (((ParenthesizedExpressionSyntax) syntax).expression, bindings);
		}
		if (syntax is NameExpressionSyntax) {
			string name = ((NameExpressionSyntax) syntax).identifier.spelling ();
			var binding = bindings.lookup (name);
			return binding == null ? origin_record_types.lookup(name) : binding.object_class.semantic_type;
		}
		var projection = syntax as FieldAccessExpressionSyntax;
		if (projection == null) {
			return null;
		}
		SemanticType? type;
		if (projection.aggregate != null) {
			type = origin_receiver_type (projection.aggregate, bindings);
		} else {
			var binding = bindings.lookup (projection.identifier.spelling ());
			type = binding == null ? origin_record_types.lookup(projection.identifier.spelling ()) : binding.object_class.semantic_type;
		}
		if (type == null) {
			return null;
		}
		if (projection.indirect && type is TypedPointerType) {
			type = ((TypedPointerType) type).pointee;
		}
		var owner = instance_for (type);
		var property = owner == null ? null : owner.find_property (projection.field_name.spelling ());
		if (property != null) {
			return property.semantic_type;
		}
		var field = storage_field (type, projection.field_name.spelling ());
		return field == null ? null : storage_field_type (type, field);
	}
	private void require_callable_heap_inputs(DirectCallableSymbol? target) {
		if (target == null) {
			return;
		}
		var function = target as FunctionSymbol;
		if (function != null && function.return_type is ClassType && function.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			var result = signature_origins.lookup (target);
			if (result != null) {
				result.requires_heap = true;
			}
		}
		foreach (var parameter in target.parameters) {
			if (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				var origin = signature_origins.lookup (parameter);
				if (origin != null) {
					origin.requires_heap = true;
				}
			}
		}
	}
	private TypeSubstitution? generic_origin_substitution(GenericFunctionSymbol function, CallExpressionSyntax call, HashTable<string, ObjectOriginConstraint> bindings, TypeSubstitution? outer = null) {
		var substitution = new TypeSubstitution ((element) => types.slice_of (element), types.substitute_function, substitute_class, substitute_closure);
		if (call.type_arguments.length == function.type_parameters.length) {
			for (int t = 0; t < function.type_parameters.length; t++) {
				var actual = resolve_type (call.type_arguments[t]);
				if (actual == null) {
					return null;
				}
				substitution.bind (function.type_parameters[t].semantic_type, outer == null ? actual : outer.apply (actual));
			}
			return substitution;
		}
		if (call.type_arguments.length != 0) {
			return null;
		}
		var inference = new GenericCallInference (function);
		for (int p = 0; p < function.parameters.length && p < call.arguments.length; p++) {
			var syntax = call.arguments[p];
			var actual = origin_record_type (syntax) ?? origin_receiver_type (syntax, bindings);
			var name = syntax as NameExpressionSyntax;
			if (actual == null && name != null && function.parameters[p].semantic_type is FunctionValueType) {
				var code = function_names.lookup (resolve_name (name.span, name.identifier.spelling (), false)) as FunctionSymbol;
				if (code != null && !(code is GenericFunctionSymbol) && code.implicit_receiver == null && code.async_body == null && code.throws_type == null && FunctionValueType.supported_result (code.return_type, code.result_contract)) {
					var parameters = new GenericArray<SemanticType> ();
					var contracts = new GenericArray<PointerParameterContract> ();
					foreach (var parameter in code.parameters) {
						parameters.add (parameter.semantic_type);
						contracts.add (parameter.pointer_contract);
					}
					actual = types.function_value (code.return_type, parameters, contracts, code.result_contract);
				}
			}
			if (actual != null && !inference.observe_type (function.parameters[p].semantic_type, actual, p, syntax.span)) {
				return null;
			}
		}
		foreach (var parameter in function.type_parameters) {
			foreach (var observation in inference.observations) {
				if (observation.parameter != parameter) {
					continue;
				}
				substitution.bind (parameter.semantic_type, observation.candidate);
				break;
			}
		}
		return substitution;
	}
	private ClassSymbol? generic_origin_result_class(GenericFunctionSymbol function, CallExpressionSyntax call, HashTable<string, ObjectOriginConstraint> bindings) {
		var substitution = generic_origin_substitution (function, call, bindings);
		if (substitution == null) {
			return null;
		}
		var result = substitution.apply (function.return_type);
		return result.is_parameterized () ? null : instance_for (result) as ClassSymbol;
	}
	private ObjectOriginConstraint? origin_expression(ExpressionSyntax? expression, HashTable<string, ObjectOriginConstraint> bindings) {
		if (expression == null) {
			return null;
		}
		if (expression is ParenthesizedExpressionSyntax) {
			return origin_expression (((ParenthesizedExpressionSyntax) expression).expression, bindings);
		}
		if (expression is AwaitExpressionSyntax) {
			return origin_expression (((AwaitExpressionSyntax) expression).operation, bindings);
		}
		if (expression is NameExpressionSyntax) {
			var token = ((NameExpressionSyntax) expression).identifier;
			if (!bindings.contains (token.spelling ())) {
				require_callable_heap_inputs (find_function (token));
			}
			return bindings.lookup (token.spelling ());
		}
		var qualified_code = expression as FieldAccessExpressionSyntax;
		if (qualified_code != null && qualified_code.aggregate == null && !bindings.contains (qualified_code.identifier.spelling ()) && module_names.contains (qualified_code.identifier.spelling ())) {
			require_callable_heap_inputs (function_names.lookup (resolve_name (expression.span, qualified_code.identifier.spelling () + "." + qualified_code.field_name.spelling (), false)));
		}
		if (expression is MoveExpressionSyntax) {
			var move = (MoveExpressionSyntax) expression;
			if (move.fields.length == 0) {
				return bindings.lookup (move.source.spelling ());
			}
			SemanticType? type = origin_record_types.lookup (move.source.spelling ());
			foreach (var token in move.fields) {
				var record = type == null ? null : instance_for (type) as StructSymbol;
				var field = record == null ? null : record.find_field (token.spelling ());
				type = field == null ? null : field.semantic_type;
			}
			var child = type == null ? null : instance_for (type) as ClassSymbol;
			return child == null ? null : origin_constraint (child, 2);
		}
		if (expression is HeapObjectConstructionSyntax) {
			var heap = (HeapObjectConstructionSyntax) expression;
			var owner = origin_class (heap.class_name) as ClassSymbol;
			origin_arguments (heap.arguments, owner == null ? null : owner.constructor, bindings);
			return owner == null ? null : origin_constraint (owner, 2);
		}
		if (expression is CallExpressionSyntax) {
			var call = (CallExpressionSyntax) expression;
			DirectCallableSymbol? target = null;
			if (call.receiver != null && call.arguments.length == 0 && call.identifier.spelling () == "clone") {
				var root = bindings.lookup (call.receiver.spelling ());
				if (root != null && ((ClassType) root.object_class.semantic_type).intrinsically_shared) {
					return origin_constraint (root.object_class, 2);
				}
			}
			if (call.receiver == null && call.arguments.length == 1 && (call.identifier.spelling () == "shared_clone" || call.identifier.spelling () == "singleton_shutdown")) {
				var root = origin_expression (call.arguments[0], bindings);
				if (root != null && ((ClassType) root.object_class.semantic_type).intrinsically_shared) {
					return origin_constraint (root.object_class, 2);
				}
			}
			if (call.receiver == null && call.identifier.spelling () == "actor_bind" && call.arguments.length == 4) {
				var code = call.arguments[1] as NameExpressionSyntax;
				var handler = code == null ? null : find_function (code.identifier);
				if (handler != null && handler.parameters.length == 2) {
					var message = signature_origins.lookup (handler.parameters[1]);
					if (message != null) {
						message.requires_heap = true;
					}
				}
			}
			if (call.receiver_place != null) {
				var type = origin_receiver_type (call.receiver_place, bindings);
				var owner = type == null ? null : instance_for (type);
				if (owner != null) {
					target = resolve_class_method (owner, call);
				}
			} else if (call.receiver == null) {
				target = find_function (call.identifier);
			} else if (!bindings.contains (call.receiver.spelling ()) && module_names.contains (call.receiver.spelling ())) {
				target = function_names.lookup (resolve_name (call.identifier.span, call.receiver.spelling () + "." + call.identifier.spelling (), false));
			} else {
				var receiver = bindings.lookup (call.receiver.spelling ());
				var receiver_type = origin_record_types.lookup (call.receiver.spelling ());
				NativeInstanceSymbol? owner = receiver != null ? receiver.object_class : receiver_type != null ? instance_for(receiver_type) : qualified_class (call, true);
				if (owner != null) {
					if (call.identifier.spelling () == "init" && receiver == null && receiver_type == null && owner is ClassSymbol) {
						origin_arguments (call.arguments, ((ClassSymbol) owner).constructor, bindings);
						return origin_constraint ((ClassSymbol) owner, 1);
					}
					target = resolve_class_method (owner, call);
				}
			}
			var slots_receiver = call.receiver_place as FieldAccessExpressionSyntax;
			if (slots_receiver != null && (call.identifier.spelling () == "append" && call.arguments.length == 1 || call.identifier.spelling () == "replace" && call.arguments.length == 2)) {
				var container = bindings.lookup (slots_receiver.identifier.spelling ());
				var field = container == null ? null : container.object_class.find_field (slots_receiver.field_name.spelling ());
				if (field != null && field.semantic_type is OwnerSlotsType) {
					var input = origin_expression (call.arguments[call.arguments.length - 1], bindings);
					if (input != null) {
						input.requires_heap = true;
					}
				}
			}
			if (slots_receiver != null && call.identifier.spelling () == "take") {
				var container = bindings.lookup (slots_receiver.identifier.spelling ());
				var field = container == null ? null : container.object_class.find_field (slots_receiver.field_name.spelling ());
				if (field != null && field.semantic_type is OwnerSlotsType && ((OwnerSlotsType) field.semantic_type).element is ClassType) {
					return origin_constraint ((ClassSymbol) instance_for (((OwnerSlotsType) field.semantic_type).element), 2);
				}
			}
			CallableSignature? indirect = null;
			int first = 0;
			if (call.receiver == null && call.receiver_place == null) {
				if (call.identifier.spelling () == "closure_invoke" && call.arguments.length != 0) {
					indirect = origin_receiver_type (call.arguments[0], bindings) as CallableSignature;
					first = 1;
				} else {
					indirect = origin_record_types.lookup (call.identifier.spelling ()) as CallableSignature;
				}
			}
			if (indirect != null) {
				target = null;
			}
			origin_arguments (call.arguments, target, bindings, indirect, first);
			if (indirect != null && indirect.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
				SemanticType result_type;
				if (indirect is FunctionValueType) {
					result_type = ((FunctionValueType) indirect).result_type;
				} else {
					result_type = ((ClosureHandleType) indirect).result_type;
				}
				var owner = instance_for (result_type) as ClassSymbol;
				if (owner != null) {
					return origin_constraint (owner, 2);
				}
			}
			if (target != null && (target.return_type.is_struct_storage () || target.return_type is CallableSignature)) {
				origin_record_results.insert (call, target.return_type);
			}
			// Instantiate the result equation independently of all input domains.
			// The body checker still proves every move and exact result type.
			var generic = target as GenericFunctionSymbol;
			if (generic != null && generic.result_contract == ResultOwnershipContract.OWNED_TRANSFER && (ownable_parameter (generic.return_type) || generic.return_type is ClassType)) {
				var equation = generic.result_origins;
				if ((equation.domains & GenericResultOrigins.UNKNOWN) != 0) {
					var substitution = generic_origin_substitution (generic, call, bindings);
					if (substitution == null) {
						return null;
					}
					var arguments = new GenericArray<SemanticType> ();
					foreach (var parameter in generic.type_parameters) {
						arguments.add (substitution.apply (parameter.semantic_type));
					}
					equation = project_source_result (generic, arguments);
				}
				if ((equation.domains & GenericResultOrigins.UNKNOWN) != 0) {
					return null;
				}
				var owner = generic_origin_result_class (generic, call, bindings);
				var inputs = new GenericArray<ObjectOriginConstraint> ();
				for (int p = 0; p < equation.input_count; p++) {
					int ordinal = equation.input (p);
					if (ordinal < 0 || ordinal >= call.arguments.length) {
						return null;
					}
					var incoming = origin_expression (call.arguments[ordinal], bindings);
					if (incoming == null) {
						return null;
					}
					if (owner == null) {
						owner = incoming.object_class;
					}
					inputs.add (incoming);
				}
				if (owner == null) {
					return null;
				}
				var result = origin_constraint (owner, (int) equation.domains);
				foreach (var incoming in inputs) {
					result.include (incoming);
				}
				return result;
			}
			return target == null ? null : signature_origins.lookup (target);
		}
		if (expression is IndexExpressionSyntax) {
			var indexed = (IndexExpressionSyntax) expression;
			origin_expression (indexed.container, bindings);
			origin_expression (indexed.subscript, bindings);
		}
		if (expression is FieldAccessExpressionSyntax && ((FieldAccessExpressionSyntax) expression).aggregate != null) {
			origin_expression (((FieldAccessExpressionSyntax) expression).aggregate, bindings);
		}
		if (expression is TextMemberExpressionSyntax) {
			origin_expression (((TextMemberExpressionSyntax) expression).receiver, bindings);
		}
		if (expression is ComparisonChainSyntax) {
			foreach (var operand in ((ComparisonChainSyntax) expression).operands) {
				origin_expression (operand, bindings);
			}
		}
		if (expression is BinaryExpressionSyntax) {
			origin_expression (((BinaryExpressionSyntax) expression).left, bindings);
			origin_expression (((BinaryExpressionSyntax) expression).right, bindings);
		}
		if (expression is ShortCircuitExpressionSyntax) {
			origin_expression (((ShortCircuitExpressionSyntax) expression).left, bindings);
			origin_expression (((ShortCircuitExpressionSyntax) expression).right, bindings);
		}
		if (expression is PrefixExpressionSyntax) {
			origin_expression (((PrefixExpressionSyntax) expression).operand, bindings);
		}
		if (expression is ConversionExpressionSyntax) {
			origin_expression (((ConversionExpressionSyntax) expression).operand, bindings);
		}
		return null;
	}
	private void origin_block(BlockStatementSyntax body, FunctionSymbol function, HashTable<string, ObjectOriginConstraint> outer) {
		origin_statements (body.statements, function, outer);
	}
	private void origin_match(MatchStatementSyntax match, FunctionSymbol function, HashTable<string, ObjectOriginConstraint> outer) {
		origin_expression (match.scrutinee, outer);
		var scrutinee = match.scrutinee;
		while (scrutinee is ParenthesizedExpressionSyntax) {
			scrutinee = ((ParenthesizedExpressionSyntax) scrutinee).expression;
		}
		bool consuming = scrutinee is MoveExpressionSyntax || scrutinee is CallExpressionSyntax || scrutinee is AwaitExpressionSyntax;
		var incoming_records = origin_record_types;
		foreach (var arm in match.arms) {
			var bindings = new HashTable<string, ObjectOriginConstraint> (str_hash, str_equal);
			foreach (var name in outer.get_keys ()) {
				bindings.insert (name, outer.lookup (name));
			}
			origin_record_types = new HashTable<string, SemanticType> (str_hash, str_equal);
			foreach (var name in incoming_records.get_keys ()) {
				origin_record_types.insert (name, incoming_records.lookup (name));
			}
			var type = arm.qualifier == null ? null : find_named (arm.qualifier) as EnumType;
			var definition = type == null ? null : enum_definition_for (type);
			var variant = definition == null || arm.variant == null ? null : definition.find_variant (arm.variant.spelling ());
			if (consuming && variant != null) {
				for (uint i = 0; i < arm.bindings.length; i++) {
					var binding = arm.bindings[i];
					var field = binding.field == null ? (i < variant.field_count ? variant.field (i) : null) : variant.find_field (binding.field.spelling ());
					var child = field == null || !field.owns_child ? null : instance_for (field.semantic_type) as ClassSymbol;
					if (field != null && field.owns_record && binding.binding.spelling () != "_") {
						origin_record_types.insert (binding.binding.spelling (), field.semantic_type);
					}
					if (child != null && binding.binding.spelling () != "_") {
						bindings.insert (binding.binding.spelling (), origin_constraint (child, 2));
					}
				}
			}
			origin_block (arm.body, function, bindings);
		}
		origin_record_types = incoming_records;
	}
	private void origin_record_initializer(StructInitializerSyntax initializer, SemanticType type, HashTable<string, ObjectOriginConstraint> bindings) {
		var record = instance_for (type) as StructSymbol;
		if (record == null) {
			return;
		}
		foreach (var child in initializer.fields) {
			var field = record.find_field (child.name.spelling ());
			if (field == null) {
				continue;
			}
			if (child.initializer != null) {
				origin_record_initializer (child.initializer, field.semantic_type, bindings);
			} else {
				var incoming = origin_expression (child.expression, bindings);
				if (field.owns_child && incoming != null) {
					incoming.requires_heap = true;
				}
			}
		}
	}
	private void origin_statements(GenericArray<StatementSyntax> statements, FunctionSymbol function, HashTable<string, ObjectOriginConstraint> outer, ExpressionSyntax? condition = null) {
		var incoming_records = origin_record_types;
		origin_record_types = new HashTable<string, SemanticType> (str_hash, str_equal);
		foreach (var name in incoming_records.get_keys ()) {
			origin_record_types.insert (name, incoming_records.lookup (name));
		}
		foreach (var parameter in function.parameters) {
			origin_record_types.insert (parameter.name, parameter.semantic_type);
		}
		var bindings = new HashTable<string, ObjectOriginConstraint> (str_hash, str_equal);
		foreach (var name in outer.get_keys ()) {
			bindings.insert (name, outer.lookup (name));
		}
		foreach (var statement in statements) {
			if (statement is BlockStatementSyntax) {
				origin_block ((BlockStatementSyntax) statement, function, bindings);
			} else if (statement is InferredLocalDeclarationSyntax) {
				var local = (InferredLocalDeclarationSyntax) statement;
				var node = origin_expression (local.initializer, bindings);
				bindings.insert (local.name.spelling (), node);
				var type = origin_record_type (local.initializer);
				if (type == null) {
					type = origin_receiver_type (local.initializer, bindings);
				}
				if (type != null) {
					origin_record_types.insert (local.name.spelling (), type);
				}
			} else if (statement is LocalDeclarationSyntax) {
				var local = (LocalDeclarationSyntax) statement;
				var node = origin_expression (local.initializer, bindings);
				bindings.insert (local.name.spelling (), node);
				var type = origin_record_type (local.initializer);
				if (type == null) {
					type = origin_receiver_type (local.initializer, bindings);
				}
				var application = local.type_name as GenericTypeApplicationSyntax;
				if (application != null && (application.identifier.spelling () == "Fn" || application.identifier.spelling () == "Closure" || application.identifier.spelling () == "CheckedClosure")) {
					type = resolve_type (local.type_name);
				}
				if (type != null) {
					origin_record_types.insert (local.name.spelling (), type);
				}
			} else if (statement is StructLocalDeclarationSyntax) {
				var local = (StructLocalDeclarationSyntax) statement;
				var owner = origin_class (local.type_name) as ClassSymbol;
				if (owner != null) {
					bindings.insert (local.name.spelling (), origin_constraint (owner, 1));
				} else {
					var type = resolve_type (local.type_name);
					if (type != null && type.is_struct_storage ()) {
						origin_record_types.insert (local.name.spelling (), type);
						origin_record_initializer (local.initializer, type, bindings);
					}
				}
			} else if (statement is AssignmentStatementSyntax) {
				var assignment = (AssignmentStatementSyntax) statement;
				var old = bindings.lookup (assignment.name.spelling ());
				var node = origin_expression (assignment.expression, bindings);
				if (old != null) {
					old.include (node);
				}
			} else if (statement is FieldAssignmentStatementSyntax) {
				var assignment = (FieldAssignmentStatementSyntax) statement;
				var node = origin_expression (assignment.expression, bindings);
				var receiver = bindings.lookup (assignment.target.identifier.spelling ());
				var field = receiver == null ? null : receiver.object_class.find_field (assignment.target.field_name.spelling ());
				if (field != null && field.owns_child && node != null) {
					node.requires_heap = true;
				}
				var property = receiver == null ? null : receiver.object_class.find_property (assignment.target.field_name.spelling ());
				if (property != null && property.is_borrowed && property.setter != null) {
					var parameter = signature_origins.lookup (property.setter.parameters[0]);
					if (parameter != null) {
						parameter.include (node);
					}
				}
			} else if (statement is CallStatementSyntax) {
				origin_expression (((CallStatementSyntax) statement).call, bindings);
			} else if (statement is AwaitStatementSyntax) {
				origin_expression (((AwaitStatementSyntax) statement).expression, bindings);
			} else if (statement is ReturnStatementSyntax) {
				var node = origin_expression (((ReturnStatementSyntax) statement).expression, bindings);
				var result = signature_origins.lookup (function);
				if (result != null) {
					result.include (node);
				}
			} else if (statement is ThrowStatementSyntax) {
				origin_expression (((ThrowStatementSyntax) statement).expression, bindings);
			} else if (statement is IfStatementSyntax) {
				var branch = (IfStatementSyntax) statement;
				origin_expression (branch.condition, bindings);
				int constant = GenericSourceResultOrigins.literal_condition (branch.condition);
				if (constant != 0) {
					origin_block (branch.then_body, function, bindings);
				}
				if (constant != 1 && branch.else_body != null) {
					origin_block (branch.else_body, function, bindings);
				}
			} else if (statement is WithStatementSyntax) {
				var scoped = (WithStatementSyntax) statement;
				var nested = new GenericArray<StatementSyntax> ();
				if (scoped.initializer != null) {
					nested.add (scoped.initializer);
				}
				nested.add (scoped.body);
				origin_statements (nested, function, bindings);
			} else if (statement is ForeachStatementSyntax) {
				var loop = (ForeachStatementSyntax) statement;
				origin_expression (loop.collection, bindings);
				origin_block (loop.body, function, bindings);
			} else if (statement is ForStatementSyntax) {
				var loop = (ForStatementSyntax) statement;
				var nested = new GenericArray<StatementSyntax> ();
				if (loop.initializer != null) {
					nested.add (loop.initializer);
				}
				if (GenericSourceResultOrigins.literal_condition (loop.condition) != 0) {
					nested.add (loop.body);
					if (loop.step != null) {
						nested.add (loop.step);
					}
				}
				origin_statements (nested, function, bindings, loop.condition);
			} else if (statement is WhileStatementSyntax) {
				var loop = (WhileStatementSyntax) statement;
				origin_expression (loop.condition, bindings);
				if (GenericSourceResultOrigins.literal_condition (loop.condition) != 0) {
					origin_block (loop.body, function, bindings);
				}
			} else if (statement is TryStatementSyntax) {
				var guarded = (TryStatementSyntax) statement;
				origin_block (guarded.body, function, bindings);
				foreach (var caught in guarded.catches) {
					origin_block (caught.body, function, bindings);
				}
			} else if (statement is MatchStatementSyntax) {
				origin_match ((MatchStatementSyntax) statement, function, bindings);
			}
		}
		origin_expression (condition, bindings);
		origin_record_types = incoming_records;
	}
	private void seed_origin_signature(FunctionSymbol function) {
		bool heap_boundary = function.foreign_heap_boundary;
		if (native_heap_boundaries != null) {
			foreach (var declaration in native_heap_boundaries) {
				var span = declaration.name.span;
				if (span.file == function.name_span.file && span.start == function.name_span.start && span.end == function.name_span.end) {
					heap_boundary = true;
					break;
				}
			}
		}
		if (function.result_class != null && !signature_origins.contains (function)) {
			var origin = origin_constraint (function.result_class, ((ClassType) function.return_type).intrinsically_shared ? 2 : 0);
			origin.requires_heap = heap_boundary || ((ClassType) function.return_type).intrinsically_shared;
			signature_origins.insert (function, origin);
		}
		if (function.result_class != null && heap_boundary) {
			signature_origins.lookup (function).requires_heap = true;
		}
		foreach (var parameter in function.parameters) {
			if (!(parameter.semantic_type is ClassType) || parameter.semantic_type.is_parameterized ()) {
				continue;
			}
			if (signature_origins.contains (parameter)) {
				if (heap_boundary && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					signature_origins.lookup (parameter).requires_heap = true;
				}
				continue;
			}
			var owner = (ClassSymbol) instance_for (parameter.semantic_type);
			var origin = origin_constraint (owner, parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER ? 0 : 1);
			origin.requires_heap = (heap_boundary || ((ClassType) parameter.semantic_type).intrinsically_shared || function.async_body != null && function.async_body.runtime.threaded) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER;
			signature_origins.insert (parameter, origin);
		}
	}

	private void queue_origin_function(FunctionSymbol function, BlockStatementSyntax body, bool async_declaration = false) {
		seed_origin_signature (function);
		if (async_declaration) {
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is ClassType && !parameter.semantic_type.is_parameterized () && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					signature_origins.lookup (parameter).requires_heap = true;
				}
			}
		}
		if (queued_origin_functions.contains (function)) {
			return;
		}
		queued_origin_functions.insert (function, true);
		origin_functions.add (function);
		origin_bodies.add (body);
	}

	private void queue_origin_inventory(SyntaxProgram syntax, GenericArray<DirectCallableSymbol> declarations, GenericArray<NativeInstanceSymbol> instances) {
		for (int i = 0; i < declarations.length; i++) {
			if (declarations[i] is FunctionSymbol) {
				queue_origin_function ((FunctionSymbol) declarations[i], syntax.functions[i].body, syntax.functions[i].is_async);
			}
		}
		for (int i = 0; i < instances.length; i++) {
			foreach (var method in instances[i].methods) {
				queue_origin_function (method, method_syntax.lookup (method).body);
			}
			foreach (var member in instance_syntax[i].members) {
				var lifecycle = member as LifecycleDeclarationSyntax;
				if (lifecycle != null) {
					var owner = (ClassSymbol) instances[i];
					queue_origin_function (lifecycle.is_constructor ? (FunctionSymbol) owner.constructor : owner.destructor, lifecycle.body);
				}
				var property = member as PropertyDeclarationSyntax;
				if (property != null) {
					var symbol = instances[i].find_property (property.name.spelling ());
					queue_origin_function (symbol.getter, property.getter.body);
					if (property.setter != null) {
						queue_origin_function (symbol.setter, property.setter.body);
					}
				}
			}
		}
	}

	private bool resolve_object_origins(SyntaxProgram syntax, GenericArray<DirectCallableSymbol> declarations, GenericArray<NativeInstanceSymbol> instances) {
		if (draining_object_origins) {
			return true;
		}
		origin_program = syntax;
		origin_declarations = declarations;
		draining_object_origins = true;
		var saved_class = specializing_class;
		var saved_method = specializing_method;
		var saved_parameters = method_type_parameters;
		var saved_lexical = lexical_types;
		var saved_elements = element_obligations;
		var saved_records = origin_record_types;
		var saved_origin_function = origin_function;
		lexical_types = new HashTable<string, TypeParameterSymbol> (str_hash, str_equal);
		bool complete = collect_pending_object_origins (syntax, declarations, instances);
		specializing_class = saved_class;
		specializing_method = saved_method;
		method_type_parameters = saved_parameters;
		lexical_types = saved_lexical;
		element_obligations = saved_elements;
		origin_record_types = saved_records;
		origin_function = saved_origin_function;
		draining_object_origins = false;
		return complete;
	}

	private bool validate_object_composition(GenericArray<NativeInstanceSymbol> instances) {
		foreach (var definition in ordered_enums) {
			for (uint v = 0; v < definition.variant_count; v++) {
				for (uint f = 0; f < definition.variant (v).field_count; f++) {
					var field = definition.variant (v).field (f);
					if (field.owns_scalar && !valid_enum_scalar_owner (field)) {
						fail (field.span, "owned enum scalar payload requires an exact Resource or nonpolymorphic native heap Class");
						return false;
					}
				}
			}
		}
		foreach (var instance in instances) {
			foreach (var field in instance.fields) {
				var slots = field.semantic_type as OwnerSlotsType;
				if (slots == null) {
					continue;
				}
				var element = instance_for (slots.element) as ClassSymbol;
				bool valid_element = slots.element.get_type () == typeof (HandleType);
				if (slots.element is StructType) {
					valid_element = copy_fields (slots.element) != null;
				}
				if (slots.element is ClassType) {
					valid_element = element != null && !element.polymorphic && element.parent_class == null;
				}
				if (!(instance is ClassSymbol) || ((ClassSymbol) instance).polymorphic || !valid_element) {
					fail (field.span, "owner slots require an exact nonpolymorphic Class owner and supported Class, record or Resource elements");
					return false;
				}
			}
		}
		foreach (var instance in instances) {
			if (instance is ClassSymbol) {
				foreach (var property in instance.properties) {
					var result = instance_for (property.semantic_type) as ClassSymbol;
					if (property.is_owned_lazy && (result == null || result.polymorphic)) {
						fail (property.span, "owned lazy cache requires an exact nonpolymorphic Class result");
						return false;
					}
				}
				foreach (var field in instance.fields) {
					if (field.owns_child && ((ClassSymbol) instance_for (field.semantic_type)).polymorphic) {
						fail (field.span, "owned child fields require an exact nonpolymorphic ClassType");
						return false;
					}
				}
				if (!OwnedChildComposition.acyclic (instance.semantic_type, child_edges)) {
					fail (instance.span, "cyclic owned child composition is unsupported");
					return false;
				}
			}
		}
		return true;
	}

	private bool collect_pending_object_origins(SyntaxProgram syntax, GenericArray<DirectCallableSymbol> declarations, GenericArray<NativeInstanceSymbol> instances) {
		if (!validate_object_composition (instances)) {
			return false;
		}
		queue_origin_inventory (syntax, declarations, instances);
		derive_generic_result_origins ();
		if (diagnostic != null) {
			return false;
		}
		var functions = origin_functions;
		var bodies = origin_bodies;
		for (; origin_body_cursor < functions.length; origin_body_cursor++) {
			int i = origin_body_cursor;
			var function = functions[i];
			origin_function = function;
			lexical_types.remove_all ();
			var generic = function as GenericFunctionSymbol;
			if (generic != null) {
				foreach (var parameter in generic.type_parameters) {
					lexical_types.insert (parameter.name, parameter);
				}
			}
			element_obligations = generic == null ? new GenericSliceObligations () : generic.element_obligations;
			var bindings = new HashTable<string, ObjectOriginConstraint> (str_hash, str_equal);
			var method = function as MethodSymbol;
			var lifecycle = function as LifecycleSymbol;
			var property = function as PropertyAccessorSymbol;
			var owner = (method != null ? method.declaring_type : lifecycle != null ? lifecycle.declaring_class : property == null ? null : property.property_symbol.declaring_type) as ClassSymbol;
			specializing_class = owner;
			specializing_method = method == null ? null : method.generic_method_instance;
			method_type_parameters = specializing_method == null ? new string[0] : method_parameter_names (method_syntax.lookup (method));
			if (owner != null) {
				bindings.insert ("this", origin_constraint (owner, 1));
			}
			foreach (var parameter in function.parameters) {
				bindings.insert (parameter.name, signature_origins.lookup (parameter));
			}
			var constructor = function as ConstructorSymbol;
			if (constructor != null && constructor.declaring_class.parent_class != null) {
				var initializer = constructor_initializers.lookup (constructor);
				if (initializer.base_arguments != null) {
					origin_arguments (initializer.base_arguments, constructor.declaring_class.parent_class.constructor, bindings);
				}
			}
			origin_block (bodies[i], function, bindings);
			if (diagnostic != null || !drain_class_declarations ()) {
				return false;
			}
			queue_origin_inventory (syntax, declarations, instances);
		}
		if (!validate_object_composition (instances)) {
			return false;
		}
		lexical_types.remove_all ();
		specializing_class = null;
		specializing_method = null;
		method_type_parameters = {};
		foreach (var node in origin_constraints) {
			node.domains = node.intrinsic_domains;
		}
		// Least fixed point first; ungrounded legacy domains then seed lexical.
		// Required field authority constrains uncalled/forwarded signatures;
		// explicit lexical producers still retain their conflicting origin.
		bool required_changed = false;
		do {
			required_changed = false;
			foreach (var node in origin_constraints) {
				if (node.requires_heap) {
					node.domains |= 2;
					foreach (var input in node.inputs) {
						if (!input.requires_heap) {
							input.requires_heap = true;
							required_changed = true;
						}
					}
				}
			}
		} while (required_changed);
		// A second fixed point exposes mixed callers/forwarding components.
		for (int phase = 0; phase < 2; phase++) {
			bool changed = false;
			do {
				changed = false;
				foreach (var node in origin_constraints) {
					int domains = node.domains;
					foreach (var input in node.inputs) {
						domains |= input.domains;
					}
					if (domains != node.domains) {
						node.domains = domains;
						changed = true;
					}
				}
			} while (changed);
			if (phase == 0) {
				foreach (var node in origin_constraints) {
					if (node.domains == 0) {
						node.domains = 1;
					}
				}
			}
		}
		// Keep equations for later closed requests; the analyzer destructor breaks cycles.
		foreach (var function in functions) {
			var result = signature_origins.lookup (function);
			if (result != null) {
				var generic = function as GenericFunctionSymbol;
				if (generic != null && (generic.result_origins.domains & GenericResultOrigins.UNKNOWN) != 0) {
					var arguments = new GenericArray<SemanticType> ();
					foreach (var parameter in generic.type_parameters) {
						arguments.add (parameter.semantic_type);
					}
					var equation = project_source_result (generic, arguments);
					if (diagnostic != null) {
						return false;
					}
					if ((equation.domains & GenericResultOrigins.UNKNOWN) == 0) {
						generic.result_origins = equation;
						var heaps = new bool[function.parameters.length];
						foreach (var parameter in function.parameters) {
							var input = signature_origins.lookup (parameter);
							heaps[parameter.ordinal] = input != null && input.domains == 2;
						}
						result.domains = (int) equation.evaluate (heaps);
					}
				}
				bool deferred = deferred_class_result (function);
				if (result.domains == 3 && !deferred) {
					fail (function.span, "owned Class result joins incompatible heap and caller-backed storage origins");
					return false;
				}
				function.heap_result = !deferred && result.domains == 2;
				if (function.heap_result) {
					function.result_storage = null;
				} else if (function.result_storage == null) {
					function.result_storage = new ResultObjectStorageSymbol (function.result_class);
				}
				if (function.throws_type != null && !function.heap_result && !deferred) {
					fail (function.span, "throwing caller-backed Class result requires a heap-origin factory");
					return false;
				}
			}
			foreach (var parameter in function.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !(parameter.semantic_type is ClassType) || parameter.semantic_type.is_parameterized ()) {
					continue;
				}
				var node = signature_origins.lookup (parameter);
				if (node.domains == 3) {
					fail (parameter.span, "owned Class parameter joins incompatible heap and lexical storage origins");
					return false;
				}
				parameter.heap_object = node.domains == 2;
			}
		}
		return true;
	}

	private bool slots_candidate(ExpressionSyntax? syntax, ValueScope values) {
		return syntax is FieldAccessExpressionSyntax && field_context_type ((FieldAccessExpressionSyntax) syntax, values) is OwnerSlotsType;
	}
	private bool slots_call(CallExpressionSyntax syntax, ValueScope values) {
		return slots_candidate (syntax.receiver_place, values);
	}
	private CheckedPlace? check_slots_place(ExpressionSyntax syntax, ValueScope values) {
		if (checking_function != null && (checking_function.async_body != null || checking_function is GenericFunctionSymbol)) {
			fail (syntax.span, "owner-slot operations require synchronous concrete native code");
			return null;
		}
		var load = check_field ((FieldAccessExpressionSyntax) syntax, values) as CheckedLoadExpression;
		if (load == null) {
			return null;
		}
		return load.source;
	}
	private CheckedExpression? check_slot_operand(CheckedPlace store, ExpressionSyntax operand, ValueScope values) {
		var field = (store is CheckedReceiverFieldPlace) ? ((CheckedReceiverFieldPlace) store).field : ((CheckedObjectFieldPlace) store).field;
		pending_field_borrows.add (field.containing_type.semantic_type);
		var result = check_expression (operand, values);
		pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		return result;
	}
	private bool slots_mutation(CheckedPlace store, SourceSpan span) {
		if (active_with.length != 0) {
			fail (span, "with receiver scope excludes structural slot mutation");
			return false;
		}
		var field = (store is CheckedReceiverFieldPlace) ? ((CheckedReceiverFieldPlace) store).field : ((CheckedObjectFieldPlace) store).field;
		foreach (var pending in pending_field_borrows) {
			if (field_overlap (field.containing_type.semantic_type, pending)) {
				fail (span, "owner-slot structural mutation overlaps an active indexed/field loan");
				return false;
			}
		}
		return true;
	}


	private SyntaxProgram? source_program;
	private HashTable<string, ModuleBinding> module_types = new HashTable<string, ModuleBinding> (str_hash, str_equal);
	private HashTable<string, ModuleBinding> module_values = new HashTable<string, ModuleBinding> (str_hash, str_equal);
	private HashTable<string, bool> module_names = new HashTable<string, bool> (str_hash, str_equal);
	private CompilationUnitSyntax? source_unit(SourceSpan span) {
		if (source_program != null) {
			foreach (var unit in source_program.units) {
				if (unit.span.file == span.file) {
					return unit;
				}
			}
		}
		return null;
	}
	private string source_namespace(SourceSpan span) {
		var unit = source_unit (span);
		return unit == null || unit.namespace_name == null ? "" : unit.namespace_name.spelling ();
	}
	private string declaration_name(Token token) {
		string space = source_namespace (token.span);
		return space == "" ? token.spelling () : space + "." + token.spelling ();
	}
	private void bind_module(Token token, SyntaxNode declaration, bool type) {
		string space = source_namespace (token.span);
		string key = declaration_name (token);
		(type ? module_types : module_values).insert (key, new ModuleBinding (key, space, declaration.module_internal));
	}
	private bool collect_modules(SyntaxProgram source) {
		source_program = source;
		foreach (var unit in source.units) {
			if (unit.namespace_name != null) {
				module_names.insert (unit.namespace_name.spelling (), true);
			}
			foreach (var declaration in unit.native_instances ()) {
				bind_module (declaration.name, declaration, true);
			}
			foreach (var declaration in unit.enums) {
				bind_module (declaration.name, declaration, true);
			}
			foreach (var declaration in unit.functions) {
				bind_module (declaration.name, declaration, false);
			}
			foreach (var declaration in unit.constants) {
				bind_module (declaration.name, declaration, false);
			}
		}
		foreach (var unit in source.units) {
			foreach (var imported in unit.imports) {
				if (!module_names.contains (imported.spelling ())) {
					fail (imported.span, "unknown imported namespace '%s'; supply its source files explicitly".printf (imported.spelling ()));
					return false;
				}
			}
		}
		return true;
	}
	// Lookup returns canonical keys; the original source remains diagnostic and
	// caller-information provenance. Imports never create new symbol identities.
	private string resolve_name(SourceSpan span, string name, bool type = true) {
		var entries = type ? module_types : module_values;
		string space = source_namespace (span);
		if (name.contains (".")) {
			var direct = entries.lookup (name);
			if (direct != null && direct.restricted && direct.space != space) {
				fail (span, "internal declaration '%s' is accessible only within namespace '%s'".printf (name, direct.space));
				return "<inaccessible>";
			}
			return name;
		}
		if (space != "" && entries.contains (space + "." + name)) {
			return space + "." + name;
		}
		ModuleBinding? selected = null;
		var unit = source_unit (span);
		if (unit != null) {
			foreach (var imported in unit.imports) {
				var candidate = entries.lookup (imported.spelling () + "." + name);
				if (candidate == null) {
					continue;
				}
				if (candidate.restricted && candidate.space != space) {
					continue;
				}
				if (selected != null && selected != candidate) {
					fail (span, "ambiguous imported name '%s': '%s' and '%s'; qualify the reference".printf (name, selected.name, candidate.name));
					return "<ambiguous>";
				}
				selected = candidate;
			}
		}
		return selected == null ? name : selected.name;
	}
	private ConstantSymbol? qualified_constant(FieldAccessExpressionSyntax field, ValueScope values) {
		if (field.aggregate != null || field.indirect || field.identifier == null || values.lookup (field.identifier.spelling ()) != null || !module_names.contains (field.identifier.spelling ())) {
			return null;
		}
		return constant_scope == null ? null : constant_scope.lookup (resolve_name (field.span, field.identifier.spelling () + "." + field.field_name.spelling (), false)) as ConstantSymbol;
	}
	private bool visible_nominal(SourceSpan span, string name) {
		string key = resolve_name (span, name);
		return named_types.contains (key) || generic_struct_names.contains (key) || generic_class_names.contains (key);
	}
	// Origin collection precedes lexical generic body checking. Consult only
	// already-established Class identities; resolving arbitrary body types here
	// would diagnose symbolic T or Struct<T> before their real checking scope.
	private ClassSymbol? origin_class(TypeNameSyntax syntax) {
		var application = syntax as GenericTypeApplicationSyntax;
		if (application != null) {
			var definition = generic_class_names.lookup (type_key (application));
			if (definition == null) {
				return null;
			}
			var saved = diagnostic;
			var type = resolve_type (application);
			if (type == null) {
				diagnostic = saved;
				return null;
			}
			return instance_for (type) as ClassSymbol;
		}
		if (syntax.get_type () != typeof (TypeNameSyntax) || syntax.stars.length != 0) {
			return null;
		}
		return instance_names.lookup (type_key (syntax)) as ClassSymbol;
	}
	private ClassSymbol? qualified_class(CallExpressionSyntax call, bool origin = false) {
		if (call.receiver == null) {
			return null;
		}
		if (call.qualifier_arguments.length == 0) {
			return find_instance (call.receiver) as ClassSymbol;
		}
		if (!generic_class_names.contains (resolve_name (call.receiver.span, call.receiver.spelling ()))) {
			return null;
		}
		var application = new GenericTypeApplicationSyntax (call.receiver, call.qualifier_arguments, call.span);
		if (origin) {
			return origin_class (application);
		}
		var type = resolve_type (application);
		return type == null ? null : instance_for (type) as ClassSymbol;
	}
	private string type_key(TypeNameSyntax syntax) {
		return resolve_name (syntax.span, syntax.lookup_name ());
	}
	private bool exact_heap_class_argument(SemanticType type) {
		var owner = instance_for (type) as ClassSymbol;
		return owner != null && owner.generic_instance == null && !owner.polymorphic && owner.parent_class == null && !((ClassType) type).is_interface;
	}
	private ExactGenericClassType? request_class(GenericTypeApplicationSyntax application, ExactClassTemplate definition) {
		if (application.type_arguments.length != definition.identity.parameter_count) {
			fail (application.span, "generic Class '%s' requires exactly %d type arguments, found %u".printf (definition.identity.name, definition.identity.parameter_count, application.type_arguments.length));
			return null;
		}
		if (++class_request_depth > 128) {
			class_request_depth--;
			fail (application.span, "generic type-expression depth limit 128 exceeded while instantiating '%s'".printf (definition.identity.name));
			return null;
		}
		var values = new GenericArray<SemanticType> ();
		foreach (var syntax in application.type_arguments) {
			var argument = resolve_type (syntax);
			if (argument == null) {
				class_request_depth--;
				return null;
			}
			values.add (argument);
		}
		class_request_depth--;
		return request_class_arguments (definition, new TypeArgumentVector (values), application.span);
	}

	private NativeInstanceSymbol? instance_for(SemanticType? type) {
		var existing = instance_types.lookup (type);
		if (existing != null || !(type is ExactGenericClassType) || !type.is_parameterized ()) {
			return existing;
		}
		var application = (ExactGenericClassType) type;
		var definition = generic_class_names.lookup (application.definition.name);
		if (definition == null) {
			return null;
		}
		if (++class_request_depth > 128) {
			class_request_depth--;
			fail (definition.syntax.span, "generic Class type argument nesting exceeds 128");
			return null;
		}
		var owner = new ClassSymbol.specialized (definition.syntax.span, definition.syntax.name.span, application, -1);
		owner.generic_instance = new ExactClassGenericInstance.application (application.definition, application.arguments, application);
		instance_types.insert (application, owner);
		class_applications.add (owner);
		var saved = specializing_class;
		// Open applications carry the declaration's authority while checking
		// generic helpers, just as closed applications do on the worklist.
		bool complete = bind_class_allocation (owner, definition.syntax) && collect_instance_fields (owner, definition.syntax);
		if (complete) {
			// Cleanup authority belongs to every declared owned child, even
			// when this helper only observes one of its sibling fields.
			foreach (var field in owner.fields) {
				if (field.owns_child && field.semantic_type.is_parameterized () && instance_for (field.semantic_type) == null) {
					complete = false;
					break;
				}
			}
		}
		if (complete) {
			// A symbolic application owns member signatures, never specialized
			// bodies. Signature collection must not clear its caller's scope.
			var saved_lexical = lexical_types;
			lexical_types = new HashTable<string, TypeParameterSymbol> (str_hash, str_equal);
			foreach (var parameter in saved_lexical.get_values ()) {
				lexical_types.insert (parameter.name, parameter);
			}
			complete = collect_instance_members (owner, definition.syntax);
			lexical_types = saved_lexical;
		}
		specializing_class = saved;
		class_request_depth--;
		return complete ? owner : null;
	}

	private SemanticType? materialize_owning_record(GenericStructApplicationType application, SourceSpan span) {
		var definition = application.definition;
		if (definition == null || !definition.owning_storage || !definition.fields_complete || application.is_parameterized () || class_requests == null) {
			fail (span, "owning generic records require a complete closed storage application");
			return null;
		}
		if (active_owning_records.contains (application)) {
			fail (span, "recursive generic struct layout: " + application.display_name ());
			return null;
		}
		var prior = definition.owning_instances.lookup (application);
		if (prior != null) {
			return prior.semantic_type;
		}
		if (active_owning_records.size () >= 256 || next_owned_record_ordinal >= GenericResourceLimits.CLOSED_INSTANCES) {
			fail (span, "owning generic record materialization limit exceeded");
			return null;
		}
		var syntax = owning_record_syntax.lookup (definition);
		var owner = new StructSymbol (definition.span, definition.name_span, next_owned_record_ordinal++, application.display_name ());
		((StructType) owner.semantic_type).bind_generic_application (definition.nominal_identity, application.type_arguments);
		((StructType) owner.semantic_type).bind_owning_application (new OwnedRecordApplicationContract (definition.owning_contract, application.type_arguments));
		owner.owning_instantiation = new OwnedRecordInstantiation (definition, application.type_arguments);
		definition.owning_instances.insert (application, owner);
		instance_types.insert (owner.semantic_type, owner);
		instance_names.insert (owner.name, owner);
		class_requests.add (owner);
		class_request_syntax.add (syntax);
		active_owning_records.insert (application, true);
		var substitution = definition.substitution (application.type_arguments);
		foreach (var field in definition.fields) {
			SemanticType? type = substitution.apply (field.semantic_type);
			var nested = type as GenericStructApplicationType;
			if (nested != null && nested.definition.owning_storage) {
				type = materialize_owning_record (nested, span);
			}
			if (type == null) {
				return null;
			}
			var concrete = new StructFieldSymbol (field.span, field.name_span, owner, type, field.ordinal, field.is_private);
			if (field.owns_parameter) {
				if (type is ClassType) {
					concrete.owns_child = true;
				} else if (type is HandleType && handle_types.contains (type)) {
					concrete.owned_cleanup = handle_types.lookup (type).cleanup;
				} else {
					fail (span, "owning record substitution lost its exact declared owner capability");
					return null;
				}
			} else {
				concrete.owns_child = field.owns_child;
				concrete.owns_buffer = field.owns_buffer;
				concrete.owned_cleanup = field.owned_cleanup;
			}
			owner.fields.add (concrete);
		}
		active_owning_records.remove (application);
		collected_instance_fields.insert (owner, true);
		aggregate_owner_flow_needed = true;
		return owner.semantic_type;
	}

	private ExactGenericClassType substitute_class(ExactGenericClassType original, TypeArgumentVector arguments) {
		var definition = generic_class_names.lookup (original.definition.name);
		if (definition == null) {
			return original;
		}
		return request_class_arguments (definition, arguments, definition.syntax.span) ?? original;
	}

	private ExactGenericClassType? request_class_arguments(ExactClassTemplate definition, TypeArgumentVector arguments, SourceSpan span) {
		if (definition.identity.structure != null) {
			for (int c = 0; c < definition.identity.structure.constraint_count; c++) {
				var constraint = definition.identity.structure.constraint (c);
				if (!GenericClassDeclaredShape.constraint (constraint, arguments)) {
					fail (span, constraint.exact_heap_class ? "ExactHeapClass requires a concrete nongeneric native Class argument" : "generic Class type arguments do not satisfy the declared capability constraint");
					return null;
				}
			}
		}
		if (definition.identity.structure == null) {
			var argument = arguments.at (0);
			if (!(argument is ClassType) || argument is ExactGenericClassType) {
				fail (span, "ExactHeapClass requires a concrete nongeneric native Class argument");
				return null;
			}
		}
		if (!arguments.closed ()) {
			return definition.open_application (arguments);
		}
		var existing = definition.find_arguments (arguments);
		if (existing != null) {
			return (ExactGenericClassType) existing.semantic_type;
		}
		if (class_requests == null || class_request_syntax == null) {
			fail (span, "generic Class request was not closed before declaration materialization");
			return null;
		}
		if (closed_class_count++ >= GenericResourceLimits.CLOSED_INSTANCES) {
			fail (span, "closed generic Class instance limit %u exceeded while instantiating '%s'".printf (GenericResourceLimits.CLOSED_INSTANCES, definition.identity.name));
			return null;
		}
		var type = new ExactGenericClassType.application (definition.identity, arguments);
		if (!GenericResourceLimits.admits_type (type)) {
			fail (span, "generic materialization limit exceeded: type-expression depth %d while instantiating '%s'".printf (GenericResourceLimits.TYPE_DEPTH, definition.identity.name));
			return null;
		}
		var owner = new ClassSymbol.specialized (definition.syntax.span, definition.syntax.name.span, type, next_class_ordinal++);
		owner.generic_instance = new ExactClassGenericInstance.application (definition.identity, arguments, type);
		definition.instances.add (owner);
		class_requests.add (owner);
		class_request_syntax.add (definition.syntax);
		instance_types.insert (type, owner);
		instance_names.insert (owner.name, owner);
		if (definition.syntax.parent_class != null) {
			var saved = specializing_class;
			specializing_class = owner;
			var parent_type = resolve_type (definition.syntax.parent_class);
			specializing_class = saved;
			var parent = parent_type == null ? null : instance_for (parent_type) as ClassSymbol;
			if (parent == null) {
				if (diagnostic == null) {
					fail (definition.syntax.parent_class.span, "generic Class parent requires a resolved native Class or interface");
				}
				return null;
			}
			owner.parent_class = parent;
			owner.polymorphic = true;
			parent.polymorphic = true;
			type.parent_type = (ClassType) parent.semantic_type;
		}
		if (class_declarations_ready && !drain_class_declarations ()) {
			return null;
		}
		if (origin_program != null && !draining_class_declarations && !draining_object_origins && !resolve_object_origins (origin_program, origin_declarations, class_requests)) {
			return null;
		}
		return type;
	}

	private static bool contains_span(SourceSpan outer, SourceSpan inner) {
		return outer.file == inner.file && outer.start <= inner.start && inner.end <= outer.end;
	}

	private bool substituted_copy_type(TypeNameSyntax syntax, SemanticType? type) {
		if (type == null || specializing_class == null || specializing_class.generic_instance == null || specializing_class.generic_instance.definition.structure == null) {
			return false;
		}
		var definition = generic_class_names.lookup (specializing_class.generic_instance.definition.name);
		bool parameter = false;
		foreach (string name in method_type_parameters) {
			parameter |= syntax.lookup_name () == name;
		}
		foreach (string name in definition.parameters) {
			parameter |= syntax.lookup_name () == name;
		}
		return parameter && (FunctionValueType.symbolic_copy (type) || GenericArgumentTypes.plain_copy (type, copy_fields, copy_premise));
	}
	private DirectCallableSymbol? find_function(Token token) {
		return function_names.lookup (resolve_name (token.span, token.spelling (), false));
	}
	private NativeInstanceSymbol? find_instance(Token token) {
		return instance_names.lookup (resolve_name (token.span, token.spelling ()));
	}
	private SemanticType? find_named(Token token) {
		return named_types.lookup (resolve_name (token.span, token.spelling ()));
	}
	private static string export_name(string canonical) {
		if (!canonical.contains (".")) {
			return canonical;
		}
		var result = new StringBuilder ("astra_ns");
		foreach (string component in canonical.split (".")) {
			result.append ("_%d_%s".printf (component.length, component));
		}
		return result.str;
	}
	private static string c_export_name(FunctionDeclarationSyntax syntax, string canonical) {
		if (syntax.foreign_policy != null) {
			foreach (var entry in syntax.foreign_policy.entries) {
				if (entry.key.spelling () == "name") {
					return entry.decoded_value;
				}
			}
		}
		return export_name (canonical);
	}
	private static CBoolAbi c_bool_abi(FunctionDeclarationSyntax syntax) {
		if (syntax.foreign_policy != null) {
			foreach (var entry in syntax.foreign_policy.entries) {
				if (entry.key.spelling () == "bool_abi") {
					return CBoolAbi.parse (entry.decoded_value);
				}
			}
		}
		return CBoolAbi.NONE;
	}
	private static bool c_value_export(FunctionDeclarationSyntax syntax) {
		var entries = syntax.foreign_policy == null ? syntax.ccode : syntax.foreign_policy.entries;
		if (!syntax.is_c_export || entries == null) {
			return false;
		}
		if (syntax.foreign_policy == null && entries.length != 1) {
			return false;
		}
		foreach (var entry in entries) {
			if (entry.key.spelling () == "record_abi" && entry.decoded_value == "value-lp64") {
				return true;
			}
		}
		return false;
	}

	private int foreign_selection = -1;
	private SemanticAnalyzer () {
	}
	private ToolingIndex? tooling;
	~SemanticAnalyzer () {
		foreach (var node in origin_constraints) {
			while (node.inputs.length != 0) {
				node.inputs.remove_index (node.inputs.length - 1);
			}
		}
	}

	public static SemanticResult analyze(CompilationUnitSyntax unit, GenericArray<ForeignDeclarationInput>? foreign_inputs = null, GenericArray<ForeignHandleInput>? handle_inputs = null) {
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (unit);
		try {
			return analyze_program (new SyntaxProgram (units), foreign_inputs, handle_inputs);
		} catch (SourceSetError error) {
			GLib.error ("single source: %s", error.message);
		}
	}

	private GenericArray<FunctionDeclarationSyntax>? native_heap_boundaries;
	private NativeDeclarationRegistry? native_declarations;
	private bool native_body(FunctionSymbol function) {
		if (!function.name_span.file.native_interface) {
			return false;
		}
		if (native_declarations == null || native_declarations.lookup (function) == null) {
			fail (function.name_span, "unexpected imported native callable");
			return false;
		}
		return true;
	}
	private static CheckedBlockStatement native_block(SourceSpan span) {
		return new CheckedBlockStatement (span, new GenericArray<CheckedStatement> (), new LexicalRegion (null, 0));
	}
	public static SemanticResult analyze_program(SyntaxProgram syntax, GenericArray<ForeignDeclarationInput>? foreign_inputs = null, GenericArray<ForeignHandleInput>? handle_inputs = null, ToolingIndex? tooling = null, GenericArray<FunctionDeclarationSyntax>? native_heap_boundaries = null, NativeDeclarationRegistry? native_declarations = null, int foreign_selection = -1) {
		var analyzer = new SemanticAnalyzer ();
		analyzer.foreign_selection = foreign_selection;
		analyzer.tooling = tooling;
		analyzer.native_heap_boundaries = native_heap_boundaries;
		analyzer.native_declarations = native_declarations;
		var program = analyzer.check_program (syntax, foreign_inputs, handle_inputs);
		// Projection substitutions own callbacks into this analyzer. Drop the
		// analysis-only cache before returning, on success and on diagnostics.
		analyzer.projected_origin_requests.remove_range (0, analyzer.projected_origin_requests.length);
		analyzer.projected_origin_registry.remove_all ();
		return new SemanticResult (program, analyzer.diagnostic);
	}

	private void fail(SourceSpan span, string message) {
		if (diagnostic == null) {
			diagnostic = new Diagnostic (span, message);
		}
	}

	private void fail_duplicate(SourceSpan span, owned string message, SourceSpan previous) {
		if (span.file != previous.file) {
			int line;
			int column;
			previous.file.locate (previous.start, out line, out column);
			message += "\nprevious declaration: %s:%d:%d".printf (previous.file.path, line, column);
		}
		fail (span, message);
	}

	// Collect every syntactically present dependency before evaluating any
	// value. Both lazy operands pass this same closed-subset authority.
	private bool constant_dependencies(ExpressionSyntax syntax, ValueScope values, GenericArray<ConstantDependency>? dependencies = null) {
		if (syntax is TextLiteralExpressionSyntax || syntax is IntegerLiteralExpressionSyntax || syntax is FloatLiteralExpressionSyntax || syntax is BooleanLiteralExpressionSyntax) {
			return true;
		}
		if (syntax is NameExpressionSyntax) {
			string name = ((NameExpressionSyntax) syntax).identifier.spelling ();
			var symbol = values.lookup (name) ?? values.lookup (resolve_name (syntax.span, name, false));
			if (symbol == null) {
				fail (syntax.span, "unknown name '%s' in constant expression".printf (name));
				return false;
			}
			if (!(symbol is ConstantSymbol)) {
				fail (syntax.span, "nonconstant dependency '%s': runtime bindings cannot supply a constant expression".printf (name));
				return false;
			}
			if (dependencies != null) {
				dependencies.add (new ConstantDependency (constant_indices.lookup ((ConstantSymbol) symbol), syntax.span));
			}
			return true;
		}
		if (syntax is TextMemberExpressionSyntax && ((TextMemberExpressionSyntax) syntax).member.spelling () == "byte_length") {
			return constant_dependencies (((TextMemberExpressionSyntax) syntax).receiver, values, dependencies);
		}
		if (syntax is FieldAccessExpressionSyntax) {
			var constant = qualified_constant ((FieldAccessExpressionSyntax) syntax, values);
			if (constant != null) {
				if (dependencies != null) {
					dependencies.add (new ConstantDependency (constant_indices.lookup (constant), syntax.span));
				}
				return true;
			}
			var field = (FieldAccessExpressionSyntax) syntax;
			if (!field.indirect && field.aggregate == null && field.field_name.spelling () == "byte_length") {
				return constant_dependencies (new NameExpressionSyntax (field.identifier), values, dependencies);
			}
		}
		if (syntax is ParenthesizedExpressionSyntax) {
			return constant_dependencies (((ParenthesizedExpressionSyntax) syntax).expression, values, dependencies);
		}
		if (syntax is PrefixExpressionSyntax) {
			return constant_dependencies (((PrefixExpressionSyntax) syntax).operand, values, dependencies);
		}
		if (syntax is ConversionExpressionSyntax) {
			return constant_dependencies (((ConversionExpressionSyntax) syntax).operand, values, dependencies);
		}
		if (syntax is ShortCircuitExpressionSyntax) {
			var lazy = (ShortCircuitExpressionSyntax) syntax;
			return constant_dependencies (lazy.left, values, dependencies) && constant_dependencies (lazy.right, values, dependencies);
		}
		if (syntax is ComparisonChainSyntax) {
			foreach (var operand in ((ComparisonChainSyntax) syntax).operands) {
				if (!constant_dependencies (operand, values, dependencies)) {
					return false;
				}
			}
			return true;
		}
		if (syntax is BinaryExpressionSyntax) {
			var binary = (BinaryExpressionSyntax) syntax;
			return constant_dependencies (binary.left, values, dependencies) && constant_dependencies (binary.right, values, dependencies);
		}
		fail (syntax.span, "unsupported constant expression: only scalar literals, constants, scalar operators and explicit scalar conversions are permitted; calls, memory, allocation and ownership operations are excluded");
		return false;
	}

	private ConstantValue? check_constant_expression(ExpressionSyntax syntax, ValueScope values, SemanticType? expected, string context) {
		if (!constant_dependencies (syntax, values)) {
			return null;
		}
		bool previous = checking_constant;
		checking_constant = true;
		var checked = check_expression (syntax, values, expected);
		checking_constant = previous;
		if (checked == null) {
			return null;
		}
		if (!ConstantValue.supports (checked.semantic_type)) {
			fail (syntax.span, "unsupported constant type '%s' in %s".printf (checked.semantic_type.display_name (), context));
			return null;
		}
		if (expected != null && checked.semantic_type != expected) {
			fail (syntax.span, "expected constant initializer of type '%s', found '%s'".printf (expected.display_name (), checked.semantic_type.display_name ()));
			return null;
		}
		var evaluator = new ConstantEvaluator (context);
		var value = evaluator.evaluate (checked);
		if (value == null) {
			fail (evaluator.diagnostic.span, evaluator.diagnostic.message);
		}
		return value;
	}

	private SemanticType? resolve_constant_type(TypeNameSyntax syntax, ValueScope values) {
		// Excluded type components (including aggregate extents) must never
		// evaluate a pending constant, even inside a conversion destination.
		if (syntax is ArrayTypeSyntax || syntax is SliceTypeSyntax || syntax is VectorTypeSyntax || syntax is PointerTypeSyntax || syntax is GenericTypeApplicationSyntax || syntax.stars.length != 0) {
			fail (syntax.span, "unsupported constant type '%s'; const requires a concrete scalar type".printf (syntax.spelling ()));
			return null;
		}
		var type = resolve_type (syntax, values);
		if (type != null && !ConstantValue.supports (type)) {
			fail (syntax.span, "unsupported constant type '%s'; const requires bool, a supported integer, f32 or f64".printf (type.display_name ()));
			return null;
		}
		return type;
	}

	private bool evaluate_constant(ConstantSymbol symbol, ValueScope values) {
		var syntax = symbol.declaration;
		var type = syntax.type_name == null ? null : resolve_constant_type (syntax.type_name, values);
		if (syntax.type_name != null && type == null) {
			return false;
		}
		var value = check_constant_expression (syntax.initializer, values, type, "constant '%s'".printf (symbol.name));
		if (value == null) {
			return false;
		}
		symbol.value = value;
		symbol.state = ConstantState.COMPLETE;
		return true;
	}

	private CheckedStatement? check_local_constant(ConstantDeclarationSyntax syntax, ValueScope values) {
		string name = syntax.name.spelling ();
		var previous = values.lookup (name) ?? values.lookup (resolve_name (syntax.name.span, name, false)) ?? (Symbol?) find_function (syntax.name);
		if (previous != null) {
			fail_duplicate (syntax.name.span, "constant '%s' conflicts with a visible binding or callable".printf (name), previous.name_span);
			return null;
		}
		var symbol = new ConstantSymbol (syntax, values.region);
		if (!evaluate_constant (symbol, values)) {
			return null;
		}
		values.insert (name, symbol);
		return new CheckedConstantDeclaration (symbol);
	}

	private bool collect_constants(SyntaxProgram syntax) {
		constant_scope = new ValueScope (null, new LexicalRegion (null, 0));
		foreach (var declaration in syntax.constants) {
			string name = declaration_name (declaration.name);
			var previous = constant_scope.lookup (name) ?? (Symbol?) function_names.lookup (name);
			if (previous != null) {
				fail_duplicate (declaration.name.span, "duplicate constant or callable '%s'".printf (name), previous.name_span);
				return false;
			}
			var symbol = new ConstantSymbol (declaration, null, name);
			constant_indices.insert (symbol, (int) constants.length);
			constants.add (symbol);
			constant_scope.insert (name, symbol);
		}
		var graph = new GenericArray<ConstantEdges> ();
		foreach (var symbol in constants) {
			var edges = new ConstantEdges ();
			if (!constant_dependencies (symbol.declaration.initializer, constant_scope, edges.dependencies)) {
				return false;
			}
			graph.add (edges);
		}
		// Explicit DFS frames avoid call-stack growth on finite dependency
		// graphs. Edges contain indices, never owning symbol cycles.
		var stack = new GenericArray<ConstantFrame> ();
		for (int root = 0; root < constants.length; root++) {
			if (constants[root].state == ConstantState.COMPLETE) {
				continue;
			}
			constants[root].state = ConstantState.VISITING;
			stack.add (new ConstantFrame (root));
			while (stack.length != 0) {
				var frame = stack[stack.length - 1];
				var edges = graph[frame.index].dependencies;
				if (frame.next < edges.length) {
					var edge = edges[frame.next++];
					var target = constants[edge.index];
					if (target.state == ConstantState.COMPLETE) {
						continue;
					}
					if (target.state == ConstantState.VISITING) {
						var message = new StringBuilder ("constant dependency cycle");
						bool involved = false;
						foreach (var active in stack) {
							if (active.index == edge.index) {
								involved = true;
							}
							if (!involved) {
								continue;
							}
							var member = constants[active.index];
							int line;
							int column;
							member.name_span.file.locate (member.name_span.start, out line, out column);
							message.append ("\nconstant '%s': %s:%d:%d".printf (member.name, member.name_span.file.path, line, column));
						}
						fail (edge.span, message.str);
						return false;
					}
					target.state = ConstantState.VISITING;
					stack.add (new ConstantFrame (edge.index));
				} else {
					if (!evaluate_constant (constants[frame.index], constant_scope)) {
						return false;
					}
					stack.remove_index (stack.length - 1);
				}
			}
		}
		return true;
	}

	private int constant_extent(ExpressionSyntax syntax, ValueScope? values) {
		var value = check_constant_expression (syntax, values ?? constant_scope ?? new ValueScope (null, new LexicalRegion (null, 0)), null, "fixed-array extent");
		if (value == null) {
			if (diagnostic != null) {
				diagnostic = new Diagnostic (diagnostic.span, (syntax is IntegerLiteralExpressionSyntax) ? "ARRAY-1 array length must be in 1..1024 (current implementation bound)" : "invalid array extent (requires integer constant in 1..1024): " + diagnostic.message);
			}
			return 0;
		}
		if (value.integer == null || value.integer.bits == 0 || !value.integer.fits_nonnegative (ArrayType.MAX_LENGTH)) {
			fail (syntax.span, "ARRAY-1 array length must be in 1..1024 (current implementation bound)");
			return 0;
		}
		return (int) value.integer.bits;
	}

	private SemanticType? resolve_contract_type(TypeNameSyntax syntax, ValueScope? values = null) {
		if (!(syntax is NonNullTypeSyntax)) {
			return resolve_type (syntax, values);
		}
		var type = resolve_type (((NonNullTypeSyntax) syntax).underlying, values);
		if (type == null) {
			return null;
		}
		if (!NonNullReferenceTypes.supports (type)) {
			fail (syntax.span, "nonnull requires an exact concrete Class or Resource reference, closed general Class, interface borrow or native Fn; raw, Weak and open generic strengthening is excluded");
			return null;
		}
		return type;
	}
	private SemanticType? callable_result(TypeNameSyntax syntax, out ResultOwnershipContract contract, string invalid_result) {
		var channel = syntax as CallableChannelTypeSyntax;
		contract = channel != null && channel.keyword.kind == TokenKind.OWNED ? ResultOwnershipContract.OWNED_TRANSFER : ResultOwnershipContract.UNMANAGED;
		if (channel != null && channel.keyword.kind != TokenKind.OWNED) {
			fail (syntax.span, "callable borrowed results require an explicit result lifetime contract");
			return null;
		}
		var result = resolve_type (channel == null ? syntax : channel.underlying);
		if (result == null) {
			return null;
		}
		if (!FunctionValueType.supported_result (result, contract)) {
			fail (syntax.span, invalid_result);
			return null;
		}
		return result;
	}

	private OwnedValueProducer? callable_owned_result(CallableSignature signature, SemanticType result, SourceSpan span, bool acquire) {
		if (signature.result_contract != ResultOwnershipContract.OWNED_TRANSFER) {
			return null;
		}
		if (!acquire) {
			fail (span, "owned callable result requires a complete owned value consumer");
			return null;
		}
		if (GenericBorrowTypes.symbolic (result)) {
			return new OwnedValueProducer (OwnedProducerKind.NATIVE_OWNED_CALL, result, null);
		}
		if (result is ClassType) {
			var owner = instance_for (result) as ClassSymbol;
			if (owner == null) {
				fail (span, "owned callable Class result requires its exact nominal declaration");
				return null;
			}
			return new OwnedValueProducer (OwnedProducerKind.NATIVE_OWNED_CALL, result, null, owner);
		}
		var owner = handle_types.lookup (result);
		if (owner == null || result.get_type () != typeof (HandleType)) {
			fail (span, "owned callable result requires its exact nominal Resource cleanup");
			return null;
		}
		return new OwnedValueProducer (OwnedProducerKind.NATIVE_OWNED_CALL, result, owner.cleanup);
	}

	private bool callable_parameters(GenericTypeApplicationSyntax application, int first, string kind, out GenericArray<SemanticType> parameters, out GenericArray<PointerParameterContract> contracts) {
		parameters = new GenericArray<SemanticType> ();
		contracts = new GenericArray<PointerParameterContract> ();
		for (int p = first; p < application.type_arguments.length; p++) {
			var channel = application.type_arguments[p] as CallableChannelTypeSyntax;
			var parameter = resolve_type (channel == null ? application.type_arguments[p] : channel.underlying);
			if (parameter == null) {
				return false;
			}
			bool owned = channel != null && channel.keyword.kind == TokenKind.OWNED;
			if (channel != null && !check_generic_position (parameter, owned, !owned, channel.span)) {
				return false;
			}
			if (owned && !(parameter is ClassType) && parameter.get_type () != typeof (HandleType) && !GenericBorrowTypes.symbolic (parameter)) {
				fail (channel.span, "owned callable parameter requires its exact Class or Resource transfer contract");
				return false;
			}
			bool borrowed = channel != null && !owned && (parameter is ClassType || parameter.get_type () == typeof (HandleType) || GenericBorrowTypes.symbolic (parameter) || parameter.is_struct_storage () && struct_value_mode (parameter) == StructValueMode.MOVE_VALUE);
			if (!FunctionValueType.scalar (parameter) && !parameter.is_struct_storage () && !FunctionValueType.symbolic_copy (parameter) && !borrowed && !owned) {
				fail (application.span, kind == "Fn" ? "Fn parameters require copied numeric scalars or bool, or an exact copied record" : kind + " arguments require copied scalar types");
				return false;
			}
			parameters.add (parameter);
			contracts.add (owned ? PointerParameterContract.OWNED_TRANSFER : borrowed ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED);
		}
		return true;
	}

	private SemanticType? resolve_type(TypeNameSyntax syntax, ValueScope? values = null) {
		if (syntax is CallableChannelTypeSyntax) {
			fail (syntax.span, "typed callable ownership channel requires its enclosing signature contract");
			return null;
		}
		if (syntax is SharedTypeSyntax) {
			var payload = resolve_type (((SharedTypeSyntax) syntax).payload, values) as ClassType;
			if (payload == null || payload.is_interface || payload is ExactGenericClassType || payload.intrinsically_shared) {
				if (diagnostic == null) {
					fail (syntax.span, "shared requires a nonshared concrete native Class payload; redundant intrusive boxing and unsupported value families are rejected");
				}
				return null;
			}
			return shared_type (payload, false, syntax.span);
		}

		if (syntax is NonNullTypeSyntax) {
			fail (syntax.span, "nonnull requires a qualified parameter, local or result contract");
			return null;
		}
		if (syntax.namespace_qualifier == null && lexical_types.contains (syntax.identifier.spelling ()) && !(syntax is SliceTypeSyntax) && (syntax.stars.length != 0 || syntax is PointerTypeSyntax || syntax is VectorTypeSyntax || syntax is ArrayTypeSyntax)) {
			fail (syntax.span, "GEN-1 type parameters cannot occur inside pointer, array or vector type constructors; only direct T[] is supported");
			return null;
		}
		if (syntax is OwnerSlotsTypeSyntax) {
			var marker = (OwnerSlotsTypeSyntax) syntax;
			var element = resolve_type (marker.element);
			if (element == null) {
				return null;
			}
			if (!(element is ClassType) && !(element is StructType) && element.get_type () != typeof (HandleType)) {
				return resolve_type (new ArrayTypeSyntax.expression (marker.element, new NameExpressionSyntax (marker.marker), marker.close), values);
			}
			if (!slots_field_type_context) {
				fail (syntax.span, "owner-slot types are admitted only as owned native Class fields");
				return null;
			}
			return types.slots_of (element);
		}
		var slice = syntax as SliceTypeSyntax;
		if (slice != null) {
			var element = resolve_type (slice.element_type, values);
			if (element == null) {
				return null;
			}
			if (element.is_parameterized () && (!(element is TypeParameterType) || !element_premise ((TypeParameterType) element))) {
				fail (syntax.span, "generic slice requires a direct plain-copy T with a signature-derived mutable element-storage premise");
				return null;
			}
			if (element_fields_complete && element.is_struct_storage () && !check_collection_element (element, slice.element_type.span)) {
				return null;
			}
			var type = types.slice_of (element);
			if (type == null) {
				fail (slice.element_type.span, "unsupported slice element type '%s'; requires supported numeric storage or a borrowed text descriptor".printf (element.display_name ()));
			}
			return type;
		}
		var array = syntax as ArrayTypeSyntax;
		if (array != null) {
			var element = resolve_type (array.element_type, values);
			if (element == null) {
				return null;
			}
			if (!element.is_directly_dereferenceable_value_type () && !(element.is_struct_storage () && !element.is_parameterized ())) {
				fail (array.element_type.span, "unsupported array element type '%s'; ARRAY-1 requires a numeric scalar or numeric vector".printf (element.display_name ()));
				return null;
			}
			if (element_fields_complete && element.is_struct_storage () && !check_collection_element (element, array.element_type.span)) {
				return null;
			}
			int length = constant_extent (array.extent, values);
			if (diagnostic != null) {
				return null;
			}
			var type = types.array_of (element, length);
			return type;
		}
		var pointer = syntax as PointerTypeSyntax;
		if (pointer != null) {
			if (pointer.pointee is PointerTypeSyntax) {
				fail (syntax.span, "pointer depth greater than one is unsupported");
				return null;
			}
			var pointee = resolve_type (pointer.pointee);
			if (pointee == null) {
				return null;
			}
			return resolve_pointer_type (syntax.span, pointee);
		}
		var vector = syntax as VectorTypeSyntax;
		var application = syntax as GenericTypeApplicationSyntax;
		if (application != null) {
			if (application.namespace_qualifier == null && application.identifier.spelling () == "ContextBytes") {
				if (application.type_arguments.length != 1) {
					fail (syntax.span, "ContextBytes requires one exact owned allocator handle type");
					return null;
				}
				var allocator = resolve_type (application.type_arguments[0]) as HandleType;
				var bytes = allocator == null ? null : types.context_bytes_of (allocator);
				if (bytes == null) {
					fail (syntax.span, "ContextBytes requires a declared owned allocator lifetime/thread contract");
				}
				return bytes;
			}
			if (application.namespace_qualifier == null && application.identifier.spelling () == "CheckedClosure") {
				if (application.type_arguments.length < 3 || application.type_arguments.length > 7) {
					fail (syntax.span, "CheckedClosure requires exact Class environment, exception bound, scalar result and up to four scalar parameters");
					return null;
				}
				var environment = resolve_type (application.type_arguments[0]) as ClassType;
				var error = resolve_exception_type (application.type_arguments[1]);
				ResultOwnershipContract result_contract;
				var result = callable_result (application.type_arguments[2], out result_contract, "CheckedClosure requires exact nongeneric Class environment, nominated exception type and copied scalar signature");
				if (environment == null || !ClosureHandleType.supports_environment (environment) || error == null || result == null) {
					if (diagnostic == null) {
						fail (syntax.span, "CheckedClosure requires exact nongeneric Class environment, nominated exception type and copied scalar signature");
					}
					return null;
				}
				GenericArray<SemanticType> parameters;
				GenericArray<PointerParameterContract> contracts;
				if (!callable_parameters (application, 3, "CheckedClosure", out parameters, out contracts)) {
					return null;
				}
				return closure_type (environment, result, parameters, syntax.span, error, false, false, contracts, result_contract);
			}
			if (application.namespace_qualifier == null && application.identifier.spelling () == "ActorSender") {
				if (application.type_arguments.length != 2) {
					fail (syntax.span, "ActorSender requires receiver and message types");
					return null;
				}
				var environment = resolve_type (application.type_arguments[0]) as ClassType;
				var message = resolve_type (application.type_arguments[1]);
				if (environment == null || environment.concurrency_policy_identity != 16 || message == null) {
					fail (syntax.span, "ActorSender requires an exact Actor receiver");
					return null;
				}
				var parameters = new GenericArray<SemanticType> ();
				parameters.add (message);
				var actor = closure_type (environment, types.int_type, parameters, syntax.span, null, false, true);
				if (!actor.supported ()) {
					fail (syntax.span, "Actor message requires copied numeric/bool scalar or exact owned native Class");
					return null;
				}
				return actor;
			}
			if (application.namespace_qualifier == null && application.identifier.spelling () == "Thread") {
				if (application.type_arguments.length != 1) {
					fail (syntax.span, "Thread requires one exact moved environment type");
					return null;
				}
				var environment = resolve_type (application.type_arguments[0]) as ClassType;
				if (environment == null || environment.is_interface || environment is ExactGenericClassType) {
					fail (syntax.span, "Thread requires an exact nongeneric native Class environment");
					return null;
				}
				var parameters = new GenericArray<SemanticType> ();
				parameters.add (types.int_type);
				return closure_type (environment, types.int_type, parameters, syntax.span, null, true);
			}
			if (application.namespace_qualifier == null && application.identifier.spelling () == "Closure") {
				if (application.type_arguments.length < 2 || application.type_arguments.length > 6) {
					fail (syntax.span, "Closure requires an exact Class environment, scalar result and up to four scalar parameters");
					return null;
				}
				var environment = resolve_type (application.type_arguments[0]) as ClassType;
				ResultOwnershipContract result_contract;
				var result = callable_result (application.type_arguments[1], out result_contract, "Closure requires an exact concrete nongeneric Class environment and copied scalar signature");
				if (environment == null || !ClosureHandleType.supports_environment (environment) || result == null) {
					if (diagnostic == null) {
						fail (syntax.span, "Closure requires an exact concrete nongeneric Class environment and copied scalar signature");
					}
					return null;
				}
				GenericArray<SemanticType> parameters;
				GenericArray<PointerParameterContract> contracts;
				if (!callable_parameters (application, 2, "Closure", out parameters, out contracts)) {
					return null;
				}
				return closure_type (environment, result, parameters, syntax.span, null, false, false, contracts, result_contract);
			}
			if (application.identifier.spelling () == "Shared" || application.identifier.spelling () == "Weak") {
				if (application.type_arguments.length != 1) {
					fail (syntax.span, "Shared/Weak requires exactly one concrete native Class argument");
					return null;
				}
				var payload = resolve_type (application.type_arguments[0]) as ClassType;
				if (payload == null || payload.is_interface && !payload.intrinsically_shared || payload is ExactGenericClassType || payload.intrinsically_shared && application.identifier.spelling () == "Shared") {
					if (diagnostic == null) {
						fail (syntax.span, "Shared/Weak payload requires an exact concrete nongeneric native Class");
					}
					return null;
				}
				return shared_type (payload, application.identifier.spelling () == "Weak", syntax.span);
			}
			if (application.namespace_qualifier == null && application.identifier.spelling () == "Callback" && !visible_nominal (application.span, "Callback")) {
				if (application.type_arguments.length < 1 || application.type_arguments.length > 257) {
					fail (syntax.span, "Callback requires a result and up to 256 copied scalar parameters");
					return null;
				}
				ResultOwnershipContract result_contract;
				var result = callable_result (application.type_arguments[0], out result_contract, "Callback requires a copied scalar or void result");
				if (result == null) {
					return null;
				}
				GenericArray<SemanticType> parameters;
				GenericArray<PointerParameterContract> contracts;
				if (!callable_parameters (application, 1, "Callback", out parameters, out contracts)) {
					return null;
				}
				var type = new CallbackType (result, parameters);
				if (result_contract != ResultOwnershipContract.UNMANAGED || !type.supported ()) {
					fail (syntax.span, "Callback channels require copied i32/u32/i64/u64/f32/f64/bool arguments and a scalar or void result");
					return null;
				}
				return types.function_value (result, parameters, null, result_contract, true);
			}
			if (application.namespace_qualifier == null && application.identifier.spelling () == "Fn") {
				if (application.type_arguments.length < 1 || application.type_arguments.length > 5) {
					fail (syntax.span, "Fn requires a result and up to four copied scalar parameters");
					return null;
				}
				ResultOwnershipContract result_contract;
				var result = callable_result (application.type_arguments[0], out result_contract, "Fn result requires a copied numeric scalar or bool, or an exact owned Resource result");
				if (result == null) {
					return null;
				}
				GenericArray<SemanticType> parameters;
				GenericArray<PointerParameterContract> contracts;
				if (!callable_parameters (application, 1, "Fn", out parameters, out contracts)) {
					return null;
				}
				return types.function_value (result, parameters, contracts, result_contract);
			}
			var class_template = generic_class_names.lookup (type_key (application));
			if (class_template != null) {
				return request_class (application, class_template);
			}
			var enumeration = named_types.lookup (type_key (application)) as EnumType;
			if (enumeration != null) {
				return resolve_enum_application (enumeration, application.type_arguments, syntax.span);
			}
			var definition = generic_struct_names.lookup (type_key (application));
			if (definition == null || (application.namespace_qualifier == null && lexical_types.contains (application.identifier.spelling ()))) {
				fail (syntax.span, "type '%s' is not a generic struct definition".printf (application.identifier.spelling ()));
				return null;
			}
			if (application.type_arguments.length != definition.type_parameters.length) {
				fail (syntax.span, "generic struct '%s' requires exactly %u type arguments, found %u".printf (definition.name, definition.type_parameters.length, application.type_arguments.length));
				return null;
			}
			var arguments = new GenericArray<SemanticType> ();
			foreach (var argument_syntax in application.type_arguments) {
				var argument = resolve_type (argument_syntax);
				if (argument == null) {
					return null;
				}
				if (argument is EnumType) {
					fail (argument_syntax.span, "enum-containing generic structs remain outside ENUM-OWN-1");
					return null;
				}
				var parameter = definition.type_parameters[arguments.length];
				if (parameter.transport_mode == GenericTransportMode.OWNABLE) {
					if (!GenericCapabilityAuthority.satisfies (argument, GenericCapabilityIdentity.OWNABLE)) {
						fail (argument_syntax.span, "owning generic record argument requires its declared Ownable capability");
						return null;
					}
				} else if (!(!element_fields_complete && argument.is_struct_storage ()) && !GenericArgumentTypes.plain_copy (argument, copy_fields, copy_premise)) {
					fail (argument_syntax.span, "generic struct type argument '%s' is unsupported: requires GEN1_PLAIN_COPY; void, handles, classes, noncopyable records, slices, arrays and typed pointers are deferred".printf (argument.display_name ()));
					return null;
				}
				arguments.add (argument);
			}
			if (!definition.nominal_identity.admits (arguments)) {
				fail (syntax.span, "native module: closed record application is not exported: " + definition.nominal_identity.application_name (arguments));
				return null;
			}
			var requested = definition.application (arguments);
			return definition.owning_storage && definition.fields_complete && !requested.is_parameterized () ? materialize_owning_record (requested, syntax.span) : requested;
		}
		if (vector == null) {
			return resolve_type_name (syntax.span, syntax.spelling ());
		}
		var element = resolve_type (vector.element_type);
		if (element == null) {
			return null;
		}
		if (!(element is IntegerType) && !(element is FloatingType) && element != types.bool_type) {
			fail (vector.element_type.span, "vector element must be an exact integer, f32, f64, or bool type");
			return null;
		}
		// Bounded parsing also diagnoses enormous literals deterministically.
		int lanes = 0;
		string spelling = vector.lane_count.spelling ();
		for (int i = 0; i < spelling.length; i++) {
			if (lanes > 16) {
				break;
			}
			lanes = lanes * 10 + (spelling[i] - '0');
		}
		var type = types.vector_of (element, lanes);
		if (type == null) {
			fail (vector.span, "unsupported VEC-1 vector shape '%s': lanes must be 2, 4, 8, or 16 and numeric payload at most 128 bits".printf (vector.spelling ()));
		}
		return type;
	}

	private CheckedProgram? check_program(SyntaxProgram unit, GenericArray<ForeignDeclarationInput>? foreign_inputs, GenericArray<ForeignHandleInput>? handle_inputs) {
		if (!collect_modules (unit)) {
			return null;
		}
		var handles = collect_handles (handle_inputs);
		if (handles == null) {
			return null;
		}
		if (!collect_com_handles (unit, handles) || !collect_c_class_handles (unit, handles)) {
			return null;
		}
		shared_handle_inventory = handles;
		var instances = collect_native_instances (unit);
		var syntax_instances = instance_syntax;
		if (instances == null) {
			return null;
		}
		// Validate external declarations before collecting the unified namespace.
		// Neither normalized input nor its frontend survives as callable identity.
		var foreign_symbols = new GenericArray<CFunctionSymbol> ();
		foreach (var handle in handles) {
			if (handle.com_import != null && !collect_com_functions (handle, foreign_symbols)) {
				return null;
			}
		}
		if (foreign_inputs != null) {
			for (int i = 0; i < foreign_inputs.length; i++) {
				var symbol = collect_foreign_signature (foreign_inputs[i]);
				if (symbol == null) {
					return null;
				}
				foreign_symbols.add (symbol);
			}
		}
		// Complete signatures before inspecting any body. Arrays preserve source
		// order; hash tables are used only for lookup, never for traversal.
		var declarations = new GenericArray<DirectCallableSymbol> ();
		var c_functions = new GenericArray<CFunctionSymbol> ();
		for (int i = 0; i < unit.functions.length; i++) {
			var symbol = collect_signature (unit.functions[i]);
			if (symbol == null) {
				return null;
			}
			declarations.add (symbol);
			function_names.insert (symbol.name, symbol);
			lexical_types.remove_all ();
			if (symbol.domain == CallableDomain.C) {
				c_functions.add ((CFunctionSymbol) symbol);
			}
		}
		var class_imports = collect_c_class_functions (unit, instances);
		if (class_imports == null || !admit_foreign_classes (instances, syntax_instances)) {
			return null;
		}
		// Source externs first, then supplied files/declarations in input order.
		for (int i = 0; i < foreign_symbols.length; i++) {
			var symbol = foreign_symbols[i];
			if (function_names.contains (symbol.name)) {
				fail (symbol.name_span, "duplicate function '%s'; overloading is not implemented".printf (symbol.name));
				return null;
			}
			function_names.insert (symbol.name, symbol);
			c_functions.add (symbol);
		}

		if (native_declarations != null) {
			foreach (var request in native_declarations.method_requests) {
				var owner_type = resolve_type (request.owner);
				var owner = owner_type == null ? null : instance_for (owner_type) as ClassSymbol;
				if (owner == null || owner.generic_instance == null || owner.semantic_type.is_parameterized ()) {
					fail (request.owner.span, "native method selection requires an exact closed generic Class");
					return null;
				}
				int member = -1;
				for (int i = 0; i < owner.generic_instance.definition.generic_method_count; i++) {
					if (owner.generic_instance.definition.generic_method_name (i) == request.member.lookup_name ()) {
						member = i;
						break;
					}
				}
				if (member < 0) {
					fail (request.member.span, "native method selection requires a declared generic member");
					return null;
				}
				var arguments = new GenericArray<SemanticType> ();
				foreach (var syntax in request.member.type_arguments) {
					var argument = resolve_type (syntax);
					if (argument == null) {
						return null;
					}
					arguments.add (argument);
				}
				var method = request_class_method (owner, member, new TypeArgumentVector (arguments), request.member.span);
				if (method == null) {
					return null;
				}
				request.key = NativeDeclarationRegistry.function_key (method);
			}
		}
		if (!resolve_object_origins (unit, declarations, instances) || !collect_constants (unit)) {
			return null;
		}
		AsyncRuntimeIdentity? program_runtime = null;
		foreach (var nomination in unit.async_runtimes) {
			string space = source_namespace (nomination.span);
			if (async_runtimes.contains (space)) {
				fail (nomination.span, "one exact runtime nomination is supported per namespace");
				return null;
			}
			var error = resolve_exception_type (nomination.error);
			var status = resolve_type (nomination.status) as EnumType;
			if (error == null) {
				return null;
			}
			var definition = status == null ? null : enum_definition_for (status);
			if (definition == null || definition.variant_count != 2 || definition.variant (0).identity.name != "Completed" || definition.variant (1).identity.name != "Cancelled" || !definition.payload_free) {
				fail (nomination.status.span, "virtual root status requires the ordinary enum { Completed, Cancelled }");
				return null;
			}
			if (function_names.contains (declaration_name (nomination.name)) || named_types.contains (declaration_name (nomination.name))) {
				fail (nomination.name.span, "executor nomination conflicts with a declared identity");
				return null;
			}
			var error_class = instance_for (error) as ClassSymbol;
			if (error_class == null || error_class.constructor == null || error_class.constructor.parameters.length != 1 || !(error_class.constructor.parameters[0].semantic_type is StringType)) {
				fail (nomination.error.span, "nominated runtime error requires an ordinary one-string init constructor");
				return null;
			}
			AsyncProviderKind provider = AsyncProviderKind.VIRTUAL;
			bool composable = false;
			if (nomination.provider != null) {
				if (nomination.provider.text_payload != null && nomination.provider.text_payload.equal_content (new Astra.Text.TextBytes ("linux-io-uring".data))) {
					provider = AsyncProviderKind.LINUX_IO_URING;
				} else if (nomination.provider.text_payload != null && nomination.provider.text_payload.equal_content (new Astra.Text.TextBytes ("posix-threaded".data))) {
					provider = AsyncProviderKind.POSIX_THREADED;
				} else if (nomination.provider.text_payload != null && nomination.provider.text_payload.equal_content (new Astra.Text.TextBytes ("linux-io-uring-composed".data))) {
					provider = AsyncProviderKind.LINUX_IO_URING;
					composable = true;
				} else if (nomination.provider.text_payload != null && nomination.provider.text_payload.equal_content (new Astra.Text.TextBytes ("posix-threaded-composed".data))) {
					provider = AsyncProviderKind.POSIX_THREADED;
					composable = true;
				} else if (nomination.provider.text_payload != null && nomination.provider.text_payload.equal_content (new Astra.Text.TextBytes ("virtual-composed".data))) {
					provider = AsyncProviderKind.VIRTUAL;
					composable = true;
				} else {
					fail (nomination.provider.span, "unsupported explicit async provider");
					return null;
				}
			}
			var runtime = new AsyncRuntimeIdentity (nomination.span, nomination.name.spelling (), error, status, provider, composable);
			if (program_runtime != null && !runtime.compatible (program_runtime) && !(runtime.composable && program_runtime.composable && runtime.error_type == program_runtime.error_type)) {
				fail (nomination.span, "source runtime nominations require the same provider and nominal error type");
				return null;
			}
			program_runtime = runtime;
			async_runtimes.insert (space, runtime);
		}
		for (int i = 0; i < unit.functions.length; i++) {
			if (!unit.functions[i].is_async) {
				continue;
			}
			var symbol = (FunctionSymbol) declarations[i];
			var async_runtime = runtime_for (symbol.span);
			if (async_runtime == null && symbol.name_span.file.native_interface) {
				if (!native_body (symbol)) {
					return null;
				}
				// Opaque declarations have no executor/status source facade. Bind
				// them to the compilation's explicitly nominated compatible runtime;
				// imported metadata still checks the exact provider and error type.
				async_runtime = program_runtime;
			}
			if (async_runtime == null) {
				fail (unit.functions[i].async_keyword.span, "async declaration requires an explicit virtual runtime nomination");
				return null;
			}
			if (unit.functions[i].is_c_export || symbol is GenericFunctionSymbol || symbol.return_type is ClassType || symbol.return_type is HandleType || symbol.return_type is StringType || symbol.return_type is TypedPointerType || symbol.return_type is RawPointerType || (symbol.return_type is SliceType && symbol.result_contract != ResultOwnershipContract.OWNED_TRANSFER)) {
				fail (symbol.span, "async success requires void, copied values, enum or an owned array; exported, generic, borrowed, Class and Resource results are outside the first task scope");
				return null;
			}
			foreach (var parameter in symbol.parameters) {
				if (parameter.semantic_type is ClassType && parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is SliceType)) {
					fail (parameter.span, "async Class captures require owned transfer; borrowed Class/Resource/text/pointer captures are excluded and require synchronous native calls; borrowed arrays require a sealed direct parent-local loan");
					return null;
				}
			}
			foreach (var parameter in symbol.parameters) {
				if (!AsyncClosureCaptures.valid (parameter.semantic_type, parameter.pointer_contract, async_runtime.threaded)) {
					fail (parameter.span, "async Closure captures require an owned handle and a single-threaded executor");
					return null;
				}
			}
			symbol.async_body = new AsyncBodyContract (symbol.span, symbol.return_type, symbol.result_contract, symbol.throws_type, async_runtime);
		}
		foreach (var imported in c_functions) {
			if (!imported.metadata.callback_abi.is_valid () || (imported.metadata.callback != null) != (imported.metadata.callback_abi == CCallbackAbi.I32_CONTEXT_I32_SYNC)) {
				fail (imported.span, "callback requires exact callback name and callback_abi = 'i32-context-i32-sync'; retained callbacks are unsupported");
				return null;
			}
			if (imported.metadata.callback == null) {
				continue;
			}
			var callback = function_names.lookup (imported.metadata.callback) as FunctionSymbol;
			if (imported.metadata.record_abi != CRecordAbi.NATURAL_LP64 || imported.return_type.kind != TypeKind.INT || imported.parameters.length != 2 || !imported.parameters[0].semantic_type.is_struct_pointer () || imported.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || imported.parameters[1].semantic_type.kind != TypeKind.INT || imported.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED || callback == null || callback is GenericFunctionSymbol || callback is MethodSymbol || callback.return_type.kind != TypeKind.INT || callback.parameters.length != 2 || callback.parameters[0].semantic_type != imported.parameters[0].semantic_type || callback.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || callback.parameters[1].semantic_type.kind != TypeKind.INT || callback.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED || callback.throws_type != null || callback.async_body != null) {
				fail (imported.span, "synchronous C callback requires an exact nonthrowing native int callback(borrowed POD* context, int value) and matching import");
				return null;
			}
		}
		var generic_functions = new GenericArray<CheckedGenericFunction> ();
		lexical_types.remove_all ();
		var properties = new GenericArray<CheckedProperty> ();
		var functions = new GenericArray<CheckedFunction> ();
		var c_exports = new GenericArray<CExportSymbol> ();
		aggregate_owner_flow_needed = false;
		foreach (var definition in ordered_enums) {
			if (EnumValueAuthority.owns (definition, enum_definition_for)) {
				aggregate_owner_flow_needed = true;
			}
		}
		foreach (var definition in instances) {
			if (definition is StructSymbol && owning_record_field (definition.semantic_type) != null) {
				aggregate_owner_flow_needed = true;
			}
		}
		for (int i = 0; i < unit.functions.length; i++) {
			if (declarations[i].domain == CallableDomain.C) {
				continue;
			}
			var symbol = (FunctionSymbol) declarations[i];
			var locals = new GenericArray<LocalSymbol> ();
			if (native_body (symbol)) {
				functions.add (new CheckedFunction (symbol, locals, native_block (symbol.span)));
				continue;
			}
			if (diagnostic != null) {
				return null;
			}
			next_loop_ordinal = 0;
			next_region_ordinal = 0;
			next_object_ordinal = 0;
			assert (active_loops.length == 0);
			lexical_types.remove_all ();
			var generic = symbol as GenericFunctionSymbol;
			element_obligations = generic == null ? new GenericSliceObligations () : generic.element_obligations;
			if (generic != null) {
				foreach (var parameter in generic.type_parameters) {
					lexical_types.insert (parameter.name, parameter);
				}
			}
			begin_ownership_flow (symbol);
			var body = check_block (unit.functions[i].body, symbol, null, locals);
			if (body != null) {
				foreach (var loan in suspension_loans) {
					if (locals.find (loan.storage) && exposed_suspension_arrays.contains (loan.storage)) {
						fail (loan.view.span, "suspension loan requires sealed parent-local backing without stored or uncontrolled aliases");
						return null;
					}
				}
			}
			if (body != null && !verify_ownership_flow (body, symbol)) {
				return null;
			}
			if (body != null && generic != null) {
				generic.heap_consumer_parameter = heap_consumer_parameter (generic, locals, generic_owner_flow);
				storage_flows.insert (generic, generic_owner_flow);
			}
			generic_owner_flow = null;
			lexical_types.remove_all ();
			if (body == null) {
				return null;
			}
			if (generic == null) {
				functions.add (new CheckedFunction (symbol, locals, body));
			} else {
				generic_functions.add (new CheckedGenericFunction (generic, locals, body));
			}
			if (unit.functions[i].is_c_export) {
				c_exports.add (new CExportSymbol (unit.functions[i].span, symbol.name_span, symbol, c_export_name (unit.functions[i], symbol.name), ForeignAbi.C, c_exports.length, c_value_export (unit.functions[i]) ? CRecordAbi.VALUE_LP64 : CRecordAbi.NONE, c_bool_abi (unit.functions[i])));
			}
		}
		foreach (var imported in class_imports) {
			var region = new LexicalRegion (null, 0);
			var locals = new GenericArray<LocalSymbol> ();
			var statements = new GenericArray<CheckedStatement> ();
			foreach (var parameter in imported.parameters) {
				if (parameter.struct_value_contract != null || parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					locals.add (new LocalSymbol (parameter.span, parameter.name_span, parameter.semantic_type, locals.length, region, parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER ? handle_types.lookup (parameter.semantic_type).cleanup : null, parameter));
				}
			}
			statements.add (new CheckedForeignReturn (imported.span, imported.foreign_import, imported.foreign_error_factory));
			functions.add (new CheckedFunction (imported, locals, new CheckedBlockStatement (imported.span, statements, region)));
		}
		var checked_lifecycles = new HashTable<LifecycleSymbol, bool> (direct_hash, direct_equal);
		var checked_properties = new HashTable<PropertySymbol, bool> (direct_hash, direct_equal);
		int checked_body_count = 0;
		do {
			checked_body_count = (int) functions.length;
			if (!expand_class_applications ()) {
				return null;
			}
			if (!check_method_bodies (instances, functions)) {
				return null;
			}
			specializing_class = null;
			for (int i = 0; i < instances.length; i++) {
				var owner = instances[i] as ClassSymbol;
				if (owner == null) {
					continue;
				}
				specializing_class = owner;
				foreach (var member in syntax_instances[i].members) {
					var syntax = member as LifecycleDeclarationSyntax;
					if (syntax == null) {
						continue;
					}
					LifecycleSymbol symbol = syntax.is_constructor ? (LifecycleSymbol) owner.constructor : owner.destructor;
					if (checked_lifecycles.contains (symbol)) {
						continue;
					}
					var locals = new GenericArray<LocalSymbol> ();
					if (native_body (symbol)) {
						var body = native_block (syntax.span);
						if (syntax.is_constructor) {
							functions.add (new CheckedConstructor ((ConstructorSymbol) symbol, locals, body, new FieldInitializationState ((int) owner.fields.length)));
						} else {
							functions.add (new CheckedDestructor ((DestructorSymbol) symbol, locals, body));
						}
						checked_lifecycles.insert (symbol, true);
						continue;
					}
					if (diagnostic != null) {
						return null;
					}
					next_loop_ordinal = 0;
					next_region_ordinal = 0;
					next_object_ordinal = 0;
					field_state = syntax.is_constructor ? new FieldInitializationState ((int) owner.fields.length) : null;
					checking_lifecycle = symbol;
					begin_ownership_flow (symbol);
					var body = check_block (syntax.body, symbol, null, locals);
					checking_lifecycle = null;
					if (!verify_ownership_flow (body, symbol)) {
						return null;
					}
					generic_owner_flow = null;
					if (syntax.is_constructor) {
						foreach (var field in owner.fields) {
							if (!field_state.is_definite (field.ordinal)) {
								fail (syntax.name.span, "constructor '%s.init': field '%s' is not definitely initialized on every successful completion".printf (owner.name, field.name));
								return null;
							}
						}
						functions.add (new CheckedConstructor ((ConstructorSymbol) symbol, locals, body, field_state));
					} else {
						functions.add (new CheckedDestructor ((DestructorSymbol) symbol, locals, body));
					}
					checked_lifecycles.insert (symbol, true);
					field_state = null;
				}
			}
			specializing_class = null;
			for (int i = 0; i < instances.length; i++) {
				foreach (var member in syntax_instances[i].members) {
					var syntax = member as PropertyDeclarationSyntax;
					if (syntax == null) {
						continue;
					}
					specializing_class = instances[i] as ClassSymbol;
					var symbol = instances[i].find_property (syntax.name.spelling ());
					if (checked_properties.contains (symbol)) {
						continue;
					}
					var getter = check_accessor (syntax.getter, symbol.getter);
					if (getter == null) {
						return null;
					}
					CheckedPropertyAccessor? setter = null;
					functions.add (getter);
					if (syntax.setter != null) {
						setter = check_accessor (syntax.setter, symbol.setter);
						if (setter == null) {
							return null;
						}
						functions.add (setter);
					}
					properties.add (new CheckedProperty (symbol, getter, setter));
					checked_properties.insert (symbol, true);
				}
			}
			specializing_class = null;
		} while (functions.length != checked_body_count);

		foreach (var instance in instances) {
			var owner = instance as ClassSymbol;
			if (owner == null || owner.generic_instance == null || !owner.generic_instance.definition.general_bodies) {
				continue;
			}
			int member = (int) owner.fields.length;
			if (owner.constructor != null) {
				owner.constructor.member_ordinal = member++;
			}
			foreach (var method in owner.methods) {
				method.member_ordinal = member++;
			}
			foreach (var property in owner.properties) {
				property.member_ordinal = member++;
			}
			if (owner.destructor != null) {
				owner.destructor.member_ordinal = member;
			}
		}
		// Least fixed point: only a retaining terminal or one exact edge to
		// an already qualified helper can justify a heap request. Cycles have
		// no terminal proof, regardless of declaration or request order.
		var heap_qualified = new HashTable<GenericFunctionSymbol, bool> (direct_hash, direct_equal);
		bool heap_changed = false;
		do {
			heap_changed = false;
			foreach (var definition in generic_functions) {
				var function = definition.definition;
				var scope = heap_consumer_scopes.lookup (function);
				if (function.heap_consumer_parameter < 0 || heap_qualified.contains (function) || scope == null) {
					continue;
				}
				var target = scope.target as GenericFunctionSymbol;
				if (scope.target == null || consuming_class_member (scope.target, scope.parameter, function.parameters[function.heap_consumer_parameter].semantic_type) || CallableTypes.consumes (scope.target, scope.parameter, function.parameters[function.heap_consumer_parameter].semantic_type) || (target != null && target.result_contract != ResultOwnershipContract.OWNED_TRANSFER && heap_qualified.contains (target) && target.heap_consumer_parameter == scope.parameter)) {
					heap_qualified.insert (function, true);
					heap_changed = true;
				}
			}
		} while (heap_changed);
		foreach (var definition in generic_functions) {
			if (!heap_qualified.contains (definition.definition)) {
				definition.definition.heap_consumer_parameter = -1;
			}
		}
		var storage_requirements = new GenericStorageRequirements ();
		foreach (var definition in generic_functions) {
			var flow = storage_flows.lookup (definition.definition);
			foreach (var parameter in definition.definition.parameters) {
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && parameter.semantic_type is ClassType && parameter.heap_object) {
					storage_requirements.constrain (parameter, GenericStorageRequirements.HEAP, definition.definition);
				}
			}
			foreach (var local in definition.locals) {
				if (local.incoming_parameter != null) {
					storage_requirements.link (local.incoming_parameter, local);
				}
				foreach (var edge in flow.transfers_for (local)) {
					if (edge.local && edge.target != null) {
						storage_requirements.link (local, edge.target);
						continue;
					}
					var target = edge.target as FunctionSymbol;
					if (target != null && edge.parameter >= 0 && edge.parameter < target.parameters.length) {
						var parameter = target.parameters[edge.parameter];
						if (target is GenericFunctionSymbol && (ownable_parameter (parameter.semantic_type) || parameter.semantic_type is ClassType)) {
							storage_requirements.link (local, parameter);
						} else if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (ownable_parameter (parameter.semantic_type) || parameter.semantic_type is ClassType)) {
							storage_requirements.constrain (local, ownable_parameter (parameter.semantic_type) || parameter.heap_object ? GenericStorageRequirements.HEAP : GenericStorageRequirements.CALLER, edge.target);
						}
					} else if (CallableTypes.consumes (edge.target, edge.parameter, local.semantic_type)) {
						storage_requirements.constrain (local, GenericStorageRequirements.HEAP, edge.target);
					}
				}
			}
		}
		storage_requirements.solve ();
		foreach (var argument in heap_generic_order) {
			if (!storage_requirements.permits (argument.parameter, true)) {
				fail (argument.span, "generic ownership transfer requires caller-backed storage at a reachable consuming boundary");
				return null;
			}
		}
		foreach (var argument in lexical_generic_order) {
			if (!storage_requirements.permits (argument.parameter, false)) {
				var boundary = storage_requirements.reason (argument.parameter, false);
				string kind = "consuming native Class boundary";
				if (boundary is MethodSymbol) {
					kind = "consuming Class member";
				} else if (boundary is FunctionValueType || boundary is ClosureHandleType) {
					kind = "consuming callable Class channel";
				}
				fail (argument.span, kind + " requires an independently heap-owned argument; lexical storage cannot be transferred through that helper");
				return null;
			}
		}
		var structures = new GenericArray<StructSymbol> ();
		foreach (var instance in instances) {
			if (instance is StructSymbol) {
				structures.add ((StructSymbol) instance);
			}
		}
		try {
			types.complete_function_records (copy_fields);
			foreach (var handle in handles) {
				var closure = handle.semantic_type as ClosureHandleType;
				if (closure != null) {
					closure.complete_records (copy_fields);
				}
			}
		} catch (StructLeafError error) {
			fail (unit.span, error.message);
			return null;
		}
		foreach (var function in functions) {
			if (!function.symbol.name_span.file.native_interface) {
				continue;
			}
			var declaration = native_declarations == null ? null : native_declarations.lookup (function.symbol);
			if (declaration == null) {
				fail (function.span, "unexpected imported native callable");
				return null;
			}
			function.bind_native_declaration (NativeDeclarationRegistry.signature (declaration, function.symbol));
		}
		foreach (var instance in instances) {
			var owner = instance as ClassSymbol;
			if (owner == null || !owner.name_span.file.native_interface || owner.destructor != null || native_declarations == null) {
				continue;
			}
			owner.native_destructor_declaration = native_declarations.lookup_key (owner.name_span.file, "C:" + owner.semantic_type.display_name () + "::deinit");
		}
		var program = new CheckedProgram (unit.span, types, functions, c_functions, c_exports, structures, handles);
		foreach (var definition in ordered_enums) {
			program.enums.add (definition);
		}
		foreach (var constant in constants) {
			program.constants.add (constant);
		}
		foreach (var instance in instances) {
			if (instance is ClassSymbol) {
				program.classes.add ((ClassSymbol) instance);
			}
		}
		foreach (var property in properties) {
			program.properties.add (property);
		}
		foreach (var generic in generic_functions) {
			program.generic_functions.add (generic);
		}
		foreach (var application in class_applications) {
			program.class_applications.add (application);
		}
		foreach (var application in method_applications) {
			program.method_applications.add (application);
		}
		foreach (var generic in generic_structs) {
			program.generic_structs.add (generic);
		}
		foreach (var definition in generic_classes) {
			program.generic_classes.add (definition.identity);
		}
		if (!validate_allocation_policies (program)) {
			return null;
		}
		foreach (var definition in program.all_definitions ()) {
			var function = definition.symbol;
			if (function.async_body == null || !function.async_body.runtime.threaded) {
				continue;
			}
			foreach (var parameter in function.parameters) {
				if (!thread_capture_type (parameter.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
					fail (parameter.span, "threaded task parameter is not Send; thread-bound, foreign and unqualified shared captures cannot migrate");
					return null;
				}
			}
			foreach (var local in definition.locals) {
				if (!(local.semantic_type is TaskType) && local.semantic_type.kind != TypeKind.VOID && !thread_capture_type (local.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
					fail (local.span, "threaded task local cannot migrate with its native frame");
					return null;
				}
			}
			if (function.return_type.kind != TypeKind.VOID && !thread_capture_type (function.return_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
				fail (function.span, "threaded task result is not Send");
				return null;
			}
		}

		diagnostic = CallerInformation.validate_program (program) ?? Utf8FactoryContracts.validate_program (program) ?? readonly_inspection.validate (program, copy_fields) ?? SemanticNonNull.check (program, nonnull_definitions) ?? SemanticTextOrigins.check (program) ?? SemanticRuntimeLifetimes.check (program);
		return diagnostic == null ? program : null;
	}

	private static bool self_receiver(CheckedExpression value, ReceiverSymbol receiver) {
		while (value is CheckedClassUpcast) {
			value = ((CheckedClassUpcast) value).reference;
		}
		return value is CheckedThisExpression && ((CheckedThisExpression) value).receiver == receiver;
	}
	private CheckedExpression upcast_class(CheckedExpression value, SemanticType expected) {
		if (value.semantic_type == expected) {
			return value;
		}
		var source_receiver = value.semantic_type as ReceiverType;
		var target_receiver = expected as ReceiverType;
		var source = (source_receiver == null ? value.semantic_type : source_receiver.instance_type) as ClassType;
		var target = (target_receiver == null ? expected : target_receiver.instance_type) as ClassType;
		if (source == null || target == null || !source.derives_from (target) || (source_receiver == null) != (target_receiver == null) || (source_receiver != null && source_receiver.mode != target_receiver.mode)) {
			return value;
		}
		return new CheckedClassUpcast (value.span, value, (ClassSymbol) instance_for (source), (ClassSymbol) instance_for (target), expected);
	}

	private bool declared_owned_property(NativeInstanceSymbol owner, PropertyDeclarationSyntax property) {
		if (property.foreign_member == null || property.is_lazy || property.is_borrowed || property.setter != null || property.dispatch != MemberDispatchSyntax.DIRECT) {
			return false;
		}
		foreach (var syntax in instance_syntax) {
			var root = syntax as ClassDeclarationSyntax;
			if (root != null && root.name.span.file == owner.name_span.file && root.name.span.start == owner.name_span.start && ForeignApiAdmission.selected (root)) {
				return true;
			}
		}
		return false;
	}
	private CheckedPropertyAccessor? check_accessor(PropertyAccessorSyntax syntax, PropertyAccessorSymbol symbol) {
		var locals = new GenericArray<LocalSymbol> ();
		if (native_body (symbol)) {
			return new CheckedPropertyAccessor (symbol, locals, native_block (syntax.span));
		}
		if (diagnostic != null) {
			return null;
		}
		if (symbol is PropertyGetterSymbol && symbol.property_symbol.is_owned_lazy) {
			var statements = new GenericArray<CheckedStatement> ();
			statements.add (new CheckedReturnStatement (syntax.span, new CheckedLazyObserve (syntax.span, symbol.property_symbol)));
			return new CheckedPropertyAccessor (symbol, locals, new CheckedBlockStatement (syntax.span, statements, new LexicalRegion (null, 0)));
		}
		next_loop_ordinal = 0;
		next_region_ordinal = 0;
		next_object_ordinal = 0;
		begin_ownership_flow (symbol);
		var body = check_block (syntax.body, symbol, null, locals);
		if (!verify_ownership_flow (body, symbol)) {
			return null;
		}
		generic_owner_flow = null;
		if (body != null && symbol.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
			var returned = body.statements.length == 1 ? body.statements[0] as CheckedReturnStatement : null;
			var load = returned == null ? null : returned.expression as CheckedLoadExpression;
			var record_return = body.statements.length == 1 ? body.statements[0] as CheckedStructReturn : null;
			var observation = record_return == null ? null : record_return.producer as CheckedStructBorrowSnapshot;
			var field = observation == null ? (load == null ? null : load.source as CheckedReceiverFieldPlace) : observation.source as CheckedReceiverFieldPlace;
			if (locals.length != 0 || field == null || !self_receiver (field.receiver, symbol.implicit_receiver) || !field.field.is_owned_field || field.field.owns_buffer || field.semantic_type != symbol.return_type) {
				fail (syntax.span, "borrowed property getter requires one exact owned receiver field projection without local storage or effects");
				return null;
			}
		}
		if (body != null && symbol.return_type is StringType) {
			var returned = body.statements.length == 1 ? body.statements[0] as CheckedReturnStatement : null;
			var value = returned == null ? null : returned.expression;
			var load = value as CheckedLoadExpression;
			var field = load == null ? null : load.source as CheckedReceiverFieldPlace;
			if (!(value is CheckedTextExpression || value is CheckedConstantReference || (field != null && self_receiver (field.receiver, symbol.implicit_receiver) && field.field.text_snapshot))) {
				fail (syntax.span, "receiver text getter requires one literal, constant or readonly receiver snapshot return; effectful and unproved getters are unsupported");
				return null;
			}
		}
		return body == null ? null : new CheckedPropertyAccessor (symbol, locals, body);
	}

	private bool complete_class_dispatch(ClassSymbol owner, HashTable<ClassSymbol, bool> complete) {
		if (complete.contains (owner)) {
			return true;
		}
		if (owner.parent_class != null) {
			if (!complete_class_dispatch (owner.parent_class, complete)) {
				return false;
			}
			foreach (var entry in owner.parent_class.virtual_entries) {
				owner.virtual_entries.add (entry);
			}
		}
		foreach (var field in owner.fields) {
			if (owner.parent_class != null && owner.parent_class.find_member (field.name) != null) {
				fail (field.span, "derived fields cannot shadow an inherited member");
				return false;
			}
		}
		var members = new GenericArray<FunctionSymbol> ();
		foreach (var method in owner.methods) {
			members.add (method);
		}
		foreach (var property in owner.properties) {
			members.add (property.getter);
		}
		foreach (var member in members) {
			var property = member as PropertyGetterSymbol;
			string name = property == null ? member.name : property.property_symbol.name;
			var inherited = owner.parent_class == null ? null : owner.parent_class.find_member (name);
			FunctionSymbol? prior = inherited as MethodSymbol;
			if (inherited is PropertySymbol) {
				prior = ((PropertySymbol) inherited).getter;
			}
			if (member.dispatch_kind == ClassDispatchKind.DIRECT) {
				if (inherited != null) {
					fail (member.span, "derived members require explicit override of an inherited virtual member");
					return false;
				}
				continue;
			}
			if (member.result_contract == ResultOwnershipContract.OWNED_TRANSFER || member.return_type is EnumType || member.return_type.is_struct_storage ()) {
				fail (member.span, "virtual subset excludes owning results");
				return false;
			}
			foreach (var parameter in member.parameters) {
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.semantic_type is EnumType || parameter.semantic_type.is_struct_storage ()) {
					fail (member.span, "virtual subset requires nonowning scalar, vector or bounded borrow parameters");
					return false;
				}
			}
			owner.polymorphic = true;
			if (member.dispatch_kind == ClassDispatchKind.VIRTUAL) {
				if (inherited != null) {
					fail (member.span, "virtual declaration cannot shadow an inherited member; use override");
					return false;
				}
				member.virtual_slot = (int) owner.virtual_entries.length;
				owner.virtual_entries.add (member);
			} else {
				if (prior == null || prior.dispatch_kind == ClassDispatchKind.DIRECT || (property == null) != (prior is MethodSymbol) || prior.return_type != member.return_type || prior.result_contract != member.result_contract || prior.parameters.length != member.parameters.length) {
					fail (member.span, "override requires an inherited virtual member with the exact callable signature");
					return false;
				}
				for (int p = 0; p < member.parameters.length; p++) {
					var a = member.parameters[p];
					var b = prior.parameters[p];
					if (a.semantic_type != b.semantic_type || a.pointer_contract != b.pointer_contract || a.caller_information != null || b.caller_information != null) {
						fail (a.span, "override parameters must retain the exact type and borrow contract; caller annotations are excluded from this subset");
						return false;
					}
				}
				if (member.throws_type != null && (prior.throws_type == null || !member.throws_type.derives_from (prior.throws_type))) {
					fail (member.span, "override cannot broaden its inherited checked throws bound");
					return false;
				}
				member.virtual_slot = prior.virtual_slot;
				owner.virtual_entries.set (member.virtual_slot, member);
			}
		}
		if (!((ClassType) owner.semantic_type).is_interface) {
			foreach (var entry in owner.virtual_entries) {
				var declaration = entry as MethodSymbol;
				if (declaration != null && declaration.declaring_type.semantic_type is ClassType && ((ClassType) declaration.declaring_type.semantic_type).is_interface) {
					fail (owner.span, "concrete Class must explicitly override every interface operation");
					return false;
				}
			}
		}
		if (owner.parent_class != null) {
			owner.polymorphic = true;
			owner.parent_class.polymorphic = true;
		}
		complete.insert (owner, true);
		return true;
	}

	private static bool interface_read_expression(ExpressionSyntax expression, ClassSymbol owner) {
		if (expression is IntegerLiteralExpressionSyntax || expression is BooleanLiteralExpressionSyntax || expression is NameExpressionSyntax) {
			return true;
		}
		if (expression is IndexExpressionSyntax) {
			var indexed = (IndexExpressionSyntax) expression;
			return interface_read_expression (indexed.container, owner) && interface_read_expression (indexed.subscript, owner);
		}
		if (expression is ParenthesizedExpressionSyntax) {
			return interface_read_expression (((ParenthesizedExpressionSyntax) expression).expression, owner);
		}
		if (expression is PrefixExpressionSyntax) {
			return interface_read_expression (((PrefixExpressionSyntax) expression).operand, owner);
		}
		if (expression is ComparisonChainSyntax) {
			foreach (var operand in ((ComparisonChainSyntax) expression).operands) {
				if (!interface_read_expression (operand, owner)) {
					return false;
				}
			}
			return true;
		}
		if (expression is BinaryExpressionSyntax) {
			var binary = (BinaryExpressionSyntax) expression;
			return interface_read_expression (binary.left, owner) && interface_read_expression (binary.right, owner);
		}
		if (expression is ShortCircuitExpressionSyntax) {
			var binary = (ShortCircuitExpressionSyntax) expression;
			return interface_read_expression (binary.left, owner) && interface_read_expression (binary.right, owner);
		}
		var field = expression as FieldAccessExpressionSyntax;
		return field != null && !field.indirect && field.aggregate == null && field.identifier.kind == TokenKind.THIS && owner.find_field (field.field_name.spelling ()) != null;
	}

	private bool interface_readonly_implementation(FunctionDeclarationSyntax syntax, MethodSymbol method) {
		var owner = method.declaring_type as ClassSymbol;
		if (owner == null || ((ClassType) owner.semantic_type).is_interface) {
			return true;
		}
		bool required = false;
		for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
			if (((ClassType) ancestor.semantic_type).is_interface && ancestor.find_method (method.name) != null) {
				required = true;
			}
		}
		if (!required) {
			return true;
		}
		if (!interface_read_block (syntax.body, owner)) {
			fail (syntax.span, "interface read-only implementation requires copied expression returns and conditions; calls, mutation and ownership operations are excluded");
			return false;
		}
		return true;
	}
	private static bool interface_read_block(BlockStatementSyntax body, ClassSymbol owner) {
		foreach (var statement in body.statements) {
			var returned = statement as ReturnStatementSyntax;
			if (returned != null) {
				if (returned.expression == null || !interface_read_expression (returned.expression, owner)) {
					return false;
				}
				continue;
			}
			var branch = statement as IfStatementSyntax;
			if (branch != null) {
				if (!interface_read_expression (branch.condition, owner) || !interface_read_block (branch.then_body, owner) ||
				    branch.else_body != null && !interface_read_block (branch.else_body, owner)) {
					return false;
				}
				continue;
			}
			if (statement is BlockStatementSyntax && interface_read_block ((BlockStatementSyntax) statement, owner)) {
				continue;
			}
			return false;
		}
		return true;
	}

	private PropertySymbol? collect_property(PropertyDeclarationSyntax syntax, NativeInstanceSymbol owner, int member_ordinal) {
		string name = syntax.name.spelling ();
		if (owner is ClassSymbol && (name == "init" || name == "deinit")) {
			fail (syntax.name.span, "class lifecycle name '%s' is reserved; properties cannot use it".printf (name));
			return null;
		}
		if (owner.find_declared_member (name) != null) {
			fail (syntax.name.span, "property/member name collision '%s' in '%s'; fields, methods and properties share one namespace without overloading".printf (name, owner.name));
			return null;
		}
		var type = resolve_contract_type (syntax.type_name);
		if (type is CallbackType) {
			fail (syntax.span, "Callback is call-scoped and cannot be a property value");
			return null;
		}
		if (type == null) {
			return null;
		}
		bool symbolic_copy = owner.semantic_type.is_parameterized () && GenericArgumentTypes.plain_copy (type, copy_fields, copy_premise);
		bool symbolic_cache = symbolic_copy && type is TypeParameterType;
		bool symbolic_borrow = owner.semantic_type.is_parameterized () && ownable_parameter (type);
		bool borrowed_view = syntax.is_borrowed && !substituted_copy_type (syntax.type_name, type);
		if (syntax.type_name is NonNullTypeSyntax && (!borrowed_view || syntax.is_lazy || syntax.setter != null)) {
			fail (syntax.span, "nonnull property requires an established pure get-only receiver borrow");
			return null;
		}
		bool owns_foreign = syntax.owned_keyword != null && declared_owned_property (owner, syntax);
		bool owns_cache = syntax.owned_keyword != null && !owns_foreign;
		if (owns_cache && (!(owner is ClassSymbol) || !(type is ClassType) || type is ExactGenericClassType && !GenericClassTypes.general (type) || ((ClassType) type).is_interface || !syntax.is_lazy || syntax.setter != null || syntax.dispatch != MemberDispatchSyntax.DIRECT)) {
			fail (syntax.span, "owned lazy cache requires an exact unique native Class result");
			return null;
		}
		if (borrowed_view) {
			bool record_view = type.is_struct_storage () && owning_record_field (type) != null;
			if (!(owner is ClassSymbol) || (!(type is HandleType) && !(type is ClassType) && !record_view && !symbolic_borrow) || type is ExactGenericClassType && !GenericClassTypes.general (type) || (type is ClassType && ((ClassType) type).is_interface) || syntax.is_lazy || syntax.dispatch != MemberDispatchSyntax.DIRECT || syntax.throws_class != null) {
				fail (syntax.span, "borrowed property requires a direct nonthrowing native Class getter over one exact owned Resource or concrete child Class field or owning record");
				return null;
			}
			if (owner.name_span.file.native_interface) {
				string key = "C:" + owner.semantic_type.display_name () + "::get:" + syntax.name.spelling ();
				var declaration = native_declarations == null ? null : native_declarations.lookup_key (owner.name_span.file, key);
				bool has_storage = false;
				foreach (var field in owner.fields) {
					has_storage |= field.containing_type == owner && field.is_owned_field && !field.owns_buffer && field.semantic_type == type && (!record_view || declaration != null && declaration.record_field == field.name);
				}
				if (declaration == null || !has_storage) {
					fail (syntax.getter.span, "native receiver borrow requires its exact imported getter and owned receiver storage");
					return null;
				}
			} else {
				var returned = syntax.getter.body.statements.length == 1 ? syntax.getter.body.statements[0] as ReturnStatementSyntax : null;
				var projection = returned == null ? null : returned.expression as FieldAccessExpressionSyntax;
				var field = projection == null ? null : owner.find_field (projection.field_name.spelling ());
				if (field == null || field.containing_type != owner || !field.is_owned_field || field.owns_buffer || field.semantic_type != type) {
					fail (syntax.getter.span, "borrowed property getter requires return this.owned_field with the exact declared Class or Resource type");
					return null;
				}
			}
		}
		if (syntax.is_lazy && (!(owner is ClassSymbol) || syntax.setter != null || syntax.dispatch != MemberDispatchSyntax.DIRECT || (!owns_cache && !symbolic_cache && !PropertyValueTypes.supports_cache (type)))) {
			fail (syntax.span, "lazy property requires a nonvirtual get-only class property with a copied primitive, vector, mask or raw pointer result");
			return null;
		}
		if (syntax.throws_class != null && (!(owner is ClassSymbol) || syntax.setter != null || syntax.dispatch != MemberDispatchSyntax.DIRECT || (!owns_cache && !PropertyValueTypes.supports_cache (type)))) {
			fail (syntax.throws_class.span, "property throws requires a nonvirtual get-only class property with a copied value result");
			return null;
		}
		if (owns_foreign && (!(type is ClassType) || ((ClassType) type).is_interface || type is ExactGenericClassType || syntax.throws_class != null)) {
			fail (syntax.span, "declared owning property requires an exact direct nonthrowing Class result");
			return null;
		}
		if (!borrowed_view && !owns_cache && !owns_foreign && !symbolic_copy && !PropertyValueTypes.supports (type, copy_fields)) {
			fail (syntax.type_name.span, "unsupported property value type '%s'; requires a plain native parameter/result value without ownership or lifetime contracts".printf (type.display_name ()));
			return null;
		}
		if (type is StringType && (!(owner is ClassSymbol) || syntax.setter != null)) {
			fail (syntax.span, "receiver text property requires a get-only native class property");
			return null;
		}
		var property = new PropertySymbol (syntax.span, syntax.name.span, owner, type, owner.properties.length, member_ordinal);
		property.is_owned_foreign = owns_foreign;
		property.is_borrowed = borrowed_view || owns_cache;
		property.is_owned_lazy = owns_cache;
		property.is_lazy = syntax.is_lazy;
		property.getter = new PropertyGetterSymbol (syntax.getter.span, syntax.getter.keyword.span, property);
		if (owns_foreign) {
			property.getter.result_class = (ClassSymbol) instance_for (type);
			property.getter.result_storage = new ResultObjectStorageSymbol (property.getter.result_class);
		}
		if (type.is_struct_storage ()) {
			property.getter.struct_result_contract = new StructValueContract (type, borrowed_view ? StructValueMode.BORROW_VALUE : StructValueMode.COPY_VALUE);
		}
		if (syntax.type_name is NonNullTypeSyntax) {
			property.getter.mark_nonnull_result ();
		}
		if (syntax.throws_class != null) {
			property.getter.throws_type = resolve_exception_type (syntax.throws_class);
			if (property.getter.throws_type == null) {
				return null;
			}
		}
		property.getter.dispatch_kind = (ClassDispatchKind) syntax.dispatch;
		if (syntax.dispatch != MemberDispatchSyntax.DIRECT && (!(owner is ClassSymbol) || syntax.setter != null)) {
			fail (syntax.span, "virtual property subset requires a get-only native class property");
			return null;
		}
		if (syntax.setter != null) {
			var parameter = syntax.setter.parameter;
			if (parameter.caller_information != null) {
				fail (parameter.span, "caller information is unsupported on property setter parameters");
				return null;
			}
			var parameter_type = resolve_type (parameter.type_name);
			if (parameter_type == null) {
				return null;
			}
			if (parameter_type != type) {
				fail (parameter.type_name.span, "setter parameter for property '%s.%s' must exactly match '%s', found '%s'".printf (owner.name, name, type.display_name (), parameter_type.display_name ()));
				return null;
			}
			if (borrowed_view != (parameter.owned_keyword != null) || parameter.borrowed_keyword != null) {
				fail (parameter.span, "borrowed property replacement requires one exact owned parameter; plain properties require unmanaged values");
				return null;
			}
			var symbol = new ParameterSymbol (parameter.span, parameter.name.span, type, 0, borrowed_view ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.UNMANAGED);
			if (type.is_struct_storage ()) {
				symbol.struct_value_contract = new StructValueContract (type);
			}
			property.setter = new PropertySetterSymbol (syntax.setter.span, syntax.setter.keyword.span, property, types.void_type, symbol);
		}
		return property;
	}

	private CForeignCleanupContract intern_cleanup(CForeignCleanupContract source) {
		var cleanup = cleanups.lookup (source.external_symbol);
		if (cleanup == null) {
			cleanup = new CForeignCleanupContract (source.external_symbol, source.symbol_span);
			cleanups.insert (cleanup.external_symbol, cleanup);
		}
		return cleanup;
	}

	private CheckedStatement? check_heap_local(SourceSpan span, SourceSpan name_span, HeapObjectConstructionSyntax syntax, SemanticType? expected, ValueScope values, GenericArray<LocalSymbol> locals) {
		var type = resolve_type (syntax.class_name);
		if (type == null) {
			return null;
		}
		var owner = instance_for (type) as ClassSymbol;
		if (owner == null) {
			fail (syntax.class_name.span, "new C(args) requires a concrete native class");
			return null;
		}
		if (((ClassType) owner.semantic_type).is_interface) {
			fail (syntax.span, "interface is a borrowed contract and cannot be constructed");
			return null;
		}
		if (expected != null && expected != type) {
			fail (syntax.class_name.span, "heap construction requires the exact destination class");
			return null;
		}
		if (owner.constructor == null) {
			fail (syntax.span, "heap construction requires an explicit init constructor");
			return null;
		}
		if (owner.constructor.throws_type != null && !check_exception_effect (owner.constructor.throws_type, syntax.span)) {
			return null;
		}
		if (values.lookup (name_span.text ()) != null) {
			fail (name_span, "duplicate heap owner binding");
			return null;
		}
		if (syntax.arguments.length != owner.constructor.parameters.length) {
			fail (syntax.span, "heap construction requires the exact initializer argument count");
			return null;
		}
		CheckedExpression? allocation_context = null;
		bool contextual = owner.allocation_policy != null && owner.allocation_policy.kind == AllocationKind.CONTEXT;
		if (contextual != (syntax.allocation_context != null)) {
			fail (syntax.span, "context allocation requires an explicit instance and matching Class Allocator(kind=\"context\", context=...) contract");
			return null;
		}
		LocalSymbol? context_owner = null;
		if (contextual) {
			if (!(syntax.allocation_context is NameExpressionSyntax)) {
				fail (syntax.allocation_context.span, "allocator selection requires a named context value or borrowed context parameter");
				return null;
			}
			allocation_context = check_expression (syntax.allocation_context, values, null, OwnershipUse.NULL_COMPARISON, null, true);
			if (allocation_context == null) {
				return null;
			}
			var context_type = allocation_context.semantic_type as HandleType;
			if (context_type == null || context_type.context_mode != owner.allocation_policy.context_mode) {
				fail (syntax.allocation_context.span, "allocator instance lifetime/thread contract differs from the constructed Class policy");
				return null;
			}
			context_owner = values.lookup (((NameExpressionSyntax) syntax.allocation_context).identifier.spelling ()) as LocalSymbol;
			if (context_type.context_mode == "scoped-affine") {
				var parameter = allocation_context as CheckedParameterReferenceExpression;
				var loan = context_owner == null ? null : context_owner.scoped_backing;
				bool local = loan != null && loan.valid () && loan.context_ordinal == context_owner.ordinal && loan.region_ordinal == context_owner.lexical_region.ordinal && context_owner.lexical_region.outlives (values.region);
				bool borrowed = parameter != null && parameter.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE;
				if (checking_function == null || checking_function.async_body != null || !local && !borrowed) {
					fail (syntax.span, "scoped construction requires its exact synchronous backing loan or borrowed context parameter");
					return null;
				}
				// SemanticRuntimeLifetimes.check must reconstruct the entire body,
				// including every derived owner, store, result and exceptional exit.
			}
		}
		if (syntax.fallible) {
			if (checking_function != null && checking_function.async_body != null) {
				fail (syntax.span, "try_new requires a synchronous construction site");
				return null;
			}
			if (owner.allocation_policy == null) {
				fail (syntax.span, "try_new requires an explicit checked allocation policy");
				return null;
			}
			foreach (var parameter in owner.constructor.parameters) {
				bool scalar = (parameter.semantic_type is IntegerType || parameter.semantic_type is FloatingType || parameter.semantic_type.kind == TypeKind.BOOL) && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
				bool owner_input = (parameter.semantic_type is ClassType || parameter.semantic_type is HandleType || parameter.semantic_type is SliceType) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER;
				bool record = parameter.struct_value_contract != null && parameter.struct_value_contract.mode != StructValueMode.BORROW_VALUE;
				if (!scalar && !owner_input && !record) {
					fail (syntax.span, "try_new requires copied values or exact Class/Resource/buffer/record constructor inputs");
					return null;
				}
			}
		}
		var arguments = new GenericArray<CheckedExpression> ();
		uint context_borrow_depth = pending_callable_borrows.length;
		uint reservation_depth = enum_reservations.length;
		if (context_owner != null) {
			pending_callable_borrows.add (context_owner);
		}
		for (int a = 0; a < syntax.arguments.length; a++) {
			var parameter = owner.constructor.parameters[a];
			var argument = check_argument (syntax.arguments[a], values, owner.name + ".init", parameter, parameter.semantic_type, a);
			if (argument == null) {
				return null;
			}
			if (argument.semantic_type != parameter.semantic_type) {
				fail (argument.span, "heap initializer argument has the wrong exact type");
				return null;
			}
			if (syntax.fallible && argument is CheckedOwnedArgument) {
				var transfer = ((CheckedOwnedArgument) argument).transfer;
				if (transfer != null && (transfer.source.semantic_type != argument.semantic_type || transfer.source.requires_nonnull || transfer.source.incoming_parameter != null && transfer.source.incoming_parameter.requires_nonnull)) {
					fail (argument.span, "fallible input transfer requires an exact nullable source slot");
					return null;
				}
			}
			arguments.add (argument);
		}
		while (pending_callable_borrows.length > context_borrow_depth) {
			pending_callable_borrows.remove_index (pending_callable_borrows.length - 1);
		}
		if (!commit_record_arguments (arguments)) {
			return null;
		}
		while (enum_reservations.length > reservation_depth) {
			var source = enum_reservations[reservation_depth];
			CheckedOwnedArgument? outgoing = null;
			foreach (var input in arguments) {
				var owned = input as CheckedOwnedArgument;
				if (owned != null && owned.transfer != null && owned.transfer.source == source) {
					outgoing = owned;
				}
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.move (source, source.name, syntax.span, owner.constructor, outgoing == null ? -1 : outgoing.parameter.ordinal);
			}
			enum_reservations.remove_index (reservation_depth);
		}
		if (syntax.fallible && generic_owner_flow != null) {
			foreach (var input in arguments) {
				var record = input as CheckedStructArgument;
				var moved = record == null ? null : record.producer as CheckedStructMoveProducer;
				if (moved != null) {
					record_all_events (GenericOwnershipEventKind.ACQUIRE, moved.source, input.span);
				}
			}
			foreach (var input in arguments) {
				var argument = input as CheckedOwnedArgument;
				if (argument != null && argument.transfer != null && tracked_generic_storage_owner (argument.transfer.source)) {
					generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, argument.transfer.source, argument.transfer.source.name, argument.span);
				}
			}
		}
		var storage = new LexicalObjectStorageSymbol (span, name_span, owner, next_object_ordinal++, values.region, syntax.fallible);
		storage.heap_allocated = true;
		storage.cleanup_rank = (int) locals.length;
		var local = new LocalSymbol (span, name_span, type, locals.length, values.region, null, null, owner);
		local.heap_object = true;
		local.object_storage = storage;
		locals.add (local);
		values.insert (local.name, local);
		return new CheckedConstructorObjectInitialization (span, storage, local, owner.constructor, arguments, allocation_context);
	}

	private ClassDeclarationSyntax? com_declaration(SyntaxProgram unit, string name) {
		foreach (var imported in unit.com_interfaces) {
			if (imported.name.spelling () == name && imported.declaration != null) {
				return imported.declaration;
			}
		}
		return null;
	}
	private bool order_com_declaration(ClassDeclarationSyntax syntax, SyntaxProgram unit, GenericArray<ClassDeclarationSyntax> output, HashTable<string, int> state, uint remaining = 32) {
		string name = syntax.name.spelling ();
		if (remaining == 0 || state.lookup (name) == 1) {
			fail (syntax.span, "COM interface inheritance requires an acyclic chain of at most 32 declarations");
			return false;
		}
		if (state.lookup (name) == 2) {
			return true;
		}
		state.insert (name, 1);
		if (syntax.parent_class != null) {
			var parent = com_declaration (unit, syntax.parent_class.spelling ());
			if (parent == null) {
				fail (syntax.parent_class.span, "COM interface base requires its exact declarations-v1 protocol");
				return false;
			}
			if (!order_com_declaration (parent, unit, output, state, remaining - 1)) {
				return false;
			}
		}
		state.insert (name, 2);
		output.add (syntax);
		return true;
	}
	private GenericArray<ClassDeclarationSyntax>? imported_class_declarations(SyntaxProgram unit) {
		var result = new GenericArray<ClassDeclarationSyntax> ();
		foreach (var syntax in unit.c_classes) {
			result.add (syntax);
		}
		var state = new HashTable<string, int> (str_hash, str_equal);
		foreach (var imported in unit.com_interfaces) {
			if (imported.declaration != null && !order_com_declaration (imported.declaration, unit, result, state)) {
				return null;
			}
		}
		return result;
	}
	private GenericArray<SyntaxNode> imported_class_members(ClassDeclarationSyntax syntax, SyntaxProgram unit) {
		var result = new GenericArray<SyntaxNode> ();
		if (syntax.foreign_import.kind == DeclarationPolicyId.COM_IMPORT && syntax.parent_class != null) {
			var parent = com_declaration (unit, syntax.parent_class.spelling ());
			foreach (var member in imported_class_members (parent, unit)) {
				if (!(member is LifecycleDeclarationSyntax)) {
					result.add (member);
				}
			}
		}
		foreach (var member in syntax.members) {
			result.add (member);
		}
		return result;
	}
	private ForeignGObjectImport? gobject_class_identity(ClassDeclarationSyntax syntax) {
		if (syntax.foreign_import.kind != DeclarationPolicyId.GOBJECT_IMPORT) {
			return null;
		}
		string name = "", space = "", version = "", prefix = "", header = "", records = "";
		foreach (var entry in syntax.foreign_import.entries) {
			switch (entry.key.spelling ()) {
			case "type": name = entry.decoded_value;
				break;
			case "namespace": space = entry.decoded_value;
				break;
			case "version": version = entry.decoded_value;
				break;
			case "symbol_prefix": prefix = entry.decoded_value;
				break;
			case "header": header = entry.decoded_value;
				break;
			case "records": records = entry.decoded_value;
				break;
			}
		}
		var result = new ForeignGObjectImport (name, space, version, prefix, header, records);
		if (!result.valid ()) {
			fail (syntax.span, "GObjectImport requires exact type/namespace/version, symbol_prefix and portable SDK header");
			return null;
		}
		return result;
	}
	private bool c_class_identity(ClassDeclarationSyntax syntax, out string prefix, out ForeignLifetime lifetime, out string iid) {
		bool com = syntax.foreign_import.kind == DeclarationPolicyId.COM_IMPORT;
		bool gobject = syntax.foreign_import.kind == DeclarationPolicyId.GOBJECT_IMPORT;
		prefix = "";
		iid = "";
		lifetime = (com || gobject) ? ForeignLifetime.SHARED : ForeignLifetime.UNIQUE;
		string profile = "", ownership = (com || gobject) ? "shared" : "", threading = "";
		foreach (var entry in syntax.foreign_import.entries) {
			switch (entry.key.spelling ()) {
			case "name": prefix = entry.decoded_value;
				break;
			case "profile": profile = entry.decoded_value;
				break;
			case "threading": threading = entry.decoded_value;
				break;
			case "type": case "namespace": case "version": case "symbol_prefix": case "header": case "records": if (!gobject) {
					fail (entry.span, "GType facts require GObjectImport");
					return false;
			}
				break;
			case "iid": if (!com) {
					fail (entry.span, "IID requires a declared COM interface");
					return false;
			}
				iid = entry.decoded_value.ascii_down ();
				break;
			case "lifetime": if (com || gobject) {
					fail (entry.span, "foreign object ownership follows its actual reference authority");
					return false;
			}
				ownership = entry.decoded_value;
				break;
			case "bool_abi": if (com || gobject || entry.decoded_value != "c99") {
					fail (entry.span, "CImport bool ABI requires c99; COM uses standard BOOL32");
					return false;
			}
				break;
				default: fail (entry.span, "unsupported declaration-driven foreign import fact");
				return false;
			}
		}
		if (profile != "declarations-v1" || !ForeignClassPolicy.identifier (prefix) || prefix.has_prefix ("astra_") || ownership != "unique" && ownership != "shared" || threading != "constructing" || syntax.type_parameters.length != 0 || !com && syntax.parent_class != null || syntax.fields.length != 0 || com && !ComExportContract.guid (iid)) {
			fail (syntax.span, "declaration-driven imports require a portable name, exact root lifetime, constructing-thread context, fieldless nongeneric declarations and a valid COM IID when selected");
			return false;
		}
		if (gobject && gobject_class_identity (syntax) == null) {
			return false;
		}
		lifetime = ownership == "shared" ? ForeignLifetime.SHARED : ForeignLifetime.UNIQUE;
		return true;
	}
	private bool collect_c_class_handles(SyntaxProgram unit, GenericArray<HandleSymbol> handles) {
		var prefixes = new HashTable<string, bool> (str_hash, str_equal);
		var iids = new HashTable<string, bool> (str_hash, str_equal);
		var imports = imported_class_declarations (unit);
		if (imports == null) {
			return false;
		}
		foreach (var syntax in imports) {
			string prefix;
			ForeignLifetime lifetime;
			string iid;
			if (!c_class_identity (syntax, out prefix, out lifetime, out iid)) {
				return false;
			}
			if (iid != "") {
				if (iids.contains (iid)) {
					fail (syntax.span, "COM interface declarations require distinct explicit IIDs");
					return false;
				}
				iids.insert (iid, true);
			}
			string name = syntax.name.spelling ();
			if (named_types.contains (name) || types.resolve (name) != null || prefixes.contains (prefix)) {
				fail (syntax.span, "duplicate imported Class nominal name or prefix");
				return false;
			}
			var cleanup = intern_cleanup (new CForeignCleanupContract ("astra_foreign16_import_cleanup_" + prefix, syntax.span));
			var handle = new HandleSymbol (syntax.span, syntax.name.span, cleanup, null, handles.length, ForeignImportContract.root_identity (name, prefix, lifetime, iid, gobject_class_identity (syntax), foreign_selection));
			c_class_kinds.insert (handle.semantic_type, syntax.foreign_import.kind == DeclarationPolicyId.GOBJECT_IMPORT ? ForeignValueKind.GOBJECT : iid == "" ? ForeignValueKind.NATIVE_OBJECT : ForeignValueKind.COM_OBJECT);
			c_class_prefixes.insert (handle.semantic_type, prefix);
			if (lifetime == ForeignLifetime.SHARED) {
				c_class_shared.insert (handle.semantic_type, true);
			}
			handles.add (handle);
			named_types.insert (name, handle.semantic_type);
			handle_types.insert (handle.semantic_type, handle);
			prefixes.insert (prefix, true);
		}
		return true;
	}
	private GenericArray<FunctionSymbol>? collect_c_class_functions(SyntaxProgram unit, GenericArray<NativeInstanceSymbol> instances) {
		var output = new GenericArray<FunctionSymbol> ();
		var imports = imported_class_declarations (unit);
		if (imports == null) {
			return null;
		}
		foreach (var syntax in imports) {
			string prefix;
			ForeignLifetime lifetime;
			string iid;
			if (!c_class_identity (syntax, out prefix, out lifetime, out iid)) {
				return null;
			}
			var gobject = gobject_class_identity (syntax);
			uint personality = gobject != null ? ForeignClassPolicy.GOBJECT : iid == "" ? ForeignClassPolicy.C : ForeignClassPolicy.COM;
			var handle = handle_types.lookup (named_types.lookup (syntax.name.spelling ()));
			var members = new GenericArray<ForeignMemberContract> ();
			var targets = new GenericArray<FunctionSymbol> ();
			string[] factories = {};
			string[] native_names = {};
			string[] protocol_names = {};
			var declarations = new GenericArray<FunctionDeclarationSyntax> ();
			var kinds = new GenericArray<ForeignMemberKind> ();
			var ordinals = new GenericArray<int> ();
			string[] properties = {};
			var source_names = new HashTable<string, bool> (str_hash, str_equal);
			var source_members = imported_class_members (syntax, unit);
			for (int m = 0; m < source_members.length; m++) {
				var source = source_members[m];
				var method = source as FunctionDeclarationSyntax;
				var property = source as PropertyDeclarationSyntax;
				string source_name = method != null ? method.name.spelling() : property == null ? "" : property.name.spelling ();
				if (source_name == "" || source_names.contains (source_name)) {
					fail (source.span, "CImport requires unique declared method and property names");
					return null;
				}
				source_names.insert (source_name, true);
				if (method != null) {
					declarations.add (method);
					kinds.add ((method is LifecycleDeclarationSyntax) ? ForeignMemberKind.CONSTRUCTOR : ForeignMemberKind.METHOD);
					ordinals.add (m);
					properties += "";
					continue;
				}
				if (property.foreign_member == null || property.throws_class == null || property.is_borrowed || property.is_lazy || property.dispatch != MemberDispatchSyntax.DIRECT) {
					fail (property.span, "CImport properties require selected checked accessors with explicit result ownership");
					return null;
				}
				var annotations = new HashTable<string, bool> (str_hash, str_equal);
				foreach (var annotation in property.foreign_channels) {
					string parameter = "";
					foreach (var entry in annotation.entries) {
						if (entry.key.spelling () == "parameter") {
							parameter = entry.decoded_value;
						}
					}
					if (annotations.contains (parameter) || parameter != "result" && (property.setter == null || parameter != property.setter.parameter.name.spelling ()) || property.setter != null && property.setter.parameter.name.spelling () == "result") {
						fail (annotation.span, "property ForeignChannel must select its getter result or unique explicit setter parameter");
						return null;
					}
					annotations.insert (parameter, true);
				}
				foreach (var accessor in new PropertyAccessorSyntax?[] { property.getter, property.setter }) {
					if (accessor == null) {
						continue;
					}
					bool get = accessor == property.getter;
					string generated = "__astra_import_%s_%d".printf (get ? "get" : "set", m);
					bool collision = false;
					do {
						collision = false;
						foreach (var candidate in syntax.members) {
							var named = candidate as FunctionDeclarationSyntax;
							if (named != null && named.name.spelling () == generated) {
								generated += "_";
								collision = true;
								break;
							}
						}
					} while (collision);
					var parameters = new GenericArray<ParameterSyntax> ();
					if (!get) {
						parameters.add (accessor.parameter);
					}
					var result = get ? property.type_name : new TypeNameSyntax (new Token.generated (TokenKind.IDENTIFIER, property.type_name.span, "void"));
					var declaration = new FunctionDeclarationSyntax (result, new Token.generated (TokenKind.IDENTIFIER, property.name.span, generated), property.name, parameters, new GenericArray<Token> (), property.name, accessor.body, null, null, get ? property.owned_keyword : null);
					declaration.throws_class = property.throws_class;
					declaration.foreign_member = property.foreign_member;
					foreach (var annotation in property.foreign_channels) {
						string selected = "";
						foreach (var entry in annotation.entries) {
							if (entry.key.spelling () == "parameter") {
								selected = entry.decoded_value;
							}
						}
						if (get == (selected == "result")) {
							declaration.foreign_channels.add (annotation);
						}
					}
					declarations.add (declaration);
					kinds.add (get ? ForeignMemberKind.GETTER : ForeignMemberKind.SETTER);
					ordinals.add (m);
					properties += property.name.spelling ();
				}
			}
			for (int d = 0; d < declarations.length; d++) {
				var declaration = declarations[d];
				int m = ordinals[d];
				var kind = kinds[d];
				string property_name = properties[d];
				var selection = declaration == null ? null : declaration.foreign_member;
				if (declaration == null || selection == null || declaration.body.statements.length != 0 || declaration.type_parameters.length != 0 || declaration.throws_class == null) {
					fail (source_members[m].span, "CImport members require selected bodyless checked declarations");
					return null;
				}
				bool constructor = declaration is LifecycleDeclarationSyntax && ((LifecycleDeclarationSyntax) declaration).is_constructor;
				if (declaration is LifecycleDeclarationSyntax && !constructor) {
					fail (declaration.span, "CImport destruction follows its explicit root lifetime");
					return null;
				}
				var result_type = constructor ? handle.semantic_type : resolve_type (declaration.return_type);
				if (result_type == null) {
					return null;
				}
				bool owned_bytes = !constructor && ForeignApiTypes.byte_view (result_type) && declaration.owned_keyword != null;
				string result_prefix = "";
				bool result_shared = false;
				ForeignValueKind result_kind = ForeignValueKind.NATIVE_OBJECT;
				bool owned_object = constructor || declaration.owned_keyword != null && imported_c_root (result_type, out result_prefix, out result_shared, out result_kind);
				if (constructor) {
					result_prefix = prefix;
					result_shared = lifetime == ForeignLifetime.SHARED;
					result_kind = gobject != null ? ForeignValueKind.GOBJECT : iid == "" ? ForeignValueKind.NATIVE_OBJECT : ForeignValueKind.COM_OBJECT;
				}
				var result_value = owned_object ? new ForeignValueType (result_kind, result_type.nominal_name ()) : owned_bytes ? new ForeignValueType (ForeignValueKind.BYTES) : ForeignApiTypes.copied (result_type, (type) => ForeignApiAdmission.record_for (type, instances));
				var error_type = resolve_type (declaration.throws_class) as ClassType;
				if (result_value == null || error_type == null || error_type.is_interface || !owned_object && !owned_bytes && declaration.owned_keyword != null) {
					fail (declaration.span, "CImport result or exact checked exception type is not supported");
					return null;
				}
				string name = constructor ? (iid == "" ? "create" : "acquire") : property_name != "" ? property_name : declaration.name.spelling (), factory_name = "", mapping_text = "", native_binding = property_name != "" ? property_name : declaration.name.spelling ();
				int64 domain = 0, null_status = 0;
				foreach (var entry in selection.entries) {
					switch (entry.key.spelling ()) {
					case "name": name = entry.decoded_value;
						break;
					case "native": if (iid == "") {
							fail (entry.span, "native mapping requires a declared foreign interface");
							return null;
					}
						native_binding = entry.decoded_value;
						break;
					case "error_factory": factory_name = entry.decoded_value;
						break;
					case "errors": mapping_text = entry.decoded_value;
						break;
					case "error_domain": if (!int64.try_parse (entry.decoded_value, out domain)) {
							domain = 0;
					}
						break;
					case "null_status": if (!int64.try_parse (entry.decoded_value, out null_status) || null_status <= 0 || null_status > int32.MAX) {
							fail (entry.span, "CImport null_status requires a positive i32 nullable-result status");
							return null;
					}
						break;
						default: fail (entry.span, "unsupported imported Foreign member fact");
						return null;
					}
				}
				if (kind == ForeignMemberKind.GETTER || kind == ForeignMemberKind.SETTER) {
					name = (kind == ForeignMemberKind.GETTER ? "get_" : "set_") + name;
					if (kind == ForeignMemberKind.SETTER) {
						null_status = 0;
					}
				}
				var error_factory = function_names.lookup (factory_name) as FunctionSymbol;
				if (error_factory == null || error_factory is GenericFunctionSymbol || error_factory.implicit_receiver != null || error_factory.async_body != null || error_factory.throws_type != null || error_factory.return_type != error_type || error_factory.result_contract != ResultOwnershipContract.OWNED_TRANSFER || error_factory.parameters.length != 2 || error_factory.parameters[0].semantic_type.kind != TypeKind.INT || error_factory.parameters[1].semantic_type.kind != TypeKind.INT || error_factory.parameters[0].pointer_contract != PointerParameterContract.UNMANAGED || error_factory.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED || domain <= 0 || domain > int32.MAX) {
					fail (declaration.span, "CImport error_factory requires an exact nonthrowing owned heap exception factory(i32 domain,i32 status) and positive error domain");
					return null;
				}
				var cases = new GenericArray<ForeignErrorCase> ();
				foreach (string item in mapping_text.split (",")) {
					string[] pair = item.strip ().split ("=");
					int64 status = 0;
					if (pair.length != 2 || !int64.try_parse (pair[1], out status) || status < int32.MIN || status >= 0) {
						fail (declaration.span, "CImport errors requires named negative i32 status mappings");
						return null;
					}
					cases.add (new ForeignErrorCase (pair[0].strip (), (int32) status));
				}
				var mapping = new ForeignErrorMap ((int32) domain, cases);
				var parameters = new GenericArray<ParameterSymbol> ();
				var channels = new GenericArray<ForeignChannel> ();
				var annotations = new HashTable<string, ForeignPolicySyntax> (str_hash, str_equal);
				foreach (var annotation in declaration.foreign_channels) {
					string selected_parameter = "";
					foreach (var entry in annotation.entries) {
						if (entry.key.spelling () == "parameter") {
							selected_parameter = entry.decoded_value;
						}
					}
					bool found = selected_parameter == "result";
					foreach (var parameter in declaration.parameters) {
						if (selected_parameter == "result" && parameter.name.spelling () == "result") {
							fail (annotation.span, "ForeignChannel result is ambiguous with an actual parameter named result");
							return null;
						}
						found |= parameter.name.spelling () == selected_parameter;
					}
					if (!found || annotations.contains (selected_parameter)) {
						fail (annotation.span, "CImport ForeignChannel requires one unique actual native parameter");
						return null;
					}
					annotations.insert (selected_parameter, annotation);
				}
				string receiver_name = "__astra_foreign_receiver";
				bool collision = true;
				while (collision) {
					collision = false;
					foreach (var parameter in declaration.parameters) {
						if (parameter.name.spelling () == receiver_name) {
							receiver_name += "_";
							collision = true;
							break;
						}
					}
				}
				if (!constructor) {
					parameters.add (new ParameterSymbol (declaration.span, syntax.name.span, handle.semantic_type, 0, PointerParameterContract.BORROWED_NOESCAPE, receiver_name));
				}
				var logical_parameters = new GenericArray<ParameterSymbol> ();
				foreach (var parameter in declaration.parameters) {
					var type = resolve_type (parameter.type_name);
					var value = type == null ? null : ForeignApiTypes.copied (type, (type) => ForeignApiAdmission.record_for (type, instances));
					var pointee = type == null ? null : ForeignApiTypes.scalar_pointee (type);
					bool reference = pointee != null && parameter.borrowed_keyword != null;
					bool bytes = type != null && ForeignApiTypes.byte_view (type) && parameter.borrowed_keyword != null;
					bool text = type is StringType;
					bool callback = type is CallbackType && parameter.borrowed_keyword != null;
					bool query_input = iid != "" && constructor && declaration.parameters.length == 1 && type != null && type.is_void_pointer () && parameter.borrowed_keyword != null;
					string object_prefix;
					bool object_shared;
					ForeignValueKind object_kind = ForeignValueKind.NATIVE_OBJECT;
					bool object = type != null && imported_c_root (type, out object_prefix, out object_shared, out object_kind);
					bool owns_object = object && parameter.owned_keyword != null;
					if ((!query_input && !callback && !reference && !bytes && !text && !object && (value == null || !value.scalar () && value.kind != ForeignValueKind.RECORD || parameter.borrowed_keyword != null)) || parameter.owned_keyword != null && !owns_object || parameter.caller_information != null) {
						fail (parameter.span, "CImport parameter channel is not implemented for this native type");
						return null;
					}
					var symbol = new ParameterSymbol (parameter.span, parameter.name.span, type, parameters.length, owns_object ? PointerParameterContract.OWNED_TRANSFER : query_input || callback || reference || bytes || text || object ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED);
					if (type.is_struct_storage ()) {
						symbol.struct_value_contract = new StructValueContract (type, StructValueMode.COPY_VALUE);
					}
					parameters.add (symbol);
					logical_parameters.add (symbol);
				}
				var logical = new FunctionSymbol (declaration.span, declaration.name.span, result_type, logical_parameters);
				var normalizer = new ForeignParameterAdmission ((type) => ForeignApiAdmission.record_for (type, instances), imported_c_root);
				foreach (var parameter in logical_parameters) {
					if (iid != "" && constructor) {
						if (logical_parameters.length != 1 || !parameter.semantic_type.is_void_pointer () || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || name != "acquire") {
							fail (declaration.span, "COM acquisition requires one borrowed IUnknown pointer and its checked error factory");
							return null;
						}
						var annotation = annotations.lookup (parameter.name);
						if (annotation != null) {
							foreach (var entry in annotation.entries) {
								string key = entry.key.spelling (), value = entry.decoded_value;
								if (key == "parameter" || key == "direction" && value == "in" || key == "scope" && value == "call" || key == "transfer" && value == "none" || key == "nullable" && value == "false") {
									continue;
								}
								fail (entry.span, "COM acquisition requires a mandatory call-scoped IUnknown pointer");
								return null;
							}
						}
						channels.add (new ForeignChannel (parameter.name, new ForeignValueType (ForeignValueKind.COM_OBJECT, "IUnknown"), ForeignDirection.IN, ForeignTransfer.BORROW, false, ForeignTextEncoding.NONE, -1, -1, -1, "", true));
						continue;
					}
					var channel = normalizer.parameter_channel (logical, parameter, declaration, annotations.lookup (parameter.name));
					if (channel == null) {
						diagnostic = normalizer.diagnostic;
						return null;
					}
					channels.add (channel);
				}
				var encoding = owned_bytes ? ForeignTextEncoding.BYTES : ForeignTextEncoding.NONE;
				var result_annotation = annotations.lookup ("result");
				bool nullable_result = false;
				if (!constructor && owned_object && result_annotation != null) {
					foreach (var entry in result_annotation.entries) {
						if (entry.key.spelling () == "nullable" && entry.decoded_value == "true") {
							nullable_result = true;
						}
					}
				}
				if (owned_bytes && result_annotation != null) {
					foreach (var entry in result_annotation.entries) {
						if (entry.key.spelling () == "encoding") {
							if (entry.decoded_value == "utf8-counted") {
								encoding = ForeignTextEncoding.UTF8_COUNTED;
							} else if (entry.decoded_value == "utf8-nul") {
								encoding = ForeignTextEncoding.UTF8_NUL;
							}
						}
					}
				}
				if (owned_bytes && encoding != ForeignTextEncoding.BYTES) {
					result_value = new ForeignValueType (ForeignValueKind.TEXT);
				}
				var result = owned_object ? new ForeignChannel ("result", result_value, ForeignDirection.OUT, ForeignTransfer.OWN, nullable_result, ForeignTextEncoding.NONE, -1, -1, -1, result_prefix + (result_shared ? "_release" : "_destroy")) : owned_bytes ? new ForeignChannel ("result", result_value, ForeignDirection.OUT, ForeignTransfer.OWN, false, encoding, -1, -1, -1, prefix + (encoding == ForeignTextEncoding.BYTES ? "_bytes_release" : "_text_release"), false, -1, -1, encoding != ForeignTextEncoding.UTF8_NUL) : new ForeignChannel ("result", result_value, ForeignDirection.OUT);
				if (result_annotation != null) {
					foreach (var entry in result_annotation.entries) {
						string key = entry.key.spelling (), value = entry.decoded_value;
						if (key == "parameter" || key == "direction" && value == "out" || key == "transfer" && value == (result.transfer == ForeignTransfer.OWN ? "full" : "none") || key == "nullable" && value == (nullable_result ? "true" : "false") || key == "encoding" && value == (encoding == ForeignTextEncoding.BYTES ? "bytes" : encoding == ForeignTextEncoding.UTF8_COUNTED ? "utf8-counted" : encoding == ForeignTextEncoding.UTF8_NUL ? "utf8-nul" : "none")) {
							continue;
						}
						fail (entry.span, "ForeignChannel result facts differ from its actual result ownership or representation");
						return null;
					}
				}
				var member = new ForeignMemberContract (kind, name, ForeignApiTypes.member_key (handle.name, kind, m), channels, result, error_type.nominal_name (), personality, m, mapping, (int32) null_status);
				if (!member.valid () || !ForeignApiTypes.errors (member, error_type, (name) => named_types.lookup (name) as ClassType)) {
					fail (declaration.span, "inconsistent imported member status/channel contract");
					return null;
				}
				var function = new FunctionSymbol (declaration.span, declaration.name.span, result_type, parameters, owned_object || owned_bytes ? ResultOwnershipContract.OWNED_TRANSFER : ResultOwnershipContract.UNMANAGED, owned_object ? handle_types.lookup (result_type).cleanup : null, CallableDomain.NATIVE, handle.name + "." + declaration.name.spelling ());
				function.throws_type = error_type;
				function.foreign_error_factory = error_factory;
				if (result_type.is_struct_storage ()) {
					function.struct_result_contract = new StructValueContract (result_type, StructValueMode.COPY_VALUE);
				}
				if (function_names.contains (function.name)) {
					fail (declaration.span, "duplicate imported member name");
					return null;
				}
				function_names.insert (function.name, function);
				members.add (member);
				targets.add (function);
				factories += factory_name;
				native_names += declaration.name.spelling ();
				protocol_names += native_binding;
				if (kind == ForeignMemberKind.GETTER) {
					imported_getters.insert (handle.name + "." + property_name, function);
				}
				if (kind == ForeignMemberKind.SETTER) {
					var getter = imported_getters.lookup (handle.name + "." + property_name);
					if (getter == null || channels.length != 1 || !members[members.length - 2].result.value_type.equal (channels[0].value_type)) {
						fail (declaration.span, "imported property accessors require the same exact logical value type");
						return null;
					}
					imported_setters.insert (handle.name + "." + property_name, function);
				}
			}
			bool declared_bool = false, uses_bool = false;
			foreach (var entry in syntax.foreign_import.entries) {
				declared_bool |= entry.key.spelling () == "bool_abi" && entry.decoded_value == "c99";
			}
			foreach (var member in members) {
				uses_bool |= ForeignApiTypes.uses_bool (member.result.value_type);
				for (uint p = 0; p < member.parameter_count; p++) {
					uses_bool |= ForeignApiTypes.uses_bool (member.parameter (p).value_type);
				}
			}
			if (gobject == null && iid == "" && uses_bool != declared_bool) {
				fail (syntax.span, "CImport copied bool channels require explicit bool_abi=c99");
				return null;
			}
			ForeignComInterface? protocol = null;
			if (iid != "") {
				ForeignComInterface? parent = null;
				if (syntax.parent_class != null) {
					var parent_handle = handle_types.lookup (named_types.lookup (syntax.parent_class.spelling ()));
					parent = parent_handle == null || parent_handle.c_import == null ? null : parent_handle.c_import.com;
					if (parent == null) {
						fail (syntax.parent_class.span, "COM base protocol lost its admitted declaration");
						return null;
					}
				}
				var own = new GenericArray<ForeignMemberContract> ();
				string[] bindings = {};
				uint inherited = parent == null ? 0 : parent.requirement_count, requirement = 0;
				for (uint index = 0; index < members.length; index++) {
					var member = members[index];
					if (member.kind == ForeignMemberKind.CONSTRUCTOR) {
						continue;
					}
					if (requirement++ < inherited) {
						continue;
					}
					own.add (member);
					bindings += protocol_names[index];
				}
				protocol = new ForeignComInterface (handle.name, prefix, iid, own, bindings, parent);
			}
			var api = new ForeignApiContract (handle.name, prefix, lifetime, personality, members, foreign_selection);
			var contract = new ForeignImportContract (api, factories, native_names, protocol, gobject);
			if (!contract.valid ()) {
				fail (syntax.span, "invalid imported Class schema, names, or lifetime");
				return null;
			}
			handle.c_import = contract;
			for (uint m = 0; m < targets.length; m++) {
				targets[m].foreign_import = new ForeignImportBinding (contract, m);
				output.add (targets[m]);
			}
		}
		return output;
	}
	private CallExpressionSyntax? imported_member(CallExpressionSyntax syntax, ValueScope values, out DirectCallableSymbol? target) {
		target = null;
		if (syntax.receiver == null && syntax.receiver_place == null || syntax.type_arguments.length != 0 || syntax.qualifier_arguments.length != 0) {
			return null;
		}
		var value = syntax.receiver == null ? null : values.lookup (syntax.receiver.spelling ());
		var type = syntax.receiver_place != null ? place_context_type(syntax.receiver_place, values) : (value is LocalSymbol) ? ((LocalSymbol) value).semantic_type : (value is ParameterSymbol) ? ((ParameterSymbol) value).semantic_type : named_types.lookup (syntax.receiver.spelling ());
		var handle = type == null ? null : handle_types.lookup (type);
		if (handle == null || handle.c_import == null) {
			return null;
		}
		var function = function_names.lookup (handle.name + "." + syntax.identifier.spelling ()) as FunctionSymbol;
		bool instance = syntax.receiver_place != null || value != null;
		if (function == null || function.foreign_import == null || (function.foreign_import.member.kind == ForeignMemberKind.CONSTRUCTOR) == instance) {
			return null;
		}
		target = function;
		var arguments = new GenericArray<ExpressionSyntax> ();
		if (instance) {
			arguments.add (syntax.receiver_place ?? new NameExpressionSyntax (syntax.receiver));
		}
		foreach (var argument in syntax.arguments) {
			arguments.add (argument);
		}
		return new CallExpressionSyntax (syntax.identifier, syntax.open_paren, arguments, syntax.commas, syntax.close_paren);
	}
	private FunctionSymbol? imported_property_for_type(SemanticType? type, string name, bool setter = false) {
		var handle = type == null ? null : handle_types.lookup (type);
		return handle == null || handle.c_import == null ? null : (setter ? imported_setters : imported_getters).lookup (handle.name + "." + name);
	}
	private FunctionSymbol? imported_property(FieldAccessExpressionSyntax syntax, ValueScope values, bool setter = false) {
		if (syntax.indirect) {
			return null;
		}
		var receiver = syntax.aggregate ?? new NameExpressionSyntax (syntax.identifier);
		return imported_property_for_type (place_context_type (receiver, values), syntax.field_name.spelling (), setter);
	}
	private CallExpressionSyntax? imported_property_call(ExpressionSyntax input, ValueScope values, ExpressionSyntax? replacement = null) {
		var syntax = input as FieldAccessExpressionSyntax;
		if (syntax == null) {
			return null;
		}
		var function = imported_property (syntax, values, replacement != null);
		if (function == null) {
			if (replacement != null && imported_property (syntax, values) != null) {
				fail (syntax.span, "imported property is read-only: missing setter");
			}
			return null;
		}
		var arguments = new GenericArray<ExpressionSyntax> ();
		if (replacement != null) {
			arguments.add (replacement);
		}
		string local_name = function.name.substring (function.name.last_index_of_char ('.') + 1);
		var name = new Token.generated (TokenKind.IDENTIFIER, syntax.field_name.span, local_name);
		return new CallExpressionSyntax (name, syntax.field_name, arguments, new GenericArray<Token> (), new Token (TokenKind.CLOSE_PAREN, replacement == null ? syntax.field_name.span : replacement.span), syntax.aggregate == null ? syntax.identifier : null, syntax.dot, syntax.aggregate);
	}

	private GenericArray<HandleSymbol>? collect_handles(GenericArray<ForeignHandleInput>? inputs) {
		var handles = new GenericArray<HandleSymbol> ();
		if (inputs == null) {
			return handles;
		}
		foreach (var input in inputs) {
			string name = input.name_span.text ();
			if (input.context_mode != "" && !AllocationPolicy.valid_context_mode (input.context_mode)) {
				fail (input.name_span, "allocator context requires a versioned owned-affine, owned-transfer, owned-concurrent or scoped-affine contract");
				return null;
			}
			if (types.resolve (name) != null || named_types.contains (name)) {
				fail (input.name_span, "handle type '%s' conflicts with an existing type".printf (name));
				return null;
			}
			if (RetainedContracts.reserved_symbol (input.cleanup.external_symbol)) {
				fail (input.cleanup.symbol_span ?? input.name_span, "compiler-private retained callback runtime symbol cannot be declared by source");
				return null;
			}
			if (AllocationPolicy.reserved_symbol (input.cleanup.external_symbol)) {
				fail (input.cleanup.symbol_span ?? input.name_span, "compiler-private allocation runtime symbol cannot be declared as a Resource destructor");
				return null;
			}
			if (input.cleanup.external_symbol == "") {
				fail (input.cleanup.symbol_span ?? input.name_span, "handle destroy_function must be nonempty");
				return null;
			}
			var header = input.header == null ? null : new CForeignHeader (input.header.name, input.header.span);
			var symbol = new HandleSymbol (input.span, input.name_span, intern_cleanup (input.cleanup), header, handles.length, "", input.context_mode);
			handles.add (symbol);
			named_types.insert (name, symbol.semantic_type);
			handle_types.insert (symbol.semantic_type, symbol);
		}
		return handles;
	}
	private bool collect_com_handles(SyntaxProgram unit, GenericArray<HandleSymbol> handles) {
		var prefixes = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var syntax in unit.com_interfaces) {
			if (syntax.declaration != null) {
				continue;
			}
			string prefix = "", iid = "", view = "", threading = "";
			foreach (var entry in syntax.policy.entries) {
				switch (entry.key.spelling ()) {
				case "name": prefix = entry.decoded_value;
					break;
				case "iid": iid = entry.decoded_value;
					break;
				case "view": view = entry.decoded_value;
					break;
				case "threading": threading = entry.decoded_value;
					break;
					default: fail (entry.span, "unsupported COMImport argument");
					return false;
				}
			}
			var contract = new ComImportContract (syntax.name.spelling (), prefix, iid, view);
			if (!contract.valid () || threading != "constructing" || prefixes.contains (prefix) || named_types.contains (contract.native_name) || types.resolve (contract.native_name) != null) {
				fail (syntax.span, "COMImport requires a unique nominal name/prefix, explicit application IID, value/scale view and threading=constructing");
				return false;
			}
			var cleanup = intern_cleanup (new CForeignCleanupContract (prefix + "_release", syntax.span));
			var symbol = new HandleSymbol (syntax.span, syntax.name.span, cleanup, null, handles.length, contract.identity ());
			symbol.com_import = contract;
			handles.add (symbol);
			named_types.insert (symbol.name, symbol.semantic_type);
			handle_types.insert (symbol.semantic_type, symbol);
			prefixes.insert (prefix, true);
		}
		return true;
	}
	private bool collect_com_functions(HandleSymbol handle, GenericArray<CFunctionSymbol> output) {
		var contract = handle.com_import;
		foreach (var role in new ComImportRole[] { ComImportRole.ACQUIRE, ComImportRole.CLONE, ComImportRole.GET, ComImportRole.SET, ComImportRole.SCALE }) {
			if (!contract.admits (role)) {
				continue;
			}
			bool owner_result = role == ComImportRole.ACQUIRE || role == ComImportRole.CLONE;
			var parameters = new GenericArray<ForeignParameterInput> ();
			parameters.add (new ForeignParameterInput (handle.span, handle.name_span, handle.name_span, role == ComImportRole.ACQUIRE ? "void*" : handle.name, PointerParameterContract.BORROWED_NOESCAPE, "self"));
			if (role == ComImportRole.SET || role == ComImportRole.SCALE) {
				parameters.add (new ForeignParameterInput (handle.span, handle.name_span, handle.name_span, "int", PointerParameterContract.UNMANAGED, "value"));
			}
			if (role != ComImportRole.SET) {
				parameters.add (new ForeignParameterInput (handle.span, handle.name_span, handle.name_span, "int*", PointerParameterContract.BORROWED_NOESCAPE, "out"));
			}
			string name = contract.prefix + "_" + ComImportContract.suffix (role);
			var metadata = new CForeignMetadata (name, null, null, null, CTextAbi.NONE, null, CBufferAbi.NONE, null, CRecordAbi.NONE, null, null, CCallbackAbi.NONE, null, role == ComImportRole.SET ? CPointerAbi.NONE : CPointerAbi.I32_NOESCAPE, contract, role);
			var symbol = collect_foreign_signature (new ForeignDeclarationInput (handle.span, handle.name_span, handle.name_span, parameters, metadata, owner_result ? handle.name : "int", owner_result, name));
			if (symbol == null) {
				return false;
			}
			output.add (symbol);
		}
		return true;
	}

	private bool check_struct_layout(StructSymbol structure, HashTable<StructSymbol, StructSymbol> complete, GenericArray<StructSymbol> active) {
		if (complete.contains (structure)) {
			return true;
		}
		for (int i = 0; i < active.length; i++) {
			if (active[i] != structure) {
				continue;
			}
			var path = new StringBuilder ();
			for (int j = i; j < active.length; j++) {
				path.append (active[j].name + " → ");
			}
			path.append (structure.name);
			fail (structure.name_span, "recursive by-value struct layout: " + path.str);
			return false;
		}
		active.add (structure);
		foreach (var field in structure.fields) {
			if (field.semantic_type is StructType && !check_struct_layout ((StructSymbol) instance_for (field.semantic_type), complete, active)) {
				return false;
			}
		}
		active.remove_index (active.length - 1);
		complete.insert (structure, structure);
		return true;
	}

	private bool policy_uint(CCodeEntrySyntax entry, out uint value) {
		value = 0;
		for (int i = 0; i < entry.decoded_value.length; i++) {
			char digit = entry.decoded_value[i];
			if (digit < '0' || digit > '9' || value > (uint.MAX - (uint) (digit - '0')) / 10) {
				fail (entry.span, "storage policy requires an unsigned decimal integer in range");
				return false;
			}
			value = value * 10 + (uint) (digit - '0');
		}
		return true;
	}
	private bool bind_pod_representation(StructSymbol owner, NativeInstanceDeclarationSyntax syntax) {
		var type = (StructType) owner.semantic_type;
		if (syntax.representation == null && syntax.alignment == null) {
			return type.bind_representation ("");
		}
		string layout = "", members = "", active = "";
		uint tag = 0;
		bool has_tag = false;
		if (syntax.representation != null) {
			foreach (var entry in syntax.representation) {
				switch (entry.key.spelling ()) {
				case "layout": layout = entry.decoded_value;
					break;
				case "members": members = entry.decoded_value;
					break;
				case "active": active = entry.decoded_value;
					break;
				case "tag": has_tag = true;
					if (!policy_uint (entry, out tag)) {
						return false;
					}
					break;
					default: fail (entry.span, "unsupported Repr option");
					return false;
				}
			}
		}
		bool union_layout = layout == "C-union" || layout == "C-tagged-union";
		if (syntax.representation == null || !union_layout && (syntax.representation.length != 1 || layout != "C")) {
			fail (syntax.span, "Repr requires layout=\"C\" on a natural scalar POD record; Align alone does not change native record layout");
			return false;
		}
		if (union_layout && (members == "" || active == "" || has_tag != (layout == "C-tagged-union"))) {
			fail (syntax.span, "C union projection requires explicit members/active; tagged form additionally requires one tag value");
			return false;
		}
		uint alignment = 1;
		if (syntax.alignment != null && (syntax.alignment.length != 1 || syntax.alignment[0].key.spelling () != "bytes" || !policy_uint (syntax.alignment[0], out alignment))) {
			fail (syntax.span, "POD Align requires one decimal bytes option");
			return false;
		}
		string[] names = {};
		string[] types = {};
		foreach (var field in owner.fields) {
			names += field.name;
			types += field.semantic_type.display_name ();
			if (field.is_owned_field) {
				fail (field.span, "Repr(C) excludes owned fields");
				return false;
			}
		}
		var policy = new PodRepresentation (owner.name, names, types, alignment, members, active, layout == "C-tagged-union", tag);
		if (union_layout && !policy.valid ()) {
			fail (syntax.span, "C union projection requires 2..8 named i64/u64 members, one matching active field, and optional leading i64 tag with value 0..2147483647; no inactive-member access or reinterpretation");
			return false;
		}
		if (!policy.valid () || !type.bind_representation (policy.identity) || owner.methods.length != 0 || owner.properties.length != 0) {
			fail (syntax.span, "Repr(C) admits 1..32 natural scalar POD fields; requested Align cannot exceed natural C alignment");
			return false;
		}
		owner.representation = policy;
		return true;
	}
	private bool bind_class_allocation(ClassSymbol owner, NativeInstanceDeclarationSyntax syntax) {
		if (syntax.representation != null) {
			fail (syntax.span, "Repr(C) requires an eligible POD record; native Class layout is not a C representation");
			return false;
		}
		var type = (ClassType) owner.semantic_type;
		var concurrency = syntax.concurrency_policy;
		if (!ConcurrencyPolicy.matches (concurrency, concurrency == null ? 0 : concurrency.identity) || !type.bind_concurrency_policy (concurrency == null ? 0 : concurrency.identity)) {
			fail (syntax.span, "invalid concurrency declaration policy identity");
			return false;
		}
		if (concurrency != null && concurrency.actor && concurrency.identity != 16) {
			fail (syntax.span, "Actor requires its exclusive dedicated-executor policy");
			return false;
		}
		if (concurrency != null && owner.generic_instance != null) {
			fail (syntax.span, "declaration concurrency policies currently require a nongeneric Class; generic containers may own qualified shared elements");
			return false;
		}
		owner.concurrency_policy = concurrency == null ? null : concurrency.copy ();
		if (syntax.allocator == null && syntax.alignment == null) {
			if (!type.bind_allocation_policy ("")) {
				fail (syntax.span, "Class allocation identity differs from its declaration");
				return false;
			}
			return true;
		}
		uint alignment = 1;
		if (syntax.alignment != null) {
			if (syntax.alignment.length != 1 || syntax.alignment[0].key.spelling () != "bytes" || !policy_uint (syntax.alignment[0], out alignment) || !AllocationPolicy.power_of_two (alignment) || alignment > 4096) {
				fail (syntax.span, "Align requires bytes to be a supported power of two, at most 4096");
				return false;
			}
		}
		var kind = AllocationKind.HEAP;
		uint capacity = 0;
		uint blocks = 0;
		bool blocks_specified = false;
		string domain = "class_" + Checksum.compute_for_string (ChecksumType.SHA256, owner.name);
		string? allocate = null;
		string? release = null;
		string context_mode = "";
		if (syntax.allocator != null) {
			foreach (var entry in syntax.allocator) {
				switch (entry.key.spelling ()) {
				case "kind": kind = AllocationKind.parse (entry.decoded_value);
					break;
				case "domain": domain = entry.decoded_value;
					break;
				case "capacity": if (!policy_uint (entry, out capacity)) {
						return false;
				}
					break;
				case "blocks": blocks_specified = true;
					if (!policy_uint (entry, out blocks)) {
						return false;
					}
					break;
				case "allocate": allocate = entry.decoded_value;
					break;
				case "release": release = entry.decoded_value;
					break;
				case "context": context_mode = entry.decoded_value;
					break;
					default: fail (entry.span, "unknown Allocator option");
					return false;
				}
			}
		}
		if (kind == AllocationKind.STATIC && !blocks_specified) {
			blocks = 1;
		}
		var policy = new AllocationPolicy (kind, domain, capacity, blocks, alignment, allocate, release, context_mode);
		if (!policy.valid () || !type.bind_allocation_policy (policy.identity)) {
			fail (syntax.span, "invalid allocator kind, domain, capacity, block budget, alignment or custom hooks");
			return false;
		}
		owner.allocation_policy = policy;
		return true;
	}
	private bool validate_allocation_policies(CheckedProgram program) {
		foreach (var owner in program.structs) {
			if (owner.representation != null && (owner.methods.length != 0 || owner.properties.length != 0)) {
				fail (owner.span, "Repr(C) requires a scalar POD record without methods or properties");
				return false;
			}
		}
		foreach (var handle in shared_handle_inventory) {
			var sharing = handle.semantic_type as SharedHandleType;
			if (sharing != null && !sharing.is_weak && sharing.payload_type.intrinsically_shared) {
				fail (handle.span, "intrinsic Shared Class cannot be redundantly boxed with shared or Shared<T>");
				return false;
			}
		}
		var domains = new HashTable<string, AllocationPolicy> (str_hash, str_equal);
		foreach (var owner in program.classes) {
			var concurrency = owner.concurrency_policy;
			if (concurrency != null && (owner.exception_root || exception_root != null && ((ClassType) owner.semantic_type).derives_from ((ClassType) exception_root.semantic_type))) {
				fail (owner.span, "native exceptions require their independent unique lifetime policy");
				return false;
			}
			if (concurrency != null && concurrency.actor && (concurrency.identity != 16 || owner.parent_class != null || owner.polymorphic || owner.allocation_policy != null || ((ClassType) owner.semantic_type).is_interface || !thread_capture_type (owner.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true))) {
				fail (owner.span, "Actor requires an exact hosted receiver with transferable state and no sender cycles");
				return false;
			}
			if (concurrency != null && concurrency.singleton && (concurrency.identity != 7 || owner.constructor == null || owner.parent_class != null || owner.polymorphic || owner.allocation_policy != null)) {
				fail (owner.span, "process Singleton requires exact Shared, Monitor, Singleton policy, an explicit constructor and the hosted heap");
				return false;
			}
			if (concurrency != null && concurrency.singleton) {
				foreach (var field in owner.fields) {
					if (!(field.semantic_type is IntegerType || field.semantic_type is FloatingType || field.semantic_type.kind == TypeKind.BOOL)) {
						fail (field.span, "bounded Singleton initialization requires copied numeric state");
						return false;
					}
				}
				foreach (var parameter in owner.constructor.parameters) {
					if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(parameter.semantic_type is IntegerType || parameter.semantic_type is FloatingType || parameter.semantic_type.kind == TypeKind.BOOL)) {
						fail (parameter.span, "bounded Singleton constructor requires copied numeric inputs");
						return false;
					}
				}
			}
			if (owner.parent_class != null && ((ClassType) owner.parent_class.semantic_type).concurrency_policy_identity != ((ClassType) owner.semantic_type).concurrency_policy_identity) {
				fail (owner.span, "inheritance requires identical root concurrency policies");
				return false;
			}
			if (concurrency != null && (concurrency.monitor || concurrency.thread_bound || concurrency.actor)) {
				foreach (var field in owner.fields) {
					if (!field.is_private) {
						fail (field.span, "Monitor/ThreadBound state requires private fields and compiler-mediated methods");
						return false;
					}
				}
			}
			if (concurrency != null && concurrency.monitor) {
				foreach (var method in owner.methods) {
					if (method.async_body != null || !(FunctionValueType.scalar (method.return_type) || method.return_type.kind == TypeKind.VOID || method.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) {
						fail (method.span, "Monitor methods require synchronous copied scalar/void or owning snapshot results; protected borrows cannot escape");
						return false;
					}
				}
				foreach (var property in owner.properties) {
					if (property.is_borrowed || !FunctionValueType.scalar (property.semantic_type)) {
						fail (property.span, "Monitor property cannot expose a protected borrow or mutable view");
						return false;
					}
				}
			}
			var policy = owner.allocation_policy;
			if (!AllocationPolicy.matches (policy, ((ClassType) owner.semantic_type).allocation_policy_identity)) {
				fail (owner.span, "allocation policy differs from its admitted Class declaration");
				return false;
			}
			if (policy == null) {
				continue;
			}
			if (owner.polymorphic || owner.parent_class != null || ((ClassType) owner.semantic_type).is_interface || owner.exception_root) {
				fail (owner.span, "Allocator and Align require an exact nonpolymorphic native Class");
				return false;
			}
			var prior = domains.lookup (policy.domain);
			if (prior != null && prior.domain_identity != policy.domain_identity) {
				fail (owner.span, "conflicting allocator policies for the same named domain");
				return false;
			}
			domains.insert (policy.domain, policy);
			if (policy.kind != AllocationKind.CUSTOM) {
				continue;
			}
			foreach (string hook in new string[] { policy.allocate_hook, policy.release_hook }) {
				FunctionSymbol? target = null;
				foreach (var exported in program.c_exports) {
					if (exported.external_symbol == hook) {
						target = exported.target;
					}
				}
				bool allocate = hook == policy.allocate_hook;
				bool valid = target != null && target.throws_type == null && target.async_body == null && target.return_type.kind == (allocate ? TypeKind.INT : TypeKind.VOID) && target.parameters.length == (allocate ? 4 : 2);
				if (target != null) {
					foreach (var parameter in target.parameters) {
						valid &= parameter.semantic_type.kind == TypeKind.INT && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
					}
				}
				if (!valid) {
					fail (owner.span, "custom allocator hooks require exact native C exports int(int,int,int,int) and void(int,int), without throws or async");
					return false;
				}
			}
		}
		return true;
	}
	// Initial and member-local requests share one ordered declaration worklist.
	// A nested request can append a skeleton during collection; all its fields
	// are completed before collecting the next member signature.
	private bool drain_class_declarations() {
		if (draining_class_declarations) {
			return true;
		}
		assert (class_requests != null && class_request_syntax != null);
		draining_class_declarations = true;
		var saved_class = specializing_class;
		var saved_method = specializing_method;
		var saved_parameters = method_type_parameters;
		var saved_lexical = lexical_types;
		var saved_elements = element_obligations;
		bool saved_premises = collecting_enum_premises;
		lexical_types = new HashTable<string, TypeParameterSymbol> (str_hash, str_equal);
		specializing_method = null;
		method_type_parameters = {};
		bool complete = collect_pending_class_declarations ();
		specializing_class = saved_class;
		specializing_method = saved_method;
		method_type_parameters = saved_parameters;
		lexical_types = saved_lexical;
		element_obligations = saved_elements;
		collecting_enum_premises = saved_premises;
		draining_class_declarations = false;
		return complete;
	}

	private bool collect_pending_class_declarations() {
		while (class_field_cursor < class_requests.length || class_member_cursor < class_requests.length) {
			while (class_field_cursor < class_requests.length) {
				int index = class_field_cursor++;
				var instance = class_requests[index];
				if (collected_instance_fields.contains (instance)) {
					continue;
				}
				if (instance is ClassSymbol && !bind_class_allocation ((ClassSymbol) instance, class_request_syntax[index])) {
					return false;
				}
				if (!collect_instance_fields (instance, class_request_syntax[index])) {
					return false;
				}
			}
			specializing_class = null;
			if (!validate_instance_layouts (class_requests)) {
				return false;
			}
			while (class_member_cursor < class_requests.length && class_field_cursor == class_requests.length) {
				int index = class_member_cursor++;
				if (!collected_instance_members.contains (class_requests[index]) && !collect_instance_members (class_requests[index], class_request_syntax[index])) {
					return false;
				}
			}
		}
		return finish_instance_members (class_requests, class_request_syntax);
	}

	private bool collect_instance_fields(NativeInstanceSymbol symbol, NativeInstanceDeclarationSyntax declaration) {
		specializing_class = symbol as ClassSymbol;
		string category = (symbol is ClassSymbol) ? "class" : "struct";
		if (symbol is StructSymbol && declaration.fields.length == 0) {
			fail (declaration.name.span, "empty struct '%s' is not supported".printf (symbol.name));
			return false;
		}
		foreach (var field in declaration.fields) {
			string name = field.name.spelling ();
			if (symbol is ClassSymbol && (name == "init" || name == "deinit")) {
				fail (field.name.span, "class lifecycle name '%s' is reserved; fields cannot use it".printf (name));
				return false;
			}
			if (symbol.find_field (name) != null) {
				fail (field.name.span, "duplicate field '%s' in %s '%s'".printf (name, category, symbol.name));
				return false;
			}
			slots_field_type_context = field.type_name is OwnerSlotsTypeSyntax;
			var field_type = resolve_contract_type (field.type_name);
			slots_field_type_context = false;
			if (field_type == null) {
				return false;
			}
			if (field_type.is_scoped_allocator ()) {
				fail (field.span, "scoped context cannot be stored in a field");
				return false;
			}
			if (field_type is CallbackType) {
				fail (field.span, "Callback is call-scoped and cannot be stored in a field");
				return false;
			}
			bool owning_field = field.owned_keyword != null && !substituted_copy_type (field.type_name, field_type) || field_type is ClassType && ((ClassType) field_type).intrinsically_shared;
			if (field.type_name is NonNullTypeSyntax && (!(symbol is ClassSymbol) || !owning_field || symbol.semantic_type is ExactGenericClassType || symbol.semantic_type.is_parameterized ())) {
				fail (field.span, "nonnull fields require an exact owned native Class field");
				return false;
			}
			if (field_type is ExactGenericClassType && (!GenericClassTypes.general (field_type) || !owning_field)) {
				fail (field.span, GenericClassTypes.general (field_type) ? "generic child fields require an owned closed general Class application" : "generic bag child-field composition is outside the finite direct-member scope");
				return false;
			}
			if (field_type is OwnerSlotsType) {
				if (!(symbol is ClassSymbol) || !owning_field || field.readonly_keyword != null) {
					fail (field.span, "owner slots require an owned native Class field");
					return false;
				}
				symbol.fields.add (new StructFieldSymbol (field.span, field.name.span, symbol, field_type, symbol.fields.length, field.private_keyword != null));
				continue;
			}
			if (field.readonly_keyword != null) {
				if (!(symbol is ClassSymbol) || !(field_type is StringType) || owning_field) {
					fail (field.span, "readonly fields require an unqualified string snapshot in a native class");
					return false;
				}
				var descriptor = new StructFieldSymbol (field.span, field.name.span, symbol, field_type, symbol.fields.length, field.private_keyword != null);
				descriptor.text_snapshot = true;
				symbol.fields.add (descriptor);
				continue;
			}
			if (field_type.is_text_slice ()) {
				fail (field.type_name.span, "string slice fields are unsupported; deep borrows cannot be stored in fields");
				return false;
			}
			if (owning_field) {
				if (!(symbol is ClassSymbol) && !(symbol is StructSymbol)) {
					fail (field.type_name.span, "owned fields require concrete native storage");
					return false;
				}
				if (symbol.semantic_type.is_parameterized () && ownable_parameter (field_type)) {
					var descriptor = new StructFieldSymbol (field.span, field.name.span, symbol, field_type, symbol.fields.length, field.private_keyword != null);
					descriptor.owns_parameter = true;
					symbol.fields.add (descriptor);
					continue;
				}
				if (!(field_type is StructType && symbol is ClassSymbol) && !(field_type is ClassType) && !(field_type is SliceType) && (!(field_type is HandleType) || !handle_types.contains (field_type))) {
					fail (field.type_name.span, "owned fields require an exact nominal Resource, buffer, concrete child ClassType or record carrying an ownership obligation");
					return false;
				}
				var descriptor = new StructFieldSymbol (field.span, field.name.span, symbol, field_type, symbol.fields.length, field.private_keyword != null);
				if (field_type is StructType) {
					descriptor.owns_record = true;
				} else if (field_type is ClassType) {
					descriptor.owns_child = true;
				} else if (field_type is SliceType) {
					descriptor.owns_buffer = true;
				} else {
					descriptor.owned_cleanup = handle_types.lookup (field_type).cleanup;
				}
				if (field.type_name is NonNullTypeSyntax) {
					descriptor.mark_nonnull ();
				}
				symbol.fields.add (descriptor);
				continue;
			}
			if (field_type is StringType) {
				fail (field.type_name.span, "string fields are unsupported in TEXT-1");
				return false;
			}
			if (field_type is SliceType) {
				fail (field.type_name.span, "slice struct fields are unsupported in SLICE-1");
				return false;
			}
			if (field_type is ArrayType) {
				fail (field.type_name.span, "array struct fields are unsupported in ARRAY-1");
				return false;
			}
			if (field_type is VectorType && symbol is ClassSymbol) {
				fail (field.type_name.span, "vector struct fields are unsupported in VEC-1");
				return false;
			}
			if (field_type is HandleType) {
				fail (field.type_name.span, "resource-valued struct fields are unsupported in RESOURCE-1");
				return false;
			}
			if (field_type.is_typed_pointer ()) {
				fail (field.type_name.span, "typed-pointer struct fields are not supported yet; fields must be 'int', 'bool' or 'void*'");
				return false;
			}
			if (field_type.kind == TypeKind.VOID) {
				fail (field.type_name.span, "field type cannot be 'void'");
				return false;
			}
			bool scoped_copy = symbol.semantic_type.is_parameterized () && GenericArgumentTypes.plain_copy (field_type, copy_fields, copy_premise);
			if (!scoped_copy && !NativeFieldTypes.supports (field_type, true)) {
				fail (field.type_name.span, "native fields require integer, f32, bool, void* or concrete record storage; unqualified object-reference fields are unsupported");
				return false;
			}
			symbol.fields.add (new StructFieldSymbol (field.span, field.name.span, symbol, field_type, symbol.fields.length, field.private_keyword != null));
		}
		collected_instance_fields.insert (symbol, true);
		return true;
	}

	private bool validate_instance_layouts(GenericArray<NativeInstanceSymbol> instances) {
		foreach (var instance in instances) {
			if (!(instance is StructSymbol)) {
				continue;
			}
			foreach (var field in instance.fields) {
				if (!field.is_owned_field && !NativeFieldTypes.supports (field.semantic_type, true)) {
					fail (field.span, "owning record companions require ordinary scalar or nested record storage");
					return false;
				}
			}
		}
		var complete_layouts = new HashTable<StructSymbol, StructSymbol> (direct_hash, direct_equal);
		var active_layouts = new GenericArray<StructSymbol> ();
		foreach (var instance in instances) {
			if (instance is StructSymbol && !check_struct_layout ((StructSymbol) instance, complete_layouts, active_layouts)) {
				return false;
			}
		}
		foreach (var instance in instances) {
			foreach (var field in instance.fields) {
				if (!(field.semantic_type is StructType)) {
					continue;
				}
				bool copied = CopyabilityAuthority.of (field.semantic_type, copy_fields) == Copyability.COPYABLE;
				if (field.owns_record && copied) {
					fail (field.span, "owned fields require an exact nominal Resource, buffer, concrete child ClassType or record carrying an ownership obligation; this concrete record is copyable");
					return false;
				}
				if (instance is ClassSymbol) {
					field.owns_record = !copied;
				}
			}
		}
		element_fields_complete = true;
		foreach (var instance in instances) {
			foreach (var field in instance.fields) {
				var slots = field.semantic_type as OwnerSlotsType;
				if (slots == null || !(slots.element is StructType)) {
					continue;
				}
				try {
					StructLeafOrder.enumerate_storage (slots.element, copy_fields);
				} catch (StructLeafError error) {
					fail (field.span, "record slots require a complete supported layout: " + error.message);
					return false;
				}
			}
		}
		foreach (var definition in generic_structs) {
			lexical_types.remove_all ();
			foreach (var parameter in definition.type_parameters) {
				lexical_types.insert (parameter.name, parameter);
			}
			foreach (var field in definition.fields) {
				if (!check_application_arguments (field.semantic_type, field.span)) {
					return false;
				}
			}
		}
		lexical_types.remove_all ();
		foreach (var instance in instances) {
			foreach (var field in instance.fields) {
				if (!check_application_arguments (field.semantic_type, field.span)) {
					return false;
				}
			}
		}
		foreach (var instance in instances) {
			foreach (var field in instance.fields) {
				if (field.owns_buffer && !check_collection_element (((SliceType) field.semantic_type).element_type, field.span)) {
					return false;
				}
			}
		}
		return true;
	}

	private bool collect_instance_members(NativeInstanceSymbol structure, NativeInstanceDeclarationSyntax declaration) {
		if (!ForeignApiAdmission.selected (declaration as ClassDeclarationSyntax)) {
			foreach (var member in declaration.members) {
				if (member.foreign_member != null || member.foreign_channels.length != 0) {
					fail (member.span, "Foreign member selection requires a declarations-v1 Class export");
					return false;
				}
			}
		}
		specializing_class = structure as ClassSymbol;
		string category = (structure is ClassSymbol) ? "class" : "struct";
		if (owning_record_field (structure.semantic_type) != null) {
			foreach (var member in declaration.members) {
				if (member is FunctionDeclarationSyntax || member is PropertyDeclarationSyntax) {
					fail (member.span, "owning record methods and properties are deferred");
					return false;
				}
			}
		}
		for (int m = 0; m < declaration.members.length; m++) {
			var property_syntax = declaration.members[m] as PropertyDeclarationSyntax;
			if (property_syntax != null) {
				var property = collect_property (property_syntax, structure, m);
				if (property == null) {
					return false;
				}
				structure.properties.add (property);
				continue;
			}
			var syntax = declaration.members[m] as FunctionDeclarationSyntax;
			if (syntax == null) {
				continue;
			}
			string name = syntax.name.spelling ();
			var lifecycle = syntax as LifecycleDeclarationSyntax;
			if (lifecycle != null) {
				var owner = structure as ClassSymbol;
				if (owner == null) {
					fail (syntax.span, "struct lifecycle members are unsupported");
					return false;
				}
				if (lifecycle.is_constructor ? owner.constructor != null : owner.destructor != null) {
					fail (syntax.name.span, "duplicate lifecycle member '%s' in class '%s'; only one is permitted, without overloading".printf (name, owner.name));
					return false;
				}
				var symbol = collect_signature (syntax, owner, m) as LifecycleSymbol;
				if (symbol == null) {
					return false;
				}
				if (symbol is ConstructorSymbol) {
					owner.constructor = (ConstructorSymbol) symbol;
					constructor_initializers.insert ((ConstructorSymbol) symbol, lifecycle);
				} else {
					owner.destructor = (DestructorSymbol) symbol;
				}
				continue;
			}
			if (structure is ClassSymbol && (name == "init" || name == "deinit")) {
				fail (syntax.name.span, "class lifecycle name '%s' is reserved; lifecycle declarations have no result type".printf (name));
				return false;
			}
			if (structure.find_field (name) != null) {
				fail (syntax.name.span, "field/method name collision '%s' in %s '%s'".printf (name, category, structure.name));
				return false;
			}
			if (structure.find_declared_member (name) is MethodSymbol) {
				fail (syntax.name.span, "duplicate method '%s' in %s '%s'; overloading is not implemented".printf (name, category, structure.name));
				return false;
			}
			if (structure.find_property (name) != null) {
				fail (syntax.name.span, "method/property name collision '%s' in '%s'".printf (name, structure.name));
				return false;
			}
			if (syntax.type_parameters.length != 0 && structure is ClassSymbol && ((ClassSymbol) structure).generic_instance != null && ((ClassSymbol) structure).generic_instance.definition.general_bodies) {
				continue;
			}
			var symbol = collect_signature (syntax, structure, m) as MethodSymbol;
			if (symbol == null) {
				return false;
			}
			if (structure.semantic_type is ClassType && ((ClassType) structure.semantic_type).is_interface) {
				if (symbol.return_type != types.int_type || symbol.throws_type != null || symbol.result_contract != ResultOwnershipContract.UNMANAGED) {
					fail (syntax.span, "interface operations require nonthrowing copied int results");
					return false;
				}
				foreach (var parameter in symbol.parameters) {
					if (parameter.semantic_type != types.int_type || parameter.pointer_contract != PointerParameterContract.UNMANAGED || parameter.caller_information != null) {
						fail (parameter.span, "interface operation parameters require copied int values");
						return false;
					}
				}
			}
			structure.methods.add (symbol);
			method_syntax.insert (symbol, syntax);
		}
		foreach (var method in structure.methods) {
			seed_origin_signature (method);
		}
		var owner = structure as ClassSymbol;
		if (owner != null && owner.constructor != null) {
			seed_origin_signature (owner.constructor);
		}
		if (owner != null && owner.destructor != null) {
			seed_origin_signature (owner.destructor);
		}
		foreach (var property in structure.properties) {
			seed_origin_signature (property.getter);
			if (property.setter != null) {
				seed_origin_signature (property.setter);
			}
		}
		collected_instance_members.insert (structure, true);
		return true;
	}

	private bool finish_instance_members(GenericArray<NativeInstanceSymbol> instances, GenericArray<NativeInstanceDeclarationSyntax> syntax_instances) {
		for (int i = 0; i < instances.length; i++) {
			foreach (var member in syntax_instances[i].members) {
				var syntax = member as PropertyDeclarationSyntax;
				if (syntax == null || syntax.factory_syntax == null) {
					continue;
				}
				var property = instances[i].find_property (syntax.name.spelling ());
				property.factory = instances[i].find_method (syntax.factory_syntax.name.spelling ());
				if (property.factory == null || property.factory.result_contract != ResultOwnershipContract.OWNED_TRANSFER || property.factory.return_type != property.semantic_type) {
					fail (syntax.span, "owned lazy property lost exact owned factory channel");
					return false;
				}
			}
		}
		foreach (var instance in instances) {
			if (instance is ClassSymbol && !complete_class_dispatch ((ClassSymbol) instance, completed_class_dispatch)) {
				return false;
			}
		}
		foreach (var instance in instances) {
			var owner = instance as ClassSymbol;
			var key = owner == null ? null : owner.generic_instance;
			if (key == null || key.definition.structure == null) {
				continue;
			}
			for (int c = 0; c < key.definition.structure.constraint_count; c++) {
				var constraint = key.definition.structure.constraint (c);
				if (!GenericClassDeclaredShape.constraint (constraint, key.arguments, null, exact_heap_class_argument)) {
					fail (owner.span, constraint.exact_heap_class ? "ExactHeapClass requires a concrete nongeneric nonpolymorphic native Class argument" : "generic Class type arguments do not satisfy the declared capability constraint");
					return false;
				}
			}
		}
		foreach (var instance in instances) {
			if (!(instance is ClassSymbol) || ((ClassSymbol) instance).constructor != null) {
				continue;
			}
			foreach (var field in instance.fields) {
				if (field.is_owned_field || field.text_snapshot) {
					fail (field.span, "owned %s field '%s' requires an explicit constructor and definite initialization".printf (field.owns_buffer ? "runtime-array" : "Resource", field.name));
					return false;
				}
			}
		}
		return true;
	}

	private GenericArray<NativeInstanceSymbol>? collect_native_instances(SyntaxProgram unit) {
		foreach (var instance in unit.native_instances ()) {
			var declaration = instance as ClassDeclarationSyntax;
			if (declaration != null && declaration.foreign_export != null && declaration.type_parameters.length != 0) {
				fail (declaration.foreign_export.span, "foreign Class export requires a concrete nongeneric root");
				return null;
			}
		}
		foreach (var declaration in unit.structs) {
			if (declaration.allocator != null || declaration.type_parameters.length != 0 && (declaration.alignment != null || declaration.representation != null)) {
				fail (declaration.span, "Allocator selects an exact Class; Repr(C) requires a concrete POD record");
				return null;
			}
		}
		var instances = new GenericArray<NativeInstanceSymbol> ();
		var syntax_instances = unit.native_instances (false);
		foreach (var declaration in syntax_instances) {
			var additions = new GenericArray<FunctionDeclarationSyntax> ();
			foreach (var member in declaration.members) {
				var property = member as PropertyDeclarationSyntax;
				if (property == null || property.owned_keyword == null || property.factory_syntax != null) {
					continue;
				}
				if (!property.is_lazy && ForeignApiAdmission.selected (declaration as ClassDeclarationSyntax) && property.foreign_member != null && !property.is_borrowed && property.setter == null && property.dispatch == MemberDispatchSyntax.DIRECT) {
					continue;
				}
				if (!(declaration is ClassDeclarationSyntax) || !property.is_lazy || property.is_borrowed || property.setter != null || property.dispatch != MemberDispatchSyntax.DIRECT) {
					fail (property.span, "owned property requires a direct get-only native lazy class property");
					return null;
				}
				string generated = "__astra_lazy_factory_" + property.name.spelling ();
				int suffix = 0;
				bool collision = false;
				do {
					collision = false;
					foreach (var candidate in declaration.members) {
						var method = candidate as FunctionDeclarationSyntax;
						var field = candidate as StructFieldDeclarationSyntax;
						var declared = candidate as PropertyDeclarationSyntax;
						if ((method != null && method.name.spelling () == generated) || (field != null && field.name.spelling () == generated) || (declared != null && declared.name.spelling () == generated)) {
							collision = true;
						}
					}
					if (collision) {
						generated = "__astra_lazy_factory_" + property.name.spelling () + "_%d".printf (++suffix);
					}
				} while (collision);
				var prototype = Parser.parse (new SourceFile.from_text ("<compiler-owned-lazy-factory>", "class __Generated{owned int " + generated + "(){return 0;}}"));
				assert (prototype.diagnostic == null);
				var model = prototype.unit.classes[0].methods[0];
				var factory = new FunctionDeclarationSyntax (property.type_name, model.name, model.open_paren, model.parameters, model.commas, model.close_paren, property.getter.body, null, null, property.owned_keyword);
				factory.throws_class = property.throws_class;
				property.factory_syntax = factory;
				additions.add (factory);
			}
			foreach (var factory in additions) {
				declaration.methods.add (factory);
				declaration.members.add (factory);
			}
		}
		instance_syntax = syntax_instances;
		foreach (var declaration in unit.native_instances ()) {
			var generic = declaration as ClassDeclarationSyntax;
			if (generic == null || generic.type_parameters.length == 0) {
				continue;
			}
			string name = declaration_name (generic.name);
			if (types.resolve (declaration.name.spelling ()) != null || named_types.contains (name) || generic_class_names.contains (name)) {
				fail (generic.name.span, "duplicate or conflicting generic Class definition");
				return null;
			}
			Diagnostic? error;
			var definition = ExactClassTemplate.check (generic, out error, name, (span, source_name) => resolve_name (span, source_name));
			if (definition == null) {
				fail (error.span, error.message);
				return null;
			}
			if (generic.allocator != null || generic.alignment != null || generic.representation != null) {
				var declaration_policy = new ClassSymbol (generic.span, generic.name.span, -1, name);
				if (!bind_class_allocation (declaration_policy, generic)) {
					return null;
				}
			}
			generic_class_names.insert (name, definition);
			generic_classes.add (definition);
		}
		var generic_syntax = new GenericArray<StructDeclarationSyntax> ();
		foreach (var declaration in unit.structs) {
			if (declaration.type_parameters.length == 0) {
				continue;
			}
			string name = declaration_name (declaration.name);
			if (types.resolve (declaration.name.spelling ()) != null || named_types.contains (name) || generic_struct_names.contains (name) || generic_class_names.contains (name)) {
				string message = "duplicate or conflicting generic struct type '%s'".printf (name);
				if (generic_struct_names.contains (name)) {
					fail_duplicate (declaration.name.span, message, generic_struct_names.lookup (name).name_span);
				} else {
					fail (declaration.name.span, message);
				}
				return null;
			}
			var definition = new GenericStructSymbol (declaration.span, declaration.name.span, generic_structs.length, name,
				native_declarations == null ? null : native_declarations.record_applications (declaration.span.file));
			definition.owning_storage = declaration.where_clauses.length != 0;
			if (definition.owning_storage) {
				owning_record_syntax.insert (definition, declaration);
			}
			generic_struct_names.insert (name, definition);
			generic_structs.add (new CheckedGenericStruct (definition));
			generic_syntax.add (declaration);
		}
		int struct_ordinal = 0;
		int class_ordinal = 0;
		// Establish the entire type namespace before resolving any fields.
		foreach (var declaration in syntax_instances) {
			string name = declaration_name (declaration.name);
			string category = declaration.keyword.kind == TokenKind.CLASS ? "class" : "struct";
			if (types.resolve (declaration.name.spelling ()) != null) {
				fail (declaration.name.span, "%s name '%s' conflicts with builtin type".printf (category, name));
				return null;
			}
			if (generic_class_names.contains (name)) {
				fail (declaration.name.span, "native type conflicts with a generic Class definition");
				return null;
			}
			if (instance_names.contains (name) || generic_struct_names.contains (name)) {
				fail_duplicate (declaration.name.span, "duplicate %s type '%s'".printf (category, name), instance_names.contains (name) ? instance_names.lookup (name).name_span : generic_struct_names.lookup (name).name_span);
				return null;
			}
			if (named_types.contains (name)) {
				fail (declaration.name.span, "%s type '%s' conflicts with imported handle type".printf (category, name));
				return null;
			}
			NativeInstanceSymbol symbol = declaration.keyword.kind == TokenKind.CLASS ? (NativeInstanceSymbol) new ClassSymbol (declaration.span, declaration.name.span, class_ordinal++, name) : new StructSymbol (declaration.span, declaration.name.span, struct_ordinal++, name);
			if (declaration is ClassDeclarationSyntax) {
				((ClassType) symbol.semantic_type).is_interface = ((ClassDeclarationSyntax) declaration).is_interface;
			}
			instances.add (symbol);
			named_types.insert (name, symbol.semantic_type);
			instance_names.insert (name, symbol);
			instance_types.insert (symbol.semantic_type, symbol);
		}
		next_owned_record_ordinal = struct_ordinal;
		ClassSymbol? nominated_root = null;
		var parent_edges = new HashTable<ClassSymbol, ClassSymbol> (direct_hash, direct_equal);
		for (int i = 0; i < instances.length; i++) {
			var syntax = syntax_instances[i] as ClassDeclarationSyntax;
			var owner = instances[i] as ClassSymbol;
			if (owner == null) {
				continue;
			}
			if (syntax.parent_class != null) {
				var parent = instance_names.lookup (type_key (syntax.parent_class)) as ClassSymbol;
				if (parent == null) {
					fail (syntax.parent_class.span, "class parent requires an exact native class declaration");
					return null;
				}
				parent_edges.insert (owner, parent);
			}
			if (syntax.exception_root != null) {
				if (nominated_root != null || parent_edges.contains (owner)) {
					fail (syntax.exception_root.span, "ExceptionRoot requires one unique root class without a parent");
					return null;
				}
				owner.exception_root = true;
				nominated_root = owner;
				exception_root = owner;
			}
		}
		foreach (var instance in instances) {
			var owner = instance as ClassSymbol;
			if (owner == null) {
				continue;
			}
			var chain = new HashTable<ClassSymbol, bool> (direct_hash, direct_equal);
			int depth = 0;
			for (ClassSymbol? current = owner; current != null; current = parent_edges.lookup (current)) {
				if (chain.contains (current) || ++depth > 256) {
					fail (owner.span, "class inheritance must be acyclic and bounded to 256 ancestors");
					return null;
				}
				chain.insert (current, true);
				if (parent_edges.contains (owner)) {
					current.polymorphic = true;
				}
			}
		}
		foreach (var owner in parent_edges.get_keys ()) {
			owner.parent_class = parent_edges.lookup (owner);
			((ClassType) owner.semantic_type).parent_type = (ClassType) owner.parent_class.semantic_type;
		}
		foreach (var declaration in unit.enums) {
			string name = declaration_name (declaration.name);
			if (types.resolve (declaration.name.spelling ()) != null || named_types.contains (name) || generic_struct_names.contains (name) || generic_class_names.contains (name)) {
				fail (declaration.name.span, "duplicate or conflicting enum type '%s'".printf (name));
				return null;
			}
			var parameters = new GenericArray<TypeParameterSymbol> ();
			var types = new GenericArray<SemanticType> ();
			var names = new HashTable<string, bool> (str_hash, str_equal);
			foreach (var token in declaration.type_parameters) {
				string parameter_name = token.spelling ();
				bool shadows = false;
				foreach (var other in unit.enums) {
					if (declaration_name (other.name) == resolve_name (token.span, parameter_name)) {
						shadows = true;
					}
				}
				if (this.types.resolve (parameter_name) != null || visible_nominal (token.span, parameter_name) || shadows || names.contains (parameter_name)) {
					fail (token.span, "duplicate or shadowing enum type parameter '%s'".printf (parameter_name));
					return null;
				}
				var parameter = new TypeParameterSymbol (token.span, parameters.length);
				parameters.add (parameter);
				types.add (parameter.semantic_type);
				names.insert (parameter_name, true);
			}
			int parameter_count = parameters.length;
			if (parameter_count < 0) {
				fail (declaration.span, "enum parameter count exceeds compiler limits");
				return null;
			}
			var elements = new bool[parameter_count];
			foreach (var variant in declaration.variants) {
				foreach (var field in variant.fields) {
					var slice = field.type_name as SliceTypeSyntax;
					if (field.owned_keyword != null && slice != null) {
						for (int i = 0; i < parameters.length; i++) {
							if (slice.element_type.spelling () == parameters[i].name) {
								elements[i] = true;
							}
						}
					}
				}
			}
			var type = new EnumType (name, types, elements);
			named_types.insert (name, type);
			enum_parameters.insert (type, parameters);
		}
		// Propagate only declared owned-array requirements through exact written
		// applications, before resolving bodies or selecting concrete callers.
		bool changed_enum_premises = true;
		while (changed_enum_premises) {
			changed_enum_premises = false;
			foreach (var declaration in unit.enums) {
				var type = (EnumType) find_named (declaration.name);
				var parameters = enum_parameters.lookup (type);
				foreach (var variant in declaration.variants) {
					foreach (var field in variant.fields) {
						var application = field.type_name as GenericTypeApplicationSyntax;
						var nested = application == null ? null : named_types.lookup (type_key (application)) as EnumType;
						if (nested == null || application.type_arguments.length != nested.argument_count) {
							continue;
						}
						for (uint a = 0; a < nested.argument_count; a++) {
							if (!nested.requires_array_element (a)) {
								continue;
							}
							for (uint p = 0; p < parameters.length; p++) {
								if (application.type_arguments[a].spelling () == parameters[p].name) {
									changed_enum_premises = type.require_array_element (p) || changed_enum_premises;
								}
							}
						}
					}
				}
			}
		}
		foreach (var definition in generic_classes) {
			foreach (var parameter in definition.syntax.type_parameters) {
				if (types.resolve (parameter.spelling ()) != null || visible_nominal (parameter.span, parameter.spelling ())) {
					fail (parameter.span, "generic Class type parameter cannot shadow a builtin or nominal definition");
					return null;
				}
			}
			foreach (var method in definition.syntax.methods) {
				foreach (var parameter in method.type_parameters) {
					bool class_parameter = false;
					foreach (string name in definition.parameters) {
						class_parameter |= name == parameter.spelling ();
					}
					if (class_parameter || types.resolve (parameter.spelling ()) != null || visible_nominal (parameter.span, parameter.spelling ())) {
						fail (parameter.span, "method type parameter cannot shadow a class parameter, builtin or nominal type");
						return null;
					}
				}
			}
		}
		class_requests = instances;
		class_request_syntax = syntax_instances;
		next_class_ordinal = class_ordinal;
		// All nominal names exist before enforcing the accepted lexical parameter
		// policy. All parameter lists exist before resolving recursive applications.
		for (int g = 0; g < generic_structs.length; g++) {
			var definition = generic_structs[g].definition;
			lexical_types.remove_all ();
			foreach (var token in generic_syntax[g].type_parameters) {
				string name = token.spelling ();
				if (types.resolve (name) != null) {
					fail (token.span, "builtin type name '%s' is unavailable as a type parameter".printf (name));
					return null;
				}
				if (visible_nominal (token.span, name)) {
					fail (token.span, "type parameter '%s' cannot shadow an outer type in GEN-1".printf (name));
					return null;
				}
				if (lexical_types.contains (name)) {
					fail (token.span, "duplicate type parameter '%s'".printf (name));
					return null;
				}
				GenericCapabilityIdentity[] capabilities = null;
				foreach (var clause in generic_syntax[g].where_clauses) {
					if (clause.type_parameter.spelling () != name) {
						continue;
					}
					if (capabilities.length != 0 || clause.capabilities.length != 1) {
						fail (clause.span, "owning record parameters require one exact Ownable bound");
						return null;
					}
					capabilities += GenericCapabilityIdentity.OWNABLE;
				}
				var parameter = new TypeParameterSymbol (token.span, definition.type_parameters.length, new GenericCapabilitySet (capabilities));
				definition.type_parameters.add (parameter);
				lexical_types.insert (name, parameter);
			}
			foreach (var clause in generic_syntax[g].where_clauses) {
				if (!lexical_types.contains (clause.type_parameter.spelling ())) {
					fail (clause.type_parameter.span, "unknown owning record type parameter");
					return null;
				}
			}
		}
		for (int g = 0; g < generic_structs.length; g++) {
			var definition = generic_structs[g].definition;
			lexical_types.remove_all ();
			foreach (var parameter in definition.type_parameters) {
				lexical_types.insert (parameter.name, parameter);
			}
			if (generic_syntax[g].fields.length == 0) {
				fail (definition.name_span, "empty struct '%s' is not supported".printf (definition.name));
				return null;
			}
			if (generic_syntax[g].members.length != generic_syntax[g].fields.length) {
				fail (definition.span, "generic structs permit fields only");
				return null;
			}
			foreach (var field in generic_syntax[g].fields) {
				if (definition.find_field (field.name.spelling ()) != null) {
					fail (field.name.span, "duplicate field '%s' in struct '%s'".printf (field.name.spelling (), definition.name));
					return null;
				}
				var type = resolve_type (field.type_name);
				if (type == null) {
					return null;
				}
				if (type.is_scoped_allocator ()) {
					fail (field.span, "scoped context cannot be stored in a record");
					return null;
				}
				var descriptor = new GenericStructFieldSymbol (field.span, field.name.span, definition, type, definition.fields.length);
				descriptor.is_private = field.private_keyword != null;
				if (field.owned_keyword != null) {
					if (ownable_parameter (type)) {
						descriptor.owns_parameter = true;
					} else if (type is ClassType) {
						descriptor.owns_child = true;
					} else if (type is HandleType && handle_types.contains (type)) {
						descriptor.owned_cleanup = handle_types.lookup (type).cleanup;
					} else if (type is SliceType) {
						descriptor.owns_buffer = true;
					} else {
						fail (field.span, "owning generic record fields require an exact owner or Ownable parameter");
						return null;
					}
				} else {
					if (ownable_parameter (type)) {
						fail (field.span, "Ownable record parameters require explicit owned fields");
						return null;
					}
					if (!(type is TypeParameterType) && !(type is GenericStructApplicationType) && !NativeFieldTypes.supports (type, true)) {
						fail (field.type_name.span, "unsupported generic struct field type '%s'; requires T, an accepted native struct field, or a generic struct application".printf (type.display_name ()));
						return null;
					}
				}
				definition.fields.add (descriptor);
			}
		}
		foreach (var generic in generic_structs) {
			var definition = generic.definition;
			definition.fields_complete = true;
			if (!definition.owning_storage) {
				continue;
			}
			var syntax = owning_record_syntax.lookup (definition);
			var parameters = new string[definition.type_parameters.length];
			var owners = new bool[definition.type_parameters.length];
			for (int p = 0; p < parameters.length; p++) {
				parameters[p] = definition.type_parameters[p].name;
				owners[p] = definition.type_parameters[p].transport_mode == GenericTransportMode.OWNABLE;
			}
			var fields = new GenericFieldPattern[syntax.fields.length];
			for (int f = 0; f < fields.length; f++) {
				var field = syntax.fields[f];
				if (field.readonly_keyword != null) {
					fail (field.span, "owning record fields do not admit readonly text snapshots");
					return null;
				}
				fields[f] = new GenericFieldPattern (field.name.spelling (), ExactClassTemplate.pattern (field.type_name, parameters, {}, (at, name) => resolve_name (at, name)), field.owned_keyword != null, field.private_keyword != null, false);
			}
			definition.owning_contract = new OwnedRecordDefinitionContract (definition.nominal_identity, owners, fields);
		}
		lexical_types.remove_all ();
		// Close explicit owning record applications before choosing the body
		// ownership flow. Template-local applications are resolved in their
		// actual lexical substitution instead of guessing their parameters.
		foreach (var source_unit in unit.units) {
			foreach (var application in source_unit.type_applications) {
				var definition = generic_struct_names.lookup (type_key (application));
				if (definition == null || !definition.owning_storage) {
					continue;
				}
				bool template_body = false;
				foreach (var generic in generic_classes) {
					template_body |= contains_span (generic.syntax.span, application.span);
				}
				foreach (var generic in generic_syntax) {
					template_body |= contains_span (generic.span, application.span);
				}
				foreach (var function in unit.functions) {
					template_body |= function.type_parameters.length != 0 && contains_span (function.span, application.span);
				}
				if (!template_body && resolve_type (application) == null) {
					return null;
				}
			}
		}
		// Seed concrete requests outside templates, then visit each requested
		// declaration with its lexical substitution. New nested requests extend
		// the same worklist, independently of source/request ordering.
		foreach (var source_unit in unit.units) {
			foreach (var application in source_unit.type_applications) {
				bool template_body = false;
				foreach (var definition in generic_classes) {
					template_body |= contains_span (definition.syntax.span, application.span);
				}
				foreach (var function in unit.functions) {
					template_body |= function.type_parameters.length != 0 && contains_span (function.span, application.span);
				}
				if (template_body || !generic_class_names.contains (type_key (application))) {
					continue;
				}
				if (resolve_type (application) == null) {
					return null;
				}
			}
		}
		for (int request = 0; request < instances.length; request++) {
			var owner = instances[request] as ClassSymbol;
			if (owner == null || owner.generic_instance == null) {
				continue;
			}
			var definition = generic_class_names.lookup (owner.generic_instance.definition.name);
			specializing_class = owner;
			foreach (var source_unit in unit.units) {
				foreach (var application in source_unit.type_applications) {
					if (!contains_span (definition.syntax.span, application.span) || !generic_class_names.contains (type_key (application))) {
						continue;
					}
					bool method_body = false;
					foreach (var method in definition.syntax.methods) {
						method_body |= method.type_parameters.length != 0 && contains_span (method.span, application.span);
					}
					if (!method_body && resolve_type (application) == null) {
						return null;
					}
				}
			}
		}
		specializing_class = null;
		for (int i = 0; i < instances.length; i++) {
			if (instances[i] is ClassSymbol && !bind_class_allocation ((ClassSymbol) instances[i], syntax_instances[i])) {
				return null;
			}
		}
		for (int i = 0; i < instances.length; i++) {
			if (!collected_instance_fields.contains (instances[i]) && !collect_instance_fields (instances[i], syntax_instances[i])) {
				return null;
			}
		}
		for (int i = 0; i < instances.length; i++) {
			if (instances[i] is StructSymbol && !bind_pod_representation ((StructSymbol) instances[i], syntax_instances[i])) {
				return null;
			}
		}
		specializing_class = null;
		if (!validate_instance_layouts (instances)) {
			return null;
		}
		if (!collect_enums (unit)) {
			return null;
		}
		// Complete every member signature before any free-function or method body.
		class_declarations_ready = true;
		if (!drain_class_declarations ()) {
			return null;
		}
		specializing_class = null;
		if (nominated_root != null) {
			var message = nominated_root.find_property ("message");
			if (message == null || !(message.semantic_type is StringType) || message.setter != null || message.getter.dispatch_kind != ClassDispatchKind.VIRTUAL) {
				fail (nominated_root.span, "ExceptionRoot requires an exact virtual get-only string message property");
				return null;
			}
		}

		return instances;
	}

	private bool admit_foreign_classes(GenericArray<NativeInstanceSymbol> instances, GenericArray<NativeInstanceDeclarationSyntax> syntax_instances) {
		var foreign_prefixes = new HashTable<string, bool> (str_hash, str_equal);
		for (int i = 0; i < instances.length; i++) {
			var owner = instances[i] as ClassSymbol;
			var syntax = syntax_instances[i] as ClassDeclarationSyntax;
			if (owner == null || syntax == null || syntax.foreign_export == null) {
				continue;
			}
			var attribute = syntax.foreign_export;
			if (ForeignApiAdmission.selected (syntax)) {
				Diagnostic? foreign_diagnostic;
				var com_protocols = new GenericArray<ForeignComInterface> ();
				foreach (var imported_type in handle_types.get_values ()) {
					if (imported_type.c_import != null && imported_type.c_import.com != null) {
						com_protocols.add (imported_type.c_import.com);
					}
				}
				var declared = ForeignApiAdmission.admit (owner, syntax, instances, syntax_instances, out foreign_diagnostic, imported_c_root, com_protocols, foreign_selection);
				if (declared == null) {
					diagnostic = foreign_diagnostic;
					return false;
				}
				foreach (var method in owner.methods) {
					seed_origin_signature (method);
				}
				if (owner.constructor != null) {
					seed_origin_signature (owner.constructor);
				}
				foreach (var property in owner.properties) {
					seed_origin_signature (property.getter);
					if (property.setter != null) {
						seed_origin_signature (property.setter);
					}
				}
				if (foreign_prefixes.contains (declared.prefix) || !((ClassType) owner.semantic_type).bind_foreign_policy (declared.identity ())) {
					fail (attribute.span, "declarations-v1 requires a unique foreign prefix and exact native identity");
					return false;
				}
				foreign_prefixes.insert (declared.prefix, true);
				owner.foreign_export = declared;
				continue;
			}
			if (foreign_selection >= 0) {
				fail (attribute.span, "explicit foreign personalities require declarations-v1 Class policies");
				return false;
			}
			string prefix = "";
			string property_name = "value";
			foreach (var entry in attribute.entries) {
				if (entry.key.spelling () == "name") {
					prefix = entry.decoded_value;
				} else if (entry.key.spelling () == "property") {
					property_name = entry.decoded_value;
				} else {
					fail (entry.span, "unsupported Class CExport argument");
					return false;
				}
			}
			var property = owner.find_property (property_name);
			var constructor = owner.constructor;
			if (owner.concurrency_policy == null || (owner.concurrency_policy.identity != 1 && owner.concurrency_policy.identity != 3) || owner.parent_class != null || owner.polymorphic || owner.exception_root || owner.allocation_policy != null || owner.generic_instance != null || ((ClassType) owner.semantic_type).is_interface || constructor == null || constructor.throws_type != null || constructor.parameters.length != 1 || constructor.parameters[0].semantic_type != types.int_type || constructor.parameters[0].pointer_contract != PointerParameterContract.UNMANAGED) {
				fail (attribute.span, "Class CExport requires a plain Shared or Shared Monitor heap root with a nonthrowing init(int)");
				return false;
			}
			if (property == null || property.declaring_type != owner || property.semantic_type != types.int_type || property.is_lazy || property.is_borrowed || property.getter == null || property.setter == null || property.getter.throws_type != null || property.setter.throws_type != null || property.getter.dispatch_kind != ClassDispatchKind.DIRECT || property.setter.dispatch_kind != ClassDispatchKind.DIRECT) {
				fail (attribute.span, "Class CExport requires a selected nonthrowing read/write int property");
				return false;
			}
			foreach (var field in owner.fields) {
				if (field.is_owned_field || field.text_snapshot || field.semantic_type != types.int_type) {
					fail (field.span, "selected foreign Class export requires copied int payload fields");
					return false;
				}
			}
			foreach (var other in owner.properties) {
				if (other.is_lazy) {
					fail (other.span, "selected foreign Class export excludes lazy caches");
					return false;
				}
			}
			ComExportContract? com = null;
			if (syntax.com_export != null) {
				string value_iid = "";
				string scale_iid = "";
				string threading = "";
				foreach (var entry in syntax.com_export.entries) {
					switch (entry.key.spelling ()) {
					case "value_iid": value_iid = entry.decoded_value;
						break;
					case "scale_iid": scale_iid = entry.decoded_value;
						break;
					case "threading": threading = entry.decoded_value;
						break;
						default: fail (entry.span, "unsupported COMExport argument");
						return false;
					}
				}
				com = new ComExportContract (value_iid, scale_iid);
				if (!com.valid () || threading != "constructing" || owner.concurrency_policy.identity != 1) {
					fail (syntax.com_export.span, "COMExport requires two distinct explicit application GUIDs, threading=constructing and a plain Shared root");
					return false;
				}
			}
			GObjectExportContract? gobject = null;
			if (syntax.gobject_export != null) {
				string type_name = "", namespace_name = "", version = "";
				foreach (var entry in syntax.gobject_export.entries) {
					switch (entry.key.spelling ()) {
					case "type": type_name = entry.decoded_value;
						break;
					case "namespace": namespace_name = entry.decoded_value;
						break;
					case "version": version = entry.decoded_value;
						break;
						default: fail (entry.span, "unsupported GObjectExport argument");
						return false;
					}
				}
				gobject = new GObjectExportContract (type_name, namespace_name, version);
				if (com != null || !gobject.valid () || prefix != gobject.symbol_prefix () || property_name != "value") {
					fail (syntax.gobject_export.span, "GObjectExport requires explicit Type/Namespace/1.0, matching snake-case C prefix, value property and no COM personality");
					return false;
				}
			}
			var policy = new ForeignClassPolicy (owner.name, prefix, property_name, property.ordinal, com != null ? ForeignClassPolicy.C | ForeignClassPolicy.COM : gobject != null ? ForeignClassPolicy.C | ForeignClassPolicy.GOBJECT : ForeignClassPolicy.C, com, gobject);
			if (!policy.valid () || foreign_prefixes.contains (prefix) || !((ClassType) owner.semantic_type).bind_foreign_policy (policy.identity ())) {
				fail (attribute.span, "Class CExport requires a unique explicit portable name outside the astra_ prefix");
				return false;
			}
			foreign_prefixes.insert (prefix, true);
			owner.foreign_export = policy;
		}
		foreach (var instance in instances) {
			var owner = instance as ClassSymbol;
			if (owner != null && owner.parent_class != null && owner.parent_class.foreign_export != null) {
				fail (owner.span, "selected foreign Class roots cannot participate in inheritance");
				return false;
			}
		}
		var root_policies = new GenericArray<ForeignClassPolicy> ();
		var protocols = new GenericArray<ForeignComInterface> ();
		foreach (var instance in instances) {
			var owner = instance as ClassSymbol;
			if (owner != null && owner.foreign_export != null) {
				root_policies.add (owner.foreign_export);
			}
		}
		foreach (var handle in handle_types.get_values ()) {
			if (handle.c_import != null && handle.c_import.com != null) {
				protocols.add (handle.c_import.com);
			}
		}
		foreach (var policy in root_policies) {
			if (!ForeignClassPolicy.com_roots_valid (policy, root_policies, protocols)) {
				fail (instances[0].span, "COM native object channel requires its exact Shared root and declared interface view");
				return false;
			}
		}

		return true;
	}

	private SemanticType? resolve_type_name(SourceSpan span, string source_name) {
		if (specializing_method != null) {
			for (int p = 0; p < method_type_parameters.length; p++) {
				if (source_name == method_type_parameters[p]) {
					return specializing_method.arguments.at (p);
				}
			}
		}
		string name = source_name;
		if (!name.has_suffix ("*") && !lexical_types.contains (name) && types.resolve (name) == null) {
			name = resolve_name (span, name);
		}
		if (specializing_class != null && specializing_class.generic_instance != null) {
			var key = specializing_class.generic_instance;
			var definition = generic_class_names.lookup (key.definition.name);
			if (definition != null) {
				for (int p = 0; p < definition.parameters.length; p++) {
					if (source_name == definition.parameters[p]) {
						return key.arguments.at (p);
					}
				}
			}
		}
		if (generic_class_names.contains (name)) {
			fail (span, "generic Class requires an explicit exact-Class application");
			return null;
		}
		if (name.contains ("**")) {
			fail (span, "pointer depth greater than one is unsupported");
			return null;
		}
		if (name.has_suffix ("*")) {
			var pointee = resolve_type_name (span, name.substring (0, name.length - 1));
			if (pointee == null) {
				return null;
			}
			return resolve_pointer_type (span, pointee);
		}
		if (generic_struct_names.contains (name)) {
			fail (span, "generic struct '%s' requires explicit type arguments; initializer inference is unsupported".printf (name));
			return null;
		}
		SemanticType? resolved = lexical_types.contains (name) ? lexical_types.lookup (name).semantic_type : types.resolve (name);
		if (resolved == null) {
			resolved = named_types.lookup (name);
		}
		if (resolved == null) {
			fail (span, name == "Task" ? "Task fields, parameters and return escapes are excluded; use an inferred local and explicit consuming await" : "unknown type '%s'".printf (name));
		}
		return resolved;
	}

	private SemanticType? resolve_pointer_type(SourceSpan span, SemanticType pointee) {
		if (owning_record_field (pointee) != null) {
			fail (span, "owning record pointer and address exposure are deferred");
			return null;
		}
		if (pointee is GenericStructApplicationType && pointee.is_parameterized ()) {
			fail (span, "parameterized generic Struct* is deferred; only fully concrete generic struct pointers are supported");
			return null;
		}
		if (pointee is ClassType) {
			fail (span, "ClassType* is unsupported; object references are not typed data pointers");
			return null;
		}
		if (pointee is VectorType && ((VectorType) pointee).is_mask) {
			fail (span, "bool-vector pointers are unsupported; bool memory representation and alignment are not defined");
			return null;
		}
		if (pointee != types.void_type && !pointee.is_typed_data_pointee ()) {
			fail (span, "typed pointer pointee must be an integer, f32, numeric vector, or native struct; bool and resource storage are unsupported");
			return null;
		}
		return pointee == types.void_type ? (SemanticType) types.raw_pointer_type : types.pointer_to (pointee);
	}

	private SemanticType? resolve_foreign_type(SourceSpan span, string name, bool record_pointer = false) {
		if (name.contains ("<")) {
			fail (span, "C ABI vectors are not supported yet");
			return null;
		}
		if (name.contains ("*") && name != "void*" && !record_pointer) {
			fail (span, "unsupported foreign pointer type; C/VAPI supports only 'void*'");
			return null;
		}
		if (record_pointer && name.has_suffix ("*")) {
			string pointee_name = name.substring (0, name.length - 1);
			return resolve_type_name (span, resolve_name (span, pointee_name) + "*");
		}
		return resolve_type_name (span, name);
	}

	private CFunctionSymbol? collect_foreign_signature(ForeignDeclarationInput input) {
		if (!input.metadata.bool_policy_valid ()) {
			fail (input.span, "bool_abi requires its admitted c99 copied boolean profile");
			return null;
		}
		if (!input.metadata.import_policy_valid ()) {
			fail (input.span, "GObjectImport requires its admitted policy identity and explicit bridge/SDK header");
			return null;
		}
		if (!input.metadata.pointer_abi.is_valid () || input.metadata.pointer_abi != CPointerAbi.NONE && (input.metadata.record_abi != CRecordAbi.NONE || input.metadata.text_abi != CTextAbi.NONE || input.metadata.buffer_abi != CBufferAbi.NONE || input.metadata.callback != null || input.metadata.owned_result != null)) {
			fail (input.span, "pointer_abi requires i32-noescape without alternate transports or owned result");
			return null;
		}
		if (ForeignClassPolicy.reserved_symbol (input.metadata.external_symbol)) {
			fail (input.span, "compiler-private foreign adapter runtime symbol cannot be declared by source");
			return null;
		}
		if (AllocationPolicy.reserved_symbol (input.metadata.external_symbol)) {
			fail (input.span, "compiler-private allocation runtime symbol cannot be declared by source");
			return null;
		}
		if (RetainedContracts.reserved_symbol (input.metadata.external_symbol)) {
			fail (input.metadata.external_symbol_span ?? input.name_span, "compiler-private retained callback runtime symbol cannot be declared by source");
			return null;
		}
		if (!input.metadata.record_abi.is_valid ()) {
			fail (input.metadata.record_abi_span ?? input.span, "unsupported C record_abi; expected 'natural-lp64'");
			return null;
		}
		if (!input.metadata.text_abi.is_valid ()) {
			fail (input.metadata.text_abi_span ?? input.span, "unsupported C text_abi; expected 'utf8-i32'");
			return null;
		}
		if (!input.metadata.buffer_abi.is_valid ()) {
			fail (input.metadata.buffer_abi_span ?? input.span, "unsupported C buffer_abi; expected 'u8-i32'");
			return null;
		}
		bool has_text = false;
		bool has_buffer = false;
		bool has_record = false;
		bool has_pointer = false;
		bool value_record = input.metadata.record_abi == CRecordAbi.VALUE_LP64;
		if (value_record && (input.parameters.length > 2 || input.metadata.callback != null || input.metadata.text_abi != CTextAbi.NONE || input.metadata.buffer_abi != CBufferAbi.NONE)) {
			fail (input.span, "value-lp64 supports at most two parameters and no alternate C transport groups");
			return null;
		}

		if (input.metadata.owned_result != null && input.return_type_name != "void*") {
			fail (input.return_type_span, "foreign owned-result contract requires exactly a 'void*' result");
			return null;
		}
		var return_type = resolve_foreign_type (input.return_type_span, input.return_type_name);
		if (return_type != null && return_type.is_scoped_allocator ()) {
			fail (input.return_type_span, "scoped contexts are created only by the lexical scoped_allocator intrinsic");
			return null;
		}
		if (return_type == null) {
			return null;
		}
		if (input.metadata.buffer_abi != CBufferAbi.NONE && return_type.is_nullable_pointer_value ()) {
			fail (input.return_type_span, "C byte buffer imports cannot return pointer-like values");
			return null;
		}
		if (input.metadata.record_abi != CRecordAbi.NONE && return_type.is_nullable_pointer_value ()) {
			fail (input.return_type_span, "C record imports cannot return pointer-like values or derived owners");
			return null;
		}
		if (input.owned_result && !(return_type is HandleType)) {
			fail (input.return_type_span, "'owned' foreign result qualifier requires a nominal handle type");
			return null;
		}
		if (return_type.is_struct_storage () && !value_record) {
			fail (input.return_type_span, "struct types are not supported at C/VAPI function boundaries");
			return null;
		}
		if (value_record && return_type.is_struct_storage ()) {
			if (!CPlainRecordTypes.value (return_type, copy_fields)) {
				fail (input.return_type_span, "value-lp64 requires 1..3 eightbyte numeric fields, or f32/f64; nested, packed and owning records are unsupported");
				return null;
			}
			has_record = true;
		}
		if (!(value_record && return_type.is_struct_storage ()) && !require_c_scalar_capability (return_type, input.return_type_span)) {
			return null;
		}
		if (!(value_record && return_type.is_struct_storage ()) && !(input.metadata.bool_abi == CBoolAbi.C99 && return_type.kind == TypeKind.BOOL) && return_type != types.int_type && !(return_type is IntegerType && ((IntegerType) return_type).bit_width == 64) && return_type != types.void_type && return_type != types.raw_pointer_type && !(return_type is HandleType) && !(return_type is F64Type) && !(return_type is F32Type)) {
			fail (input.return_type_span, "C result type must be 'int', 'void*' or 'void'; foreign bool is unsupported");
			return null;
		}
		var parameters = new GenericArray<ParameterSymbol> ();
		var names = new HashTable<string, ParameterSymbol> (str_hash, str_equal);
		for (int i = 0; i < input.parameters.length; i++) {
			var parameter = input.parameters[i];
			bool record = input.metadata.record_abi == CRecordAbi.NATURAL_LP64 && parameter.type_name.has_suffix ("*") && parameter.type_name != "void*";
			bool scalar_pointer = input.metadata.pointer_abi == CPointerAbi.I32_NOESCAPE && parameter.type_name == "int*";
			if (scalar_pointer) {
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					fail (parameter.span, "i32-noescape requires explicit borrowed int*");
					return null;
				}
				has_pointer = true;
			}
			bool buffer = parameter.type_name == "u8[]" && input.metadata.buffer_abi == CBufferAbi.U8_I32;
			if (buffer && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				fail (parameter.span, "foreign byte buffer requires buffer_abi = \"u8-i32\" and explicit borrowed u8[]");
				return null;
			}
			if (buffer) {
				has_buffer = true;
			}
			if (!parameter.pointer_contract.is_valid () || parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && parameter.type_name != "void*" && !buffer && !record && !scalar_pointer && !(parameter.type_name == "string" && input.metadata.text_abi == CTextAbi.UTF8_I32) && !(named_types.lookup (parameter.type_name) is HandleType))) {
				fail (parameter.span, "'borrowed' parameter requires exactly 'void*'");
				return null;
			}
			var parameter_type = buffer ? types.slice_of (types.u8_type) : resolve_foreign_type (parameter.type_span, parameter.type_name, record || scalar_pointer);
			if (parameter_type == null) {
				return null;
			}
			if (record) {
				StructSymbol? declaration = null;
				if (parameter_type is TypedPointerType) {
					declaration = instance_for (((TypedPointerType) parameter_type).pointee) as StructSymbol;
				}
				if (declaration != null && declaration.representation != null && declaration.representation.is_union) {
					fail (parameter.span, "C union projection requires value-lp64 by-value transport; borrowed mutable union aliases are unsupported");
					return null;
				}
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || !CPlainRecordTypes.pointer (parameter_type, copy_fields)) {
					fail (parameter.span, "natural-lp64 requires explicit borrowed Struct* with 1..32 copied numeric scalar fields; bool, pointers, nested/owned records and packing are unsupported");
					return null;
				}
				has_record = true;
			}
			if (parameter_type == types.void_type) {
				fail (parameter.type_span, "parameter type cannot be 'void'");
				return null;
			}
			if (parameter_type.is_struct_storage () && !value_record) {
				fail (parameter.type_span, "struct types are not supported at C/VAPI function boundaries");
				return null;
			}
			if (parameter_type is StringType) {
				if (input.metadata.text_abi == CTextAbi.NONE) {
					fail (parameter.type_span, "C parameter type must be 'int' or 'void*'; foreign bool is unsupported");
					return null;
				}
				has_text = true;
				if (input.metadata.text_abi != CTextAbi.UTF8_I32 || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					fail (parameter.span, "foreign string parameter requires text_abi = \"utf8-i32\" and explicit borrowed string");
					return null;
				}
			}
			if (value_record && parameter_type.is_struct_storage ()) {
				if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !CPlainRecordTypes.value (parameter_type, copy_fields)) {
					fail (parameter.span, "value-lp64 requires copied numeric POD values without borrowed/owned qualifiers");
					return null;
				}
				has_record = true;
			}
			if (!record && !scalar_pointer && !(value_record && parameter_type.is_struct_storage ()) && !require_c_scalar_capability (parameter_type, parameter.type_span)) {
				return null;
			}
			if (!(value_record && parameter_type.is_struct_storage ()) && !(input.metadata.bool_abi == CBoolAbi.C99 && parameter_type.kind == TypeKind.BOOL) && parameter_type != types.int_type && !(parameter_type is IntegerType && ((IntegerType) parameter_type).bit_width == 64) && parameter_type != types.raw_pointer_type && !(parameter_type is HandleType) && !(parameter_type is F64Type) && !(parameter_type is F32Type) && !(parameter_type is StringType) && !buffer && !record && !scalar_pointer) {
				fail (parameter.type_span, "C parameter type must be 'int' or 'void*'; foreign bool is unsupported");
				return null;
			}
			string name = parameter.name;
			if (names.contains (name)) {
				fail (parameter.name_span, "duplicate parameter '%s'".printf (name));
				return null;
			}
			var symbol = new ParameterSymbol (parameter.span, parameter.name_span, parameter_type, i, parameter.pointer_contract, name);
			parameters.add (symbol);
			names.insert (symbol.name, symbol);
		}
		if (input.metadata.buffer_abi != CBufferAbi.NONE && !has_buffer) {
			fail (input.metadata.buffer_abi_span ?? input.span, "buffer_abi requires at least one borrowed u8[] parameter");
			return null;
		}
		if (input.metadata.pointer_abi != CPointerAbi.NONE && (!has_pointer || return_type.is_nullable_pointer_value () && !input.metadata.com_owner_result)) {
			fail (input.span, "pointer_abi requires borrowed int* and no pointer-like result");
			return null;
		}
		if (input.metadata.record_abi != CRecordAbi.NONE && !has_record) {
			fail (input.metadata.record_abi_span ?? input.span, "record_abi requires at least one borrowed scalar POD Struct* parameter");
			return null;
		}
		if (input.metadata.text_abi != CTextAbi.NONE && !has_text) {
			fail (input.metadata.text_abi_span ?? input.span, "text_abi requires at least one borrowed string parameter");
			return null;
		}
		var metadata = input.metadata;
		bool device_parameters = true;
		foreach (var parameter in parameters) {
			device_parameters &= parameter.semantic_type.kind == TypeKind.INT && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
		}
		if (!metadata.device_signature (return_type.kind == TypeKind.INT, parameters.length, device_parameters)) {
			fail (input.span, "invalid PC device policy: requires its exact i32 signature without foreign transport or ownership metadata");
			return null;
		}
		if (input.owned_result) {
			metadata = metadata.copy_with_owned_result (new CForeignOwnedResultContract (handle_types.lookup (return_type).cleanup));
		}
		if (metadata.owned_result != null) {
			var source = metadata.owned_result.cleanup;
			if (source.external_symbol == "") {
				fail (source.symbol_span ?? input.name_span, "foreign cleanup external symbol must be nonempty");
				return null;
			}
			var cleanup = intern_cleanup (source);
			metadata = metadata.copy_with_owned_result (new CForeignOwnedResultContract (cleanup));
		}
		bool has_bool = return_type.kind == TypeKind.BOOL;
		foreach (var parameter in parameters) {
			has_bool |= parameter.semantic_type.kind == TypeKind.BOOL;
		}
		if (!metadata.bool_signature_valid (has_bool)) {
			fail (input.span, "c99 requires copied bool channels without alternate transports, owned results or GObject/COM/device policies");
			return null;
		}
		SemanticType[] argument_types = null;
		PointerParameterContract[] contracts = null;
		foreach (var parameter in parameters) {
			argument_types += parameter.semantic_type;
			contracts += parameter.pointer_contract;
		}
		if (!ComImportTypes.valid (metadata, return_type, argument_types, contracts, metadata.owned_result == null ? "" : metadata.owned_result.cleanup.external_symbol)) {
			fail (input.span, "COMImport callable lost its exact nominal IID, ownership, out or context role");
			return null;
		}
		return new CFunctionSymbol (input.span, input.name_span, return_type, parameters, metadata, source_namespace (input.name_span) == "" ? input.name : source_namespace (input.name_span) + "." + input.name);
	}

	private SemanticOwnershipFlow? generic_owner_flow;
	private static bool consuming_class_member(Object? target, int ordinal, SemanticType type) {
		var method = target as MethodSymbol;
		if (method == null || !GenericClassTypes.general (method.declaring_type.semantic_type) || method.async_body != null || method.throws_type != null || method.result_contract == ResultOwnershipContract.OWNED_TRANSFER || ordinal < 0 || ordinal >= method.parameters.length) {
			return false;
		}
		var parameter = method.parameters[ordinal];
		return parameter.semantic_type == type && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (ownable_parameter (type) || type is ClassType && parameter.heap_object);
	}
	private int heap_consumer_parameter(GenericFunctionSymbol function, GenericArray<LocalSymbol> locals, GenericOwnershipFlow flow) {
		bool returning = function.result_contract == ResultOwnershipContract.OWNED_TRANSFER;
		if (function.async_body != null || function.throws_type != null) {
			return -1;
		}
		if (returning) {
			if (!ownable_parameter (function.return_type)) {
				return -1;
			}
		} else if (function.return_type.kind != TypeKind.VOID && !GenericBorrowTypes.scalar (function.return_type)) {
			return -1;
		}
		int ordinal = -1;
		foreach (var parameter in function.parameters) {
			if (ownable_parameter (parameter.semantic_type) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				if (ordinal != -1) {
					return -1;
				}
				ordinal = parameter.ordinal;
			} else if (!GenericClassTypes.borrowed_context (parameter.semantic_type, parameter.pointer_contract) && (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(GenericBorrowTypes.scalar (parameter.semantic_type) || parameter.semantic_type is FunctionValueType))) {
				return -1;
			}
		}
		if (ordinal == -1 || (returning && function.return_type != function.parameters[ordinal].semantic_type)) {
			return -1;
		}
		if (returning) {
			foreach (var local in locals) {
				if (local.incoming_parameter == null && (local.is_owned || local.semantic_type is ClassType)) {
					return -1;
				}
			}
		}
		foreach (var local in locals) {
			if (local.incoming_parameter == function.parameters[ordinal]) {
				var scope = flow.transfer_scopes.lookup (local) ?? new GenericOwnerTransferScope ();
				if (!scope.valid || scope.returned != returning || (returning && scope.target != null)) {
					return -1;
				}
				heap_consumer_scopes.insert (function, scope);
				return ordinal;
			}
		}
		return -1;
	}
	private static bool ownable_parameter(SemanticType? type) {
		return type is TypeParameterType && ((TypeParameterType) type).transport_mode == GenericTransportMode.OWNABLE;
	}
	private CheckedStatement? check_generic_owner_local(SourceSpan span, Token name, ExpressionSyntax expression, SemanticType type, ValueScope values, GenericArray<LocalSymbol> locals, CheckedExpression? checked_initializer = null) {
		if (!(checking_function is GenericFunctionSymbol) || !ownable_parameter (type)) {
			fail (span, "generic owned locals require the declared Ownable capability");
			return null;
		}
		var previous = values.lookup (name.spelling ());
		if (previous != null) {
			fail (name.span, previous is ParameterSymbol || (previous is LocalSymbol && ((LocalSymbol) previous).incoming_parameter != null)
				    ? "local '%s' conflicts with parameter".printf (name.spelling ()) : "duplicate local '%s'".printf (name.spelling ()));
			return null;
		}
		ExpressionSyntax direct = expression;
		while (direct is ParenthesizedExpressionSyntax) {
			direct = ((ParenthesizedExpressionSyntax) direct).expression;
		}
		LocalSymbol? source = null;
		CheckedExpression? initializer = checked_initializer;
		if (expression is MoveExpressionSyntax) {
			var moved = (MoveExpressionSyntax) expression;
			source = values.lookup (moved.source.spelling ()) as LocalSymbol;
			if (source == null || !source.is_generic_owner || source.semantic_type != type || source.heap_object || source.object_owner != null || source.cleanup != null) {
				fail (expression.span, "generic owned locals require an exact owned binding of their declared type; borrowed bindings cannot transfer ownership");
				return null;
			}
			if (check_move_source (moved, values) == null) {
				return null;
			}
			initializer = new CheckedOwnershipMove (moved.span, source);
		} else if (initializer != null || direct is CallExpressionSyntax) {
			if (initializer == null) {
				initializer = check_expression (expression, values, type, OwnershipUse.ACQUIRE);
			}
			if (initializer == null) {
				return null;
			}
			var invocation = initializer as CheckedInvocation;
			if (initializer.semantic_type != type || invocation == null || invocation.result_producer () == null) {
				fail (expression.span, "generic owned locals require an exact owning result");
				return null;
			}
		} else {
			fail (expression.span, "generic owned locals require explicit move or an exact owning producer");
			return null;
		}
		var local = new LocalSymbol (span, name.span, type, locals.length, values.region);
		local.generic_owned_local = true;
		local.generic_owner_source = source;
		if (source != null) {
			generic_owner_flow.move (source, source.name, expression.span, local, -1, false, true);
		} else {
			generic_owner_flow.owner_event (GenericOwnershipEventKind.LOCAL_ACQUIRE, local, local.name, span);
		}
		locals.add (local);
		values.insert (local.name, local);
		return new CheckedOwnedLocalDeclaration (span, local, initializer);
	}
	private static bool deferred_class_result(FunctionSymbol function) {
		var generic = function as GenericFunctionSymbol;
		return generic != null && generic.return_type is ClassType
		       && generic.result_contract == ResultOwnershipContract.OWNED_TRANSFER
		       && (generic.result_origins.domains & GenericResultOrigins.UNKNOWN) != 0;
	}
	private GenericArray<SourceResultOriginRequest> projected_origin_requests = new GenericArray<SourceResultOriginRequest> ();
	private int projected_generic_origins;
	private HashTable<GenericRequestKey, SourceResultOriginRequest> projected_origin_registry = new HashTable<GenericRequestKey, SourceResultOriginRequest> (GenericRequestKey.hash, GenericRequestKey.equal);
	private SourceResultOriginRequest? request_source_result(FunctionSymbol function, GenericArray<SemanticType> arguments) {
		var vector = new TypeArgumentVector (arguments);
		var key = new GenericRequestKey (function, vector);
		var prior = projected_origin_registry.lookup (key);
		if (prior != null) {
			return prior;
		}
		if (projected_origin_requests.length >= GenericResourceLimits.CLOSED_INSTANCES + origin_functions.length) {
			fail (function.span, "result-origin analysis exceeded its bounded context inventory");
			return null;
		}
		var generic = function as GenericFunctionSymbol;
		if (generic != null && (arguments.length != generic.type_parameters.length || vector.closed () && projected_generic_origins++ >= GenericResourceLimits.CLOSED_INSTANCES)) {
			fail (function.span, "generic result-origin projection exceeded its exact arity or closed-instance budget");
			return null;
		}
		var substitution = new TypeSubstitution ((element) => types.slice_of (element), types.substitute_function, substitute_class, substitute_closure);
		foreach (var argument in arguments) {
			if (!GenericResourceLimits.admits_type (argument)) {
				fail (function.span, "generic result-origin projection exceeded the type-depth budget");
				return null;
			}
		}
		if (generic != null) {
			for (int t = 0; t < arguments.length; t++) {
				substitution.bind (generic.type_parameters[t].semantic_type, arguments[t]);
			}
		}
		var result = new SourceResultOriginRequest (function, vector, substitution);
		projected_origin_requests.add (result);
		projected_origin_registry.insert (key, result);
		return result;
	}
	private BlockStatementSyntax? source_result_body(FunctionSymbol function) {
		var method = function as MethodSymbol;
		if (method != null) {
			var syntax = method_syntax.lookup (method);
			return syntax == null ? null : syntax.body;
		}
		for (int i = 0; i < origin_functions.length; i++) {
			if (origin_functions[i] == function) {
				return origin_bodies[i];
			}
		}
		return null;
	}
	private GenericResultOrigins source_result_edge(FunctionSymbol function, CallExpressionSyntax call, HashTable<string, SemanticType> locals, TypeSubstitution substitution) {
		var arguments = new GenericArray<SemanticType> ();
		var generic = function as GenericFunctionSymbol;
		if (generic != null) {
			var saved = origin_record_types;
			origin_record_types = locals;
			var inferred = generic_origin_substitution (generic, call, new HashTable<string, ObjectOriginConstraint> (str_hash, str_equal), substitution);
			origin_record_types = saved;
			if (inferred == null) {
				return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
			}
			foreach (var parameter in generic.type_parameters) {
				arguments.add (inferred.apply (parameter.semantic_type));
			}
		}
		var request = request_source_result (function, arguments);
		return request == null ? new GenericResultOrigins (GenericResultOrigins.UNKNOWN) : request.equation;
	}
	private GenericResultOrigins project_source_result(FunctionSymbol function, GenericArray<SemanticType> arguments) {
		var root = request_source_result (function, arguments);
		if (root == null) {
			return new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		if (root.solved) {
			return root.equation;
		}
		var saved_class = specializing_class;
		var saved_method = specializing_method;
		var saved_parameters = method_type_parameters;
		var saved_lexical = lexical_types;
		var saved_records = origin_record_types;
		var saved_function = origin_function;
		bool changed = false;
		do {
			changed = false;
			uint before = projected_origin_requests.length;
			for (int i = 0; i < projected_origin_requests.length; i++) {
				var current = projected_origin_requests[i];
				if (current.solved) {
					continue;
				}
				var body = source_result_body (current.function);
				GenericResultOrigins equation;
				if (body == null) {
					equation = new GenericResultOrigins ((current.function.return_type is ClassType) ? (current.function.heap_result ? GenericResultOrigins.HEAP : GenericResultOrigins.CALLER) : GenericResultOrigins.UNKNOWN);
				} else {
					var method = current.function as MethodSymbol;
					specializing_class = method == null ? null : method.declaring_type as ClassSymbol;
					specializing_method = method == null ? null : method.generic_method_instance;
					method_type_parameters = specializing_method == null ? new string[0] : method_parameter_names (method_syntax.lookup (method));
					lexical_types = new HashTable<string, TypeParameterSymbol> (str_hash, str_equal);
					var generic = current.function as GenericFunctionSymbol;
					if (generic != null) {
						foreach (var parameter in generic.type_parameters) {
							lexical_types.insert (parameter.name, parameter);
						}
					}
					origin_function = current.function;
					origin_record_types = new HashTable<string, SemanticType> (str_hash, str_equal);
					var analysis = new GenericSourceResultOrigins (current.function, new HashTable<FunctionSymbol, GenericResultOrigins> (direct_hash, direct_equal), generic_origin_target,
						(syntax) => { var type = resolve_contract_type (syntax);
						              return type == null ? null : current.substitution.apply (type);
						}, current.substitution,
						(callee, call, locals) => source_result_edge (callee, call, locals, current.substitution));
					equation = analysis.derive (body);
				}
				if (!current.equation.same (equation)) {
					current.equation = equation;
					changed = true;
				}
				if (diagnostic != null) {
					break;
				}
			}
			changed |= projected_origin_requests.length != before;
		} while (changed && diagnostic == null);
		if (diagnostic == null) {
			foreach (var current in projected_origin_requests) {
				current.solved = (current.equation.domains & GenericResultOrigins.UNKNOWN) == 0;
			}
		}
		specializing_class = saved_class;
		specializing_method = saved_method;
		method_type_parameters = saved_parameters;
		lexical_types = saved_lexical;
		origin_record_types = saved_records;
		origin_function = saved_function;
		return root.equation;
	}
	private FunctionSymbol? generic_origin_target(CallExpressionSyntax call, HashTable<string, SemanticType> locals, TypeSubstitution? substitution) {
		SemanticType? receiver = null;
		if (call.receiver != null) {
			receiver = locals.lookup (call.receiver.spelling ());
		} else if (call.receiver_place != null) {
			var saved = origin_record_types;
			origin_record_types = locals;
			receiver = origin_receiver_type (call.receiver_place, new HashTable<string, ObjectOriginConstraint> (str_hash, str_equal));
			origin_record_types = saved;
		}
		if (receiver != null) {
			// Unsolved source member flags cannot establish a factory origin.
			if (substitution == null || receiver.is_parameterized ()) {
				return null;
			}
			var owner = instance_for (receiver);
			return owner == null ? null : resolve_class_method (owner, call, substitution);
		}
		if (call.identifier.spelling () == "init" && (call.receiver != null || call.receiver_place != null) && (call.receiver == null || !module_names.contains (call.receiver.spelling ()))) {
			var owner = qualified_class (call, true) as ClassSymbol;
			return owner == null ? null : owner.constructor;
		}
		if (call.receiver_place != null || (call.receiver != null && !module_names.contains (call.receiver.spelling ()))) {
			return null;
		}
		string name = (call.receiver == null ? "" : call.receiver.spelling () + ".") + call.identifier.spelling ();
		return function_names.lookup (resolve_name (call.span, name, false)) as FunctionSymbol;
	}
	private void derive_generic_result_origins() {
		// Resolve source factory dependencies with generic wrappers. Ordinary
		// functions have not received their solved allocation flags yet.
		var equations = new HashTable<FunctionSymbol, GenericResultOrigins> (direct_hash, direct_equal);
		foreach (var function in origin_functions) {
			if (function is MethodSymbol || function is LifecycleSymbol || function is PropertyAccessorSymbol) {
				continue;
			}
			if (function.result_contract == ResultOwnershipContract.OWNED_TRANSFER && (ownable_parameter (function.return_type) || function.return_type is ClassType)) {
				equations.insert (function, new GenericResultOrigins ());
			}
		}
		bool changed = false;
		do {
			changed = false;
			for (int i = 0; i < origin_functions.length; i++) {
				var function = origin_functions[i];
				if (!equations.contains (function)) {
					continue;
				}
				lexical_types.remove_all ();
				var generic = function as GenericFunctionSymbol;
				if (generic != null) {
					foreach (var parameter in generic.type_parameters) {
						lexical_types.insert (parameter.name, parameter);
					}
				}
				var saved_origin = origin_function;
				origin_function = function;
				var analysis = new GenericSourceResultOrigins (function, equations, generic_origin_target, (syntax) => resolve_contract_type (syntax));
				var result = analysis.derive (origin_bodies[i]);
				origin_function = saved_origin;
				if (!equations.lookup (function).same (result)) {
					equations.insert (function, result);
					changed = true;
				}
				if (generic != null) {
					generic.result_origins = result;
				}
				if (diagnostic != null) {
					return;
				}
			}
		} while (changed);
		lexical_types.remove_all ();
	}
	private bool owned_call_heap_result(CheckedCallExpression call) {
		var function = call.target as FunctionSymbol;
		if (function == null) {
			return false;
		}
		if (!(call is CheckedGenericCall) || !(function.return_type is TypeParameterType || function.return_type is ClassType)) {
			return function.heap_result;
		}
		if (!(call.semantic_type is ClassType) || function.result_contract != ResultOwnershipContract.OWNED_TRANSFER) {
			return false;
		}
		var heaps = new bool[call.arguments.length];
		for (int i = 0; i < call.arguments.length; i++) {
			var argument = call.arguments[i] as CheckedOwnedArgument;
			heaps[i] = argument != null && argument.transfer != null && argument.transfer.source.heap_object;
		}
		var equation = ((GenericFunctionSymbol) function).result_origins;
		if ((equation.domains & GenericResultOrigins.UNKNOWN) != 0) {
			equation = project_source_result (function, ((CheckedGenericCall) call).type_arguments);
		}
		uint domains = equation.evaluate (heaps);
		if (domains == (GenericResultOrigins.CALLER | GenericResultOrigins.HEAP)) {
			fail (call.span, "generic Class result joins incompatible heap and caller-backed storage origins");
		}
		if (equation.captured_caller) {
			fail (call.span, "generic Class result cannot escape callee-local caller storage acquired by a local");
		}
		return domains == GenericResultOrigins.HEAP;
	}
	private bool check_generic_position(SemanticType? type, bool owned, bool borrowed, SourceSpan span) {
		if (!(type is TypeParameterType)) {
			return true;
		}
		if (borrowed) {
			if (!ownable_parameter (type)) {
				fail (span, "borrowed T requires explicit capability Ownable");
				return false;
			}
			return true;
		}
		if (owned && !ownable_parameter (type)) {
			fail (span, "owned T requires explicit capability Ownable");
			return false;
		}
		if (!owned && ownable_parameter (type)) {
			fail (span, "plain T value transport is unavailable for an Ownable type parameter; use owned T");
			return false;
		}
		return true;
	}
	private bool check_generic_borrow_source(ExpressionSyntax syntax, ValueScope values) {
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		var symbol = (syntax is NameExpressionSyntax) ? values.lookup (((NameExpressionSyntax) syntax).identifier.spelling ()) : null;
		var owner = symbol as LocalSymbol;
		var incoming = symbol as ParameterSymbol;
		bool forwarded = incoming != null && GenericBorrowTypes.accepts (incoming.semantic_type) && incoming.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE;
		if (syntax is NullPointerExpressionSyntax || (owner != null && owner.is_owned) || forwarded) {
			return true;
		}
		fail (syntax.span, "generic borrowed argument requires a live exact owner, borrowed T parameter or explicit contextual null");
		return false;
	}
	private CheckedOwnershipReturn? check_generic_owned_return(ReturnStatementSyntax syntax, FunctionSymbol function, ValueScope values) {
		CheckedOwnershipMove? transfer = null;
		CheckedExpression? producer = null;
		if (syntax.expression is MoveExpressionSyntax) {
			transfer = check_move ((MoveExpressionSyntax) syntax.expression, values, true);
			if (transfer == null) {
				return null;
			}
		} else if (syntax.expression is CallExpressionSyntax) {
			var call = check_expression (syntax.expression, values, function.return_type, OwnershipUse.ACQUIRE);
			var invocation = call as CheckedInvocation;
			if (invocation == null || invocation.result_producer () == null) {
				fail (syntax.expression.span, "owned T forwarding requires an exact owned-result invocation");
				return null;
			}
			producer = call;
		} else {
			fail (syntax.expression.span, "owned T result requires explicit move of an incoming owner or direct owned-result forwarding; copying and generic null construction are unsupported");
			return null;
		}
		if ((transfer != null ? transfer.semantic_type : producer.semantic_type) != function.return_type) {
			fail (syntax.span, "owned generic return requires the exact result type parameter");
			return null;
		}
		return new CheckedOwnershipReturn (syntax.span, function.return_type, null, transfer, null, producer);
	}
	private static int generic_truth(CheckedExpression? expression) {
		return (expression is CheckedBooleanExpression) ? (((CheckedBooleanExpression) expression).literal == BooleanLiteral.TRUE ? 1 : 0) : -1;
	}

	private bool collect_caller_information(ParameterSyntax syntax, ParameterSymbol parameter, GenericArray<ParameterSymbol> earlier) {
		var annotation = syntax.caller_information;
		if (annotation == null) {
			return true;
		}
		CallerInformationKind kind;
		switch (annotation.name.spelling ()) {
		case "CallerFilePath": kind = CallerInformationKind.FILE_PATH;
			break;
		case "CallerLineNumber": kind = CallerInformationKind.LINE_NUMBER;
			break;
		case "CallerArgumentExpression": kind = CallerInformationKind.ARGUMENT_EXPRESSION;
			break;
			default: fail (annotation.span, "unknown native caller-information annotation");
			return false;
		}
		int target = -1;
		if (kind == CallerInformationKind.ARGUMENT_EXPRESSION) {
			if (annotation.target == null || annotation.target.kind != TokenKind.TEXT || annotation.target.text_payload == null || !annotation.target.text_payload.valid ()) {
				fail (annotation.span, "CallerArgumentExpression requires one string literal");
				return false;
			}
			foreach (var candidate in earlier) {
				if (candidate.caller_information == null && annotation.target.text_payload.equal_content (new Astra.Text.TextBytes (candidate.name.data))) {
					target = candidate.ordinal;
					break;
				}
			}
			if (target < 0) {
				fail (annotation.span, "CallerArgumentExpression must name an earlier required non-annotated parameter; unknown names, self, caller parameters, this and member paths are unsupported");
				return false;
			}
		} else if (annotation.target != null) {
			fail (annotation.span, "file/line caller-information annotations take no payload");
			return false;
		}
		parameter.caller_information = new CallerInformationContract (kind, annotation.span, target);
		return true;
	}

	private bool check_method_bodies(GenericArray<NativeInstanceSymbol> instances, GenericArray<CheckedFunction> functions) {
		bool more_methods = false;
		do {
			more_methods = false;
			for (int i = 0; i < instances.length; i++) {
				specializing_class = instances[i] as ClassSymbol;
				for (int m = 0; m < instances[i].methods.length; m++) {
					var method = instances[i].methods[m];
					if (checked_methods.contains (method)) {
						continue;
					}
					var syntax = method_syntax.lookup (method);
					specializing_method = method.generic_method_instance;
					method_type_parameters = specializing_method == null ? new string[0] : method_parameter_names (syntax);
					if (native_body (method)) {
						functions.add (new CheckedMethod (method, new GenericArray<LocalSymbol> (), native_block (syntax.span)));
						checked_methods.insert (method, true);
						more_methods = true;
						continue;
					}
					if (diagnostic != null) {
						return false;
					}
					if (syntax.is_signal) {
						var owner = method.declaring_type as ClassSymbol;
						var policy = owner == null ? null : owner.foreign_export;
						ForeignSignalBinding? binding = null;
						if (policy != null && policy.declared_api != null) {
							for (uint n = 0; n < policy.declared_api.member_count; n++) {
								var member = policy.declared_api.member (n);
								if (member.kind == ForeignMemberKind.SIGNAL && member.native_member_ordinal == method.member_ordinal) {
									binding = new ForeignSignalBinding (policy,n);
								}
							}
						}
						if (binding == null || !binding.valid ()) {
							fail (syntax.span,"signal requires its exact declaration-driven shared GObject contract");
							return false;
						}
						var region = new LexicalRegion (null,0);
						var signal_locals = new GenericArray<LocalSymbol> ();
						foreach (var parameter in method.parameters) {
							if (parameter.struct_value_contract != null) {
								signal_locals.add (new LocalSymbol (parameter.span,parameter.name_span,parameter.semantic_type,signal_locals.length,region,null,parameter));
							}
						}
						var statements = new GenericArray<CheckedStatement> ();
						statements.add (new CheckedForeignSignalReturn (syntax.span,binding));
						functions.add (new CheckedMethod (method,signal_locals,new CheckedBlockStatement (syntax.span,statements,region)));
						checked_methods.insert (method,true);
						more_methods = true;
						continue;
					}
					if (!interface_readonly_implementation (syntax,method)) {
						return false;
					}
					var locals = new GenericArray<LocalSymbol> ();
					next_loop_ordinal = 0;
					next_region_ordinal = 0;
					next_object_ordinal = 0;
					begin_ownership_flow (method);
					var body = check_block (syntax.body,method,null,locals);
					if (!verify_ownership_flow (body,method)) {
						return false;
					}
					generic_owner_flow = null;
					functions.add (new CheckedMethod (method,locals,body));
					checked_methods.insert (method,true);
					more_methods = true;
				}
			}
		} while (more_methods);
		specializing_method = null;
		method_type_parameters = {};
		specializing_class = null;
		return true;
	}

	private static string[] method_parameter_names(FunctionDeclarationSyntax syntax) {
		var names = new string[syntax.type_parameters.length];
		for (int p = 0; p < names.length; p++) {
			names[p] = syntax.type_parameters[p].spelling ();
		}
		return names;
	}

	private MethodSymbol? resolve_class_method(NativeInstanceSymbol instance,CallExpressionSyntax call,TypeSubstitution? projection = null) {
		var owner = instance as ClassSymbol;
		var key = owner == null ? null : owner.generic_instance;
		if (key == null || !key.definition.general_bodies) {
			return instance.find_method (call.identifier.spelling ());
		}
		int member = -1;
		for (int m = 0; m < key.definition.generic_method_count; m++) {
			if (key.definition.generic_method_name (m) == call.identifier.spelling ()) {
				member = m;
			}
		}
		if (member < 0) {
			return instance.find_method (call.identifier.spelling ());
		}
		var definition = generic_class_names.lookup (key.definition.name);
		FunctionDeclarationSyntax? syntax = null;
		foreach (var candidate in definition.syntax.methods) {
			if (candidate.name.spelling () == call.identifier.spelling () && candidate.type_parameters.length != 0) {
				syntax = candidate;
			}
		}
		if (syntax == null) {
			fail (call.span,"generic method lost its original source declaration");
			return null;
		}
		if (call.type_arguments.length != syntax.type_parameters.length) {
			string expected = syntax.type_parameters.length == 1 ? "one" : syntax.type_parameters.length.to_string ();
			fail (call.span,"generic method '%s' requires %s explicit ordered type arguments, found %u".printf (call.identifier.spelling (),expected,call.type_arguments.length));
			return null;
		}
		var values = new GenericArray<SemanticType> ();
		foreach (var type in call.type_arguments) {
			var argument = resolve_type (type);
			if (argument == null) {
				return null;
			}
			values.add (projection == null ? argument : projection.apply (argument));
		}
		var arguments = new TypeArgumentVector (values);
		if (projection != null && !arguments.closed ()) {
			return null;
		}
		return request_class_method (owner,member,arguments,call.span);
	}

	private MethodSymbol? request_class_method(ClassSymbol owner,int member,TypeArgumentVector arguments,SourceSpan span) {
		var key = owner.generic_instance;
		var definition = generic_class_names.lookup (key.definition.name);
		string name = key.definition.generic_method_name (member);
		FunctionDeclarationSyntax? syntax = null;
		foreach (var candidate in definition.syntax.methods) {
			if (candidate.name.spelling () == name && candidate.type_parameters.length != 0) {
				syntax = candidate;
			}
		}
		if (syntax == null || arguments.length != syntax.type_parameters.length) {
			fail (span,"generic method request lost its exact declared arity");
			return null;
		}
		var declaration = key.definition.structure.find_member (name);
		for (int c = 0; c < declaration.constraint_count; c++) {
			if (!GenericClassDeclaredShape.constraint (declaration.constraint (c),key.arguments,arguments,exact_heap_class_argument)) {
				fail (span,declaration.constraint (c).exact_heap_class ? "ExactHeapClass requires a concrete nongeneric nonpolymorphic native Class argument" : "generic method type arguments do not satisfy the declared capability constraint");
				return null;
			}
		}
		foreach (var method in owner.methods) {
			var prior = method.generic_method_instance;
			if (prior != null && prior.member == member && prior.arguments.matches (arguments)) {
				return method;
			}
		}
		foreach (var method in method_applications) {
			var prior = method.generic_method_instance;
			if (method.declaring_type == owner && prior.member == member && prior.arguments.matches (arguments)) {
				return method;
			}
		}
		if (!owner.semantic_type.is_parameterized () && arguments.closed () && closed_method_count++ >= GenericResourceLimits.CLOSED_INSTANCES) {
			fail (span,"generic method materialization limit %u exceeded while requesting '%s'".printf (GenericResourceLimits.CLOSED_INSTANCES,name));
			return null;
		}
		var request = new ClassMethodInstance.application (key,member,arguments);
		var saved_class = specializing_class;
		var saved_method = specializing_method;
		var saved_parameters = method_type_parameters;
		var saved_lexical = lexical_types;
		var saved_elements = element_obligations;
		bool saved_premises = collecting_enum_premises;
		lexical_types = new HashTable<string,TypeParameterSymbol> (str_hash,str_equal);
		foreach (var parameter in saved_lexical.get_values ()) {
			lexical_types.insert (parameter.name,parameter);
		}
		specializing_class = owner;
		specializing_method = request;
		method_type_parameters = method_parameter_names (syntax);
		var result = collect_signature (syntax,owner,0) as MethodSymbol;
		specializing_class = saved_class;
		specializing_method = saved_method;
		method_type_parameters = saved_parameters;
		lexical_types = saved_lexical;
		element_obligations = saved_elements;
		collecting_enum_premises = saved_premises;
		if (result == null) {
			return null;
		}
		result.generic_method_instance = request;
		if (owner.semantic_type.is_parameterized () || !arguments.closed ()) {
			result.application_scope = (draining_object_origins ? origin_function : checking_function) as GenericFunctionSymbol;
			if (result.application_scope == null) {
				fail (span,"symbolic generic method requires its exact enclosing generic scope");
				return null;
			}
			method_applications.add (result);
			class_method_requests.add (new GenericClassMethodRequest (result,result.application_scope));
			return result;
		}
		owner.methods.add (result);
		method_syntax.insert (result,syntax);
		seed_origin_signature (result);
		if (origin_program != null && !draining_object_origins && !resolve_object_origins (origin_program,origin_declarations,class_requests)) {
			return null;
		}
		return result;
	}

	private bool declared_foreign_member(FunctionDeclarationSyntax syntax,NativeInstanceSymbol? owner) {
		if (!(owner is ClassSymbol) || syntax.foreign_member == null) {
			return false;
		}
		foreach (var declaration in instance_syntax) {
			if (declaration.name.span.file == owner.name_span.file && declaration.name.span.start == owner.name_span.start && declaration.name.span.end == owner.name_span.end) {
				return ForeignApiAdmission.selected (declaration as ClassDeclarationSyntax);
			}
		}
		return false;
	}
	private DirectCallableSymbol? collect_signature(FunctionDeclarationSyntax syntax,NativeInstanceSymbol? declaring_type = null,int member_ordinal = -1) {
		if (syntax.foreign_policy != null) {
			var policy = syntax.foreign_policy;
			if (declaring_type != null || syntax.ccode != null || syntax.floating_point != null || syntax.extern_keyword != null || syntax.export_keyword != null || (policy.kind != DeclarationPolicyId.C_IMPORT && policy.kind != DeclarationPolicyId.C_EXPORT && policy.kind != DeclarationPolicyId.GOBJECT_IMPORT) || syntax.is_c_import != (syntax.body == null)) {
				fail (policy.span,"CImport/CExport require one top-level C declaration with an exact import/export body contract");
				return null;
			}
			foreach (var entry in policy.entries) {
				if (entry.key.spelling () == "name" && !CForeignMetadata.portable_symbol (entry.decoded_value)) {
					fail (entry.value.span,"CImport/CExport name requires a portable C identifier");
					return null;
				}
				if (policy.kind == DeclarationPolicyId.C_EXPORT && entry.key.spelling () == "record_abi" && entry.decoded_value != "value-lp64") {
					fail (entry.value.span,"CExport record_abi requires value-lp64");
					return null;
				}
			}
		}
		if (declaring_type == null || !declaring_type.semantic_type.is_parameterized () && (specializing_method == null || specializing_method.arguments.closed ())) {
			lexical_types.remove_all ();
		}
		var type_parameters = new GenericArray<TypeParameterSymbol> ();
		if (syntax.type_parameters.length != 0 && specializing_method == null) {
			if (declaring_type != null) {
				fail (syntax.name.span,"GEN-1 supports only top-level generic functions; generic members are deferred");
				return null;
			}
			if (syntax.name.spelling () == "main") {
				fail (syntax.name.span,"main cannot be a generic function");
				return null;
			}
			if (syntax.is_c_import || syntax.is_c_export) {
				fail (syntax.name.span,"generic C ABI functions are unsupported");
				return null;
			}
			foreach (var token in syntax.type_parameters) {
				string parameter_name = token.spelling ();
				if (types.resolve (parameter_name) != null) {
					fail (token.span,"builtin type name '%s' is unavailable as a type parameter".printf (parameter_name));
					return null;
				}
				if (visible_nominal (token.span,parameter_name)) {
					fail (token.span,"type parameter '%s' cannot shadow an outer type in GEN-1".printf (parameter_name));
					return null;
				}
				if (lexical_types.contains (parameter_name)) {
					fail (token.span,"duplicate type parameter '%s'".printf (parameter_name));
					return null;
				}
				GenericCapabilityIdentity[] capabilities = null;
				foreach (var clause in syntax.where_clauses) {
					if (clause.type_parameter.spelling () != parameter_name) {
						continue;
					}
					foreach (var capability_token in clause.capabilities) {
						var capability = capability_names.resolve (capability_token.spelling ());
						if (capability == null) {
							fail (capability_token.span,"unknown generic capability '%s'; expected Eq, Ordered, Numeric, Bitwise, Shift or Ownable".printf (capability_token.spelling ()));
							return null;
						}
						capabilities += capability.identity;
					}
				}
				var parameter = new TypeParameterSymbol (token.span,type_parameters.length,new GenericCapabilitySet (capabilities));
				type_parameters.add (parameter);
				lexical_types.insert (parameter_name,parameter);
			}
		}
		var requirements = new GenericArray<GenericCapabilityRequirement> ();
		foreach (var clause in syntax.where_clauses) {
			if (specializing_method != null) {
				continue;
			}
			var parameter = lexical_types.lookup (clause.type_parameter.spelling ());
			if (parameter == null) {
				fail (clause.type_parameter.span,"unknown type parameter '%s' in where clause".printf (clause.type_parameter.spelling ()));
				return null;
			}
			if (parameter.capability_requirements.length != 0) {
				fail (clause.span,"duplicate where clause for type parameter '%s'".printf (parameter.name));
				return null;
			}
			foreach (var token in clause.capabilities) {
				var capability = capability_names.resolve (token.spelling ());
				foreach (var prior in parameter.capability_requirements) {
					if (prior.capability == capability) {
						fail (token.span,"duplicate capability '%s' for type parameter '%s'".printf (token.spelling (),parameter.name));
						return null;
					}
				}
				var requirement = new GenericCapabilityRequirement (parameter,capability,token.span);
				parameter.capability_requirements.add (requirement);
				requirements.add (requirement);
			}
		}
		foreach (var parameter in type_parameters) {
			if (parameter.transport_mode == GenericTransportMode.OWNABLE && parameter.capability_requirements.length != 1) {
				fail (parameter.span,"Ownable cannot combine with value capabilities on the same type parameter in GEN-OWN-1");
				return null;
			}
		}
		bool foreign = syntax.is_c_import;
		bool boundary = foreign || syntax.is_c_export;
		var bool_abi = c_bool_abi (syntax);
		if (!bool_abi.valid ()) {
			fail (syntax.foreign_policy.span,"bool_abi requires the explicit c99 copied boolean profile");
			return null;
		}
		if (boundary) {
			foreach (var parameter in syntax.parameters) {
				if (parameter.caller_information != null) {
					fail (parameter.caller_information.span,"caller information is unsupported on foreign or exported signatures");
					return null;
				}
			}
		}
		if (syntax is LifecycleDeclarationSyntax && !((LifecycleDeclarationSyntax) syntax).is_constructor) {
			foreach (var parameter in syntax.parameters) {
				if (parameter.caller_information != null) {
					fail (parameter.span,"caller information is unsupported on destructor parameters");
					return null;
				}
			}
		}
		string boundary_name = foreign ? "extern(C)" : "export(C)";
		if (boundary && syntax.foreign_policy == null && (syntax.abi_identifier == null || syntax.abi_identifier.spelling () != "C")) {
			if (syntax.abi_identifier == null) {
				fail (syntax.span,"foreign declaration lost its explicit C ABI identity");
				return null;
			}
			fail (syntax.abi_identifier.span,"unsupported foreign ABI '%s'; expected 'C'".printf (syntax.abi_identifier.spelling ()));
			return null;
		}
		string name = declaring_type == null? declaration_name(syntax.name) : syntax.name.spelling ();
		if (boundary && ForeignClassPolicy.reserved_symbol (foreign ? syntax.name.spelling () : c_export_name (syntax,name))) {
			fail (syntax.name.span,"compiler-private foreign adapter runtime symbol cannot be declared by source");
			return null;
		}
		if (boundary && AllocationPolicy.reserved_symbol (foreign ? syntax.name.spelling () : c_export_name (syntax,name))) {
			fail (syntax.name.span,"compiler-private allocation runtime symbol cannot be declared by source");
			return null;
		}
		if (boundary && RetainedContracts.reserved_symbol (foreign ? syntax.name.spelling () : c_export_name (syntax,name))) {
			fail (syntax.name.span,"compiler-private retained callback runtime symbol cannot be declared by source");
			return null;
		}
		if (declaring_type == null && function_names.contains (name)) {
			fail_duplicate (syntax.name.span,"duplicate function '%s'; overloading is not implemented".printf (name),function_names.lookup (name).name_span);
			return null;
		}
		bool value_export = c_value_export (syntax);
		if (value_export && syntax.parameters.length > 2) {
			fail (syntax.span,"value-lp64 supports at most two parameters");
			return null;
		}
		var metadata_entries = syntax.foreign_policy == null ? syntax.ccode : foreign ? syntax.foreign_policy.entries : null;
		if (metadata_entries != null && !value_export) {
			if (!foreign || declaring_type != null) {
				fail (metadata_entries[0].span,"callable CCode metadata requires an extern(C) import");
				return null;
			}
			string external_symbol = syntax.name.spelling ();
			SourceSpan? symbol_span = null;
			CForeignHeader[] headers = {};
			string gobject_carrier = "";
			var text_abi = CTextAbi.NONE;
			SourceSpan? text_span = null;
			var buffer_abi = CBufferAbi.NONE;
			SourceSpan? buffer_span = null;
			var record_abi = CRecordAbi.NONE;
			SourceSpan? record_span = null;
			var pointer_abi = CPointerAbi.NONE;
			string? callback = null;
			var callback_abi = CCallbackAbi.NONE;
			PcDeviceContract? device = null;
			foreach (var entry in metadata_entries) {
				switch (entry.key.spelling ()) {
				case "name": case "cname": external_symbol = entry.decoded_value;
					symbol_span = entry.value.span;
					break;
				case "header": case "cheader_filename": headers += new CForeignHeader (entry.decoded_value,entry.value.span);
					break;
				case "carrier": if (syntax.foreign_policy == null || syntax.foreign_policy.kind != DeclarationPolicyId.GOBJECT_IMPORT) {
						fail (entry.span,"carrier requires an explicit GObjectImport bridge");
						return null;
				}
					gobject_carrier = entry.decoded_value;
					break;
				case "text_abi": text_abi = CTextAbi.parse (entry.decoded_value);
					text_span = entry.value.span;
					break;
				case "buffer_abi": buffer_abi = CBufferAbi.parse (entry.decoded_value);
					buffer_span = entry.value.span;
					break;
				case "record_abi": record_abi = CRecordAbi.parse (entry.decoded_value);
					record_span = entry.value.span;
					break;
				case "bool_abi": break;
				case "pointer_abi": pointer_abi = CPointerAbi.parse (entry.decoded_value);
					break;
				case "callback": callback = resolve_name (entry.value.span,entry.decoded_value,false);
					break;
				case "callback_abi": callback_abi = CCallbackAbi.parse (entry.decoded_value);
					break;
				case "device": device = new PcDeviceContract (PcDeviceOperation.parse (entry.decoded_value));
					break;
					default: fail (entry.span,"unsupported callable CCode metadata");
					return null;
				}
			}
			var inputs = new GenericArray<ForeignParameterInput> ();
			foreach (var parameter in syntax.parameters) {
				inputs.add (new ForeignParameterInput (parameter.span,parameter.name.span,parameter.type_name.span,parameter.type_name.spelling (),parameter.owned_keyword != null ? PointerParameterContract.OWNED_TRANSFER : parameter.borrowed_keyword == null ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE));
			}
			var metadata = new CForeignMetadata (external_symbol,symbol_span,headers,null,text_abi,text_span,buffer_abi,buffer_span,record_abi,record_span,callback,callback_abi,device,pointer_abi,null,ComImportRole.NONE,syntax.foreign_policy != null && syntax.foreign_policy.kind == DeclarationPolicyId.GOBJECT_IMPORT ? DeclarationPolicyId.GOBJECT_IMPORT : DeclarationPolicyId.C_IMPORT,bool_abi,gobject_carrier);
			return collect_foreign_signature (new ForeignDeclarationInput (syntax.span,syntax.name.span,syntax.return_type.span,inputs,metadata,syntax.return_type.spelling (),syntax.owned_keyword != null));
		}
		element_obligations = new GenericSliceObligations ();
		collecting_enum_premises = true;
		foreach (var parameter in syntax.parameters) {
			var slice_pattern = parameter.type_name as SliceTypeSyntax;
			var element_parameter = slice_pattern == null ? null : lexical_types.lookup (slice_pattern.element_type.spelling ());
			if (element_parameter != null) {
				if (element_parameter.transport_mode != GenericTransportMode.PLAIN_COPY) {
					fail (parameter.span,"generic slices require plain-copy elements; Ownable elements are unsupported");
					return null;
				}
				element_obligations.require (element_parameter.semantic_type);
			}
		}
		var result_pattern = syntax.return_type as SliceTypeSyntax;
		var result_element = result_pattern == null ? null : lexical_types.lookup (result_pattern.element_type.spelling ());
		if (result_element != null && syntax.owned_keyword != null) {
			if (result_element.transport_mode != GenericTransportMode.PLAIN_COPY) {
				fail (syntax.return_type.span,"generic slices require plain-copy elements; Ownable elements are unsupported");
				return null;
			}
			element_obligations.require (result_element.semantic_type);
		}
		var constructor_class = declaring_type as ClassSymbol;
		bool contextual_initialization = constructor_class != null && constructor_class.allocation_policy != null && constructor_class.allocation_policy.checked_initialization ();
		ClassType? throws_type = null;
		if (syntax.throws_class != null) {
			throws_type = resolve_exception_type (syntax.throws_class);
			if (throws_type == null) {
				return null;
			}
			if (boundary || declaring_type is StructSymbol || syntax is LifecycleDeclarationSyntax && (!((LifecycleDeclarationSyntax) syntax).is_constructor || !contextual_initialization && !declared_foreign_member (syntax,declaring_type) && (!(declaring_type is ClassSymbol) || ((ClassSymbol) declaring_type).concurrency_policy == null || !((ClassSymbol) declaring_type).concurrency_policy.singleton))) {
				fail (syntax.throws_class.span,"throws requires a concrete native function, class method or bounded Singleton initializer");
				return null;
			}
		}
		var return_type = (syntax is LifecycleDeclarationSyntax) ? types.void_type : resolve_contract_type (syntax.return_type);
		if (return_type is CallbackType) {
			fail (syntax.span,"Callback is call-scoped and cannot be returned");
			return null;
		}
		bool owning_result = syntax.owned_keyword != null && !substituted_copy_type (syntax.return_type,return_type) || return_type is ClassType && ((ClassType) return_type).intrinsically_shared;
		if (return_type != null && return_type.is_scoped_allocator ()) {
			fail (syntax.return_type.span,"scoped context cannot escape its lexical backing loan through a result");
			return null;
		}
		if (return_type is ClassType && ((ClassType) return_type).is_interface) {
			fail (syntax.return_type.span,"interface values are call-scoped borrowed contracts; owning interface results are excluded");
			return null;
		}
		if (!check_generic_position (return_type,owning_result,false,syntax.span)) {
			return null;
		}
		if (return_type == null) {
			return null;
		}
		if (boundary && return_type is SharedHandleType) {
			fail (syntax.return_type.span,"Shared/Weak handles cannot cross a C boundary");
			return null;
		}
		if (return_type is EnumType && boundary) {
			fail (syntax.return_type.span,"enum boundaries require a concrete native callable; C and generic enum composition are deferred");
			return null;
		}
		if (return_type is StringType && boundary) {
			fail (syntax.return_type.span,"string results are unsupported at C boundaries");
			return null;
		}
		if (return_type is ClassType && (!owning_result || boundary)) {
			fail (syntax.return_type.span,syntax.is_async ? "async success requires copied values or owned arrays; Class task results are excluded" : "object-reference results are unsupported; result lifetime relationships are not expressible");
			return null;
		}
		if (return_type is SliceType && (return_type.is_text_slice () || !owning_result || boundary)) {
			fail (syntax.return_type.span,syntax.is_async ? "async success requires an owned array; borrowed slice task results are excluded" : "slice results are unsupported; result lifetime relationships are not expressible");
			return null;
		}
		if (return_type is ArrayType) {
			fail (syntax.return_type.span,"array results are unsupported; arrays are local storage only");
			return null;
		}
		if (owning_result && !(return_type is HandleType) && !(return_type is ClassType) && !(return_type is TypeParameterType) && !(return_type is SliceType) && !template_record (return_type)) {
			fail (syntax.owned_keyword.span,"'owned' result requires a nominal handle type; owned void* native boundaries are unsupported");
			return null;
		}
		if (syntax.is_c_export && return_type is HandleType) {
			fail (syntax.return_type.span,"export(C) of resource handle types is unsupported in RESOURCE-1");
			return null;
		}
		if (return_type.is_typed_pointer ()) {
			fail (syntax.return_type.span,syntax.is_async ? "async success requires a copied value or owned array; borrowed pointer results are excluded" : boundary ? (return_type.is_struct_pointer () ? "typed native struct pointers are not supported by the C ABI yet" : "typed data pointers are not supported by the C ABI yet") : "typed-pointer function results are unsupported; escaping pointers require return-lifetime contracts");
			return null;
		}
		if (return_type is ExactGenericClassType && !GenericClassTypes.general (return_type)) {
			fail (syntax.span,"generic bag results are outside the finite direct-member scope");
			return null;
		}
		if (return_type.is_struct_storage () && !check_struct_boundary (return_type,syntax.return_type.span,boundary && !value_export,"result")) {
			return null;
		}
		if (value_export && return_type.is_struct_storage () && !CPlainRecordTypes.value (return_type,copy_fields)) {
			fail (syntax.return_type.span,"value-lp64 requires 1..3 eightbyte numeric fields, or f32/f64; nested, packed and owning records are unsupported");
			return null;
		}
		if (boundary && !(value_export && return_type.is_struct_storage ()) && !require_c_scalar_capability (return_type,syntax.return_type.span)) {
			return null;
		}
		if (boundary && !(value_export && return_type.is_struct_storage ()) && !(bool_abi == CBoolAbi.C99 && return_type.kind == TypeKind.BOOL) && return_type != types.int_type && !(return_type is IntegerType && ((IntegerType) return_type).bit_width == 64) && return_type != types.void_type && return_type != types.raw_pointer_type && !(return_type is HandleType) && !(return_type is F64Type) && !(return_type is F32Type)) {
			fail (syntax.return_type.span,boundary_name + " result type must be 'int', 'void*' or 'void'; foreign bool is unsupported");
			return null;
		}
		if (syntax.is_async && GenericClassTypes.general (return_type)) {
			fail (syntax.span,"generic Class owner boundaries currently require synchronous native code");
			return null;
		}
		var parameters = new GenericArray<ParameterSymbol> ();
		var parameter_names = new HashTable<string,ParameterSymbol> (str_hash,str_equal);
		for (int i = 0; i < syntax.parameters.length; i++) {
			var parameter = syntax.parameters[i];
			var generic_parameter = lexical_types.lookup (parameter.type_name.spelling ());
			SemanticType? nominal_parameter = named_types.lookup (type_key (parameter.type_name));
			if (parameter.type_name is GenericTypeApplicationSyntax) {
				if (((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "ContextBytes") {
					nominal_parameter = resolve_type (parameter.type_name);
					if (nominal_parameter == null) {
						return null;
					}
				}
				var record = generic_struct_names.lookup (type_key (parameter.type_name));
				if (record != null && record.owning_storage) {
					nominal_parameter = resolve_type (parameter.type_name);
					if (nominal_parameter == null) {
						return null;
					}
				}
			}
			if (parameter.type_name is NonNullTypeSyntax || parameter.type_name is SharedTypeSyntax || parameter.type_name is GenericTypeApplicationSyntax && ((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "Callback") {
				nominal_parameter = resolve_contract_type (parameter.type_name);
				if (nominal_parameter == null) {
					return null;
				}
			}
			if ((specializing_class != null && specializing_class.generic_instance != null) || (parameter.type_name is GenericTypeApplicationSyntax && (generic_class_names.contains (type_key (parameter.type_name)) || ((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "Shared" || ((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "Weak" || (((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "ActorSender" || ((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "Thread" || ((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "Closure" || ((GenericTypeApplicationSyntax) parameter.type_name).identifier.spelling () == "CheckedClosure")))) {
				nominal_parameter = resolve_type (parameter.type_name);
				if (nominal_parameter == null) {
					return null;
				}
			}
			if (nominal_parameter is TypeParameterType) {
				generic_parameter = null;
				foreach (var candidate in lexical_types.get_values ()) {
					if (candidate.semantic_type == nominal_parameter) {
						generic_parameter = candidate;
						break;
					}
				}
			}
			bool copy_substitution = substituted_copy_type (parameter.type_name,nominal_parameter);
			bool owning_parameter = parameter.owned_keyword != null && !copy_substitution || parameter.borrowed_keyword == null && nominal_parameter is ClassType && ((ClassType) nominal_parameter).intrinsically_shared;
			if (!check_generic_position (generic_parameter == null ? null : generic_parameter.semantic_type,owning_parameter,parameter.borrowed_keyword != null,parameter.span)) {
				return null;
			}
			if (nominal_parameter is ClassType) {
				if (boundary) {
					fail (parameter.type_name.span,"object-reference parameters are unsupported at C boundaries");
					return null;
				}
				if (((ClassType) nominal_parameter).is_interface && owning_parameter) {
					fail (parameter.span,"interface parameters are borrowed contracts and cannot consume an owner");
					return null;
				}
			}
			if (parameter.borrowed_keyword != null && !copy_substitution && generic_parameter == null && !(parameter.type_name is SliceTypeSyntax) && !(nominal_parameter is ContextBytesType) && parameter.type_name.spelling () != "void*" && parameter.type_name.spelling () != "string" && !(nominal_parameter is HandleType) && !(nominal_parameter is ClassType) && !(nominal_parameter is CallbackType) && !(!boundary && nominal_parameter != null && nominal_parameter.is_struct_storage ()) && !(!boundary && parameter.type_name.spelling ().has_suffix ("*"))) {
				fail (parameter.span,"'borrowed' parameter requires exactly 'void*'");
				return null;
			}
			if (parameter.borrowed_keyword != null && syntax.is_c_export) {
				fail (parameter.span,"borrowed parameters are unsupported on export(C) functions");
				return null;
			}
			if (owning_parameter && (boundary || (!(nominal_parameter is HandleType) && !(nominal_parameter is ClassType) && !(nominal_parameter is ContextBytesType) && generic_parameter == null && !(parameter.type_name is SliceTypeSyntax) && !template_record (nominal_parameter)))) {
				fail (parameter.span,"'owned' parameter requires a native function and an exact nominal handle type; C ownership boundaries and owned void* are unsupported");
				return null;
			}
			var parameter_type = resolve_contract_type (parameter.type_name);
			if (parameter_type != null && parameter_type.is_scoped_allocator () && (owning_parameter || syntax.is_async)) {
				fail (parameter.span,"scoped context parameters require a synchronous nonescaping borrow");
				return null;
			}
			if (parameter_type is CallbackType && (boundary || parameter.borrowed_keyword == null || owning_parameter || syntax.is_async)) {
				fail (parameter.span,"Callback requires an explicit borrowed parameter in synchronous native code");
				return null;
			}
			if (parameter.borrowed_keyword != null && parameter_type is TypedPointerType && !CPlainRecordTypes.pointer (parameter_type,copy_fields) && !(declared_foreign_member (syntax,declaring_type) && ForeignApiTypes.scalar_pointee (parameter_type) != null)) {
				fail (parameter.span,"borrowed typed pointer requires a concrete scalar POD Struct* context");
				return null;
			}
			if (parameter_type is ExactGenericClassType && !GenericClassTypes.general (parameter_type) && owning_parameter) {
				fail (parameter.span,"generic bag helper parameters are call-scoped borrowed only");
				return null;
			}
			if (parameter_type != null && parameter_type.is_text_slice () && owning_parameter) {
				fail (parameter.span,"owned string slices are unsupported; text descriptors require a deep borrowed view");
				return null;
			}
			if (syntax.is_async && parameter_type is SharedHandleType) {
				fail (parameter.type_name.span,"Shared/Weak transfer requires a synchronous single-threaded callable");
				return null;
			}
			if (syntax.is_async && parameter_type is ClosureHandleType && !AsyncClosureCaptures.valid (parameter_type,
				owning_parameter ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE,false)) {
				fail (parameter.type_name.span,"async Closure capture requires one owned non-actor, non-threaded handle");
				return null;
			}
			if (boundary && parameter_type is SharedHandleType) {
				fail (parameter.type_name.span,"Shared/Weak handles cannot cross a C boundary");
				return null;
			}
			if (parameter_type is EnumType && boundary) {
				fail (parameter.type_name.span,"enum boundaries require a concrete native callable; C and generic enum composition are deferred");
				return null;
			}
			if (parameter_type is StringType && boundary) {
				fail (parameter.type_name.span,"string parameters are unsupported at C boundaries");
				return null;
			}
			if (parameter_type is SliceType && boundary) {
				fail (parameter.type_name.span,boundary ? "slice parameters are unsupported at C boundaries" : "native slice parameters require explicit 'borrowed'");
				return null;
			}
			if (parameter_type is ArrayType) {
				fail (parameter.type_name.span,"array parameters are unsupported; arrays are local storage only");
				return null;
			}
			if (parameter_type == null) {
				return null;
			}
			if (parameter_type == types.void_type) {
				fail (parameter.type_name.span,"parameter type cannot be 'void'");
				return null;
			}
			if (parameter_type.is_struct_storage () && !check_struct_boundary (parameter_type,parameter.type_name.span,boundary && !value_export,"parameter")) {
				return null;
			}
			if (syntax.is_c_export && parameter_type is HandleType) {
				fail (parameter.type_name.span,"export(C) of resource handle types is unsupported in RESOURCE-1");
				return null;
			}
			if (boundary && parameter_type.is_typed_pointer ()) {
				fail (parameter.type_name.span,parameter_type.is_struct_pointer () ? "typed native struct pointers are not supported by the C ABI yet" : "typed data pointers are not supported by the C ABI yet");
				return null;
			}
			if (value_export && parameter_type.is_struct_storage () && !CPlainRecordTypes.value (parameter_type,copy_fields)) {
				fail (parameter.type_name.span,"value-lp64 requires 1..3 eightbyte numeric fields, or f32/f64; nested, packed and owning records are unsupported");
				return null;
			}
			if (boundary && !(value_export && parameter_type.is_struct_storage ()) && !require_c_scalar_capability (parameter_type,parameter.type_name.span)) {
				return null;
			}
			if (boundary && !(value_export && parameter_type.is_struct_storage ()) && !(bool_abi == CBoolAbi.C99 && parameter_type.kind == TypeKind.BOOL) && parameter_type != types.int_type && !(parameter_type is IntegerType && ((IntegerType) parameter_type).bit_width == 64) && parameter_type != types.raw_pointer_type && !(parameter_type is HandleType) && !(parameter_type is F64Type) && !(parameter_type is F32Type)) {
				fail (parameter.type_name.span,boundary_name + " parameter type must be 'int' or 'void*'; foreign bool is unsupported");
				return null;
			}
			string parameter_name = parameter.name.spelling ();
			if (parameter_names.contains (parameter_name)) {
				fail (parameter.name.span,"duplicate parameter '%s'".printf (parameter_name));
				return null;
			}
			// Native defaults are exact semantic domains, never physical pointer
			// shape. Foreign metadata and unresolved generic transport stay explicit.
			bool record_borrow = !boundary && parameter.borrowed_keyword != null && parameter_type.is_struct_storage () && struct_value_mode (parameter_type) == StructValueMode.MOVE_VALUE;
			bool borrowed = parameter.borrowed_keyword != null && !copy_substitution && !parameter_type.is_struct_storage () || record_borrow || (!boundary && (parameter_type is StringType || parameter_type is HandleType || parameter_type is ClassType || parameter_type is SliceType));
			var symbol = new ParameterSymbol (parameter.span,parameter.name.span,parameter_type,i,owning_parameter && !template_record (parameter_type) ? PointerParameterContract.OWNED_TRANSFER : borrowed ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED);
			symbol.substituted_copy = parameter.owned_keyword != null && copy_substitution;
			if (parameter.type_name is NonNullTypeSyntax) {
				symbol.mark_nonnull ();
			}
			if (!collect_caller_information (parameter,symbol,parameters)) {
				return null;
			}
			if (parameter_type.is_struct_storage ()) {
				symbol.struct_value_contract = new StructValueContract (parameter_type,record_borrow ? StructValueMode.BORROW_VALUE : struct_value_mode (parameter_type));
			}
			parameters.add (symbol);
			parameter_names.insert (symbol.name,symbol);
		}
		if (value_export) {
			bool has_value_record = return_type.is_struct_storage ();
			foreach (var parameter in parameters) {
				if (parameter.semantic_type.is_struct_storage ()) {
					has_value_record = true;
				}
			}
			if (!has_value_record) {
				fail (syntax.span,"value-lp64 requires a record parameter or result");
				return null;
			}
		}
		foreach (var parameter in parameters) {
			if (parameter.semantic_type is ExactGenericClassType && !GenericClassTypes.general (parameter.semantic_type) && (type_parameters.length != 0 || syntax.is_async || throws_type != null || (return_type.kind != TypeKind.VOID && !GenericBorrowTypes.scalar (return_type)))) {
				fail (syntax.span,"generic bag helpers require concrete synchronous nonthrowing copied scalar/void boundaries");
				return null;
			}
		}
		int generic_borrows = 0;
		foreach (var parameter in parameters) {
			if (parameter.semantic_type is TypeParameterType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
				generic_borrows++;
			}
		}
		if (generic_borrows != 0) {
			if (generic_borrows != 1 || syntax.is_async || throws_type != null || owning_result || (return_type.kind != TypeKind.VOID && !GenericBorrowTypes.scalar (return_type))) {
				fail (syntax.span,"generic borrowing requires one borrowed T, synchronous nonthrowing native helpers and a copied scalar or void result");
				return null;
			}
			foreach (var parameter in parameters) {
				if (parameter.semantic_type is TypeParameterType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
					continue;
				}
				if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(GenericBorrowTypes.scalar (parameter.semantic_type) || parameter.semantic_type is FunctionValueType)) {
					fail (parameter.span,"generic borrow helpers permit only copied scalar adjacent parameters");
					return null;
				}
			}
		}
		if (syntax.is_c_export) {
			bool has_bool = return_type.kind == TypeKind.BOOL;
			foreach (var parameter in parameters) {
				has_bool |= parameter.semantic_type.kind == TypeKind.BOOL;
			}
			if (has_bool != (bool_abi == CBoolAbi.C99) || bool_abi == CBoolAbi.C99 && value_export) {
				fail (syntax.span,"c99 requires copied bool channels without record transport");
				return null;
			}
		}
		uint floating_policy = 0;
		if (syntax.floating_point != null) {
			if (boundary || syntax.is_async || throws_type != null || declaring_type != null) {
				fail (syntax.span,"FloatingPoint requires a synchronous nonthrowing native free function");
				return null;
			}
			bool strict = false;
			bool has_floating = FloatingPointPolicy.floating (return_type);
			foreach (var parameter in parameters) {
				if (FloatingPointPolicy.floating (parameter.semantic_type)) {
					has_floating = true;
				}
			}
			foreach (var entry in syntax.floating_point) {
				string key = entry.key.spelling ();
				string setting = entry.decoded_value;
				uint permission = FloatingPointPolicy.option (key);
				if ((permission == 0 && key != "strict") || (setting != "on" && setting != "off")) {
					fail (entry.span,"unknown FloatingPoint option or value; expected supported key and on/off");
					return null;
				}
				if (key == "strict") {
					strict = setting == "on";
				} else if (setting == "on") {
					floating_policy |= permission;
				}
			}
			if (!has_floating || (strict && floating_policy != 0)) {
				fail (syntax.span,"FloatingPoint requires a floating signature and cannot combine strict with relaxations");
				return null;
			}
			foreach (var entry in syntax.floating_point) {
				if (entry.decoded_value == "off" && (floating_policy & FloatingPointPolicy.option (entry.key.spelling ())) != 0) {
					fail (entry.span,"conflicting FloatingPoint permissions");
					return null;
				}
			}
		}
		if (foreign) {
			var metadata = new CForeignMetadata (syntax.name.spelling (),null,null,!owning_result ? null : new CForeignOwnedResultContract (handle_types.lookup (return_type).cleanup));
			return new CFunctionSymbol (syntax.span,syntax.name.span,return_type,parameters,metadata,name);
		}
		if (syntax is LifecycleDeclarationSyntax) {
			if (throws_type != null && (!((LifecycleDeclarationSyntax) syntax).is_constructor || !contextual_initialization && !declared_foreign_member (syntax,declaring_type) && (((ClassSymbol) declaring_type).concurrency_policy == null || !((ClassSymbol) declaring_type).concurrency_policy.singleton))) {
				fail (syntax.span,"escaping constructor throws is qualified only for a process Singleton");
				return null;
			}
			var lifecycle = ((LifecycleDeclarationSyntax) syntax).is_constructor ? (DirectCallableSymbol) new ConstructorSymbol (syntax.span,syntax.name.span,(ClassSymbol) declaring_type,types.void_type,parameters,member_ordinal) : new DestructorSymbol (syntax.span,syntax.name.span,(ClassSymbol) declaring_type,types.void_type,member_ordinal);
			((FunctionSymbol) lifecycle).throws_type = throws_type;
			diagnostic = CallerInformation.validate (lifecycle,types);
			return diagnostic == null ? lifecycle : null;
		}
		var result_contract = (return_type is StringType) ? ResultOwnershipContract.STATIC_TEXT : !owning_result || template_record (return_type) ? ResultOwnershipContract.UNMANAGED : ResultOwnershipContract.OWNED_TRANSFER;
		var result_cleanup = !owning_result || (return_type is ClassType) || (return_type is TypeParameterType) || (return_type is SliceType) || template_record (return_type) ? null : handle_types.lookup (return_type).cleanup;
		FunctionSymbol function = declaring_type != null ? (FunctionSymbol) new MethodSymbol (syntax.span,syntax.name.span,declaring_type,return_type,parameters,declaring_type.methods.length,member_ordinal,result_contract,result_cleanup,specializing_method == null ? null : specializing_method.name) : type_parameters.length != 0 ? (FunctionSymbol) new GenericFunctionSymbol (syntax.span,syntax.name.span,return_type,parameters,type_parameters,result_contract,result_cleanup,name) : new FunctionSymbol (syntax.span,syntax.name.span,return_type,parameters,result_contract,result_cleanup,CallableDomain.NATIVE,name);
		if (syntax.return_type is NonNullTypeSyntax) {
			function.mark_nonnull_result ();
		}
		function.throws_type = throws_type;
		function.utf8_factory = syntax.utf8_factory;
		function.bind_floating_policy (floating_policy);
		function.dispatch_kind = (ClassDispatchKind) syntax.dispatch;
		if (return_type.is_struct_storage ()) {
			function.struct_result_contract = new StructValueContract (return_type,struct_value_mode (return_type));
		}
		collecting_enum_premises = false;
		if (function is GenericFunctionSymbol) {
			foreach (var parameter in type_parameters) {
				if (element_obligations.contains (parameter.semantic_type)) {
					((GenericFunctionSymbol) function).element_obligations.require (parameter.semantic_type);
				}
			}
		}
		if (function is GenericFunctionSymbol) {
			foreach (var requirement in requirements) {
				((GenericFunctionSymbol) function).capability_requirements.add (requirement);
			}
		}
		if (return_type is ClassType) {
			function.result_class = (ClassSymbol) instance_for (return_type);
			function.result_storage = new ResultObjectStorageSymbol (function.result_class);
		}
		diagnostic = CallerInformation.validate (function,types,syntax.is_c_export);
		return diagnostic == null ? function : null;
	}

	private CheckedBlockStatement? check_block(BlockStatementSyntax syntax,FunctionSymbol function,ValueScope? parent,GenericArray<LocalSymbol> locals) {
		var region = new LexicalRegion (parent == null ? null : parent.region,next_region_ordinal++);
		var values = new ValueScope (parent ?? constant_scope,region);
		if (parent == null) {
			checking_function = function;
			if (function.implicit_receiver != null) {
				values.insert ("this",function.implicit_receiver);
			}
			foreach (var parameter in function.parameters) {
				if (constant_scope.lookup (parameter.name) != null) {
					fail (parameter.name_span,"parameter '%s' conflicts with a visible constant".printf (parameter.name));
					return null;
				}
				parameter.lexical_region = region;
				if (parameter.struct_value_contract != null || parameter.semantic_type is EnumType) {
					var local = new LocalSymbol (parameter.span,parameter.name_span,parameter.semantic_type,locals.length,region,null,parameter);
					if (parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.MOVE_VALUE) {
						if (!record_context (parameter.span)) {
							return null;
						}
						local.record_owner = owning_record_field (local.semantic_type);
						record_all_events (GenericOwnershipEventKind.ACQUIRE,local,parameter.span);
					}
					locals.add (local);
					values.insert (parameter.name,local);
					continue;
				}
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					var owner = new LocalSymbol (parameter.span,parameter.name_span,parameter.semantic_type,locals.length,region,(parameter.semantic_type is ClassType || parameter.semantic_type is TypeParameterType || parameter.semantic_type is SliceType) ? null : handle_types.lookup (parameter.semantic_type).cleanup,parameter,instance_for (parameter.semantic_type) as ClassSymbol,parameter.semantic_type is SliceType);
					owner.heap_object = parameter.heap_object;
					locals.add (owner);
					values.insert (parameter.name,owner);
				} else {
					values.insert (parameter.name,parameter);
				}
			}
		}
		var statements = new GenericArray<CheckedStatement> ();
		if (parent == null && function is ConstructorSymbol) {
			var constructor = (ConstructorSymbol) function;
			var owner = constructor.declaring_class;
			var initializer = constructor_initializers.lookup (constructor);
			if (owner.parent_class == null) {
				if (initializer.base_arguments != null) {
					fail (initializer.span,"base initializer requires an exact parent class");
					return null;
				}
			} else {
				var target = owner.parent_class.constructor;
				if (target == null || initializer.base_arguments == null || initializer.base_arguments.length != target.parameters.length) {
					fail (initializer.span,"derived init requires one explicit base initializer with all exact parent init arguments");
					return null;
				}
				var arguments = new GenericArray<CheckedExpression> ();
				for (int p = 0; p < target.parameters.length; p++) {
					var parameter = target.parameters[p];
					var argument = check_argument (initializer.base_arguments[p],values,"base init",parameter,parameter.semantic_type,p);
					if (argument == null) {
						return null;
					}
					if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER) {
						argument = upcast_class (argument,parameter.semantic_type);
					}
					if (argument.semantic_type != parameter.semantic_type) {
						fail (argument.span,"base initializer argument requires the exact parameter type");
						return null;
					}
					arguments.add (argument);
				}
				if (!commit_record_arguments (arguments)) {
					return null;
				}
				statements.add (new CheckedBaseLifecycleCall (initializer.span,target,arguments,upcast_class (new CheckedThisExpression (initializer.span,constructor.receiver),target.receiver.semantic_type)));
			}
		}

		for (int i = 0; i < syntax.statements.length; i++) {
			var statement = check_statement (syntax.statements[i],function,values,locals);
			if (statement == null) {
				return null;
			}
			statements.add (statement);
		}
		if (generic_owner_flow != null) {
			foreach (var local in locals) {
				if (local.is_generic_owner && local.incoming_parameter == null && local.lexical_region == region) {
					generic_owner_flow.owner_event (GenericOwnershipEventKind.RETIRE,local,local.name,syntax.span);
				}
			}
		}
		return new CheckedBlockStatement (syntax.span,statements,region);
	}

	private CheckedStatement? check_statement(StatementSyntax syntax,FunctionSymbol function,ValueScope values,GenericArray<LocalSymbol> locals) {
		var result = check_statement_body (syntax,function,values,locals);
		if (result != null && syntax is LocalDeclarationSyntax && ((LocalDeclarationSyntax) syntax).type_name is NonNullTypeSyntax) {
			var local = (result is CheckedLocalDeclaration) ? ((CheckedLocalDeclaration) result).local : (result is CheckedObjectConstruction) ? ((CheckedObjectConstruction) result).local : null;
			if (local == null) {
				fail (syntax.span,"nonnull local lost its exact declaration slot");
				return null;
			}
			local.mark_nonnull ();
			if (!nonnull_definitions.find (function)) {
				nonnull_definitions.add (function);
			}
		}
		if (generic_owner_flow != null && result != null) {
			var enum_store = result as CheckedEnumStore;
			if (enum_store != null && EnumValueAuthority.owns (enum_store.producer.definition,enum_definition_for)) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE,enum_store.destination,enum_store.destination.name,syntax.span);
			}
			if (result is CheckedStore) {
				read_buffer_place (((CheckedStore) result).target);
			}
			if (result is CheckedStructCopy) {
				read_buffer_place (((CheckedStructCopy) result).destination);
			}
			if (result is CheckedStructResultStore) {
				read_buffer_place (((CheckedStructResultStore) result).destination);
			}
			var acquired = result as CheckedOwnedLocalDeclaration;
			if (acquired != null && acquired.local.is_buffer_owner) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE,acquired.local,acquired.local.name,syntax.span);
			}
			var released = result as CheckedOwnershipRelease;
			if (released != null && released.owner.is_buffer_owner) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.RELEASE,released.owner,released.owner.name,syntax.span);
			}
			var replaced = result as CheckedOwnedBufferReplace;
			if (replaced != null) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE,replaced.owner,replaced.owner.name,syntax.span);
			}
			if (syntax is ReturnStatementSyntax) {
				foreach (var local in locals) {
					if (local.is_generic_owner && local.incoming_parameter == null && local.lexical_region.outlives (values.region)) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.RETIRE,local,local.name,syntax.span);
					}
				}
				generic_owner_flow.jump (GenericOwnershipEventKind.RETURN,syntax.span);
			}
			if (result is CheckedBreak || result is CheckedContinue) {
				generic_owner_flow.jump ((result is CheckedBreak) ? GenericOwnershipEventKind.BREAK : GenericOwnershipEventKind.CONTINUE,syntax.span,(result is CheckedBreak) ? ((CheckedBreak) result).target : ((CheckedContinue) result).target);
			}
		}
		return result;
	}

	private EnumDefinition? enum_definition_for(EnumType type) {
		var prior = enum_definitions.lookup (type);
		if (prior != null) {
			return prior;
		}
		var origin = type.origin;
		var source = origin == null ? null : enum_definitions.lookup (origin);
		if (source == null) {
			return null;
		}
		if (!GenericResourceLimits.admits_type (type)) {
			fail (source.span,"generic materialization limit exceeded: type-expression depth %d while instantiating '%s'".printf (GenericResourceLimits.TYPE_DEPTH,origin.display_name ()));
			return null;
		}
		if (!type.is_parameterized () && closed_enum_count++ >= GenericResourceLimits.CLOSED_INSTANCES) {
			fail (source.span,"generic enum materialization limit exceeded: at most %u closed instances while requesting '%s'".printf (GenericResourceLimits.CLOSED_INSTANCES,type.display_name ()));
			return null;
		}
		var substitution = new TypeSubstitution ((element) => types.slice_of (element),types.substitute_function,substitute_class,substitute_closure);
		for (uint i = 0; i < origin.argument_count; i++) {
			substitution.bind ((TypeParameterType) origin.argument (i),type.argument (i));
		}
		var result = source.application (type,substitution);
		enum_definitions.insert (type,result);
		ordered_enums.add (result);
		return result;
	}

	private EnumType? resolve_enum_application(EnumType origin,GenericArray<TypeNameSyntax> syntax,SourceSpan span) {
		if (syntax.length != origin.argument_count) {
			fail (span,"enum '%s' requires exactly %u explicit type arguments".printf (origin.display_name (),origin.argument_count));
			return null;
		}
		if (syntax.length == 0) {
			return origin;
		}
		var arguments = new GenericArray<SemanticType> ();
		for (uint i = 0; i < syntax.length; i++) {
			var argument = resolve_type (syntax[i]);
			if (argument == null) {
				return null;
			}
			if (!GenericArgumentTypes.plain_copy (argument,copy_fields,copy_premise)) {
				fail (syntax[i].span,"enum type arguments require exact plain-copy value premises; owning enums and slices are unsupported");
				return null;
			}
			if (origin.requires_array_element (i)) {
				var parameter = argument as TypeParameterType;
				if (parameter != null && collecting_enum_premises) {
					element_obligations.require (parameter);
				}
				if (!GenericSliceObligations.accepts (argument,copy_fields,element_premise)) {
					fail (syntax[i].span,"enum owned-array argument requires its declared element-storage premise");
					return null;
				}
			}
			arguments.add (argument);
		}
		var type = origin.application (arguments);
		enum_definition_for (type);
		return diagnostic == null ? type : null;
	}

	private bool valid_enum_scalar_owner(EnumField field) {
		if (field.owns_child) {
			var owner = instance_for (field.semantic_type) as ClassSymbol;
			return owner != null && !owner.polymorphic && !((ClassType) owner.semantic_type).is_interface;
		}
		var resource = handle_types.lookup (field.semantic_type);
		return resource != null && resource.cleanup == field.owned_cleanup;
	}

	private bool collect_enums(SyntaxProgram syntax) {
		foreach (var declaration in syntax.enums) {
			var type = (EnumType) find_named (declaration.name);
			lexical_types.remove_all ();
			element_obligations = new GenericSliceObligations ();
			foreach (var parameter in enum_parameters.lookup (type)) {
				lexical_types.insert (parameter.name,parameter);
				if (type.requires_array_element ((uint) parameter.ordinal)) {
					element_obligations.require (parameter.semantic_type);
				}
			}
			var variants = new GenericArray<EnumVariant> ();
			var names = new HashTable<string,bool> (str_hash,str_equal);
			foreach (var variant in declaration.variants) {
				string name = variant.name.spelling ();
				if (names.contains (name)) {
					fail (variant.name.span,"duplicate enum variant '%s.%s'".printf (type.display_name (),name));
					return false;
				}
				names.insert (name,true);
				var identity = new EnumVariantIdentity (type.identity,name,variants.length);
				var fields = new GenericArray<EnumField> ();
				var field_names = new HashTable<string,bool> (str_hash,str_equal);
				foreach (var field in variant.fields) {
					string field_name = field.name.spelling ();
					if (field_names.contains (field_name)) {
						fail (field.name.span,"duplicate enum payload field '%s'".printf (field_name));
						return false;
					}
					field_names.insert (field_name,true);
					var field_type = resolve_type (field.type_name);
					if (field_type == null) {
						return false;
					}
					bool owned = field.owned_keyword != null;
					var resource = handle_types.lookup (field_type);
					if (resource != null && field_type.get_type () != typeof (HandleType)) {
						resource = null;
					}
					if (owned && !(field_type is SliceType) && !(field_type is ClassType) && resource == null) {
						fail (field.span,"owned enum field requires an exact Resource, native Class or supported runtime array");
						return false;
					}
					fields.add (new EnumField (new EnumFieldIdentity (identity,field_name,fields.length),field_type,field.span,owned && field_type is SliceType,owned && resource != null ? resource.cleanup : null,owned && field_type is ClassType,field_type is StructType && owning_record_field (field_type) != null));
				}
				variants.add (new EnumVariant (identity,variant.span,fields));
			}
			var definition = new EnumDefinition (type,declaration.span,variants,(IntegerType) types.int_type);
			enum_definitions.insert (type,definition);
			ordered_enums.add (definition);
		}
		lexical_types.remove_all ();
		element_obligations = new GenericSliceObligations ();
		for (int i = 0; i < ordered_enums.length; i++) {
			var definition = ordered_enums[i];
			try {
				EnumValueAuthority.verify (definition,enum_definition_for,copy_fields,definition.semantic_type.declares_copy,definition.semantic_type.declares_element,valid_enum_scalar_owner);
			} catch (EnumContractError error) {
				fail (definition.span,error.message);
				return false;
			}
		}
		return true;
	}

	private EnumType? enum_context_type(ExpressionSyntax syntax,ValueScope values) {
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		if (syntax is NameExpressionSyntax) {
			var symbol = values.lookup (((NameExpressionSyntax) syntax).identifier.spelling ()) as LocalSymbol;
			return symbol == null ? null : symbol.semantic_type as EnumType;
		}
		var call = syntax as CallExpressionSyntax;
		if (call == null) {
			return null;
		}
		if (async_operation_call (call,values) && call.identifier.spelling () == "run") {
			return async_operation_runtime (call,values).status_type;
		}
		if (call.receiver != null && values.lookup (call.receiver.spelling ()) == null && !module_names.contains (call.receiver.spelling ()) && find_named (call.receiver) is EnumType) {
			return resolve_enum_application ((EnumType) find_named (call.receiver),call.qualifier_arguments,call.span);
		}
		if (call.receiver == null && call.receiver_place == null) {
			var target = find_function (call.identifier);
			return target == null ? null : target.return_type as EnumType;
		}
		if (call.receiver != null && values.lookup (call.receiver.spelling ()) == null && module_names.contains (call.receiver.spelling ())) {
			var target = function_names.lookup (resolve_name (call.identifier.span,call.receiver.spelling () + "." + call.identifier.spelling (),false));
			return target == null ? null : target.return_type as EnumType;
		}
		SemanticType? receiver_type = null;
		if (call.receiver != null) {
			var local = values.lookup (call.receiver.spelling ()) as LocalSymbol;
			receiver_type = local == null ? null : local.semantic_type;
		}
		if (receiver_type is TypedPointerType) {
			receiver_type = ((TypedPointerType) receiver_type).pointee;
		}
		var owner = receiver_type == null ? null : instance_for (receiver_type);
		var method = owner == null ? null : owner.find_method (call.identifier.spelling ());
		return method == null ? null : method.return_type as EnumType;
	}

	private CheckedEnumProducer? check_enum_producer(ExpressionSyntax syntax,ValueScope values,EnumType? expected = null,bool inspect = false,bool reserve = false) {
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		CheckedEnumProducer? producer = null;
		if (syntax is NameExpressionSyntax || syntax is MoveExpressionSyntax) {
			var name = (syntax is MoveExpressionSyntax) ? ((MoveExpressionSyntax) syntax).source : ((NameExpressionSyntax) syntax).identifier;
			var source = values.lookup (name.spelling ()) as LocalSymbol;
			if (source == null || !(source.semantic_type is EnumType)) {
				fail (syntax.span,"enum value requires an initialized exact enum local or value parameter");
				return null;
			}
			var definition = enum_definition_for ((EnumType) source.semantic_type);
			bool owning = EnumValueAuthority.owns (definition,enum_definition_for);
			var mode = (syntax is MoveExpressionSyntax) ? EnumUse.MOVE : inspect && owning ? EnumUse.INSPECT : EnumUse.COPY;
			if (owning && mode == EnumUse.COPY) {
				fail (syntax.span,"move-only enum transfer requires explicit 'move'; match(name) permits inspection");
				return null;
			}
			if (!owning && mode == EnumUse.MOVE) {
				fail (syntax.span,"move requires a move-only enum value");
				return null;
			}
			if (mode == EnumUse.MOVE && (source.enum_inspection_root != null || enum_inspections.find (source))) {
				fail (syntax.span,"enum inspection prevents ownership extraction or invalidation");
				return null;
			}
			if (owning && generic_owner_flow != null) {
				if (mode == EnumUse.MOVE && enum_reservations.find (source)) {
					fail (syntax.span,"enum source is reserved by an unfinished consumer");
					return null;
				}
				if (mode == EnumUse.MOVE && reserve) {
					enum_reservations.add (source);
					generic_owner_flow.owner_event (GenericOwnershipEventKind.READ,source,source.name,syntax.span);
				} else {
					generic_owner_flow.owner_event (mode == EnumUse.MOVE ? GenericOwnershipEventKind.MOVE : GenericOwnershipEventKind.READ,source,source.name,syntax.span);
				}
			}
			producer = new CheckedEnumSnapshot (syntax.span,definition,source,mode);
		} else if (syntax is AwaitExpressionSyntax) {
			producer = check_await_producer ((AwaitExpressionSyntax) syntax,values) as CheckedEnumProducer;
		} else if (syntax is CallExpressionSyntax) {
			producer = check_value_call ((CallExpressionSyntax) syntax,values,false,true) as CheckedEnumProducer;
			if (producer == null && diagnostic == null) {
				fail (syntax.span,"expected an exact enum constructor or native enum result");
			}
		} else {
			fail (syntax.span,"enum value requires explicit construction, snapshot or native call result; owning matching belongs to ENUM-OWN-1");
			return null;
		}
		if (producer != null && expected != null && producer.semantic_type != expected) {
			fail (syntax.span,"expected exact enum '%s', found '%s'".printf (expected.display_name (),producer.semantic_type.display_name ()));
			return null;
		}
		return producer;
	}

	private CheckedEnumConstruct? check_enum_constructor(CallExpressionSyntax call,ValueScope values,EnumDefinition definition) {
		if (call.type_arguments.length != 0) {
			fail (call.span,"enum type arguments precede the variant qualifier");
			return null;
		}
		var variant = definition.find_variant (call.identifier.spelling ());
		if (variant == null) {
			fail (call.identifier.span,"unknown variant '%s' in enum '%s'".printf (call.identifier.spelling (),definition.semantic_type.display_name ()));
			return null;
		}
		if (call.arguments.length != variant.field_count) {
			fail (call.span,"enum constructor '%s.%s' requires exactly %u payload arguments, found %u".printf (definition.semantic_type.display_name (),variant.identity.name,variant.field_count,call.arguments.length));
			return null;
		}
		uint reservation_depth = enum_reservations.length;
		var fields = new GenericArray<CheckedEnumFieldValue> ();
		for (uint i = 0; i < variant.field_count; i++) {
			var field = variant.field (i);
			var argument = call.arguments[i];
			CheckedExpression? scalar = null;
			CheckedStructProducer? record = null;
			CheckedEnumProducer? sum = null;
			if (field.owns_buffer) {
				bool previous_capture = enum_buffer_capture;
				enum_buffer_capture = true;
				scalar = check_buffer_producer (argument,values,(SliceType) field.semantic_type);
				enum_buffer_capture = previous_capture;
				if (scalar == null) {
					return null;
				}
			} else if (field.owns_scalar) {
				var moved = argument as MoveExpressionSyntax;
				if (moved == null) {
					fail (argument.span,"owned enum scalar payload requires an explicit move of a named owner");
					return null;
				}
				bool previous_capture = enum_scalar_capture;
				enum_scalar_capture = true;
				var transfer = check_move (moved,values);
				enum_scalar_capture = previous_capture;
				if (transfer == null) {
					return null;
				}
				if (transfer.semantic_type != field.semantic_type || transfer.cleanup != field.owned_cleanup || (field.owns_child && !transfer.source.heap_object)) {
					fail (argument.span,"owned enum scalar payload requires the exact Resource cleanup or transferable heap Class");
					return null;
				}
				scalar = transfer;
			} else if (field.semantic_type is EnumType) {
				sum = check_enum_producer (argument,values,(EnumType) field.semantic_type,false,true);
				if (sum == null) {
					return null;
				}
			} else if (field.semantic_type.is_struct_storage ()) {
				record = check_struct_producer (argument,values,field.semantic_type,field.owns_record);
				if (record == null) {
					return null;
				}
				if (field.owns_record) {
					var source = ((CheckedStructMoveProducer) record).source;
					if (enum_reservations.find (source)) {
						fail (argument.span,"record owner is reserved by an unfinished enum constructor");
						return null;
					}
					record_all_events (GenericOwnershipEventKind.READ,source,argument.span);
					enum_reservations.add (source);
				}
			} else {
				scalar = check_expression (argument,values,field.semantic_type);
				if (scalar == null) {
					return null;
				}
				if (scalar.semantic_type != field.semantic_type) {
					fail (argument.span,"enum payload '%s' expects exact type '%s', found '%s'".printf (field.identity.name,field.semantic_type.display_name (),scalar.semantic_type.display_name ()));
					return null;
				}
			}
			fields.add (new CheckedEnumFieldValue (argument.span,field,scalar,record,sum));
		}
		while (enum_reservations.length > reservation_depth) {
			var source = enum_reservations[reservation_depth];
			if (source.is_record_owner) {
				record_all_events (GenericOwnershipEventKind.MOVE,source,call.span);
			} else if (generic_owner_flow != null) {
				generic_owner_flow.move (source,source.name,call.span);
			}
			enum_reservations.remove_index (reservation_depth);
		}
		return new CheckedEnumConstruct (call.span,definition,variant,fields);
	}

	private CheckedEnumMatch? check_enum_match(MatchStatementSyntax syntax,FunctionSymbol function,ValueScope values,GenericArray<LocalSymbol> locals) {
		var scrutinee = check_enum_producer (syntax.scrutinee,values,null,true);
		if (scrutinee == null) {
			return null;
		}
		var definition = scrutinee.definition;
		var inspection = scrutinee as CheckedEnumSnapshot;
		bool inspecting = inspection != null && inspection.mode == EnumUse.INSPECT;
		var root = inspecting ? inspection.source.enum_inspection_root ?? inspection.source : null;
		var selected = new HashTable<EnumVariant,bool> (direct_hash,direct_equal);
		var arms = new GenericArray<CheckedEnumArm> ();
		bool fallback = false;
		var incoming_fields = field_state == null ? null : field_state.copy ();
		FieldInitializationState? joined_fields = null;
		foreach (var arm in syntax.arms) {
			if (fallback) {
				fail (arm.span,"match else must be the last arm");
				return null;
			}
			EnumVariant? variant = null;
			if (arm.qualifier == null) {
				if (selected.size () == definition.variant_count) {
					fail (arm.span,"unreachable match else after complete explicit coverage");
					return null;
				}
				fallback = true;
			} else {
				if (!(find_named (arm.qualifier) is EnumType) || resolve_enum_application ((EnumType) find_named (arm.qualifier),arm.type_arguments,arm.span) != scrutinee.semantic_type) {
					fail (arm.qualifier.span,"match pattern requires the exact scrutinee enum type");
					return null;
				}
				variant = definition.find_variant (arm.variant.spelling ());
				if (variant == null) {
					fail (arm.variant.span,"unknown enum pattern variant '%s'".printf (arm.variant.spelling ()));
					return null;
				}
				if (selected.contains (variant)) {
					fail (arm.variant.span,"duplicate match variant '%s'".printf (variant.identity.name));
					return null;
				}
				selected.insert (variant,true);
				if (arm.bindings.length != variant.field_count) {
					fail (arm.span,"match pattern requires exactly %u field bindings, found %u".printf (variant.field_count,arm.bindings.length));
					return null;
				}
			}
			var region = new LexicalRegion (values.region,next_region_ordinal++);
			var scope = new ValueScope (values,region);
			var bindings = new GenericArray<CheckedEnumBinding> ();
			var mapped = new HashTable<EnumField,EnumBindingSyntax> (direct_hash,direct_equal);
			bool named = arm.bindings.length != 0 && arm.bindings[0].field != null;
			for (uint i = 0; i < arm.bindings.length; i++) {
				var binding = arm.bindings[i];
				if ((binding.field != null) != named) {
					fail (binding.span,"positional and named match bindings cannot be mixed");
					return null;
				}
				var field = named ? variant.find_field (binding.field.spelling ()) : variant.field (i);
				if (field == null || mapped.contains (field)) {
					fail (binding.span,"unknown or duplicate named payload field");
					return null;
				}
				mapped.insert (field,binding);
			}
			if (variant != null) {
				for (uint i = 0; i < variant.field_count; i++) {
					var field = variant.field (i);
					var binding = mapped.lookup (field);
					string name = binding.binding.spelling ();
					if (name == "_") {
						continue;
					}
					if (scope.lookup (name) != null) {
						fail (binding.binding.span,"match binding '%s' conflicts with a visible name".printf (name));
						return null;
					}
					if (inspecting && (field.owns_scalar || field.owns_record)) {
						fail (binding.span,"owned enum scalar binding requires a consuming match; use '_' for inspection without a payload loan");
						return null;
					}
					var child = !inspecting && field.owns_child ? instance_for (field.semantic_type) as ClassSymbol : null;
					var local = new LocalSymbol (binding.span,binding.binding.span,field.semantic_type,locals.length,region,inspecting ? null : field.owned_cleanup,null,child,field.owns_buffer && !inspecting);
					local.heap_object = child != null;
					if (!inspecting && field.owns_record) {
						local.record_owner = owning_record_field (field.semantic_type);
						record_all_events (GenericOwnershipEventKind.ACQUIRE,local,binding.span);
					}
					if (!inspecting && field.owns_scalar && generic_owner_flow != null) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE,local,local.name,binding.span);
					}
					if (inspecting && (field.owns_buffer || (field.semantic_type is EnumType && EnumValueAuthority.owns (enum_definition_for ((EnumType) field.semantic_type), enum_definition_for)))) {
						local.enum_inspection_root = root;
					}
					locals.add (local);
					scope.insert (name, local);
					bindings.add (new CheckedEnumBinding (binding.span, field, local, scrutinee.instance));
				}
			}
			if (incoming_fields != null) {
				field_state = incoming_fields.copy ();
			}
			if (generic_owner_flow != null && arms.length + 1 < syntax.arms.length) {
				generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, syntax.span, -1);
			}
			var statements = new GenericArray<CheckedStatement> ();
			if (root != null) {
				enum_inspections.add (root);
			}
			foreach (var statement in arm.body.statements) {
				var checked = check_statement (statement, function, scope, locals);
				if (checked == null) {
					return null;
				}
				statements.add (checked);
			}
			if (root != null) {
				enum_inspections.remove_index (enum_inspections.length - 1);
			}
			if (field_state != null) {
				joined_fields = joined_fields == null ? field_state : FieldInitializationState.join (joined_fields, field_state);
			}
			if (generic_owner_flow != null && arms.length + 1 < syntax.arms.length) {
				generic_owner_flow.arm (1);
			}
			arms.add (new CheckedEnumArm (arm.span, variant, bindings, new CheckedBlockStatement (arm.body.span, statements, region)));
		}
		if (generic_owner_flow != null) {
			for (uint a = 1; a < syntax.arms.length; a++) {
				generic_owner_flow.end ();
			}
		}
		if (arms.length == 0 || (!fallback && selected.size () != definition.variant_count)) {
			fail (syntax.span, "nonexhaustive enum match; cover every variant or add a last else");
			return null;
		}
		if (incoming_fields != null) {
			field_state = joined_fields;
		}
		return new CheckedEnumMatch (syntax.span, scrutinee, arms);
	}

	private ClassType? resolve_exception_type(TypeNameSyntax syntax) {
		var type = resolve_type (syntax) as ClassType;
		if (type == null || exception_root == null || !type.derives_from ((ClassType) exception_root.semantic_type)) {
			fail (syntax.span, "exception type must derive from the nominated ExceptionRoot class");
			return null;
		}
		return type;
	}
	private bool check_exception_effect(ClassType bound, SourceSpan span) {
		for (int i = (int) exception_handlers.length - 1; i >= 0; i--) {
			var scope = exception_handlers[i];
			scope.effects.add (bound);
			foreach (var caught in scope.bounds) {
				if (bound.derives_from (caught)) {
					return true;
				}
			}
		}
		if (checking_function != null && checking_function.throws_type != null && bound.derives_from (checking_function.throws_type)) {
			return true;
		}
		fail (span, "unhandled checked exception bound '%s'; catch an ancestor bound or declare compatible throws".printf (bound.display_name ()));
		return false;
	}
	private CheckedStatement? check_throw(ThrowStatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (exception_root == null) {
			fail (syntax.span, "throw requires a concrete native definition and nominated exception root");
			return null;
		}
		if (syntax.is_rethrow) {
			if (caught_exceptions.length == 0) {
				fail (syntax.span, "bare throw requires the nearest lexical catch");
				return null;
			}
			var binding = caught_exceptions[caught_exceptions.length - 1];
			foreach (var effect in caught_effects.lookup (binding)) {
				if (!check_exception_effect (effect, syntax.span)) {
					return null;
				}
				if (generic_owner_flow != null) {
					generic_owner_flow.effect (effect, syntax.span, true);
				}
			}
			return new CheckedThrow (syntax.span, binding, (ClassType) exception_root.semantic_type, true);
		}
		LocalSymbol? owner = null;
		CheckedConstructorObjectInitialization? construction = null;
		if (syntax.expression is HeapObjectConstructionSyntax) {
			construction = check_heap_local (syntax.span, SourceSpan (syntax.span.file, syntax.span.start, syntax.span.start + 5), (HeapObjectConstructionSyntax) syntax.expression, null, new ValueScope (values, values.region), locals) as CheckedConstructorObjectInitialization;
			if (construction == null) {
				return null;
			}
			owner = construction.local;
		} else if (syntax.expression is MoveExpressionSyntax) {
			var move = check_move ((MoveExpressionSyntax) syntax.expression, values) as CheckedOwnershipMove;
			if (move == null) {
				return null;
			}
			owner = move.source;
		}
		if (owner == null || !owner.heap_object || !(owner.semantic_type is ClassType) || !((ClassType) owner.semantic_type).derives_from ((ClassType) exception_root.semantic_type)) {
			fail (syntax.span, "throw requires a fresh heap exception or explicit move of an owned heap exception");
			return null;
		}
		if (!check_exception_effect ((ClassType) owner.semantic_type, syntax.span)) {
			return null;
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.effect ((ClassType) owner.semantic_type, syntax.span, true);
		}
		return new CheckedThrow (syntax.span, owner, (ClassType) exception_root.semantic_type, false, construction);
	}
	private CheckedStatement? check_try(TryStatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (exception_root == null) {
			fail (syntax.span, "try requires a nominated exception root and concrete native definition");
			return null;
		}
		var handler = new ExceptionHandlerScope ();
		foreach (var caught in syntax.catches) {
			var type = resolve_exception_type (caught.class_name);
			if (type == null) {
				return null;
			}
			foreach (var prior in handler.bounds) {
				if (type.derives_from (prior)) {
					fail (caught.span, "unreachable catch: an earlier ancestor catch already handles this subtype");
					return null;
				}
			}
			handler.bounds.add (type);
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.begin_try (syntax.span, handler.bounds);
		}
		exception_handlers.add (handler);
		var body = check_block (syntax.body, function, values, locals);
		exception_handlers.remove_index (exception_handlers.length - 1);
		if (body == null) {
			return null;
		}
		var catches = new GenericArray<CheckedCatch> ();
		for (int c = 0; c < syntax.catches.length; c++) {
			if (generic_owner_flow != null) {
				generic_owner_flow.arm (c + 1);
			}
			var caught = syntax.catches[c];
			var region = new LexicalRegion (values.region, next_region_ordinal++);
			var scope = new ValueScope (values, region);
			if (scope.lookup (caught.binding.spelling ()) != null) {
				fail (caught.binding.span, "catch binding conflicts with a visible binding");
				return null;
			}
			var binding = new LocalSymbol (caught.span, caught.binding.span, handler.bounds[c], locals.length, region);
			binding.catch_borrow = true;
			locals.add (binding);
			scope.insert (binding.name, binding);
			caught_effects.insert (binding, handler.incoming (c));
			caught_exceptions.add (binding);
			var statements = new GenericArray<CheckedStatement> ();
			foreach (var statement in caught.body.statements) {
				var checked = check_statement (statement, function, scope, locals);
				if (checked == null) {
					return null;
				}
				statements.add (checked);
			}
			caught_exceptions.remove_index (caught_exceptions.length - 1);
			catches.add (new CheckedCatch (binding, new CheckedBlockStatement (caught.body.span, statements, region)));
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.end ();
		}
		return new CheckedTry (syntax.span, body, catches, (ClassType) exception_root.semantic_type);
	}

	private AsyncRuntimeIdentity? async_operation_runtime(CallExpressionSyntax call, ValueScope values) {
		var local = call.receiver == null ? null : values.lookup (call.receiver.spelling ()) as LocalSymbol;
		var executor = local == null ? null : local.semantic_type as ExecutorType;
		return executor == null ? runtime_for(call.span) : executor.runtime;
	}
	private bool async_operation_call(CallExpressionSyntax call, ValueScope values) {
		var async_runtime = async_operation_runtime (call, values);
		if (async_runtime == null) {
			return false;
		}
		if (call.receiver != null) {
			var local = values.lookup (call.receiver.spelling ()) as LocalSymbol;
			return (local != null && local.semantic_type is ExecutorType) || (local == null && call.receiver.spelling () == async_runtime.executor_name);
		}
		return checking_function != null && checking_function.async_body != null && find_function (call.identifier) == null && values.lookup (call.identifier.spelling ()) == null && (call.identifier.spelling () == "start" || call.identifier.spelling () == "cancel");
	}
	private CheckedNode? check_async_operation(CallExpressionSyntax call, ValueScope values, bool requires_value) {
		var runtime = async_operation_runtime (call, values);
		if (runtime == null || call.type_arguments.length != 0 || call.qualifier_arguments.length != 0) {
			fail (call.span, "virtual executor operation requires its exact nominated runtime and nongeneric contract");
			return null;
		}
		string name = call.identifier.spelling ();
		bool opening = call.receiver != null && call.receiver.spelling () == runtime.executor_name && values.lookup (runtime.executor_name) == null;
		bool current = call.receiver == null;
		LocalSymbol? executor = current || opening ? null : values.lookup (call.receiver.spelling ()) as LocalSymbol;
		if ((!opening && !current && (executor == null || executor.semantic_type != runtime.executor_type)) || (opening && name != "open")) {
			fail (call.span, "executor operation lost its exact unique executor identity");
			return null;
		}
		AsyncOperationKind kind;
		SemanticType result = types.void_type;
		switch (name) {
		case "open": kind = AsyncOperationKind.OPEN;
			result = runtime.executor_type;
			break;
		case "start": kind = AsyncOperationKind.START;
			break;
		case "cancel": kind = AsyncOperationKind.CANCEL;
			break;
		case "pump": kind = AsyncOperationKind.PUMP;
			result = types.u32_type;
			break;
		case "advance": if (runtime.linux || runtime.threaded) {
				fail (call.span, runtime.linux ? "Linux executor does not admit virtual advance" : "threaded executor uses real monotonic time and does not admit virtual advance");
				return null;
		}
			kind = AsyncOperationKind.ADVANCE;
			break;
		case "wait": if (!runtime.linux) {
				fail (call.span, "virtual executor does not admit Linux wait");
				return null;
		}
			kind = AsyncOperationKind.WAIT;
			break;
		case "begin_shutdown": kind = AsyncOperationKind.BEGIN_SHUTDOWN;
			break;
		case "shutdown_complete": kind = AsyncOperationKind.SHUTDOWN_COMPLETE;
			result = types.bool_type;
			break;
		case "finish_shutdown": kind = AsyncOperationKind.FINISH_SHUTDOWN;
			result = types.bool_type;
			break;
		case "run": kind = AsyncOperationKind.RUN;
			result = types.bool_type;
			break;
			default: fail (call.span, "unsupported operation on the exact virtual executor");
			return null;
		}
		if (current ? (checking_function == null || checking_function.async_body == null || (kind != AsyncOperationKind.START && kind != AsyncOperationKind.CANCEL)) : checking_function != null && checking_function.async_body != null) {
			fail (call.span, "task bodies use current-task start/cancel; host executor operations cannot enter a nested loop");
			return null;
		}
		bool task_operation = kind == AsyncOperationKind.START || kind == AsyncOperationKind.CANCEL || kind == AsyncOperationKind.RUN;
		bool argument_operation = kind == AsyncOperationKind.OPEN || kind == AsyncOperationKind.PUMP || kind == AsyncOperationKind.ADVANCE;
		if (call.arguments.length != (task_operation || argument_operation ? 1 : 0)) {
			fail (call.span, "virtual executor operation has an exact bounded argument count");
			return null;
		}
		CheckedExpression? task = null;
		CheckedExpression? argument = null;
		if (task_operation) {
			var operand = call.arguments[0];
			if (kind == AsyncOperationKind.RUN) {
				if (operand is MoveExpressionSyntax) {
					var source = values.lookup (((MoveExpressionSyntax) operand).source.spelling ()) as LocalSymbol;
					if (source != null && source.semantic_type is TaskType) {
						task = new CheckedTaskMove (operand.span, source);
					}
				} else if (operand is CallExpressionSyntax) {
					task = check_value_call ((CallExpressionSyntax) operand, values, true, true) as CheckedExpression;
				}
			} else if (operand is NameExpressionSyntax) {
				var source = values.lookup (((NameExpressionSyntax) operand).identifier.spelling ()) as LocalSymbol;
				if (source != null && source.semantic_type is TaskType) {
					task = new CheckedTaskBorrow (operand.span, source);
				}
			}
			var type = task == null ? null : task.semantic_type as TaskType;
			if (type == null || !type.runtime.compatible (runtime) || (!current && type.success_type.kind != TypeKind.VOID)) {
				fail (operand.span, "host operations require the sole void root; current-task operations borrow one exact live unique child");
				return null;
			}
			if (kind == AsyncOperationKind.RUN && type.exception_bound != null && !check_exception_effect (type.exception_bound, call.span)) {
				return null;
			}
		}
		if (argument_operation) {
			argument = check_expression (call.arguments[0], values, kind == AsyncOperationKind.OPEN ? types.int_type : types.u32_type);
			if (argument == null) {
				return null;
			}
			if (argument.semantic_type != (kind == AsyncOperationKind.OPEN ? types.int_type : types.u32_type)) {
				fail (argument.span, "capacity requires int; pump budget and virtual advance require u32");
				return null;
			}
		}
		var contract = new AsyncOperationContract (runtime, kind, result);
		if (contract.raises && !check_exception_effect (runtime.error_type, call.span)) {
			return null;
		}
		if (requires_value && result.kind == TypeKind.VOID) {
			fail (call.span, "void executor operation has no value");
			return null;
		}
		if (!requires_value && (kind == AsyncOperationKind.OPEN || kind == AsyncOperationKind.RUN)) {
			fail (call.span, "executor creation and root run require their explicit owner/status consumer");
			return null;
		}
		var operation = new CheckedAsyncOperation (call.span, contract, executor == null ? null : new CheckedExecutorBorrow (call.receiver.span, executor), task, argument);
		return kind == AsyncOperationKind.RUN ? (CheckedNode) new CheckedAsyncRun (call.span, enum_definition_for (runtime.status_type), operation) : operation;
	}

	private CheckedTaskAwait? check_task_await(AwaitExpressionSyntax syntax, ValueScope values, bool acquire_buffer = false, bool aggregate_result = false) {
		if (checking_function == null || checking_function.async_body == null) {
			fail (syntax.span, "await requires a native async body");
			return null;
		}
		bool discard = false;
		ExpressionSyntax operand = syntax.operation;
		var join = operand as CallExpressionSyntax;
		CheckedExpression? bridge_executor = null;
		LocalSymbol? bridge_anchor = null;
		if (join != null && join.receiver != null && (join.identifier.spelling () == "submit" || join.identifier.spelling () == "cancel_and_join")) {
			if (join.arguments.length != 1 || join.type_arguments.length != 0 || join.qualifier_arguments.length != 0) {
				fail (join.span, "worker submission requires one consuming typed cold task");
				return null;
			}
			bridge_executor = check_expression (new NameExpressionSyntax (join.receiver), values, null, OwnershipUse.NULL_COMPARISON, null, true);
			if (bridge_executor == null) {
				return null;
			}
			var handle = handle_types.lookup (bridge_executor.semantic_type);
			if (handle == null || !AsyncBridgeTypes.matches (bridge_executor.semantic_type, handle.cleanup.external_symbol) || !checking_function.async_body.runtime.composable || checking_function.async_body.runtime.threaded) {
				fail (join.span, "worker submission requires the exact WorkerPool close contract and a composed cooperative/Linux body");
				return null;
			}
			bridge_anchor = values.lookup (join.receiver.spelling ()) as LocalSymbol;
			discard = join.identifier.spelling () == "cancel_and_join";
			operand = join.arguments[0];
		}
		if (join != null && join.receiver == null && join.identifier.spelling () == "cancel_and_join" && find_function (join.identifier) == null && values.lookup ("cancel_and_join") == null) {
			if (join.arguments.length != 1 || join.type_arguments.length != 0) {
				fail (join.span, "cancel-and-join requires one consuming task operand");
				return null;
			}
			discard = true;
			operand = join.arguments[0];
		}
		CheckedExpression? child = null;
		uint borrow_depth = pending_callable_borrows.length;
		if (bridge_anchor != null) {
			pending_callable_borrows.add (bridge_anchor);
		}
		if (operand is MoveExpressionSyntax) {
			var move = (MoveExpressionSyntax) operand;
			var source = values.lookup (move.source.spelling ()) as LocalSymbol;
			if (source != null && source.semantic_type is TaskType) {
				child = new CheckedTaskMove (move.span, source);
			}
		} else if (operand is CallExpressionSyntax) {
			var previous_creation = direct_await_creation;
			direct_await_creation = (CallExpressionSyntax) operand;
			child = check_value_call ((CallExpressionSyntax) operand, values, true, true) as CheckedExpression;
			direct_await_creation = previous_creation;
		}
		while (pending_callable_borrows.length > borrow_depth) {
			pending_callable_borrows.remove_index (pending_callable_borrows.length - 1);
		}
		var type = child == null ? null : child.semantic_type as TaskType;
		if (type == null || (bridge_executor == null ? !type.runtime.compatible (checking_function.async_body.runtime) : !AsyncBridgeTypes.compatible (checking_function.async_body.runtime, type.runtime))) {
			fail (operand.span, "await consumes one exact unique task; worker submission requires its explicit composed provider contract");
			return null;
		}
		if (!discard && ((type.exception_bound != null && !check_exception_effect (type.exception_bound, syntax.span)) || !check_exception_effect (type.runtime.error_type, syntax.span))) {
			return null;
		}
		if (!discard && !aggregate_result && ((type.success_mode != ResultOwnershipContract.UNMANAGED && !(acquire_buffer && type.success_type is SliceType && type.success_mode == ResultOwnershipContract.OWNED_TRANSFER)) || type.success_type.is_struct_storage () || type.success_type is EnumType)) {
			fail (syntax.span, "await aggregate/owned success requires its exact frame carrier and transfer plan");
			return null;
		}
		return new CheckedTaskAwait (syntax.span, discard ? types.void_type : type.success_type, checking_function.async_body, child, discard, bridge_executor);
	}

	private CheckedNode? check_await_producer(AwaitExpressionSyntax syntax, ValueScope values) {
		var operation = check_task_await (syntax, values, false, true);
		if (operation == null) {
			return null;
		}
		if (operation.semantic_type is EnumType) {
			return new CheckedEnumAwait (enum_definition_for ((EnumType) operation.semantic_type), operation);
		}
		if (operation.semantic_type.is_struct_storage ()) {
			return new CheckedStructAwait (operation, struct_value_mode (operation.semantic_type));
		}
		if (operation.semantic_type is SliceType) {
			fail (syntax.span, "owned array await requires its explicit ownership acquisition destination");
			return null;
		}
		return operation;
	}

	private SemanticType? scope_member_type(Token name, ValueScope values) {
		var symbol = values.lookup (name.spelling ());
		if (symbol is LocalSymbol) {
			return ((LocalSymbol) symbol).semantic_type;
		}
		if (symbol is ParameterSymbol) {
			return ((ParameterSymbol) symbol).semantic_type;
		}
		return null;
	}
	private bool with_overlap(SemanticType type) {
		if (type is ReceiverType) {
			type = ((ReceiverType) type).instance_type;
		}
		foreach (var contract in active_with) {
			if (field_overlap (type, contract.source.semantic_type)) {
				return true;
			}
		}
		return false;
	}
	private CheckedExpression object_reference(SourceSpan span, LocalSymbol? local, ParameterSymbol? parameter) {
		for (int i = active_with.length - 1; i >= 0; i--) {
			if (active_with[i].source == local) {
				return new CheckedWithReference (span, active_with[i]);
			}
		}
		return local != null ? (CheckedExpression) new CheckedLocalReferenceExpression (span, local) : new CheckedParameterReferenceExpression (span, parameter);
	}
	private void with_call(DirectCallableSymbol target, CheckedExpression? receiver, GenericArray<CheckedExpression> arguments) {
		bool overlaps = receiver != null && with_overlap (receiver.semantic_type);
		foreach (var argument in arguments) {
			if (with_overlap (argument.semantic_type)) {
				overlaps = true;
			}
		}
		if (overlaps && target is FunctionSymbol) {
			readonly_inspection.require ((FunctionSymbol) target);
		}
	}
	private CheckedStatement? check_with(WithStatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (function.async_body != null || function is GenericFunctionSymbol) {
			fail (syntax.span, "with requires synchronous concrete native code");
			return null;
		}
		var region = new LexicalRegion (values.region, next_region_ordinal++);
		var scope = new ValueScope (values, region);
		var statements = new GenericArray<CheckedStatement> ();
		if (syntax.initializer != null) {
			var initial = check_statement (syntax.initializer, function, scope, locals);
			if (initial == null) {
				return null;
			}
			statements.add (initial);
		}
		var source = scope.lookup (syntax.receiver.spelling ()) as LocalSymbol;
		if (source == null || source.object_owner == null || !(source.semantic_type is ClassType)) {
			fail (syntax.receiver.span, "with requires a named owned exact native Class receiver");
			return null;
		}
		var contract = new CheckedWithContract (syntax.span, source);
		active_with.add (contract);
		active_object_receivers.add (source);
		var body = check_block (syntax.body, function, scope, locals);
		active_object_receivers.remove_index (active_object_receivers.length - 1);
		active_with.remove_index (active_with.length - 1);
		if (body == null) {
			return null;
		}
		statements.add (new CheckedWithScope (syntax.span, contract, body));
		return new CheckedBlockStatement (syntax.span, statements, region);
	}

	private CheckedStatement? check_sequence_foreach(ForeachStatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals, LocalSymbol? source_local, SemanticType type) {
		var array = type as ArrayType;
		var source = array != null ? new CheckedSliceFromArrayExpression (syntax.collection.span, source_local, types.slice_of (array.element_type)) : check_expression (syntax.collection, values, null, OwnershipUse.BUFFER_VIEW);
		if (source == null) {
			return null;
		}
		var element = ((SliceType) source.semantic_type).element_type;
		if (CopyabilityAuthority.value_copy (element, copy_fields) != Copyability.COPYABLE) {
			fail (syntax.span, "sequence foreach requires recursively copyable elements");
			return null;
		}
		if (values.lookup (syntax.binding.spelling ()) != null) {
			fail (syntax.binding.span, "foreach binding conflicts with an existing local or parameter");
			return null;
		}

		var region = new LexicalRegion (values.region, next_region_ordinal++);
		var scope = new ValueScope (values, region);
		var index = new LocalSymbol (syntax.keyword.span, syntax.keyword.span, types.int_type, locals.length, region);
		locals.add (index);
		var binding = new LocalSymbol (syntax.binding.span, syntax.binding.span, element, locals.length, region);
		locals.add (binding);
		scope.insert (syntax.binding.spelling (), binding);
		var target = new CheckedLoopTarget (syntax.keyword.span, next_loop_ordinal++);
		var authority = new CheckedSequenceIteration (syntax.span, target, source, index, binding);
		var condition = new CheckedBinaryExpression (syntax.span, types.bool_type, BinaryOperator.LESS,
			new CheckedLocalReferenceExpression (syntax.span, index), new CheckedLengthExpression (syntax.span, types.i32_type, null, source));

		if (generic_owner_flow != null) {
			generic_owner_flow.begin (GenericOwnershipEventKind.LOOP, syntax.span, -1, target);
			generic_owner_flow.arm (1);
		}
		active_loops.add (target);
		if (source_local != null) {
			sequence_sources.add (source_local);
			active_object_receivers.add (source_local);
		}
		var before = field_state == null ? null : field_state.copy ();
		var body = check_block (syntax.body, function, scope, locals);
		if (before != null) {
			field_state = before;
		}
		if (source_local != null) {
			sequence_sources.remove_index (sequence_sources.length - 1);
			active_object_receivers.remove_index (active_object_receivers.length - 1);
		}
		active_loops.remove_index (active_loops.length - 1);
		if (generic_owner_flow != null) {
			generic_owner_flow.end ();
		}
		if (body == null) {
			return null;
		}

		var place = new CheckedSliceElementPlace (syntax.binding.span, source, new CheckedLocalReferenceExpression (syntax.binding.span, index));
		CheckedStatement copied = element.is_struct_storage () ? (CheckedStatement) new CheckedStructResultStore (syntax.binding.span,
			new CheckedLocalPlace (syntax.binding.span, binding), new CheckedStructSnapshot (syntax.binding.span, place, Copyability.COPYABLE), true)
		        : new CheckedLocalDeclaration (syntax.binding.span, binding, new CheckedLoadExpression (syntax.binding.span, place));
		body.statements.insert (0, copied);
		var steps = new GenericArray<CheckedStatement> ();
		steps.add (new CheckedAssignment (syntax.span, index, new CheckedBinaryExpression (syntax.span, types.int_type, BinaryOperator.ADD,
			new CheckedLocalReferenceExpression (syntax.span, index), new CheckedIntegerExpression (syntax.span, types.int_type, AstraIntValue.from_int64 (1)))));
		var statements = new GenericArray<CheckedStatement> ();
		statements.add (new CheckedLocalDeclaration (syntax.span, index, new CheckedIntegerExpression (syntax.span, types.int_type, AstraIntValue.from_int64 (0))));
		statements.add (new CheckedWhile (syntax.span, target, condition, body, new CheckedBlockStatement (syntax.span, steps,
			new LexicalRegion (region, next_region_ordinal++)), null, authority));
		return new CheckedBlockStatement (syntax.span, statements, region);
	}

	private CheckedStatement? check_iterator_foreach(ForeachStatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals, LocalSymbol? local, ParameterSymbol? parameter, ClassSymbol owner) {
		var advance = owner.find_method ("advance");
		var current = owner.find_method ("current");
		if (owner.polymorphic || owner.parent_class != null || owner.generic_instance != null || advance == null || current == null
		    || advance.parameters.length != 0 || current.parameters.length != 0 || advance.return_type != types.bool_type
		    || advance.async_body != null || current.async_body != null || advance.dispatch_kind != ClassDispatchKind.DIRECT || current.dispatch_kind != ClassDispatchKind.DIRECT
		    || current.result_contract != ResultOwnershipContract.UNMANAGED || CopyabilityAuthority.value_copy (current.return_type, copy_fields) != Copyability.COPYABLE) {
			fail (syntax.collection.span, "iterator foreach requires an exact native Class with bool advance() and copyable current() methods");
			return null;
		}
		if ((advance.throws_type != null && !check_exception_effect (advance.throws_type, syntax.span))
		    || (current.throws_type != null && !check_exception_effect (current.throws_type, syntax.span))) {
			return null;
		}
		if (values.lookup (syntax.binding.spelling ()) != null) {
			fail (syntax.binding.span, "foreach binding conflicts with an existing local or parameter");
			return null;
		}

		var region = new LexicalRegion (values.region, next_region_ordinal++);
		var scope = new ValueScope (values, region);
		var binding = new LocalSymbol (syntax.binding.span, syntax.binding.span, current.return_type, locals.length, region);
		locals.add (binding);
		scope.insert (syntax.binding.spelling (), binding);
		CheckedExpression source = local != null ? (CheckedExpression) new CheckedLocalReferenceExpression (syntax.collection.span, local)
		        : new CheckedParameterReferenceExpression (syntax.collection.span, parameter);
		var receiver = new CheckedObjectReceiverExpression (syntax.collection.span, source, owner.receiver_type);
		var target = new CheckedLoopTarget (syntax.keyword.span, next_loop_ordinal++);
		var authority = new CheckedSequenceIteration.iterator (syntax.span, target, source, binding, advance, current);
		var condition = new CheckedCallExpression (syntax.collection.span, advance, new GenericArray<CheckedExpression> (), receiver);

		if (generic_owner_flow != null) {
			generic_owner_flow.begin (GenericOwnershipEventKind.LOOP, syntax.span, -1, target);
			if (advance.throws_type != null) {
				generic_owner_flow.effect (advance.throws_type, syntax.span);
			}
			generic_owner_flow.arm (1);
			if (current.throws_type != null) {
				generic_owner_flow.effect (current.throws_type, syntax.span);
			}
		}
		active_loops.add (target);
		if (local != null) {
			sequence_sources.add (local);
			active_object_receivers.add (local);
		}
		var before = field_state == null ? null : field_state.copy ();
		var body = check_block (syntax.body, function, scope, locals);
		if (before != null) {
			field_state = before;
		}
		if (local != null) {
			sequence_sources.remove_index (sequence_sources.length - 1);
			active_object_receivers.remove_index (active_object_receivers.length - 1);
		}
		active_loops.remove_index (active_loops.length - 1);
		if (generic_owner_flow != null) {
			generic_owner_flow.end ();
		}
		if (body == null) {
			return null;
		}

		CheckedStatement observation = current.return_type.is_struct_storage () ? (CheckedStatement) new CheckedStructResultStore (syntax.binding.span,
			new CheckedLocalPlace (syntax.binding.span, binding), new CheckedStructCallResult (syntax.binding.span, current, new GenericArray<CheckedExpression> (), receiver, Copyability.COPYABLE), true)
		        : new CheckedLocalDeclaration (syntax.binding.span, binding, new CheckedCallExpression (syntax.binding.span, current, new GenericArray<CheckedExpression> (), receiver));
		body.statements.insert (0, observation);
		var statements = new GenericArray<CheckedStatement> ();
		statements.add (new CheckedWhile (syntax.span, target, condition, body, null, null, authority));
		return new CheckedBlockStatement (syntax.span, statements, region);
	}

	private CheckedStatement? check_foreach(ForeachStatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (function.async_body != null || function is GenericFunctionSymbol) {
			fail (syntax.span, "foreach requires synchronous concrete native code");
			return null;
		}
		var name = syntax.collection as NameExpressionSyntax;
		var symbol = name == null ? null : values.lookup (name.identifier.spelling ());
		var local = symbol as LocalSymbol;
		var parameter = symbol as ParameterSymbol;
		var type = local != null ? local.semantic_type : parameter == null ? null : parameter.semantic_type;
		if (type is ArrayType || type is SliceType) {
			return check_sequence_foreach (syntax, function, values, locals, local, type);
		}
		var owner = type == null ? null : instance_for (type) as ClassSymbol;
		if (owner != null && owner.generic_instance == null && (owner.find_method ("advance") != null || owner.find_method ("current") != null)) {
			return check_iterator_foreach (syntax, function, values, locals, local, parameter, owner);
		}
		if (owner == null || owner.generic_instance == null || owner.fields.length != 1 || !(owner.fields[0].semantic_type is OwnerSlotsType)) {
			fail (syntax.collection.span, "foreach requires a named exact Bag owner or borrowed parameter");
			return null;
		}
		if (values.lookup (syntax.binding.spelling ()) != null) {
			fail (syntax.binding.span, "foreach binding conflicts with an existing local or parameter");
			return null;
		}
		var region = new LexicalRegion (values.region, next_region_ordinal++);
		var scope = new ValueScope (values, region);
		var index = new LocalSymbol (syntax.keyword.span, syntax.keyword.span, types.int_type, locals.length, region);
		locals.add (index);
		CheckedExpression receiver = local != null ? (CheckedExpression) new CheckedLocalReferenceExpression (name.span, local) : new CheckedParameterReferenceExpression (name.span, parameter);
		var store = new CheckedObjectFieldPlace (syntax.collection.span, receiver, owner.fields[0]);
		var target = new CheckedLoopTarget (syntax.keyword.span, next_loop_ordinal++);
		var element = ((OwnerSlotsType) store.semantic_type).element;
		LocalSymbol? binding = null;
		if (element is StructType) {
			if (!check_copyable_type (element, syntax.span)) {
				return null;
			}
			binding = new LocalSymbol (syntax.binding.span, syntax.binding.span, element, locals.length, region);
			locals.add (binding);
		}
		var iteration = new CheckedIterationContract (syntax.span, target, store, index, binding);
		scope.insert (syntax.binding.spelling (), binding != null ? (Symbol) binding : new IterationElementSymbol (syntax.binding.span, iteration));
		var initial = new CheckedLocalDeclaration (syntax.keyword.span, index, new CheckedIntegerExpression (syntax.keyword.span, types.int_type, AstraIntValue.from_int64 (0)));
		var condition = new CheckedBinaryExpression (syntax.collection.span, types.bool_type, BinaryOperator.LESS,
			new CheckedLocalReferenceExpression (syntax.collection.span, index), new CheckedSlotsValue (syntax.collection.span, types.int_type, store, OwnerSlotsAction.LENGTH));
		if (generic_owner_flow != null) {
			generic_owner_flow.begin (GenericOwnershipEventKind.LOOP, syntax.span, -1, target);
			generic_owner_flow.arm (1);
		}
		active_loops.add (target);
		pending_field_borrows.add (owner.semantic_type);
		if (local != null) {
			active_object_receivers.add (local);
		}
		var before = field_state == null ? null : field_state.copy ();
		foreach_depth++;
		var body = check_block (syntax.body, function, scope, locals);
		foreach_depth--;
		if (before != null) {
			field_state = before;
		}
		if (local != null) {
			active_object_receivers.remove_index (active_object_receivers.length - 1);
		}
		pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		active_loops.remove_index (active_loops.length - 1);
		if (generic_owner_flow != null) {
			generic_owner_flow.end ();
		}
		if (body == null) {
			return null;
		}
		if (binding != null) {
			var snapshot = new CheckedSlotsRecordRead (syntax.binding.span, store, new CheckedLocalReferenceExpression (syntax.binding.span, index), false);
			body.statements.insert (0, new CheckedStructResultStore (syntax.binding.span, new CheckedLocalPlace (syntax.binding.span, binding), snapshot, true));
		}
		var step_region = new LexicalRegion (region, next_region_ordinal++);
		var steps = new GenericArray<CheckedStatement> ();
		steps.add (new CheckedAssignment (syntax.keyword.span, index, new CheckedBinaryExpression (syntax.keyword.span, types.int_type, BinaryOperator.ADD,
			new CheckedLocalReferenceExpression (syntax.keyword.span, index), new CheckedIntegerExpression (syntax.keyword.span, types.int_type, AstraIntValue.from_int64 (1)))));
		var statements = new GenericArray<CheckedStatement> ();
		statements.add (initial);
		statements.add (new CheckedWhile (syntax.span, target, condition, body, new CheckedBlockStatement (syntax.keyword.span, steps, step_region), iteration));
		return new CheckedBlockStatement (syntax.span, statements, region);
	}

	private CheckedWhile? check_loop(SourceSpan span, Token keyword, ExpressionSyntax? condition_syntax, BlockStatementSyntax body_syntax, StatementSyntax? step_syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		var target = new CheckedLoopTarget (keyword.span, next_loop_ordinal++);
		if (generic_owner_flow != null) {
			generic_owner_flow.begin (GenericOwnershipEventKind.LOOP, span, -1, target);
		}
		var condition = condition_syntax == null ? new CheckedBooleanExpression (keyword.span, types.bool_type, BooleanLiteral.TRUE) : check_expression (condition_syntax, values);
		if (condition == null) {
			return null;
		}
		if (condition.semantic_type != types.bool_type) {
			fail (condition.span, "%s condition must have type 'bool', found '%s'".printf (keyword.spelling (), condition.semantic_type.display_name ()));
			return null;
		}
		active_loops.add (target);
		var before_loop = field_state == null ? null : field_state.copy ();
		if (field_state != null && condition is CheckedBooleanExpression && ((CheckedBooleanExpression) condition).literal == BooleanLiteral.FALSE) {
			field_state.reachable = false;
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.arm (1, generic_truth (condition));
		}
		var saved_unreachable = unreachable_return_origin;
		unreachable_return_origin = saved_unreachable || generic_truth (condition) == 0;
		var body = check_block (body_syntax, function, values, locals);
		CheckedBlockStatement? step = null;
		if (body != null && step_syntax != null) {
			if (generic_owner_flow != null) {
				generic_owner_flow.arm (2);
			}
			var step_region = new LexicalRegion (values.region, next_region_ordinal++);
			var checked_step = check_statement (step_syntax, function, new ValueScope (values, step_region), locals);
			if (checked_step == null) {
				return null;
			}
			var steps = new GenericArray<CheckedStatement> ();
			steps.add (checked_step);
			step = new CheckedBlockStatement (step_syntax.span, steps, step_region);
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.end ();
		}
		unreachable_return_origin = saved_unreachable;
		active_loops.remove_index (active_loops.length - 1);
		if (before_loop != null) {
			field_state = before_loop;
			if (condition is CheckedBooleanExpression && ((CheckedBooleanExpression) condition).literal == BooleanLiteral.TRUE && !constructor_breaks.contains (target)) {
				field_state.reachable = false;
			}
		}
		return body == null ? null : new CheckedWhile (span, target, condition, body, step);
	}

	// Keep compound recursion out of the large simple-statement C frame.
	// The parser's accepted nesting bound must also work in an O0 compiler.
	private CheckedStatement? check_statement_body(StatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (syntax is BlockStatementSyntax) {
			return check_block ((BlockStatementSyntax) syntax, function, values, locals);
		}
		if (syntax is IfStatementSyntax) {
			return check_if ((IfStatementSyntax) syntax, function, values, locals);
		}
		if (syntax is ForStatementSyntax) {
			return check_for ((ForStatementSyntax) syntax, function, values, locals);
		}
		if (syntax is WhileStatementSyntax) {
			var loop = (WhileStatementSyntax) syntax;
			return check_loop (loop.span, loop.keyword, loop.condition, loop.body, null, function, values, locals);
		}
		if (syntax is WithStatementSyntax) {
			return check_with ((WithStatementSyntax) syntax, function, values, locals);
		}
		if (syntax is ForeachStatementSyntax) {
			return check_foreach ((ForeachStatementSyntax) syntax, function, values, locals);
		}
		if (syntax is TryStatementSyntax) {
			return check_try ((TryStatementSyntax) syntax, function, values, locals);
		}
		if (syntax is ThrowStatementSyntax) {
			return check_throw ((ThrowStatementSyntax) syntax, function, values, locals);
		}
		if (syntax is MatchStatementSyntax) {
			return check_enum_match ((MatchStatementSyntax) syntax, function, values, locals);
		}
		return check_simple_statement (syntax, function, values, locals);
	}

	private bool unreachable_return_origin;

	private CheckedStatement? check_if(IfStatementSyntax conditional, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		var condition = check_expression (conditional.condition, values);
		if (condition == null) {
			return null;
		}
		if (condition.semantic_type != types.bool_type) {
			fail (condition.span, "if condition must have type 'bool', found '%s'".printf (condition.semantic_type.display_name ()));
			return null;
		}
		var saved_unreachable = unreachable_return_origin;
		unreachable_return_origin = saved_unreachable || generic_truth (condition) == 0;
		var incoming_fields = field_state == null ? null : field_state.copy ();
		if (field_state != null && condition is CheckedBooleanExpression && ((CheckedBooleanExpression) condition).literal == BooleanLiteral.FALSE) {
			field_state.reachable = false;
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, conditional.span, generic_truth (condition));
		}
		var then_body = check_block (conditional.then_body, function, values, locals);
		if (then_body == null) {
			return null;
		}
		var then_fields = field_state;
		unreachable_return_origin = saved_unreachable || generic_truth (condition) == 1;
		field_state = incoming_fields;
		if (field_state != null && condition is CheckedBooleanExpression && ((CheckedBooleanExpression) condition).literal == BooleanLiteral.TRUE) {
			field_state.reachable = false;
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.arm (1);
		}
		CheckedBlockStatement? else_body = null;
		if (conditional.else_body != null) {
			else_body = check_block (conditional.else_body, function, values, locals);
			if (else_body == null) {
				return null;
			}
		}
		unreachable_return_origin = saved_unreachable;
		if (field_state != null) {
			field_state = FieldInitializationState.join (then_fields, field_state);
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.end ();
		}
		return new CheckedIf (conditional.span, condition, then_body, else_body);
	}

	private CheckedStatement? check_for(ForStatementSyntax loop, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		var region = new LexicalRegion (values.region, next_region_ordinal++);
		var scope = new ValueScope (values, region);
		var statements = new GenericArray<CheckedStatement> ();
		if (loop.initializer != null) {
			var initial = check_statement (loop.initializer, function, scope, locals);
			if (initial == null) {
				return null;
			}
			statements.add (initial);
		}
		var checked_loop = check_loop (loop.span, loop.keyword, loop.condition, loop.body, loop.step, function, scope, locals);
		if (checked_loop == null) {
			return null;
		}
		statements.add (checked_loop);
		if (generic_owner_flow != null) {
			foreach (var local in locals) {
				if (local.is_generic_owner && local.incoming_parameter == null && local.lexical_region == region) {
					generic_owner_flow.owner_event (GenericOwnershipEventKind.RETIRE, local, local.name, loop.span);
				}
			}
		}
		return new CheckedBlockStatement (loop.span, statements, region);
	}

	private CheckedStatement? check_simple_statement(StatementSyntax syntax, FunctionSymbol function, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (syntax is AwaitStatementSyntax) {
			var awaited = ((AwaitStatementSyntax) syntax).expression;
			if (function.async_body == null) {
				fail (awaited.span, "await requires a native async body");
				return null;
			}
			var call = awaited.operation as CallExpressionSyntax;
			if (call != null && call.identifier.spelling () == "payload_io") {
				if (!function.async_body.runtime.linux || call.receiver != null || call.receiver_place != null || call.type_arguments.length != 0 || call.arguments.length != 1 || find_function (call.identifier) != null || values.lookup ("payload_io") != null) {
					fail (call.span, "payload_io requires the nominated Linux provider and one direct unique payload owner");
					return null;
				}
				var name = call.arguments[0] as NameExpressionSyntax;
				var local = name == null ? null : values.lookup (name.identifier.spelling ()) as LocalSymbol;
				if (local == null || !local.is_owned || local.cleanup == null || !AsyncPayloadTypes.matches (local.semantic_type, local.cleanup.external_symbol)) {
					fail (call.span, "payload_io requires an exact owned LinuxPayload with its provider destructor; borrowed captures cannot suspend");
					return null;
				}
				if (!check_exception_effect (function.async_body.runtime.error_type, syntax.span)) {
					return null;
				}
				return new CheckedAsyncDelay (syntax.span, function.async_body, new CheckedLocalReferenceExpression (name.span, local), true);
			}
			if (call == null || (call.identifier.spelling () != "delay_ticks" && call.identifier.spelling () != "delay_ms")) {
				var operation = check_task_await (awaited, values);
				return operation == null ? null : new CheckedTaskAwaitStatement (syntax.span, operation);
			}
			if ((call.identifier.spelling () == "delay_ms") != function.async_body.runtime.linux) {
				fail (call.span, "delay units do not match the exact nominated provider");
				return null;
			}
			if (call.receiver != null || call.receiver_place != null || call.type_arguments.length != 0 || call.arguments.length != 1) {
				fail (awaited.span, "virtual delay requires one direct logical tick operand");
				return null;
			}
			if (find_function (call.identifier) != null || values.lookup (call.identifier.spelling ()) != null) {
				fail (call.span, "virtual delay nomination conflicts with an ordinary callable or binding");
				return null;
			}
			var ticks = check_expression (call.arguments[0], values, types.int_type);
			if (ticks == null) {
				return null;
			}
			if (ticks.semantic_type != types.u32_type && ticks.semantic_type != types.int_type) {
				fail (ticks.span, "virtual delay requires int or u32 logical ticks");
				return null;
			}
			if (!check_exception_effect (function.async_body.runtime.error_type, syntax.span)) {
				return null;
			}
			return new CheckedAsyncDelay (syntax.span, function.async_body, ticks);
		}
		var exchange = syntax as SwapStatementSyntax;
		if (exchange != null) {
			if (active_with.length != 0) {
				fail (syntax.span, "with receiver scope excludes buffer exchange");
				return null;
			}
			var left = check_buffer_owner_slot (exchange.left, values);
			if (left == null) {
				return null;
			}
			var right = check_buffer_owner_slot (exchange.right, values);
			if (right == null) {
				return null;
			}
			if (left.place.semantic_type != right.place.semantic_type) {
				fail (syntax.span, "swap requires the same exact canonical owned buffer type; equal layout or possible equal generic arguments are insufficient");
				return null;
			}
			return new CheckedOwnedBufferExchange (syntax.span, left, right);
		}
		if (syntax is ConstantDeclarationSyntax) {
			return check_local_constant ((ConstantDeclarationSyntax) syntax, values);
		}
		var release = syntax as ReleaseStatementSyntax;
		if (release != null) {
			var owner = values.lookup (release.owner.spelling ()) as LocalSymbol;
			if (owner != null && owner.scoped_backing != null) {
				fail (release.span, "scoped context retirement is tied to its lexical backing loan");
				return null;
			}
			if (owner != null && owner.is_buffer_owner && !scoped_backing_access (owner, values.region, release.span)) {
				return null;
			}
			if (owner != null && owner.is_record_owner) {
				fail (release.span, "explicit owning record release is deferred; cleanup occurs at scope exit");
				return null;
			}
			if (owner == null || (!owner.heap_object && !owner.is_buffer_owner && (owner.cleanup == null || !owner.semantic_type.is_ownable_handle_type ()))) {
				fail (release.owner.span, "release operand '%s' must be an owned void* local".printf (release.owner.spelling ()));
				return null;
			}
			if (active_object_receivers.find (owner)) {
				fail (release.span, "cannot release an active receiver or foreach collection");
				return null;
			}
			return new CheckedOwnershipRelease (release.span, owner);
		}
		if (syntax is BreakStatementSyntax || syntax is ContinueStatementSyntax) {
			var keyword = (syntax is BreakStatementSyntax) ? ((BreakStatementSyntax) syntax).keyword : ((ContinueStatementSyntax) syntax).keyword;
			if (active_loops.length == 0) {
				fail (keyword.span, "'%s' is only valid inside a loop".printf (keyword.spelling ()));
				return null;
			}
			var target = active_loops[active_loops.length - 1];
			if (field_state != null) {
				if (field_state.reachable && syntax is BreakStatementSyntax) {
					constructor_breaks.insert (target, target);
				}
				field_state.reachable = false;
			}
			return (syntax is BreakStatementSyntax) ? (CheckedStatement) new CheckedBreak (syntax.span, target) : new CheckedContinue (syntax.span, target);
		}
		var call = syntax as CallStatementSyntax;
		if (call != null) {
			if (call.call.receiver == null && call.call.receiver_place == null && (call.call.identifier.spelling () == "actor_send" || call.call.identifier.spelling () == "actor_shutdown" || call.call.identifier.spelling () == "actor_cancel")) {
				return check_actor_send (call.call, values);
			}
			if (call.call.identifier.spelling () == "volatile_store" && call.call.receiver == null && call.call.receiver_place == null) {
				if (call.call.arguments.length != 2 || call.call.type_arguments.length != 0) {
					fail (syntax.span, "volatile_store requires one typed memory place and one exact value");
					return null;
				}
				var target = check_volatile_place (call.call.arguments[0], values);
				if (target == null) {
					return null;
				}
				var value = check_expression (call.call.arguments[1], values, target.semantic_type);
				if (value == null) {
					return null;
				}
				if (value.semantic_type != target.semantic_type) {
					fail (value.span, "volatile_store requires an exact u32 or u64 value without reinterpretation");
					return null;
				}
				return new CheckedStore (syntax.span, target, value, new VolatileAccessContract (target.semantic_type));
			}
			if (slots_call (call.call, values) && ((OwnerSlotsType) field_context_type ((FieldAccessExpressionSyntax) call.call.receiver_place, values)).element is StructType) {
				var operation = call.call;
				bool replace = operation.identifier.spelling () == "replace";
				if ((operation.identifier.spelling () != "append" && !replace) || operation.arguments.length != (replace ? 2 : 1) || operation.type_arguments.length != 0) {
					fail (syntax.span, "record slots require append(value) or replace(index, value)");
					return null;
				}
				var store = check_slots_place (operation.receiver_place, values);
				if (store == null || !slots_mutation (store, syntax.span)) {
					return null;
				}
				var index = replace ? check_slot_operand (store, operation.arguments[0], values) : null;
				if (replace && (index == null || index.semantic_type != types.int_type)) {
					if (diagnostic == null) {
						fail (syntax.span, "record slot index requires int/i32");
					}
					return null;
				}
				var producer = check_struct_producer (operation.arguments[replace ? 1 : 0], values, ((OwnerSlotsType) store.semantic_type).element);
				if (producer != null && producer.contract.mode == StructValueMode.MOVE_VALUE && !(producer is CheckedStructMoveProducer)) {
					fail (syntax.span, "owning record slot insertion requires one explicit named whole-record move");
					return null;
				}
				return producer == null ? null : new CheckedSlotsRecordTransfer (syntax.span, store, index, producer);
			}
			if (slots_call (call.call, values) && call.call.identifier.spelling () == "replace") {
				var operation = call.call;
				if (operation.arguments.length != 2 || !(operation.arguments[1] is MoveExpressionSyntax) || operation.type_arguments.length != 0) {
					fail (syntax.span, "owner-slot replace requires index and move exact_heap_owner");
					return null;
				}
				var store = check_slots_place (operation.receiver_place, values);
				if (store == null || !slots_mutation (store, syntax.span)) {
					return null;
				}
				var index = check_slot_operand (store, operation.arguments[0], values);
				if (index == null) {
					return null;
				}
				if (index.semantic_type != types.int_type) {
					fail (index.span, "owner-slot replace index requires int/i32");
					return null;
				}
				var incoming = check_move ((MoveExpressionSyntax) operation.arguments[1], values);
				if (incoming == null) {
					return null;
				}
				if ((incoming.semantic_type is ClassType && !incoming.source.heap_object) || incoming.semantic_type != ((OwnerSlotsType) store.semantic_type).element) {
					fail (syntax.span, "owner-slot replace requires sole ownership of the exact heap ClassType or Resource");
					return null;
				}
				return new CheckedSlotsReplace (syntax.span, store, index, incoming);
			}
			if (slots_call (call.call, values)) {
				var store = check_slots_place (call.call.receiver_place, values);
				if (store == null) {
					return null;
				}
				if (call.call.identifier.spelling () != "append" || call.call.arguments.length != 1 || !(call.call.arguments[0] is MoveExpressionSyntax)) {
					fail (syntax.span, "owner-slot statement requires append(move exact_heap_owner); reserve returns a bool value");
					return null;
				}
				if (!slots_mutation (store, syntax.span)) {
					return null;
				}
				var incoming = check_move ((MoveExpressionSyntax) call.call.arguments[0], values);
				if (incoming == null) {
					return null;
				}
				if ((incoming.semantic_type is ClassType && !incoming.source.heap_object) || incoming.semantic_type != ((OwnerSlotsType) store.semantic_type).element) {
					fail (syntax.span, "owner-slot append requires sole ownership of the exact heap ClassType or Resource");
					return null;
				}
				return new CheckedSlotsAppend (syntax.span, store, incoming);
			}
			if (call.call.receiver_place is FieldAccessExpressionSyntax && !indexed_member_projection (call.call.receiver_place) && !(place_context_type (call.call.receiver_place, values) is ClassType)) {
				fail (syntax.span, "method invocation on a nested struct subobject is unsupported");
				return null;
			}
			var indirect_binding = call.call.receiver == null && call.call.receiver_place == null ? values.lookup(call.call.identifier.spelling ()) : null;
			SemanticType? indirect_type = (indirect_binding is LocalSymbol) ? ((LocalSymbol) indirect_binding).semantic_type : (indirect_binding is ParameterSymbol) ? ((ParameterSymbol) indirect_binding).semantic_type : null;
			if (indirect_type is FunctionValueType || call.call.receiver == null && call.call.receiver_place == null && call.call.identifier.spelling () == "closure_invoke") {
				var value = check_value_call (call.call, values, false, false, true) as CheckedExpression;
				if (value == null) {
					return null;
				}
				if (value.semantic_type.kind != TypeKind.VOID && !FunctionValueType.scalar (value.semantic_type)) {
					fail (syntax.span, "indirect call discard requires its complete value or ownership consumer");
					return null;
				}
				return new CheckedValueStatement (syntax.span, value);
			}
			if (async_operation_call (call.call, values)) {
				var operation = check_async_operation (call.call, values, false) as CheckedAsyncOperation;
				return operation == null ? null : new CheckedAsyncOperationStatement (syntax.span, operation);
			}
			if (call.call.identifier.spelling () == "store_vector" && call.call.receiver == null && call.call.receiver_place == null) {
				var operation = check_vector_memory (call.call, values, true);
				return operation == null ? null : new CheckedVectorMemoryStatement (syntax.span, operation);
			}
			DirectCallableSymbol? target;
			CheckedExpression? receiver;
			GenericArray<SemanticType> type_arguments;
			var arguments = check_call (call.call, values, false, out target, out receiver, out type_arguments, false, true);
			if (arguments != null && target.return_type.is_struct_storage ()) {
				fail (syntax.span, "struct call result requires a bounded initialization, assignment, argument, or return consumer");
				return null;
			}
			if (arguments == null) {
				return null;
			}
			if (target is GenericFunctionSymbol) {
				return new CheckedGenericCallStatement (syntax.span, (GenericFunctionSymbol) target, type_arguments, arguments);
			}
			var statement = new CheckedCallStatement (syntax.span, target, arguments, receiver);
			statement.discard_owned_success = target is FunctionSymbol && ((FunctionSymbol) target).result_contract == ResultOwnershipContract.OWNED_TRANSFER;
			return statement;
		}
		var aggregate = syntax as StructLocalDeclarationSyntax;
		if (aggregate != null) {
			return check_struct_local (aggregate, values, locals);
		}
		var indexed_assignment = syntax as IndexedAssignmentSyntax;
		if (indexed_assignment != null) {
			var target = check_indexed_place (indexed_assignment.target, values, false);
			if (target == null) {
				return null;
			}
			var slice_place = target as CheckedSliceElementPlace;
			if (slice_place != null && slice_place.slice_type.element_access != SliceElementAccess.READ_WRITE) {
				fail (target.span, "text slice descriptor elements are read-only; slot assignment is unsupported");
				return null;
			}
			var field_borrow = slice_place == null ? null : slice_place.slice as CheckedOwnedFieldBorrow;
			if (field_borrow != null && with_overlap (field_borrow.field.containing_type.semantic_type)) {
				fail (syntax.span, "with receiver excludes overlapping buffer mutation");
				return null;
			}
			if (field_borrow != null) {
				pending_field_borrows.add (field_borrow.field.containing_type.semantic_type);
			}
			if (target.semantic_type.is_struct_storage ()) {
				var copy = check_struct_copy (syntax.span, target, indexed_assignment.expression, values);
				if (field_borrow != null) {
					pending_field_borrows.remove_index (pending_field_borrows.length - 1);
				}
				return copy;
			}
			var value = check_expression (indexed_assignment.expression, values, target.semantic_type);
			if (field_borrow != null) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			}
			if (value == null) {
				return null;
			}
			if (value.semantic_type != target.semantic_type) {
				fail (value.span, "expected assignment value of type '%s', found '%s'".printf (target.semantic_type.display_name (), value.semantic_type.display_name ()));
				return null;
			}
			return new CheckedStore (syntax.span, target, value);
		}
		var dereference_assignment = syntax as DereferenceAssignmentSyntax;
		if (dereference_assignment != null) {
			var target = check_dereference (dereference_assignment.target, values, true);
			if (target == null) {
				return null;
			}
			if (target.semantic_type.is_struct_storage ()) {
				return check_struct_copy (syntax.span, target, dereference_assignment.expression, values);
			}
			var value = check_expression (dereference_assignment.expression, values, target.semantic_type);
			if (value == null) {
				return null;
			}
			if (value.semantic_type != target.semantic_type) {
				fail (value.span, "expected assignment value of type '%s', found '%s'".printf (target.semantic_type.display_name (), value.semantic_type.display_name ()));
				return null;
			}
			return new CheckedStore (syntax.span, target, value);
		}
		var field_assignment = syntax as FieldAssignmentStatementSyntax;
		if (field_assignment != null) {
			var imported = imported_property_call (field_assignment.target, values, field_assignment.expression);
			if (imported != null) {
				return check_statement (new CallStatementSyntax (imported, field_assignment.semicolon), function, values, locals);
			}
			if (diagnostic != null) {
				return null;
			}
			var changed_type = field_assignment.target.aggregate == null ? scope_member_type(field_assignment.target.identifier, values) : place_context_type (field_assignment.target.aggregate, values);
			if (changed_type != null && with_overlap (changed_type)) {
				fail (syntax.span, "with receiver scope forbids potentially overlapping field/property mutation");
				return null;
			}
			var property = resolve_property (field_assignment.target, values);
			if (property != null) {
				return check_property_set (field_assignment, property, values);
			}
			var record_replace = check_record_replace (field_assignment, values);
			if (record_replace != null || diagnostic != null) {
				return record_replace;
			}
			var field_type = field_context_type (field_assignment.target, values);
			if (field_type != null && field_type.is_struct_storage ()) {
				var destination = check_field_place (field_assignment.target, values, false);
				if (destination == null) {
					return null;
				}
				var receiver_field = destination as CheckedReceiverFieldPlace;
				bool initializes = field_state != null && receiver_field != null;
				if (initializes && field_state.is_possible (receiver_field.field.ordinal)) {
					fail (syntax.span, "constructor record field may be initialized only once");
					return null;
				}
				var copy = check_struct_copy (syntax.span, destination, field_assignment.expression, values, initializes);
				if (copy != null && initializes) {
					field_state.initialize (receiver_field.field.ordinal);
				}
				return copy;
			}
			var target = check_field (field_assignment.target, values, false);
			if (target == null) {
				return null;
			}
			var target_load = target as CheckedLoadExpression;
			var receiver_field = target_load == null ? null : target_load.source as CheckedReceiverFieldPlace;
			var object_field = target_load == null ? null : target_load.source as CheckedObjectFieldPlace;
			var owner_field = receiver_field != null ? receiver_field.field : object_field == null ? null : object_field.field;
			if (owner_field != null && owner_field.text_snapshot && (field_state == null || receiver_field == null)) {
				fail (syntax.span, "readonly text snapshot can only be initialized once by its owning init");
				return null;
			}
			if (owner_field != null && owner_field.semantic_type is OwnerSlotsType) {
				var empty = field_assignment.expression as BufferAllocationSyntax;
				var marker = empty == null ? null : empty.count as NameExpressionSyntax;
				if (empty == null || empty.failure_call != null || marker == null || marker.identifier.spelling () != "slots" || resolve_type (empty.element_type) != ((OwnerSlotsType) owner_field.semantic_type).element || field_state == null || receiver_field == null || active_loops.length != 0 || field_state.is_possible (owner_field.ordinal)) {
					fail (syntax.span, "owner-slot descriptor requires one exact empty initialization by its constructor outside loops; replacement is unsupported");
					return null;
				}
				field_state.initialize (owner_field.ordinal);
				return new CheckedSlotsInitialize (syntax.span, target_load.source);
			}
			if (owner_field != null && owner_field.is_owned_field) {
				if (owner_field.requires_nonnull && checking_function != null && !nonnull_definitions.find (checking_function)) {
					nonnull_definitions.add (checking_function);
				}
				var move = field_assignment.expression as MoveExpressionSyntax;
				allocation_containers.add (owner_field.containing_type.semantic_type);
				if (owner_field.owns_child) {
					pending_field_borrows.add (owner_field.containing_type.semantic_type);
				}
				var incoming = move == null ? check_expression(field_assignment.expression, values, owner_field.semantic_type, OwnershipUse.ACQUIRE) : check_move (move, values);
				if (owner_field.owns_child) {
					pending_field_borrows.remove_index (pending_field_borrows.length - 1);
				}
				allocation_containers.remove_index (allocation_containers.length - 1);
				if (incoming == null) {
					return null;
				}
				if (owner_field.owns_child) {
					var transferred = incoming as CheckedOwnershipMove;
					var produced = incoming as CheckedCallExpression;
					var producer = produced == null ? null : produced.target as FunctionSymbol;
					if (incoming.semantic_type != owner_field.semantic_type || (transferred != null ? !transferred.source.heap_object : producer == null || producer.result_contract != ResultOwnershipContract.OWNED_TRANSFER || !producer.heap_result)) {
						fail (incoming.span, "owned child field transfer requires an explicit move or direct owned result of the exact heap ClassType");
						return null;
					}
				} else if (incoming.semantic_type != owner_field.semantic_type || (owner_field.owns_buffer ? incoming.owns_buffer == false : incoming.owned_cleanup != owner_field.owned_cleanup || (!(incoming is CheckedOwnershipMove) && !(incoming is CheckedInvocation)))) {
					fail (incoming.span, "owned field transfer requires an explicit move or direct owned result with the exact Resource type and cleanup contract");
					return null;
				}
				bool initializes = field_state != null && receiver_field != null;
				if (initializes) {
					if (active_loops.length > 0) {
						fail (syntax.span, "owned field initialization inside a loop is unsupported");
						return null;
					}
					if (field_state.is_possible (owner_field.ordinal)) {
						fail (syntax.span, "constructor '%s.init': owned field '%s' is possibly initialized twice".printf (owner_field.containing_type.name, owner_field.name));
						return null;
					}
					field_state.initialize (owner_field.ordinal);
				}
				return new CheckedOwnedFieldTransfer (syntax.span, target_load.source, owner_field, incoming, initializes);
			}
			var destination_borrow = target_load == null ? null : place_field_borrow (target_load.source);
			if (destination_borrow != null) {
				pending_field_borrows.add (destination_borrow.field.containing_type.semantic_type);
			}
			var expression = check_expression (field_assignment.expression, values, target.semantic_type);
			if (destination_borrow != null) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			}
			if (expression == null) {
				return null;
			}
			if (expression.semantic_type != target.semantic_type) {
				fail (expression.span, "expected assignment value of type '%s', found '%s'".printf (target.semantic_type.display_name (), expression.semantic_type.display_name ()));
				return null;
			}
			var indirect = target as CheckedIndirectFieldReference;
			if (indirect != null) {
				return new CheckedIndirectFieldAssignment (syntax.span, indirect.pointer, indirect.field, expression);
			}
			if (field_state != null && target is CheckedLoadExpression && ((CheckedLoadExpression) target).source is CheckedReceiverFieldPlace) {
				var place = (CheckedReceiverFieldPlace) ((CheckedLoadExpression) target).source;
				if (active_loops.length > 0) {
					fail (syntax.span, "constructor '%s.init': field '%s' initialization inside a loop is unsupported".printf (place.field.containing_type.name, place.field.name));
					return null;
				}
				if (field_state.is_possible (place.field.ordinal)) {
					fail (syntax.span, "constructor '%s.init': field '%s' is possibly initialized twice".printf (place.field.containing_type.name, place.field.name));
					return null;
				}
				field_state.initialize (place.field.ordinal);
				return new CheckedFieldInitialize (syntax.span, place, expression);
			}
			if (target is CheckedLoadExpression) {
				return new CheckedStore (syntax.span, ((CheckedLoadExpression) target).source, expression);
			}
			var direct = (CheckedFieldReferenceExpression) target;
			return new CheckedFieldAssignment (syntax.span, direct.local, direct.field, expression);
		}
		if (syntax is InferredLocalDeclarationSyntax) {
			return check_inferred_local ((InferredLocalDeclarationSyntax) syntax, values, locals);
		}
		if (syntax is LocalDeclarationSyntax) {
			var declaration = (LocalDeclarationSyntax) syntax;
			var local_type = resolve_contract_type (declaration.type_name, values);
			if (local_type is CallbackType) {
				fail (declaration.span, "Callback is call-scoped and cannot initialize a local");
				return null;
			}
			if (local_type == null) {
				return null;
			}
			if (scoped_allocator_binding (declaration.initializer, values)) {
				if (declaration.owned_keyword == null) {
					fail (declaration.span, "scoped context declaration requires owned or var inference");
					return null;
				}
				return check_scoped_allocator_binding (declaration.span, declaration.name, (CallExpressionSyntax) declaration.initializer, local_type, values, locals);
			}
			if (local_type.is_scoped_allocator ()) {
				fail (declaration.span, "scoped context requires a direct lexical scoped_allocator binding");
				return null;
			}
			if (local_type is ClassType && ((ClassType) local_type).intrinsically_shared) {
				var inferred = new InferredLocalDeclarationSyntax (new Token (TokenKind.VAR, declaration.type_name.span), declaration.name, declaration.equals_token, declaration.initializer, declaration.semicolon);
				var result = check_inferred_local (inferred, values, locals);
				var bound = values.lookup (declaration.name.spelling ()) as LocalSymbol;
				if (result != null && (bound == null || bound.semantic_type != local_type || !bound.heap_object)) {
					fail (declaration.span, "Shared Class local requires an exact owning heap reference");
					return null;
				}
				return result;
			}
			var field_move = declaration.initializer as MoveExpressionSyntax;
			if (field_move != null && field_move.fields.length != 0) {
				if (declaration.owned_keyword == null) {
					fail (field_move.span, "record field take requires an owned destination or var inference");
					return null;
				}
				return check_record_take (declaration.span, declaration.name, field_move, local_type, values, locals);
			}
			if (declaration.initializer is HeapObjectConstructionSyntax) {
				if (declaration.owned_keyword == null) {
					fail (declaration.span, "new class construction requires an owned destination or var inference");
					return null;
				}
				return check_heap_local (syntax.span, declaration.name.span, (HeapObjectConstructionSyntax) declaration.initializer, local_type, values, locals);
			}
			if (declaration.initializer is MoveExpressionSyntax && local_type is ClassType && declaration.owned_keyword != null) {
				var move = (MoveExpressionSyntax) declaration.initializer;
				var candidate = values.lookup (move.source.spelling ()) as LocalSymbol;
				if (candidate == null || !candidate.heap_object) {
					fail (declaration.initializer.span, "owned ClassType local requires fresh object construction; null, aliases and local owner moves are unsupported");
					return null;
				}
				var previous = values.lookup (declaration.name.spelling ());
				if (previous != null) {
					fail (declaration.name.span, (previous is ParameterSymbol) ? "local '%s' conflicts with parameter".printf (declaration.name.spelling ()) : "duplicate local '%s'".printf (declaration.name.spelling ()));
					return null;
				}
				var incoming = check_move ((MoveExpressionSyntax) declaration.initializer, values);
				if (incoming == null) {
					return null;
				}
				if (!incoming.source.heap_object || incoming.semantic_type != local_type) {
					fail (incoming.span, "class local move requires an independently owned heap object of the exact class");
					return null;
				}
				var local = new LocalSymbol (syntax.span, declaration.name.span, local_type, locals.length, values.region, null, null, incoming.object_owner);
				local.heap_object = true;
				locals.add (local);
				values.insert (local.name, local);
				return new CheckedOwnedLocalDeclaration (syntax.span, local, incoming);
			}
			if (local_type.is_text_slice () && declaration.owned_keyword != null) {
				fail (declaration.span, "owned string slices are unsupported");
				return null;
			}
			if (local_type is TypeParameterType && (declaration.owned_keyword != null || ((TypeParameterType) local_type).transport_mode == GenericTransportMode.OWNABLE)) {
				if (declaration.owned_keyword != null) {
					return check_generic_owner_local (declaration.span, declaration.name, declaration.initializer, local_type, values, locals);
				}
				fail (declaration.span, "generic owned locals and plain Ownable T locals are deferred; owned T is permitted only in function parameters and results");
				return null;
			}
			if (declaration.owned_keyword != null && !local_type.is_ownable_handle_type () && !(local_type is ClassType) && !(local_type is SliceType)) {
				fail (declaration.type_name.span, "OWN-1 supports 'owned' only on local 'void*' declarations");
				return null;
			}
			if (local_type == types.void_type) {
				fail (declaration.type_name.span, "local type cannot be 'void'");
				return null;
			}
			string name = declaration.name.spelling ();
			var previous = values.lookup (name);
			if (previous != null) {
				fail (declaration.name.span, (previous is ParameterSymbol) ? "local '%s' conflicts with parameter".printf (name) : "duplicate local '%s'".printf (name));
				return null;
			}
			if (local_type is EnumType) {
				var incoming = check_enum_producer (declaration.initializer, values, (EnumType) local_type);
				if (incoming == null) {
					return null;
				}
				var local = new LocalSymbol (syntax.span, declaration.name.span, local_type, locals.length, values.region);
				locals.add (local);
				values.insert (name, local);
				return new CheckedEnumStore (syntax.span, local, incoming, true);
			}
			if (local_type is SliceType && declaration.owned_keyword != null) {
				var incoming = check_buffer_producer (declaration.initializer, values, (SliceType) local_type);
				if (incoming == null) {
					return null;
				}
				var local = new LocalSymbol (declaration.span, declaration.name.span, local_type, locals.length, values.region, null, null, null, true);
				locals.add (local);
				values.insert (name, local);
				return new CheckedOwnedLocalDeclaration (syntax.span, local, incoming);
			}
			if (local_type is ArrayType) {
				var array = (ArrayType) local_type;
				var positional = declaration.initializer as ArrayInitializerSyntax;
				if (positional == null) {
					fail (declaration.initializer.span, "array local requires a complete positional initializer; whole-array copying is unsupported");
					return null;
				}
				if (positional.elements.length != array.length) {
					fail (positional.span, "array initializer requires exactly %d elements, found %u".printf (array.length, positional.elements.length));
					return null;
				}
				if (array.element_type.is_struct_storage ()) {
					var records = new GenericArray<CheckedArrayRecordEntry> ();
					foreach (var entry in positional.elements) {
						if (entry is ArrayStructInitializerSyntax) {
							var initializer = check_struct_initializer (((ArrayStructInitializerSyntax) entry).initializer, array.element_type, values);
							if (initializer == null) {
								return null;
							}
							records.add (new CheckedArrayRecordEntry.named (initializer));
						} else {
							var producer = check_struct_producer (entry, values, array.element_type);
							if (producer == null) {
								return null;
							}
							records.add (new CheckedArrayRecordEntry.produced (producer));
						}
					}
					var local = new LocalSymbol (declaration.span, declaration.name.span, local_type, locals.length, values.region);
					locals.add (local);
					values.insert (name, local);
					return new CheckedArrayLocalDeclaration.record_entries (syntax.span, local, records);
				}
				var elements = new GenericArray<CheckedExpression> ();
				foreach (var element in positional.elements) {
					var value = check_expression (element, values, array.element_type);
					if (value == null) {
						return null;
					}
					if (value.semantic_type != array.element_type) {
						fail (value.span, "array element expects initializer of type '%s', found '%s'".printf (array.element_type.display_name (), value.semantic_type.display_name ()));
						return null;
					}
					elements.add (value);
				}
				var local = new LocalSymbol (declaration.span, declaration.name.span, local_type, locals.length, values.region);
				locals.add (local);
				values.insert (name, local);
				return new CheckedArrayLocalDeclaration (syntax.span, local, elements);
			}
			var constructor_call = declaration.initializer as CallExpressionSyntax;
			if (constructor_call != null && constructor_call.receiver != null && constructor_call.identifier.spelling () == "init" && (constructor_call is ConstructorInitializerSyntax || local_type is ClassType)) {
				var owner = qualified_class (constructor_call);
				if (owner == null || owner.semantic_type != local_type || constructor_call.member_operator.kind != TokenKind.DOT || values.lookup (constructor_call.receiver.spelling ()) != null) {
					fail (constructor_call.span, "construction initializer requires exact ClassName.init for the fresh class local");
					return null;
				}
				if (((ClassType) owner.semantic_type).is_interface) {
					fail (constructor_call.span, "interface is a borrowed contract and cannot be constructed");
					return null;
				}
				if (owner.constructor == null) {
					fail (constructor_call.span, "class '%s' has no explicit init constructor".printf (owner.name));
					return null;
				}
				var arguments = check_arguments (constructor_call, values, owner.constructor, false);
				if (arguments == null) {
					return null;
				}
				var storage = new LexicalObjectStorageSymbol (syntax.span, declaration.name.span, owner, next_object_ordinal++, values.region);
				storage.cleanup_rank = (int) locals.length;
				var local = new LocalSymbol (syntax.span, declaration.name.span, local_type, locals.length, values.region, null, null, declaration.owned_keyword == null ? null : owner);
				if (local.object_owner != null) {
					local.object_storage = storage;
				}
				locals.add (local);
				values.insert (name, local);
				return new CheckedConstructorObjectInitialization (syntax.span, storage, local, owner.constructor, arguments);
			}
			if (local_type is ClassType && declaration.owned_keyword != null && declaration.initializer is CallExpressionSyntax && slots_call ((CallExpressionSyntax) declaration.initializer, values) && ((CallExpressionSyntax) declaration.initializer).identifier.spelling () == "take") {
				var take = check_value_call ((CallExpressionSyntax) declaration.initializer, values, true) as CheckedSlotsTake;
				if (take == null) {
					return null;
				}
				if (take.semantic_type != local_type) {
					fail (take.span, "owner-slot take requires an exact ClassType destination");
					return null;
				}
				var local = new LocalSymbol (syntax.span, declaration.name.span, local_type, locals.length, values.region, null, null, take.element);
				local.heap_object = true;
				locals.add (local);
				values.insert (name, local);
				return new CheckedOwnedLocalDeclaration (syntax.span, local, take);
			}
			if (local_type is ClassType && declaration.owned_keyword != null && declaration.initializer is CallExpressionSyntax) {
				var initializer = check_expression (declaration.initializer, values, local_type, OwnershipUse.ACQUIRE);
				if (initializer == null) {
					return null;
				}
				var invocation = initializer as CheckedInvocation;
				var producer = invocation == null ? null : invocation.result_producer ();
				if (initializer.semantic_type != local_type || producer == null || producer.object_owner == null) {
					fail (initializer.span, "owned object acquisition requires an owned result of the exact ClassType");
					return null;
				}
				var direct = initializer as CheckedCallExpression;
				var owner = producer.object_owner;
				bool heap = direct == null || owned_call_heap_result (direct);
				LexicalObjectStorageSymbol? candidate = null;
				if (!heap) {
					candidate = new LexicalObjectStorageSymbol (syntax.span, declaration.name.span, owner, next_object_ordinal++, values.region);
					candidate.result_candidate = true;
				}
				if (direct != null) {
					direct.candidate_storage = candidate;
				}
				var local = new LocalSymbol (syntax.span, declaration.name.span, local_type, locals.length, values.region, null, null, owner);
				local.heap_object = heap;
				locals.add (local);
				values.insert (name, local);
				return new CheckedOwnedLocalDeclaration (syntax.span, local, initializer);
			}
			if (local_type is ClassType && declaration.owned_keyword != null) {
				fail (declaration.initializer.span, "owned ClassType local requires fresh object construction; null, aliases and local owner moves are unsupported");
				return null;
			}
			// Fresh local identity is not visible in its own initializer.
			if (owning_record_field (local_type) != null) {
				if ((declaration.initializer is CallExpressionSyntax || declaration.initializer is AwaitExpressionSyntax) && declaration.owned_keyword == null) {
					var producer = check_struct_producer (declaration.initializer, values, local_type);
					if (producer == null) {
						return null;
					}
					var local = new LocalSymbol (syntax.span, declaration.name.span, local_type, locals.length, values.region);
					local.record_owner = owning_record_field (local_type);
					record_all_events (GenericOwnershipEventKind.ACQUIRE, local, syntax.span);
					locals.add (local);
					values.insert (name, local);
					return new CheckedStructResultStore (syntax.span, new CheckedLocalPlace (declaration.name.span, local), producer, true);
				}
				var record_move = declaration.initializer as MoveExpressionSyntax;
				if (record_move == null || declaration.owned_keyword != null) {
					fail (syntax.span, "owning record copy is forbidden; use a fresh whole-local move destination");
					return null;
				}
				return check_record_move (syntax.span, declaration.name, record_move, local_type, values, locals);
			}
			var move = declaration.initializer as MoveExpressionSyntax;
			if (move != null && declaration.owned_keyword == null) {
				fail (move.span, "'move' requires a fresh 'owned void*' local destination");
				return null;
			}
			if (local_type.is_struct_storage ()) {
				var local = new LocalSymbol (declaration.span, declaration.name.span, local_type, locals.length, values.region);
				var copy = check_struct_copy (syntax.span, new CheckedLocalPlace (declaration.name.span, local), declaration.initializer, values, true);
				if (copy == null) {
					return null;
				}
				locals.add (local);
				values.insert (name, local);
				return copy;
			}
			var initializer = (declaration.initializer is VectorInitializerSyntax) ? check_vector_initializer ((VectorInitializerSyntax) declaration.initializer, values, local_type) : move == null ? check_expression(declaration.initializer, values, local_type, declaration.owned_keyword == null ? OwnershipUse.UNMANAGED : OwnershipUse.ACQUIRE) : check_move (move, values);
			if (initializer == null) {
				return null;
			}
			if (initializer.semantic_type != local_type) {
				fail (initializer.span, "expected initializer of type '%s', found '%s'".printf (local_type.display_name (), initializer.semantic_type.display_name ()));
				return null;
			}
			CForeignCleanupContract? cleanup = null;
			if (declaration.owned_keyword != null) {
				if (initializer.owned_cleanup == null || (!(initializer is CheckedInvocation) && !(initializer is CheckedOwnershipMove) && !(initializer is CheckedSharedOperation) && !(initializer is CheckedClosureBind))) {
					fail (initializer.span, "owned local requires a direct foreign owned-result call with an explicit cleanup contract");
					return null;
				}
				cleanup = initializer.owned_cleanup;
			}
			var local = new LocalSymbol (declaration.span, declaration.name.span, local_type, locals.length, values.region, cleanup);
			if (!require_storable_borrow (initializer, local)) {
				return null;
			}
			locals.add (local);
			values.insert (name, local);
			return cleanup == null ? (CheckedStatement) new CheckedLocalDeclaration (syntax.span, local, initializer) : new CheckedOwnedLocalDeclaration (syntax.span, local, initializer);
		}
		if (syntax is AssignmentStatementSyntax) {
			var assignment = (AssignmentStatementSyntax) syntax;
			foreach (var contract in active_with) {
				if (values.lookup (assignment.name.spelling ()) == contract.source) {
					fail (syntax.span, "with receiver cannot be reassigned or rearmed while its scoped view is live");
					return null;
				}
			}
			string name = assignment.name.spelling ();
			var target = values.lookup (name);
			if (assignment.name.kind == TokenKind.THIS) {
				if (check_this (assignment.name.span, values) != null) {
					fail (assignment.name.span, "'this' cannot be rebound; the implicit receiver is not an assignable local");
				}
				return null;
			}
			if (!(target is LocalSymbol)) {
				if (target is ConstantSymbol) {
					fail (assignment.name.span, "constant '%s' is not mutable storage".printf (name));
				} else if (target is ParameterSymbol) {
					fail (assignment.name.span, "assignment to parameter '%s' is not supported".printf (name));
				} else if (function_names.contains (name) || types.resolve (name) != null || named_types.contains (name)) {
					fail (assignment.name.span, "name '%s' is not an assignable local".printf (name));
				} else {
					fail (assignment.name.span, "unknown assignment target '%s'".printf (name));
				}
				return null;
			}
			var local = (LocalSymbol) target;
			if (local.scoped_backing != null) {
				fail (assignment.span, "scoped context cannot replace or transfer its lexical backing loan");
				return null;
			}
			if (local.is_buffer_owner && !scoped_backing_access (local, values.region, assignment.span)) {
				return null;
			}
			if (sequence_sources.find (local)) {
				fail (assignment.name.span, "foreach cannot rebind or replace its active sequence");
				return null;
			}
			if (local.is_enum_parameter && !EnumValueAuthority.owns (enum_definition_for ((EnumType) local.semantic_type), enum_definition_for)) {
				fail (assignment.name.span, "by-value enum parameter storage is read-only; copy to a local before mutation");
				return null;
			}
			if (local.is_struct_parameter) {
				fail (assignment.name.span, "by-value struct parameter storage is read-only; copy to a local before mutation");
				return null;
			}
			if (local.catch_borrow) {
				fail (assignment.name.span, "catch binding is a read-only borrowed exception");
				return null;
			}
			if (local.object_owner != null) {
				fail (assignment.name.span, "owned ClassType binding '%s' cannot be rebound; only explicit consuming move is supported".printf (name));
				return null;
			}
			if (local.semantic_type is ArrayType) {
				fail (assignment.name.span, "whole-array assignment is unsupported; assign an element");
				return null;
			}
			if (local.is_buffer_owner) {
				var incoming = check_buffer_producer (assignment.expression, values, (SliceType) local.semantic_type);
				if (incoming == null) {
					return null;
				}
				if (incoming is CheckedOwnershipMove && ((CheckedOwnershipMove) incoming).source == local) {
					fail (incoming.span, "self-move replacement is unsupported");
					return null;
				}
				return new CheckedOwnedBufferReplace (syntax.span, local, incoming);
			}
			if (local.cleanup != null) {
				string producer_error = (local.semantic_type is HandleType) ? "owned value '%s' cannot be reassigned: rearming requires a direct native or foreign owned-result call" : "owned local '%s' cannot be reassigned: rearming requires a direct foreign owned-result call";
				var direct = assignment.expression;
				while (direct is ParenthesizedExpressionSyntax) {
					direct = ((ParenthesizedExpressionSyntax) direct).expression;
				}
				if (direct is MoveExpressionSyntax && local.semantic_type is HandleType) {
					var incoming = check_move ((MoveExpressionSyntax) direct, values);
					if (incoming == null) {
						return null;
					}
					if (incoming.source == local) {
						fail (direct.span, "self-move replacement is unsupported");
						return null;
					}
					if (incoming.semantic_type != local.semantic_type || incoming.cleanup != local.cleanup) {
						fail (direct.span, "owner replacement requires the exact Resource type and cleanup authority");
						return null;
					}
					return new CheckedOwnershipRearmAssignment (syntax.span, local, incoming);
				}
				var producer_syntax = direct as CallExpressionSyntax;
				if (producer_syntax == null) {
					fail (assignment.expression.span, producer_error.printf (name));
					return null;
				}
				var producer = check_expression (producer_syntax, values, local.semantic_type, OwnershipUse.ACQUIRE);
				if (producer == null) {
					return null;
				}
				if (producer.owned_cleanup == null) {
					fail (producer.span, producer_error.printf (name));
					return null;
				}
				if (producer.semantic_type != local.semantic_type) {
					fail (producer.span, "expected rearm value of type '%s', found '%s'".printf (local.semantic_type.display_name (), producer.semantic_type.display_name ()));
					return null;
				}
				if (producer.owned_cleanup != local.cleanup) {
					fail (producer.span, "owned value '%s' cannot be rearmed with a different cleanup contract (expected '%s', producer uses '%s')".printf (name, local.cleanup.external_symbol, producer.owned_cleanup.external_symbol));
					return null;
				}
				return new CheckedOwnershipRearmAssignment (syntax.span, local, producer);
			}
			if (local.semantic_type is EnumType) {
				if (local.enum_inspection_root != null || enum_inspections.find (local) || enum_reservations.find (local)) {
					fail (syntax.span, "enum inspection prevents replacement");
					return null;
				}
				var move = assignment.expression as MoveExpressionSyntax;
				if (move != null && move.source.spelling () == local.name) {
					fail (syntax.span, "direct enum self-move is unsupported");
					return null;
				}
				var incoming = check_enum_producer (assignment.expression, values, (EnumType) local.semantic_type);
				return incoming == null ? null : new CheckedEnumStore (syntax.span, local, incoming, false);
			}
			if (local.semantic_type.is_struct_storage ()) {
				return check_struct_copy (syntax.span, new CheckedLocalPlace (assignment.name.span, local), assignment.expression, values);
			}
			var expression = check_expression (assignment.expression, values, local.semantic_type);
			if (expression == null) {
				return null;
			}
			if (expression.semantic_type != local.semantic_type) {
				fail (expression.span, "expected assignment value of type '%s', found '%s'".printf (local.semantic_type.display_name (), expression.semantic_type.display_name ()));
				return null;
			}
			if (!require_storable_borrow (expression, local)) {
				return null;
			}
			return new CheckedAssignment (syntax.span, local, expression);
		}
		if (syntax is ReturnStatementSyntax) {
			if (function is ConstructorSymbol) {
				fail (syntax.span, "constructor explicit return is unsupported; completion must be body fallthrough");
				return null;
			}
			var returned = (ReturnStatementSyntax) syntax;
			if (returned.expression == null) {
				if (function.return_type != types.void_type) {
					fail (returned.keyword.span, "return requires a value of type '%s'".printf (function.return_type.display_name ()));
					return null;
				}
				return new CheckedReturnStatement (returned.span, null);
			}
			if (function.return_type == types.void_type) {
				fail (returned.expression.span, "cannot return a value from a 'void' function");
				return null;
			}
			if (function.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				var projection = returned.expression as FieldAccessExpressionSyntax;
				if (!(function is PropertyGetterSymbol) || projection == null || projection.identifier.kind != TokenKind.THIS || projection.aggregate != null || projection.indirect) {
					fail (returned.span, "receiver borrow result is restricted to its exact owned-field property projection");
					return null;
				}
				if (function.return_type.is_struct_storage ()) {
					var place = check_field_place (projection, values) as CheckedReceiverFieldPlace;
					if (place == null || !self_receiver (place.receiver, function.implicit_receiver) || !place.field.owns_record || place.semantic_type != function.return_type) {
						fail (returned.span, "receiver record borrow requires the exact complete owning receiver field");
						return null;
					}
					return new CheckedStructReturn (returned.span, new CheckedStructBorrowSnapshot (returned.span, place));
				}
				var load = check_field (projection, values) as CheckedLoadExpression;
				var field = load == null ? null : load.source as CheckedReceiverFieldPlace;
				if (field == null || !self_receiver (field.receiver, function.implicit_receiver) || !field.field.is_owned_field || field.field.owns_buffer || field.semantic_type != function.return_type) {
					fail (returned.span, "receiver borrow cannot return a temporary, unrelated owner or incompatible field");
					return null;
				}
				return new CheckedReturnStatement (returned.span, load);
			}
			if (function.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
				if (function.return_type is SliceType) {
					var incoming = check_buffer_producer (returned.expression, values, (SliceType) function.return_type);
					if (incoming == null) {
						return null;
					}
					var transfer = incoming as CheckedOwnershipMove;
					return new CheckedOwnershipReturn (returned.span, function.return_type, null, transfer, null, transfer == null ? incoming : null);
				}
				if (function.return_type is TypeParameterType) {
					return check_generic_owned_return (returned, function, values);
				}
				if (function.result_class != null) {
					return check_object_return (returned, function, values);
				}
				var move_syntax = returned.expression as MoveExpressionSyntax;
				if (move_syntax == null && !(returned.expression is NullPointerExpressionSyntax)) {
					fail (returned.expression.span, "owned result requires 'return move owner' or 'return null'; bare values and direct owned-call chaining do not transfer responsibility");
					return null;
				}
				bool previous_capture = enum_buffer_capture;
				enum_buffer_capture = true;
				var transfer = move_syntax == null ? null : check_move (move_syntax, values);
				enum_buffer_capture = previous_capture;
				if (move_syntax != null && transfer == null) {
					return null;
				}
				if (transfer != null && (transfer.semantic_type != function.return_type || transfer.cleanup != function.owned_cleanup)) {
					fail (returned.expression.span, "owned return requires exact type '%s' and its cleanup contract, found '%s'".printf (function.return_type.display_name (), transfer.semantic_type.display_name ()));
					return null;
				}
				return new CheckedOwnershipReturn (returned.span, (HandleType) function.return_type, function.owned_cleanup, transfer);
			}
			if (function.return_type is EnumType) {
				var incoming = check_enum_producer (returned.expression, values, (EnumType) function.return_type);
				return incoming == null ? null : new CheckedEnumReturn (syntax.span, incoming);
			}
			if (function.struct_result_contract != null) {
				var producer = check_struct_producer (returned.expression, values, function.return_type);
				return producer == null ? null : new CheckedStructReturn (returned.span, producer);
			}
			var expression = check_expression (returned.expression, values, function.return_type);
			if (expression == null) {
				return null;
			}
			if (expression.semantic_type != function.return_type) {
				fail (returned.expression.span, "expected return value of type '%s', found '%s'".printf (function.return_type.display_name (), expression.semantic_type.display_name ()));
				return null;
			}
			return new CheckedReturnStatement (returned.span, expression);
		}
		assert_not_reached ();
	}

	private CheckedOwnershipReturn? check_object_return(ReturnStatementSyntax syntax, FunctionSymbol function, ValueScope values) {
		var storage = function.result_storage;
		var object_class = function.result_class;
		CheckedExpression? producer = null;
		CheckedOwnershipMove? transfer = null;
		var call = syntax.expression as CallExpressionSyntax;
		if (call != null && call.receiver != null && call.identifier.spelling () == "init") {
			if (function.heap_result && !unreachable_return_origin) {
				fail (call.span, "heap-origin factory cannot construct into lexical caller storage");
				return null;
			}
			if (qualified_class (call) != object_class || values.lookup (call.receiver.spelling ()) != null || call.member_operator.kind != TokenKind.DOT) {
				fail (call.span, "return construction requires exact result ClassName.init");
				return null;
			}
			if (object_class.constructor == null) {
				fail (call.span, "class has no explicit init constructor");
				return null;
			}
			var arguments = check_arguments (call, values, object_class.constructor, false);
			if (arguments == null) {
				return null;
			}
			if (!unreachable_return_origin) {
				producer = new CheckedOwnedObjectResultConstruction (call.span, storage, object_class.constructor, arguments);
			}
		} else if (call != null) {
			var forwarded = check_expression (call, values, function.return_type, OwnershipUse.ACQUIRE) as CheckedCallExpression;
			if (forwarded == null) {
				return null;
			}
			if (forwarded.semantic_type != function.return_type || forwarded.owned_producer == null || forwarded.owned_producer.object_owner != object_class) {
				fail (call.span, "forwarded result requires an owned result of the exact ClassType");
				return null;
			}
			if (!unreachable_return_origin && !deferred_class_result (function) && owned_call_heap_result (forwarded) != function.heap_result) {
				fail (call.span, "forwarded owned result changed its resolved allocation origin");
				return null;
			}
			foreach (var argument in forwarded.arguments) {
				var owned_argument = argument as CheckedOwnedArgument;
				if (owned_argument != null && owned_argument.object_owner == object_class && owned_argument.transfer != null && !owned_argument.transfer.source.object_provenance.is_returnable ()) {
					fail (argument.span, "callee-local owned ObjectStorage cannot escape through a forwarded owned result; use direct return ClassName.init(...) instead");
					return null;
				}
			}
			forwarded.result_storage = owned_call_heap_result (forwarded) ? null : storage;
			producer = forwarded;
		} else if (syntax.expression is MoveExpressionSyntax) {
			transfer = check_move ((MoveExpressionSyntax) syntax.expression, values);
			if (transfer == null) {
				return null;
			}
			if (transfer.semantic_type != function.return_type && !(function.heap_result && transfer.source.heap_object && ((ClassType) transfer.semantic_type).derives_from ((ClassType) function.return_type))) {
				fail (transfer.span, "owned return requires exact lexical storage or a heap subtype of the result ClassType");
				return null;
			}
			if (!unreachable_return_origin && !deferred_class_result (function) && transfer.source.heap_object != function.heap_result) {
				fail (transfer.span, "owned return changed its resolved heap or caller-backed storage origin");
				return null;
			}
			if (!transfer.source.object_provenance.is_returnable ()) {
				fail (transfer.span, "callee-local owned ObjectStorage cannot escape through an owned result; use direct return ClassName.init(...) instead");
				return null;
			}
		} else if (!(syntax.expression is NullPointerExpressionSyntax)) {
			fail (syntax.expression.span, "owned object result requires direct construction, owned-result forwarding, move of an owned parameter, or null; fixed and borrowed references (including this) cannot transfer ownership");
			return null;
		}
		// All type and escape checks above remain binding in a dead arm.
		// Its result transport is erased before Core; it has no callable ABI.
		return new CheckedOwnershipReturn (syntax.span, function.return_type, null, unreachable_return_origin ? null : transfer, object_class, unreachable_return_origin ? null : producer);
	}

	private CheckedExpression? check_vector_initializer(VectorInitializerSyntax syntax, ValueScope values, SemanticType expected) {
		var vector = expected as VectorType;
		if (vector == null) {
			fail (syntax.span, "positional initializer requires a vector local type");
			return null;
		}
		if (syntax.lanes.length != vector.lane_count) {
			fail (syntax.span, "vector initializer for '%s' requires exactly %d lanes, found %u".printf (vector.display_name (), vector.lane_count, syntax.lanes.length));
			return null;
		}
		var lanes = new GenericArray<CheckedExpression> ();
		foreach (var lane in syntax.lanes) {
			var expression = check_expression (lane, values, vector.element_type);
			if (expression == null) {
				return null;
			}
			if (expression.semantic_type != vector.element_type) {
				fail (lane.span, "vector lane expects exact type '%s', found '%s'".printf (vector.element_type.display_name (), expression.semantic_type.display_name ()));
				return null;
			}
			lanes.add (expression);
		}
		return new CheckedVectorConstructExpression (syntax.span, vector, lanes);
	}

	// Local inference authority: check one initializer without a destination
	// type, then select an existing concrete local/storage/ownership contract.
	// Struct Places and COPY_VALUE producers retain their separate domain.
	private bool scoped_allocator_binding(ExpressionSyntax syntax, ValueScope values) {
		var call = syntax as CallExpressionSyntax;
		return call != null && call.receiver == null && call.receiver_place == null && call.identifier.spelling () == "scoped_allocator" && find_function (call.identifier) == null && values.lookup (call.identifier.spelling ()) == null;
	}
	private bool scoped_backing_access(LocalSymbol owner, LexicalRegion region, SourceSpan span) {
		if (pending_scoped_backings.find (owner)) {
			fail (span, "scoped backing is reserved throughout context argument evaluation");
			return false;
		}
		foreach (var context in scoped_contexts) {
			if (context.scoped_backing.backing_ordinal == owner.ordinal && context.scoped_backing.region_ordinal == context.lexical_region.ordinal && context.lexical_region.outlives (region) && context.span.file == span.file && context.span.start <= span.start) {
				fail (span, "buffer backing remains exclusively borrowed until the scoped context exits");
				return false;
			}
		}
		return true;
	}
	private CheckedStatement? check_scoped_allocator_binding(SourceSpan span, Token name, CallExpressionSyntax call, SemanticType? expected, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (values.lookup (name.spelling ()) != null) {
			fail (name.span, "duplicate scoped context binding");
			return null;
		}
		if (checking_function == null || checking_function.async_body != null || call.type_arguments.length != 1 || call.arguments.length != 3 || !(call.arguments[0] is NameExpressionSyntax)) {
			fail (call.span, "scoped_allocator requires a synchronous named binding, one scoped allocator type and (named owned byte backing, kind, slots)");
			return null;
		}
		var type = resolve_type (call.type_arguments[0]) as HandleType;
		if (type == null) {
			if (diagnostic == null) {
				fail (call.span, "scoped_allocator requires an exact context handle type");
			}
			return null;
		}
		if (type.context_mode != "scoped-affine" || type.context_cleanup != "astra_context17_destroy" || !handle_types.contains (type) || expected != null && expected != type) {
			fail (call.span, "scoped allocator type requires the exact borrowed backing and null-safe runtime destruction contract");
			return null;
		}
		var backing = values.lookup (((NameExpressionSyntax) call.arguments[0]).identifier.spelling ()) as LocalSymbol;
		var bytes = backing == null ? null : backing.semantic_type as SliceType;
		if (backing == null || !backing.is_buffer_owner || bytes == null || bytes.element_type.kind != TypeKind.U8 || !backing.lexical_region.outlives (values.region)) {
			fail (call.arguments[0].span, "scoped allocator backing requires a named complete owned u8 buffer with an enclosing lifetime");
			return null;
		}
		if (!scoped_backing_access (backing, values.region, call.span)) {
			return null;
		}
		pending_scoped_backings.add (backing);
		var kind = check_expression (call.arguments[1], values, types.int_type);
		var slots = kind == null ? null : check_expression (call.arguments[2], values, types.int_type);
		pending_scoped_backings.remove_index (pending_scoped_backings.length - 1);
		if (kind == null || slots == null) {
			return null;
		}
		if (kind.semantic_type != types.int_type || slots.semantic_type != types.int_type) {
			fail (call.span, "scoped allocator kind and slots require int values");
			return null;
		}
		var loan = new ScopedBackingLoan ((int) locals.length, backing.ordinal, values.region.ordinal);
		var cleanup = handle_types.lookup (type).cleanup;
		var local = new LocalSymbol (span, name.span, type, locals.length, values.region, cleanup);
		local.scoped_backing = loan;
		var initializer = new CheckedScopedAllocator (call.span, type, loan, backing, kind, slots, cleanup);
		if (generic_owner_flow != null) {
			generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, backing, backing.name, call.span);
		}
		locals.add (local);
		values.insert (local.name, local);
		scoped_contexts.add (local);
		return new CheckedOwnedLocalDeclaration (span, local, initializer);
	}
	private CheckedStatement? check_inferred_local(InferredLocalDeclarationSyntax syntax, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (scoped_allocator_binding (syntax.initializer, values)) {
			return check_scoped_allocator_binding (syntax.span, syntax.name, (CallExpressionSyntax) syntax.initializer, null, values, locals);
		}
		var imported = imported_property_call (syntax.initializer, values);
		if (imported != null) {
			return check_inferred_local (new InferredLocalDeclarationSyntax (syntax.keyword, syntax.name, syntax.equals_token, imported, syntax.semicolon), values, locals);
		}
		var implicit_source = syntax.initializer as NameExpressionSyntax;
		var implicit_owner = implicit_source == null ? null : values.lookup (implicit_source.identifier.spelling ()) as LocalSymbol;
		if (implicit_owner != null && implicit_owner.is_owned && (implicit_owner.semantic_type is ClosureHandleType && ((ClosureHandleType) implicit_owner.semantic_type).actor || implicit_owner.semantic_type is SharedHandleType || implicit_owner.semantic_type is ClassType && ((ClassType) implicit_owner.semantic_type).intrinsically_shared)) {
			var transfer = new MoveExpressionSyntax (new Token (TokenKind.MOVE, implicit_source.span), implicit_source.identifier);
			return check_inferred_local (new InferredLocalDeclarationSyntax (syntax.keyword, syntax.name, syntax.equals_token, transfer, syntax.semicolon), values, locals);
		}
		var field_move = syntax.initializer as MoveExpressionSyntax;
		if (field_move != null && field_move.fields.length != 0) {
			return check_record_take (syntax.span, syntax.name, field_move, null, values, locals);
		}
		var record_move = syntax.initializer as MoveExpressionSyntax;
		var record_source = record_move == null ? null : values.lookup (record_move.source.spelling ()) as LocalSymbol;
		if (record_source != null && record_source.is_record_owner) {
			return check_record_move (syntax.span, syntax.name, record_move, null, values, locals);
		}
		if (record_source != null && record_source.is_generic_owner) {
			return check_generic_owner_local (syntax.span, syntax.name, syntax.initializer, record_source.semantic_type, values, locals);
		}
		string name = syntax.name.spelling ();
		var previous = values.lookup (name);
		if (previous != null) {
			fail (syntax.name.span, (previous is ParameterSymbol) ? "local '%s' conflicts with parameter".printf (name) : "duplicate local '%s'".printf (name));
			return null;
		}
		var task_call = syntax.initializer as CallExpressionSyntax;
		var task_target = task_call == null || task_call.receiver != null ? null : find_function (task_call.identifier) as FunctionSymbol;
		if ((task_target == null || task_target.async_body == null) && enum_context_type (syntax.initializer, values) != null) {
			var incoming = check_enum_producer (syntax.initializer, values);
			if (incoming == null) {
				return null;
			}
			var local = new LocalSymbol (syntax.span, syntax.name.span, incoming.semantic_type, locals.length, values.region);
			locals.add (local);
			values.insert (name, local);
			return new CheckedEnumStore (syntax.span, local, incoming, true);
		}
		var direct = syntax.initializer;
		while (direct is ParenthesizedExpressionSyntax) {
			direct = ((ParenthesizedExpressionSyntax) direct).expression;
		}
		var property_access = (direct is TextMemberExpressionSyntax) ? expression_member ((TextMemberExpressionSyntax) direct) : (direct as FieldAccessExpressionSyntax);
		var record_type = property_access == null ? null : field_context_type (property_access, values);
		if (record_type != null && record_type.is_struct_storage ()) {
			var producer = check_struct_producer (direct, values, record_type);
			if (producer == null) {
				return null;
			}
			var local = new LocalSymbol (syntax.span, syntax.name.span, producer.semantic_type, locals.length, values.region);
			locals.add (local);
			values.insert (name, local);
			var snapshot = producer as CheckedStructSnapshot;
			if (snapshot != null && producer.contract.mode == StructValueMode.COPY_VALUE) {
				return new CheckedStructCopy (syntax.span, new CheckedLocalPlace (syntax.name.span, local), snapshot.source,
					producer.semantic_type, producer.copyability, true);
			}
			return new CheckedStructResultStore (syntax.span, new CheckedLocalPlace (syntax.name.span, local), producer, true);
		}
		// Only the complete, direct ClassName.init form constructs storage.
		// An ordinary struct method named init remains an ordinary expression.
		var constructor = syntax.initializer as CallExpressionSyntax;
		var owner = constructor == null || constructor.receiver == null || constructor.identifier.spelling () != "init" ? null : qualified_class (constructor);
		if (owner != null && values.lookup (constructor.receiver.spelling ()) == null) {
			if (((ClassType) owner.semantic_type).intrinsically_shared) {
				fail (constructor.span, "intrinsic shared construction requires independent heap storage via new");
				return null;
			}
			if (((ClassType) owner.semantic_type).is_interface) {
				fail (constructor.span, "interface is a borrowed contract and cannot be constructed");
				return null;
			}
			if (owner.constructor == null) {
				fail (constructor.span, "class '%s' has no explicit init constructor".printf (owner.name));
				return null;
			}
			var arguments = check_arguments (constructor, values, owner.constructor, false);
			if (arguments == null) {
				return null;
			}
			var storage = new LexicalObjectStorageSymbol (syntax.span, syntax.name.span, owner, next_object_ordinal++, values.region);
			storage.cleanup_rank = (int) locals.length;
			var local = new LocalSymbol (syntax.span, syntax.name.span, owner.semantic_type, locals.length, values.region, null, null, owner);
			local.object_storage = storage;
			locals.add (local);
			values.insert (name, local);
			return new CheckedConstructorObjectInitialization (syntax.span, storage, local, owner.constructor, arguments);
		}
		var indexed = direct as IndexExpressionSyntax;
		var indexed_slots = indexed == null || !(indexed.container is FieldAccessExpressionSyntax) ? null : field_context_type ((FieldAccessExpressionSyntax) indexed.container, values) as OwnerSlotsType;
		if (indexed_slots != null && indexed_slots.element.is_struct_storage ()) {
			var producer = check_slots_record_index ((IndexExpressionSyntax) direct, values);
			if (producer == null) {
				return null;
			}
			var local = new LocalSymbol (syntax.span, syntax.name.span, producer.semantic_type, locals.length, values.region);
			locals.add (local);
			values.insert (name, local);
			return new CheckedStructResultStore (syntax.span, new CheckedLocalPlace (syntax.name.span, local), producer, true);
		}
		CheckedPlace? place = null;
		if (direct is NameExpressionSyntax) {
			var source = values.lookup (((NameExpressionSyntax) direct).identifier.spelling ()) as LocalSymbol;
			if (source != null && source.semantic_type.is_struct_storage ()) {
				place = new CheckedLocalPlace (direct.span, source);
			}
		} else if (direct is FieldAccessExpressionSyntax) {
			var type = field_context_type ((FieldAccessExpressionSyntax) direct, values);
			if (type != null && type.is_struct_storage ()) {
				place = check_field_place ((FieldAccessExpressionSyntax) direct, values);
				if (place == null) {
					return null;
				}
			}
		} else if (direct is IndexExpressionSyntax && (place_context_type (direct, values) ?? types.void_type).is_struct_storage ()) {
			place = check_indexed_place ((IndexExpressionSyntax) direct, values);
			if (place == null) {
				return null;
			}
		} else if (direct is DereferenceExpressionSyntax) {
			place = check_dereference ((DereferenceExpressionSyntax) direct, values, true);
			if (place == null) {
				return null;
			}
		}
		if (place != null && place.semantic_type.is_struct_storage ()) {
			var type = place.semantic_type;
			if (!check_copyable_type (type, direct.span)) {
				return null;
			}
			var local = new LocalSymbol (syntax.span, syntax.name.span, type, locals.length, values.region);
			locals.add (local);
			values.insert (name, local);
			return new CheckedStructCopy (syntax.span, new CheckedLocalPlace (syntax.name.span, local), place, type, Copyability.COPYABLE, true);
		}
		CheckedNode? checked;
		if (direct is HeapObjectConstructionSyntax) {
			return check_heap_local (syntax.span, syntax.name.span, (HeapObjectConstructionSyntax) direct, null, values, locals);
		}
		var call = direct as CallExpressionSyntax;
		if (call != null && call.identifier.kind != TokenKind.SLICE && call.identifier.kind != TokenKind.LEN) {
			checked = check_value_call (call, values, true, true);
		} else if (direct is AwaitExpressionSyntax) {
			checked = check_await_producer ((AwaitExpressionSyntax) direct, values);
		} else if (place != null) {
			checked = new CheckedLoadExpression (direct.span, place);
		} else if (direct is MoveExpressionSyntax) {
			var source = values.lookup (((MoveExpressionSyntax) direct).source.spelling ()) as LocalSymbol;
			checked = source != null && (source.semantic_type is TaskType) ? (CheckedExpression) new CheckedTaskMove (direct.span, source) : check_move ((MoveExpressionSyntax) direct, values);
		} else {
			checked = check_expression (direct, values, null, OwnershipUse.ACQUIRE);
		}
		if (checked == null) {
			return null;
		}
		if (checked is CheckedEnumProducer) {
			var incoming = (CheckedEnumProducer) checked;
			if (incoming.semantic_type.is_parameterized ()) {
				fail (syntax.span, "unresolved enum locals require an explicit applied type");
				return null;
			}
			var local = new LocalSymbol (syntax.span, syntax.name.span, incoming.semantic_type, locals.length, values.region);
			locals.add (local);
			values.insert (name, local);
			return new CheckedEnumStore (syntax.span, local, incoming, true);
		}
		var structure = checked as CheckedStructProducer;
		if (structure != null) {
			var local = new LocalSymbol (syntax.span, syntax.name.span, structure.semantic_type, locals.length, values.region);
			if (structure.contract.mode == StructValueMode.MOVE_VALUE) {
				if (!record_context (syntax.span)) {
					return null;
				}
				local.record_owner = owning_record_field (local.semantic_type);
				record_all_events (GenericOwnershipEventKind.ACQUIRE, local, syntax.span);
			}
			locals.add (local);
			values.insert (name, local);
			return new CheckedStructResultStore (syntax.span, new CheckedLocalPlace (syntax.name.span, local), structure, true);
		}
		var initializer = (CheckedExpression) checked;
		var type = initializer.semantic_type;
		if (type.is_scoped_allocator ()) {
			fail (syntax.span, "scoped context requires a direct lexical scoped_allocator binding");
			return null;
		}
		if (type is CallbackType) {
			fail (syntax.span, "Callback is call-scoped and cannot initialize a local");
			return null;
		}
		if (ownable_parameter (type)) {
			return check_generic_owner_local (syntax.span, syntax.name, syntax.initializer, type, values, locals, initializer);
		}
		if (type.is_parameterized () && !(type is TypeParameterType)) {
			fail (syntax.initializer.span, "cannot infer a concrete local type from an unresolved type parameter; write an explicit type");
			return null;
		}
		var move = initializer as CheckedOwnershipMove;
		if (move != null && move.object_owner != null && !move.source.heap_object) {
			fail (initializer.span, "owned ClassType local requires fresh object construction; null, aliases and local owner moves are unsupported");
			return null;
		}
		var producer = initializer as CheckedCallExpression;
		var invocation = initializer as CheckedInvocation;
		var owned_producer = invocation == null ? null : invocation.result_producer ();
		var take = initializer as CheckedSlotsTake;
		var intrinsic_producer = initializer is CheckedSharedOperation && type is ClassType && ((ClassType) type).intrinsically_shared;
		var object_owner = intrinsic_producer ? instance_for (type) as ClassSymbol : take != null ? take.element : move != null && move.source.heap_object ? move.object_owner : owned_producer == null ? null : owned_producer.object_owner;
		var local = new LocalSymbol (syntax.span, syntax.name.span, type, locals.length, values.region, initializer.owned_cleanup, null, object_owner, initializer.owns_buffer);
		local.heap_object = intrinsic_producer || take != null && take.element != null || (move != null && move.source.heap_object) || (owned_producer != null && owned_producer.object_owner != null && (producer == null || owned_call_heap_result (producer)));
		if (object_owner != null && !local.heap_object) {
			var candidate = new LexicalObjectStorageSymbol (syntax.span, syntax.name.span, object_owner, next_object_ordinal++, values.region);
			candidate.result_candidate = true;
			producer.candidate_storage = candidate;
		}
		if (!local.is_owned && !require_storable_borrow (initializer, local)) {
			return null;
		}
		locals.add (local);
		values.insert (name, local);
		return local.is_owned ? (CheckedStatement) new CheckedOwnedLocalDeclaration (syntax.span, local, initializer) : new CheckedLocalDeclaration (syntax.span, local, initializer);
	}

	private FieldSymbol? owning_record_field(SemanticType type, HashTable<SemanticType, bool>? seen = null) {
		var visited = seen ?? new HashTable<SemanticType, bool> (direct_hash, direct_equal);
		if (visited.contains (type)) {
			return null;
		}
		visited.insert (type, true);
		var owner = instance_for (type) as StructSymbol;
		if (owner != null) {
			foreach (var field in owner.fields) {
				if (field.is_owned_field) {
					return field;
				}
				var nested = owning_record_field (field.semantic_type, visited);
				if (nested != null) {
					return nested;
				}
			}
		}
		return null;
	}
	private bool record_context(SourceSpan span) {
		// A local becomes visible only after its complete initializer sequence.
		// Checked effects retire the acquired field prefix before publication.
		if (checking_function is GenericFunctionSymbol) {
			fail (span, "owning records require a concrete nongeneric local context");
			return false;
		}
		return true;
	}
	private void collect_record_flow_fields(CheckedPlace place, GenericArray<CheckedFieldPlace> fields) {
		foreach (var field in storage_fields (place.semantic_type)) {
			var projection = new CheckedFieldPlace (place.span, place, (StructFieldSymbol) field);
			if (field.is_owned_field) {
				fields.add (projection);
			} else if (field.semantic_type is StructType) {
				collect_record_flow_fields (projection, fields);
			}
		}
	}
	private GenericArray<CheckedFieldPlace> record_fields_for_flow(LocalSymbol local) {
		var fields = record_flow_fields.lookup (local);
		if (fields == null) {
			fields = new GenericArray<CheckedFieldPlace> ();
			collect_record_flow_fields (new CheckedLocalPlace (local.span, local), fields);
			record_flow_fields.insert (local, fields);
		}
		return fields;
	}
	private void record_root_event(GenericOwnershipEventKind kind, LocalSymbol local, SourceSpan span) {
		if (kind != GenericOwnershipEventKind.READ && pending_record_borrows.find (local)) {
			fail (span, "record ownership mutation overlaps an active borrowed record argument");
			return;
		}
		if (generic_owner_flow != null) {
			generic_owner_flow.owner_event (kind, local, local.name, span);
		}
	}
	private void record_leaf_event(GenericOwnershipEventKind kind, LocalSymbol local, CheckedFieldPlace field, SourceSpan span) {
		if (kind != GenericOwnershipEventKind.READ && pending_record_borrows.find (local)) {
			fail (span, "record field mutation overlaps an active borrowed record argument");
			return;
		}
		if (generic_owner_flow == null) {
			return;
		}
		foreach (var candidate in record_fields_for_flow (local)) {
			if (candidate.storage_path ().same_path (field.storage_path ())) {
				generic_owner_flow.owner_event (kind, candidate, local.name + "." + candidate.storage_path ().spelling (), span);
				return;
			}
		}
		assert_not_reached ();
	}
	private void record_all_events(GenericOwnershipEventKind kind, LocalSymbol local, SourceSpan span) {
		record_root_event (kind, local, span);
		foreach (var field in record_fields_for_flow (local)) {
			record_leaf_event (kind, local, field, span);
		}
	}
	private CheckedFieldPlace? record_field_path(Token root, GenericArray<Token> fields, SourceSpan span, ValueScope values) {
		var source = values.lookup (root.spelling ()) as LocalSymbol;
		if (source == null || !source.is_record_owner || fields.length == 0) {
			fail (span, "moving ownership out of an owned field requires a named owning record root");
			return null;
		}
		CheckedPlace place = new CheckedLocalPlace (root.span, source);
		for (int i = 0; i < fields.length; i++) {
			var owner = instance_for (place.semantic_type) as StructSymbol;
			var token = fields[i];
			var field = owner == null ? null : owner.find_field (token.spelling ()) as StructFieldSymbol;
			if (field == null || !field_access_allowed (field, token.span)) {
				if (diagnostic == null) {
					fail (token.span, "record ownership operation requires an exact declared field path");
				}
				return null;
			}
			place = new CheckedFieldPlace (SourceSpan.cover (root.span, token.span), place, field);
			if (i + 1 != fields.length && (field.is_owned_field || !(field.semantic_type is StructType))) {
				fail (token.span, "record ownership operation cannot traverse an identity owner or borrowed storage");
				return null;
			}
		}
		return (CheckedFieldPlace) place;
	}
	private CheckedExpression? record_incoming(FieldSymbol field, ExpressionSyntax syntax, ValueScope values) {
		var move = syntax as MoveExpressionSyntax;
		var incoming = move == null ? check_expression(syntax, values, field.semantic_type, OwnershipUse.ACQUIRE) : check_move (move, values);
		if (incoming == null) {
			return null;
		}
		if (field.owns_buffer) {
			if (!incoming.owns_buffer) {
				fail (syntax.span, "record buffer replacement requires an exact complete owner move or producer");
				return null;
			}
		} else if (field.owns_child) {
			var moved = incoming as CheckedOwnershipMove;
			var call = incoming as CheckedCallExpression;
			if (moved != null ? !moved.source.heap_object : call == null || call.owned_producer == null || !(call.target is FunctionSymbol) || !((FunctionSymbol) call.target).heap_result) {
				fail (syntax.span, "record Class replacement requires an exact heap owner move or owned factory result");
				return null;
			}
		} else if (incoming.owned_cleanup != field.owned_cleanup || (!(incoming is CheckedOwnershipMove) && !(incoming is CheckedInvocation))) {
			fail (syntax.span, "record Resource replacement requires an exact explicit owner move or direct owned producer");
			return null;
		}
		if (incoming.semantic_type != field.semantic_type) {
			fail (syntax.span, "record field replacement requires the exact original leaf type");
			return null;
		}
		return incoming;
	}
	private CheckedStatement? check_record_take(SourceSpan span, Token name, MoveExpressionSyntax move, SemanticType? expected, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (!record_context (span)) {
			return null;
		}
		if (values.lookup (name.spelling ()) != null) {
			fail (name.span, "record field take requires a fresh local name");
			return null;
		}
		var place = record_field_path (move.source, move.fields, move.span, values);
		if (place == null) {
			return null;
		}
		var field = place.field;
		if (!field.is_owned_field || (expected != null && expected != field.semantic_type)) {
			fail (place.span, "record field take requires an exact Resource, heap Class or buffer owner leaf");
			return null;
		}
		var child = field.owns_child ? instance_for (field.semantic_type) as ClassSymbol : null;
		var destination = new LocalSymbol (span, name.span, field.semantic_type, locals.length, values.region, field.owned_cleanup, null, child, field.owns_buffer);
		destination.heap_object = child != null;
		locals.add (destination);
		values.insert (name.spelling (), destination);
		var source = (LocalSymbol) values.lookup (move.source.spelling ());
		record_root_event (GenericOwnershipEventKind.READ, source, span);
		record_leaf_event (GenericOwnershipEventKind.MOVE, source, place, span);
		if (destination.is_buffer_owner && generic_owner_flow != null) {
			generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, destination, destination.name, span);
		}
		return new CheckedRecordTake (span, source, place, destination);
	}
	private CheckedStatement? check_record_replace(FieldAssignmentStatementSyntax assignment, ValueScope values) {
		var target = assignment.target;
		var fields = new GenericArray<Token> ();
		while (target.aggregate is FieldAccessExpressionSyntax) {
			fields.insert (0, target.field_name);
			target = (FieldAccessExpressionSyntax) target.aggregate;
		}
		if (target.aggregate != null || target.indirect) {
			return null;
		}
		var owner = values.lookup (target.identifier.spelling ()) as LocalSymbol;
		if (owner == null || !owner.is_record_owner) {
			return null;
		}
		fields.insert (0, target.field_name);
		var place = record_field_path (target.identifier, fields, assignment.span, values);
		if (place == null || !place.field.is_owned_field) {
			return null;
		}
		if (!record_context (assignment.span)) {
			return null;
		}
		var incoming = record_incoming (place.field, assignment.expression, values);
		if (incoming != null) {
			record_root_event (GenericOwnershipEventKind.READ, owner, assignment.span);
			record_leaf_event (GenericOwnershipEventKind.ACQUIRE, owner, place, assignment.span);
		}
		return incoming == null ? null : new CheckedRecordReplace (assignment.span, owner, place, incoming);
	}

	private CheckedStatement? check_record_move(SourceSpan span, Token name, MoveExpressionSyntax move, SemanticType? expected, ValueScope values, GenericArray<LocalSymbol> locals) {
		if (move.fields.length != 0) {
			fail (move.span, "projected owner move requires one fresh named field destination");
			return null;
		}
		var source = values.lookup (move.source.spelling ()) as LocalSymbol;
		if (source == null || !source.is_record_owner || (expected != null && expected != source.semantic_type)) {
			fail (move.span, "whole owning record move requires an exact owning local");
			return null;
		}
		if (values.lookup (name.spelling ()) != null) {
			fail (name.span, "whole owning record move requires a fresh local name");
			return null;
		}
		if (!record_context (span)) {
			return null;
		}
		var local = new LocalSymbol (span, name.span, source.semantic_type, locals.length, values.region);
		local.record_owner = source.record_owner;
		record_all_events (GenericOwnershipEventKind.MOVE, source, span);
		record_all_events (GenericOwnershipEventKind.ACQUIRE, local, span);
		locals.add (local);
		values.insert (name.spelling (), local);
		return new CheckedStructMove (span, source, local);
	}

	private CheckedStatement? check_struct_local(StructLocalDeclarationSyntax syntax, ValueScope values, GenericArray<LocalSymbol> locals) {
		var local_type = resolve_type (syntax.type_name);
		if (local_type == null) {
			return null;
		}
		var structure = instance_for (local_type);
		if (structure is ClassSymbol && ((ClassType) local_type).is_interface) {
			fail (syntax.span, "interface is a borrowed contract and cannot be constructed");
			return null;
		}
		if (syntax.owned_keyword != null && !(structure is ClassSymbol)) {
			fail (syntax.span, "owned brace construction requires an exact ClassType");
			return null;
		}
		if (structure == null && !(local_type is GenericStructApplicationType)) {
			fail (syntax.initializer.span, "named field initializer requires a struct local type");
			return null;
		}
		string name = syntax.name.spelling ();
		var previous = values.lookup (name);
		if (previous != null) {
			fail (syntax.name.span, (previous is ParameterSymbol) ? "local '%s' conflicts with parameter".printf (name) : "duplicate local '%s'".printf (name));
			return null;
		}
		if (structure is ClassSymbol && ((ClassSymbol) structure).constructor != null) {
			fail (syntax.span, "class '%s' declares init; direct brace construction cannot bypass its constructor".printf (structure.name));
			return null;
		}
		var initializer = check_struct_initializer (syntax.initializer, local_type, values);
		if (initializer == null) {
			return null;
		}
		var initializers = initializer.fields;
		var record_owner = owning_record_field (local_type);
		if (record_owner != null && !record_context (syntax.span)) {
			return null;
		}
		var local = new LocalSymbol (syntax.span, syntax.name.span, local_type, locals.length, values.region, null, null, syntax.owned_keyword == null ? null : (ClassSymbol) structure);
		local.record_owner = record_owner;
		locals.add (local);
		values.insert (name, local);
		if (structure is ClassSymbol) {
			var storage = new LexicalObjectStorageSymbol (syntax.span, syntax.name.span, (ClassSymbol) structure, next_object_ordinal++, values.region);
			storage.cleanup_rank = local.ordinal;
			if (local.object_owner != null) {
				local.object_storage = storage;
			}
			if (storage.object_class.polymorphic) {
				fail (syntax.span, "participating class construction requires an explicit init; field aggregates cannot initialize hierarchy headers or bases");
				return null;
			}
			return new CheckedObjectConstruction (syntax.span, storage, local, initializers);
		}
		if (local.is_record_owner) {
			record_all_events (GenericOwnershipEventKind.ACQUIRE, local, syntax.span);
		}
		return new CheckedStructLocalDeclaration (syntax.span, local, initializers);
	}

	private GenericArray<FieldSymbol> storage_fields(SemanticType type) {
		var result = new GenericArray<FieldSymbol> ();
		if (type is GenericStructApplicationType) {
			foreach (var field in ((GenericStructApplicationType) type).definition.fields) {
				result.add (field);
			}
		} else {
			var owner = instance_for (type);
			if (owner != null) {
				foreach (var field in owner.fields) {
					result.add (field);
				}
			}
		}
		return result;
	}

	private FieldSymbol? storage_field(SemanticType type, string name) {
		foreach (var field in storage_fields (type)) {
			if (field.name == name) {
				return field;
			}
		}
		return null;
	}
	private SemanticType storage_field_type(SemanticType owner, FieldSymbol field) {
		return (owner is GenericStructApplicationType) ? ((GenericStructApplicationType) owner).field_type ((GenericStructFieldSymbol) field) : field.semantic_type;
	}

	private GenericArray<SemanticType>? copy_fields(SemanticType type) {
		if (type is EnumType) {
			var definition = enum_definition_for ((EnumType) type);
			return definition == null ? null : definition.value_fields ();
		}
		if (!(type is GenericStructApplicationType) && !(instance_for (type) is StructSymbol)) {
			return null;
		}
		var result = new GenericArray<SemanticType> ();
		foreach (var field in storage_fields (type)) {
			result.add (storage_field_type (type, field));
		}
		return result;
	}

	private bool element_premise(TypeParameterType parameter) {
		return copy_premise (parameter) && element_obligations.establishes (parameter, GenericElementRequirements.BUFFER);
	}

	private bool copy_premise(TypeParameterType parameter) {
		var symbol = lexical_types.lookup (parameter.name);
		return symbol != null && symbol.semantic_type == parameter && symbol.transport_mode == GenericTransportMode.PLAIN_COPY;
	}

	private bool check_application_arguments(SemanticType type, SourceSpan span, int depth = 0) {
		var application = type as GenericStructApplicationType;
		if (application == null) {
			return true;
		}
		if (depth > 256) {
			fail (span, "generic type argument nesting exceeds 256");
			return false;
		}
		for (int a = 0; a < application.type_arguments.length; a++) {
			var argument = application.type_arguments[a];
			if (!check_application_arguments (argument, span, depth + 1)) {
				return false;
			}
			if (application.definition.type_parameters[a].transport_mode == GenericTransportMode.OWNABLE) {
				if (!GenericCapabilityAuthority.satisfies (argument, GenericCapabilityIdentity.OWNABLE)) {
					fail (span, "owning generic record argument lost its Ownable bound");
					return false;
				}
			} else if (!check_copyable_type (argument, span)) {
				return false;
			}
		}
		return true;
	}

	private bool check_copyable_type(SemanticType type, SourceSpan span) {
		if (GenericArgumentTypes.plain_copy (type, copy_fields, copy_premise)) {
			return true;
		}
		fail (span, "value transport requires a complete copyable field graph under exact in-scope plain-copy premises (maximum type-application depth 256)");
		return false;
	}

	private bool check_collection_element(SemanticType type, SourceSpan span) {
		if (BufferElementTypes.supports (type, copy_fields)) {
			return true;
		}
		var invalid = BufferElementTypes.invalid_field (type, copy_fields);
		var current = type;
		string path = type.display_name ();
		if (invalid != null && invalid != "") {
			foreach (var component in invalid.split (".")) {
				int ordinal = int.parse (component);
				var members = storage_fields (current);
				if (ordinal < 0 || ordinal >= members.length) {
					break;
				}
				path += "." + members[ordinal].name;
				current = storage_field_type (current, members[ordinal]);
			}
		}
		fail (span, "record collection element requires complete copyable storage, structural zero and trivial destruction; invalid field '%s' (%s)".printf (path, current.display_name ()));
		return false;
	}

	private StructValueMode struct_value_mode(SemanticType type) {
		return owning_record_field (type) == null ? StructValueMode.COPY_VALUE : StructValueMode.MOVE_VALUE;
	}

	private bool template_record(SemanticType? type) {
		return type != null && type.is_struct_storage () && specializing_class != null && specializing_class.generic_instance != null && specializing_class.generic_instance.definition.general_bodies;
	}

	private bool check_struct_boundary(SemanticType type, SourceSpan span, bool foreign, string position) {
		if (foreign) {
			fail (span, "struct function %ss are not supported yet (including C boundaries)".printf (position));
			return false;
		}
		if (type.is_parameterized ()) {
			return check_copyable_type (type, span);
		}
		if (struct_value_mode (type) == StructValueMode.MOVE_VALUE) {
			try {
				StructLeafOrder.enumerate_storage (type, copy_fields);
			} catch (StructLeafError error) {
				fail (span, error.message);
				return false;
			}
		} else if (CopyabilityAuthority.of (type, copy_fields) != Copyability.COPYABLE) {
			fail (span, "native struct boundary requires recursively copyable type '%s'".printf (type.display_name ()));
			return false;
		}
		return true;
	}

	private bool require_mutable_struct_place(CheckedPlace place, SourceSpan span) {
		while (place is CheckedFieldPlace || place is CheckedGenericStructFieldPlace) {
			place = (place is CheckedFieldPlace) ? ((CheckedFieldPlace) place).aggregate : ((CheckedGenericStructFieldPlace) place).aggregate;
		}
		var slice = place as CheckedSliceElementPlace;
		var view = slice == null ? null : slice.slice as CheckedLocalReferenceExpression;
		if (view != null && view.local.enum_inspection_root != null) {
			fail (span, "enum inspection array view is read-only");
			return false;
		}
		var local = place as CheckedLocalPlace;
		if (local != null && local.local.is_struct_parameter) {
			fail (span, "by-value struct parameter storage is read-only; copy to a local before mutation");
			return false;
		}
		return true;
	}

	private CheckedSlotsRecordRead? check_slots_record_index(IndexExpressionSyntax syntax, ValueScope values) {
		var store = check_slots_place (syntax.container, values);
		if (store == null) {
			return null;
		}
		var element = ((OwnerSlotsType) store.semantic_type).element;
		if (!(element is StructType) || !check_copyable_type (element, syntax.span)) {
			if (diagnostic == null) {
				fail (syntax.span, "indexed slot value copying requires a copyable record");
			}
			return null;
		}
		var index = check_slot_operand (store, syntax.subscript, values);
		if (index == null || index.semantic_type != types.int_type) {
			if (diagnostic == null) {
				fail (syntax.span, "record slot index requires int/i32");
			}
			return null;
		}
		return new CheckedSlotsRecordRead (syntax.span, store, index, false);
	}

	private CheckedStructProducer? check_struct_borrow(ExpressionSyntax input, ValueScope values, SemanticType expected) {
		ExpressionSyntax syntax = input;
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		if (syntax is TextMemberExpressionSyntax) {
			syntax = expression_member ((TextMemberExpressionSyntax) syntax);
		}
		var access = syntax as FieldAccessExpressionSyntax;
		var property = access == null ? null : resolve_property (access, values);
		if (property != null && property.semantic_type == expected && property.is_borrowed && property.getter.struct_result_contract != null && property.getter.struct_result_contract.mode == StructValueMode.BORROW_VALUE) {
			var observed = check_field (access, values) as CheckedPropertyGetExpression;
			return observed == null ? null : new CheckedStructCallResult (syntax.span, property.getter, new GenericArray<CheckedExpression> (), observed.receiver, Copyability.NOT_COPYABLE);
		}
		var named = syntax as NameExpressionSyntax;
		var local = named == null ? null : values.lookup (named.identifier.spelling ()) as LocalSymbol;
		bool forwarded = local != null && local.incoming_parameter != null && local.incoming_parameter.struct_value_contract != null && local.incoming_parameter.struct_value_contract.mode == StructValueMode.BORROW_VALUE;
		if (local == null || local.semantic_type != expected || (!local.is_record_owner && !forwarded)) {
			fail (syntax.span, "borrowed record requires an exact live named owner or forwarded borrowed parameter");
			return null;
		}
		if (local.is_record_owner) {
			record_all_events (GenericOwnershipEventKind.READ, local, syntax.span);
		}
		return new CheckedStructBorrowSnapshot (syntax.span, new CheckedLocalPlace (syntax.span, local));
	}

	private CheckedStructProducer? check_struct_producer(ExpressionSyntax input, ValueScope values, SemanticType expected, bool argument = false) {
		ExpressionSyntax syntax = input;
		if (!expected.is_struct_storage ()) {
			return null;
		}
		bool moving = struct_value_mode (expected) == StructValueMode.MOVE_VALUE;
		if (moving ? !record_context (syntax.span) : !check_copyable_type (expected, syntax.span)) {
			return null;
		}
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		syntax = (ExpressionSyntax?) imported_property_call (syntax, values) ?? syntax;
		if (syntax is TextMemberExpressionSyntax && (place_context_type (((TextMemberExpressionSyntax) syntax).receiver, values) ?? types.void_type).is_struct_storage ()) {
			syntax = expression_member ((TextMemberExpressionSyntax) syntax);
		}
		var move = syntax as MoveExpressionSyntax;
		if (!moving && move != null && move.fields.length == 0 && template_record (expected)) {
			syntax = new NameExpressionSyntax (move.source);
			move = null;
		}
		if (syntax is IndexExpressionSyntax && slots_candidate (((IndexExpressionSyntax) syntax).container, values)) {
			return check_slots_record_index ((IndexExpressionSyntax) syntax, values);
		}
		if (moving && argument && move == null) {
			fail (syntax.span, "MOVE_VALUE argument requires an explicit move of a named owning record");
			return null;
		}
		if (moving && move != null) {
			var source = values.lookup (move.source.spelling ()) as LocalSymbol;
			if (move.fields.length != 0 || source == null || !source.is_record_owner || source.semantic_type != expected) {
				fail (syntax.span, "record MOVE_VALUE requires an explicit whole move of the exact owning local");
				return null;
			}
			if (!argument) {
				record_all_events (GenericOwnershipEventKind.MOVE, source, syntax.span);
			}
			return new CheckedStructMoveProducer (syntax.span, source);
		}
		if (moving && !(syntax is CallExpressionSyntax || syntax is AwaitExpressionSyntax)) {
			fail (syntax.span, "owning record boundary requires explicit move or an exact MOVE_VALUE producer");
			return null;
		}
		CheckedStructProducer? producer = null;
		var call = syntax as CallExpressionSyntax;
		var access = syntax as FieldAccessExpressionSyntax;
		var property = access == null ? null : resolve_property (access, values);
		bool projected = false;
		var selection = access == null || property != null ? null : check_producer_projection (access, values, out projected);
		if (projected) {
			producer = selection as CheckedStructProducer;
			if (producer == null) {
				if (diagnostic == null) {
					fail (syntax.span, "struct projection requires an exact copied subrecord result");
				}
				return null;
			}
		} else if (property != null) {
			var observed = check_field (access, values) as CheckedPropertyGetExpression;
			if (observed == null || property.getter.struct_result_contract == null) {
				return null;
			}
			producer = new CheckedStructCallResult (syntax.span, property.getter, new GenericArray<CheckedExpression> (), observed.receiver, Copyability.COPYABLE, property.semantic_type);
		} else if (syntax is AwaitExpressionSyntax) {
			producer = check_await_producer ((AwaitExpressionSyntax) syntax, values) as CheckedStructProducer;
			if (producer == null) {
				if (diagnostic == null) {
					fail (syntax.span, "record await requires an exact copied record task result");
				}
				return null;
			}
		} else if (call != null) {
			// Intrinsics retain their ordinary value semantics even when a record
			// is expected. Do not resolve len/slice as user function names.
			bool intrinsic = call.identifier.kind == TokenKind.LEN || call.identifier.kind == TokenKind.SLICE;
			var checked = intrinsic ? check_expression (call, values) : check_value_call (call, values, false, true);
			producer = checked as CheckedStructProducer;
			if (producer == null && intrinsic && checked is CheckedExpression && diagnostic == null) {
				fail (syntax.span, "struct boundary requires exact nominal type '%s', found '%s'; equal layout is insufficient".printf (expected.display_name (), ((CheckedExpression) checked).semantic_type.display_name ()));
			}
			if (producer == null) {
				if (diagnostic == null) {
					fail (syntax.span, "struct producer requires an exact native COPY_VALUE result");
				}
				return null;
			}
		} else {
			CheckedPlace? source = null;
			if (syntax is FieldAccessExpressionSyntax) {
				source = check_field_place ((FieldAccessExpressionSyntax) syntax, values);
			} else if (syntax is IndexExpressionSyntax) {
				source = check_indexed_place ((IndexExpressionSyntax) syntax, values);
			} else if (syntax is DereferenceExpressionSyntax) {
				source = check_dereference ((DereferenceExpressionSyntax) syntax, values, true);
			} else if (syntax is NameExpressionSyntax) {
				var local = values.lookup (((NameExpressionSyntax) syntax).identifier.spelling ()) as LocalSymbol;
				if (local != null) {
					source = new CheckedLocalPlace (syntax.span, local);
				}
			}
			if (source == null) {
				if (diagnostic == null) {
					fail (syntax.span, "struct boundary requires an initialized exact StructType Place or bounded native call result");
				}
				return null;
			}
			producer = new CheckedStructSnapshot (syntax.span, source, CopyabilityAuthority.value_copy (source.semantic_type, copy_fields, copy_premise));
		}
		if (producer.semantic_type != expected) {
			fail (syntax.span, "struct boundary requires exact nominal type '%s', found '%s'; equal layout is insufficient".printf (expected.display_name (), producer.semantic_type.display_name ()));
			return null;
		}
		if (producer.contract.mode != struct_value_mode (expected)) {
			fail (syntax.span, "struct boundary producer changed its exact copy/move transport mode");
			return null;
		}
		return producer;
	}

	private CheckedBufferOwnerSlot? check_buffer_owner_slot(ExpressionSyntax syntax, ValueScope values) {
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		var name = syntax as NameExpressionSyntax;
		if (name != null) {
			var owner = values.lookup (name.identifier.spelling ()) as LocalSymbol;
			if (owner != null && owner.is_buffer_owner) {
				if (!scoped_backing_access (owner, values.region, syntax.span)) {
					return null;
				}
				if (sequence_sources.find (owner)) {
					fail (syntax.span, "foreach cannot exchange its active sequence storage");
					return null;
				}
				if (generic_owner_flow != null) {
					generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, owner, owner.name, syntax.span);
				}
				return new CheckedBufferOwnerSlot (syntax.span, new CheckedLocalPlace (syntax.span, owner), owner, null);
			}
		}
		var access = syntax as FieldAccessExpressionSyntax;
		if (access != null) {
			if (resolve_property (access, values) != null) {
				fail (syntax.span, "swap requires owning buffer storage slots; properties are not owner slots");
				return null;
			}
			var place = check_field_place (access, values);
			if (place == null) {
				return null;
			}
			StructFieldSymbol? field = (place is CheckedReceiverFieldPlace) ? ((CheckedReceiverFieldPlace) place).field : (place is CheckedObjectFieldPlace) ? ((CheckedObjectFieldPlace) place).field : null;
			if (field != null && field.owns_buffer && field.semantic_type is SliceType) {
				foreach (var container in pending_field_borrows) {
					if (container == field.containing_type.semantic_type) {
						fail (syntax.span, "swap invalidates a pending owned-field borrow through a possibly aliasing containing object");
						return null;
					}
				}
				return new CheckedBufferOwnerSlot (syntax.span, place, null, field);
			}
		}
		fail (syntax.span, "swap operands must be initialized writable owning buffer locals, consuming parameters, or native class fields; views, values, moves and other storage are unsupported");
		return null;
	}

	private void read_buffer_place(CheckedPlace place) {
		if (generic_owner_flow == null) {
			return;
		}
		if (place is CheckedFieldPlace) {
			read_buffer_place (((CheckedFieldPlace) place).aggregate);
		}
		if (place is CheckedGenericStructFieldPlace) {
			read_buffer_place (((CheckedGenericStructFieldPlace) place).aggregate);
		}
		var slice = place as CheckedSliceElementPlace;
		var borrow = slice == null ? null : slice.slice as CheckedOwnedBufferBorrow;
		if (borrow != null) {
			generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, borrow.source, borrow.source.name, place.span);
		}
	}

	private CheckedOwnedFieldBorrow? place_field_borrow(CheckedPlace place) {
		if (place is CheckedFieldPlace) {
			return place_field_borrow (((CheckedFieldPlace) place).aggregate);
		}
		if (place is CheckedGenericStructFieldPlace) {
			return place_field_borrow (((CheckedGenericStructFieldPlace) place).aggregate);
		}
		return (place is CheckedSliceElementPlace) ? ((CheckedSliceElementPlace) place).slice as CheckedOwnedFieldBorrow : null;
	}

	private CheckedStatement? check_struct_copy(SourceSpan span, CheckedPlace destination, ExpressionSyntax syntax, ValueScope values, bool initializes_destination = false) {
		var borrow = place_field_borrow (destination);
		if (borrow != null) {
			pending_field_borrows.add (borrow.field.containing_type.semantic_type);
		}
		var result = check_struct_copy_contents (span, destination, syntax, values, initializes_destination);
		if (borrow != null) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		return result;
	}

	private CheckedStatement? check_struct_copy_contents(SourceSpan span, CheckedPlace destination, ExpressionSyntax syntax, ValueScope values, bool initializes_destination) {
		var type = destination.semantic_type;
		if (!require_mutable_struct_place (destination, span)) {
			return null;
		}
		var direct = syntax;
		while (direct is ParenthesizedExpressionSyntax) {
			direct = ((ParenthesizedExpressionSyntax) direct).expression;
		}
		if (direct is TextMemberExpressionSyntax && (place_context_type (((TextMemberExpressionSyntax) direct).receiver, values) ?? types.void_type).is_struct_storage ()) {
			direct = expression_member ((TextMemberExpressionSyntax) direct);
		}
		var access = direct as FieldAccessExpressionSyntax;
		direct = (ExpressionSyntax?) imported_property_call (direct, values) ?? direct;
		access = direct as FieldAccessExpressionSyntax;
		if (access != null && resolve_property (access, values) == null) {
			bool projected;
			var selection = check_producer_projection (access, values, out projected);
			if (projected) {
				var producer = selection as CheckedStructProducer;
				if (producer == null || producer.semantic_type != type) {
					if (diagnostic == null) {
						fail (direct.span, "struct projection requires the exact nominal copied destination type");
					}
					return null;
				}
				return new CheckedStructResultStore (span, destination, producer, initializes_destination);
			}
		}
		if (direct is CallExpressionSyntax || direct is AwaitExpressionSyntax || direct is MoveExpressionSyntax || direct is FieldAccessExpressionSyntax && resolve_property ((FieldAccessExpressionSyntax) direct, values) != null) {
			var producer = check_struct_producer (direct, values, type);
			return producer == null ? null : new CheckedStructResultStore (span, destination, producer, initializes_destination);
		}
		var proof = CopyabilityAuthority.value_copy (type, copy_fields, copy_premise);
		if (proof != Copyability.COPYABLE) {
			fail (span, "struct storage '%s' is not recursively copyable".printf (type.display_name ()));
			return null;
		}
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		CheckedPlace? source = null;
		if (syntax is FieldAccessExpressionSyntax) {
			source = check_field_place ((FieldAccessExpressionSyntax) syntax, values);
		} else if (syntax is IndexExpressionSyntax) {
			source = check_indexed_place ((IndexExpressionSyntax) syntax, values);
		} else if (syntax is DereferenceExpressionSyntax) {
			source = check_dereference ((DereferenceExpressionSyntax) syntax, values, true);
		} else if (syntax is NameExpressionSyntax) {
			var name = ((NameExpressionSyntax) syntax).identifier;
			var local = values.lookup (name.spelling ()) as LocalSymbol;
			if (local == null) {
				fail (syntax.span, "struct copy source requires an initialized local Place; unknown or unsupported name '%s'".printf (name.spelling ()));
				return null;
			}
			if (local.cleanup != null || local.object_owner != null) {
				fail (syntax.span, "struct copy excludes ownership-bearing storage");
				return null;
			}
			source = new CheckedLocalPlace (syntax.span, local);
		} else {
			fail (syntax.span, initializes_destination ? "struct local requires a complete named field initializer" : "struct copy source requires an exact concrete StructType Place");
			return null;
		}
		if (source == null) {
			return null;
		}
		if (source.semantic_type != type) {
			fail (syntax.span, "struct copy requires exact nominal type '%s', found '%s'; equal layout is insufficient".printf (type.display_name (), source.semantic_type.display_name ()));
			return null;
		}
		return new CheckedStructCopy (span, destination, source, type, proof, initializes_destination);
	}

	private CheckedStructInitializer? check_struct_initializer(StructInitializerSyntax syntax, SemanticType type, ValueScope values, string path = "") {
		var initializers = new GenericArray<CheckedFieldInitializer> ();
		var seen = new HashTable<FieldSymbol, FieldSymbol> (direct_hash, direct_equal);
		foreach (var initializer in syntax.fields) {
			var field = storage_field (type, initializer.name.spelling ());
			if (field == null) {
				fail (initializer.name.span, "unknown initializer field '%s' in %s '%s'".printf (path + initializer.name.spelling (), (type is ClassType) ? "class" : "struct", type.display_name ()));
				return null;
			}
			if (!field_access_allowed (field, initializer.name.span)) {
				return null;
			}
			if (seen.contains (field)) {
				fail (initializer.name.span, "duplicate initializer for field '%s'".printf (path + field.name));
				return null;
			}
			string field_path = path + field.name;
			var field_type = storage_field_type (type, field);
			if (field_type.is_struct_storage ()) {
				if (initializer.initializer == null) {
					var producer = check_struct_producer (initializer.expression, values, field_type);
					if (producer == null) {
						return null;
					}
					initializers.add (new CheckedFieldInitializer.from_producer (initializer.span, field, producer));
				} else {
					var nested = check_struct_initializer (initializer.initializer, field_type, values, field_path + ".");
					if (nested == null) {
						return null;
					}
					initializers.add (new CheckedFieldInitializer.nested (initializer.span, field, nested));
				}
			} else {
				if (initializer.initializer != null) {
					fail (initializer.span, "nested brace initializer requires a struct-valued field: " + field_path);
					return null;
				}
				var expression = field.is_owned_field ? record_incoming (field, initializer.expression, values) : check_expression (initializer.expression, values, field_type);
				if (expression == null) {
					return null;
				}
				if (expression.semantic_type != field_type) {
					fail (expression.span, "field '%s' expects initializer of type '%s', found '%s'".printf (field_path, field_type.display_name (), expression.semantic_type.display_name ()));
					return null;
				}
				initializers.add (new CheckedFieldInitializer (initializer.span, field, expression));
			}
			seen.insert (field, field);
		}
		foreach (var field in storage_fields (type)) {
			if (!seen.contains (field)) {
				fail (syntax.close_brace.span, "missing initializer for field '%s'".printf (path + field.name));
				return null;
			}
		}
		return new CheckedStructInitializer (syntax.span, type, initializers);
	}

	private CheckedThisExpression? check_this(SourceSpan span, ValueScope values) {
		var receiver = values.lookup ("this") as ReceiverSymbol;
		if (receiver == null) {
			fail (span, "'this' is only valid inside a struct instance method");
			return null;
		}
		return new CheckedThisExpression (span, receiver);
	}

	private DirectCallableSymbol? context_callable(CallExpressionSyntax call, ValueScope values) {
		DirectCallableSymbol? function = null;
		if (call.receiver_place != null) {
			var instance = place_context_type (call.receiver_place, values);
			var structure = instance == null ? null : instance_for (instance);
			if (structure != null) {
				function = resolve_class_method (structure, call);
			}
		} else if (call.receiver == null) {
			var callable = callable_binding (call.identifier, values);
			function = callable == null ? find_function(call.identifier) : callable.find_method ("invoke");
		} else if (values.lookup (call.receiver.spelling ()) == null && module_names.contains (call.receiver.spelling ())) {
			function = function_names.lookup (resolve_name (call.identifier.span, call.receiver.spelling () + "." + call.identifier.spelling (), false));
		} else {
			var symbol = values.lookup (call.receiver.spelling ());
			SemanticType? instance = (symbol is ReceiverSymbol) ? (SemanticType) ((ReceiverSymbol) symbol).semantic_type.instance_type : (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
			var structure = instance == null ? null : instance_for (instance);
			if (structure != null) {
				function = resolve_class_method (structure, call);
			}
		}
		return function;
	}

	private SemanticType? inferred_call_context(CallExpressionSyntax call, ValueScope values) {
		var context = generic_call_contexts.lookup (call);
		if (context == null) {
			var incoming_flow = generic_owner_flow;
			SemanticOwnershipFlow? fragment = incoming_flow == null ? null : new SemanticOwnershipFlow (call.span);
			generic_owner_flow = fragment;
			var checked = check_value_call (call, values, false, true);
			generic_owner_flow = incoming_flow;
			if (checked == null) {
				return null;
			}
			context = new GenericCallContext (checked, fragment);
			generic_call_contexts.insert (call, context);
		}
		return context.semantic_type;
	}

	private SemanticType? place_context_type(ExpressionSyntax syntax, ValueScope values) {
		if (syntax is ParenthesizedExpressionSyntax) {
			return place_context_type (((ParenthesizedExpressionSyntax) syntax).expression, values);
		}
		if (syntax is TextMemberExpressionSyntax) {
			var member = (TextMemberExpressionSyntax) syntax;
			return (place_context_type (member.receiver, values) is StringType) ? types.int_type : field_context_type (expression_member (member), values);
		}
		if (syntax is CallExpressionSyntax) {
			var call = (CallExpressionSyntax) syntax;
			var target = context_callable (call, values);
			if (target == null) {
				return null;
			}
			var generic = target as GenericFunctionSymbol;
			if (generic != null && target.return_type.is_parameterized () && !ownable_parameter (target.return_type) && call.type_arguments.length == 0) {
				return inferred_call_context (call, values);
			}
			if (generic == null || call.type_arguments.length != generic.type_parameters.length) {
				return target.return_type;
			}
			var substitution = new TypeSubstitution ((element) => types.slice_of (element), types.substitute_function, substitute_class, substitute_closure);
			for (int i = 0; i < generic.type_parameters.length; i++) {
				var argument = resolve_type (call.type_arguments[i]);
				if (argument == null) {
					return null;
				}
				substitution.bind (generic.type_parameters[i].semantic_type, argument);
			}
			return substitution.apply (target.return_type);
		}
		if (syntax is FieldAccessExpressionSyntax) {
			return field_context_type ((FieldAccessExpressionSyntax) syntax, values);
		}
		if (syntax is IndexExpressionSyntax) {
			var container = place_context_type (((IndexExpressionSyntax) syntax).container, values);
			return (container is ArrayType) ? ((ArrayType) container).element_type : (container is SliceType) ? ((SliceType) container).element_type : (container is OwnerSlotsType) ? ((OwnerSlotsType) container).element : null;
		}
		if (syntax is NameExpressionSyntax) {
			var symbol = values.lookup (((NameExpressionSyntax) syntax).identifier.spelling ());
			return (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : (symbol is ReceiverSymbol) ? ((ReceiverSymbol) symbol).semantic_type.instance_type : null;
		}
		return null;
	}

	private CheckedPlace? check_place_syntax(ExpressionSyntax syntax, ValueScope values, bool read = true) {
		if (syntax is FieldAccessExpressionSyntax) {
			return check_field_place ((FieldAccessExpressionSyntax) syntax, values, read);
		}
		if (syntax is IndexExpressionSyntax) {
			return check_indexed_place ((IndexExpressionSyntax) syntax, values, read);
		}
		fail (syntax.span, "member base requires an indexed or recursive struct Place");
		return null;
	}

	private SemanticType? field_context_type(FieldAccessExpressionSyntax field, ValueScope values) {
		SemanticType? type;
		if (field.aggregate != null) {
			type = place_context_type (field.aggregate, values);
		} else {
			var symbol = values.lookup (field.identifier.spelling ());
			type = (symbol is ReceiverSymbol) ? (SemanticType) ((ReceiverSymbol) symbol).semantic_type.instance_type : (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
		}
		if (type == null) {
			return null;
		}
		if (!field.indirect) {
			var imported = imported_property_for_type (type, field.field_name.spelling ());
			if (imported != null) {
				return imported.return_type;
			}
		}
		if (field.indirect && type.is_struct_pointer ()) {
			type = ((TypedPointerType) type).pointee;
		}
		if (type is GenericStructApplicationType) {
			var member = storage_field (type, field.field_name.spelling ());
			return member == null ? null : storage_field_type (type, member);
		}
		var owner = instance_for (type);
		if (owner == null) {
			return null;
		}
		var member = owner.find_field (field.field_name.spelling ());
		var property = owner.find_property (field.field_name.spelling ());
		return property != null ? property.semantic_type : member == null ? null : member.semantic_type;
	}

	private PropertySymbol? resolve_property(FieldAccessExpressionSyntax syntax, ValueScope values) {
		if (syntax.aggregate != null) {
			var type = place_context_type (syntax.aggregate, values);
			var owner = type == null ? null : instance_for (type);
			return owner == null ? null : owner.find_property (syntax.field_name.spelling ());
		}
		var symbol = values.lookup (syntax.identifier.spelling ());
		SemanticType? type = (symbol is ReceiverSymbol) ? (SemanticType) ((ReceiverSymbol) symbol).semantic_type.instance_type : (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
		if (type is TypedPointerType) {
			type = ((TypedPointerType) type).pointee;
		}
		var owner = type == null ? null : instance_for (type);
		return owner == null ? null : owner.find_property (syntax.field_name.spelling ());
	}

	private CheckedStatement? check_property_set(FieldAssignmentStatementSyntax syntax, PropertySymbol property, ValueScope values) {
		if (property.setter == null) {
			fail (syntax.target.field_name.span, "property '%s.%s' is read-only: missing setter".printf (property.declaring_type.name, property.name));
			return null;
		}
		NativeInstanceSymbol? owner;
		var receiver = check_member_receiver (syntax.target.identifier, syntax.target.dot, syntax.target.span, values, "property", out owner, syntax.target.aggregate);
		if (receiver == null) {
			return null;
		}
		var receiver_origin = receiver;
		while (receiver_origin is CheckedClassUpcast) {
			receiver_origin = ((CheckedClassUpcast) receiver_origin).reference;
		}
		var object_receiver = receiver_origin as CheckedObjectReceiverExpression;
		var reference = object_receiver == null ? null : object_receiver.reference as CheckedLocalReferenceExpression;
		bool owned_receiver = reference != null && reference.local.object_owner != null;
		if (owned_receiver) {
			active_object_receivers.add (reference.local);
		}
		var address_receiver = receiver as CheckedReceiverAddressExpression;
		var receiver_borrow = address_receiver == null || address_receiver.receiver_place == null ? null : place_field_borrow (address_receiver.receiver_place);
		uint field_loan_depth = pending_field_borrows.length;
		uint lazy_loan_depth = pending_lazy_borrows.length;
		if (receiver_borrow != null) {
			pending_field_borrows.add (receiver_borrow.field.containing_type.semantic_type);
		}
		reserve_receiver_loans (receiver);
		var value = property.is_borrowed || property.semantic_type.is_struct_storage () ? check_argument (syntax.expression, values, property.setter.name, property.setter.parameters[0], property.semantic_type, 0) : check_expression (syntax.expression, values, property.semantic_type);
		while (pending_field_borrows.length > field_loan_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		while (pending_lazy_borrows.length > lazy_loan_depth) {
			pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
		}
		if (owned_receiver) {
			active_object_receivers.remove_index (active_object_receivers.length - 1);
		}
		if (value == null) {
			return null;
		}
		if (value.semantic_type != property.semantic_type) {
			fail (value.span, "setter for property '%s.%s' requires exact value type '%s', found '%s'".printf (owner.name, property.name, property.semantic_type.display_name (), value.semantic_type.display_name ()));
			return null;
		}
		return new CheckedPropertySetStatement (syntax.span, property, upcast_class (receiver, property.setter.receiver.semantic_type), value);
	}

	private CheckedExpression? check_text_member(SourceSpan span, ExpressionSyntax syntax, Token member, ValueScope values) {
		var receiver = check_expression (syntax, values);
		if (receiver == null) {
			return null;
		}
		if (!(receiver.semantic_type is StringType) || member.spelling () != "byte_length") {
			fail (member.span, "string supports only the read-only byte_length member");
			return null;
		}
		return new CheckedTextLengthExpression (span, types.int_type, receiver);
	}

	private FieldAccessExpressionSyntax expression_member(TextMemberExpressionSyntax syntax) {
		return new FieldAccessExpressionSyntax.projection (syntax.receiver, new Token (TokenKind.DOT, syntax.member.span), syntax.member);
	}

	private CheckedNode? check_producer_projection(FieldAccessExpressionSyntax syntax, ValueScope values, out bool projected) {
		projected = false;
		var steps = new GenericArray<FieldAccessExpressionSyntax> ();
		steps.add (syntax);
		ExpressionSyntax root = syntax.aggregate ?? syntax;
		CheckedStructProducer? source = null;
		if (syntax.aggregate == null) {
			var local = borrowed_record_binding (syntax.identifier, values);
			if (local == null) {
				return null;
			}
			projected = true;
			source = new CheckedStructBorrowSnapshot (syntax.span, new CheckedLocalPlace (syntax.identifier.span, local));
		}
		while (source == null) {
			if (root is ParenthesizedExpressionSyntax) {
				root = ((ParenthesizedExpressionSyntax) root).expression;
				continue;
			}
			if (root is TextMemberExpressionSyntax) {
				root = expression_member ((TextMemberExpressionSyntax) root);
				continue;
			}
			var imported = imported_property_call (root, values);
			if (imported != null) {
				root = imported;
				continue;
			}
			var member = root as FieldAccessExpressionSyntax;
			var property = member == null ? null : resolve_property (member, values);
			if (property != null && property.semantic_type.is_struct_storage ()) {
				projected = true;
				if (property.is_borrowed && property.getter.struct_result_contract != null && property.getter.struct_result_contract.mode == StructValueMode.BORROW_VALUE) {
					var observed = check_field (member, values) as CheckedPropertyGetExpression;
					if (observed != null) {
						source = new CheckedStructCallResult (root.span, property.getter, new GenericArray<CheckedExpression> (), observed.receiver, Copyability.NOT_COPYABLE);
					}
				} else {
					source = check_struct_producer (root, values, property.semantic_type);
				}
				break;
			}
			if (root is CallExpressionSyntax) {
				projected = true;
				source = check_value_call ((CallExpressionSyntax) root, values, false, true) as CheckedStructProducer;
				break;
			}
			if (root is AwaitExpressionSyntax) {
				projected = true;
				source = check_await_producer ((AwaitExpressionSyntax) root, values) as CheckedStructProducer;
				break;
			}
			var indexed = root as IndexExpressionSyntax;
			if (indexed != null && slots_candidate (indexed.container, values)) {
				projected = true;
				source = check_slots_record_index (indexed, values);
				break;
			}
			if (member == null) {
				return null;
			}
			if (member.aggregate == null) {
				var local = borrowed_record_binding (member.identifier, values);
				if (local == null) {
					return null;
				}
				steps.add (member);
				projected = true;
				source = new CheckedStructBorrowSnapshot (root.span, new CheckedLocalPlace (member.identifier.span, local));
				break;
			}
			steps.add (member);
			root = member.aggregate;
		}
		if (source == null) {
			if (diagnostic == null) {
				fail (root.span, "field projection requires a bounded copied record producer");
			}
			return null;
		}
		if ((source.contract.mode != StructValueMode.COPY_VALUE || source.copyability != Copyability.COPYABLE) && source.contract.mode != StructValueMode.BORROW_VALUE) {
			fail (root.span, "record producer projection requires a copied value; owning storage requires a bounded borrowed observation");
			return null;
		}
		SemanticType selected = source.semantic_type;
		int depth = (int) steps.length;
		if (depth < 1 || depth > 256) {
			fail (syntax.span, "record projection exceeds the expression nesting limit of 256");
			return null;
		}
		int[] ordinals = new int[depth];
		for (int i = depth - 1; i >= 0; i--) {
			var step = steps[i];
			var field = storage_field (selected, step.field_name.spelling ());
			if (field == null) {
				fail (step.field_name.span, "unknown field '%s' in record producer '%s'".printf (step.field_name.spelling (), selected.display_name ()));
				return null;
			}
			if (!field_access_allowed (field, step.field_name.span)) {
				return null;
			}
			ordinals[depth - 1 - i] = field.ordinal;
			selected = storage_field_type (selected, field);
		}
		var path = new StructLeafPath (ordinals, selected);
		if (selected.is_struct_storage ()) {
			return new CheckedStructProjectionProducer (syntax.span, source, path);
		}
		var projection = new CheckedStructProjectionValue (syntax.span, source, path);
		if (source.contract.mode == StructValueMode.BORROW_VALUE) {
			projection.borrow_region = values.region;
		}
		return projection;
	}

	private LocalSymbol? borrowed_record_binding(Token name, ValueScope values) {
		var local = values.lookup (name.spelling ()) as LocalSymbol;
		var parameter = local == null ? null : local.incoming_parameter;
		return parameter != null && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.BORROW_VALUE ? local : null;
	}

	private CheckedExpression? check_field(FieldAccessExpressionSyntax syntax, ValueScope values, bool read = true) {
		if (syntax.aggregate != null && place_context_type (syntax.aggregate, values) is StringType) {
			if (!read) {
				fail (syntax.field_name.span, "string byte_length is read-only");
				return null;
			}
			return check_text_member (syntax.span, syntax.aggregate, syntax.field_name, values);
		}
		if (syntax.aggregate == null && !syntax.indirect) {
			var symbol = values.lookup (syntax.identifier.spelling ());
			var type = (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : (symbol is ConstantSymbol) ? ((ConstantSymbol) symbol).semantic_type : null;
			if (type is StringType) {
				if (!read) {
					fail (syntax.field_name.span, "string byte_length is read-only");
					return null;
				}
				return check_text_member (syntax.span, new NameExpressionSyntax (syntax.identifier), syntax.field_name, values);
			}
		}
		if (syntax.aggregate == null && !require_member_capability (values.lookup (syntax.identifier.spelling ()), syntax.span)) {
			return null;
		}
		var property = resolve_property (syntax, values);
		if (property != null) {
			if (checking_lifecycle != null && property.getter.dispatch_kind != ClassDispatchKind.DIRECT) {
				fail (syntax.span, "virtual dispatch is unavailable during construction or destruction");
				return null;
			}
			if (property.getter.throws_type != null && !check_exception_effect (property.getter.throws_type, syntax.span)) {
				return null;
			}
			NativeInstanceSymbol? owner;
			var receiver = check_member_receiver (syntax.identifier, syntax.dot, syntax.span, values, "property", out owner, syntax.aggregate, property.getter.struct_result_contract != null && property.getter.struct_result_contract.mode == StructValueMode.BORROW_VALUE);
			if (receiver != null && generic_owner_flow != null && property.getter.throws_type != null) {
				generic_owner_flow.effect (property.getter.throws_type, syntax.span);
			}
			if (receiver != null) {
				with_call (property.getter, receiver, new GenericArray<CheckedExpression> ());
			}
			return receiver == null ? null : new CheckedPropertyGetExpression (syntax.span, property, upcast_class (receiver, property.getter.receiver.semantic_type));
		}
		if (read && !(syntax.aggregate != null && place_context_type (syntax.aggregate, values) is ClassType)) {
			bool projected;
			var selection = check_producer_projection (syntax, values, out projected);
			if (projected) {
				if (selection is CheckedStructProducer) {
					fail (syntax.span, "record subprojection requires a bounded initialization, assignment, argument or return consumer");
					return null;
				}
				return selection as CheckedExpression;
			}
		}
		var place = check_field_place (syntax, values, read);
		if (place == null) {
			return null;
		}
		if (place.semantic_type.is_struct_storage ()) {
			fail (syntax.span, "struct subobject is a Place; whole-struct reads and assignment are unsupported");
			return null;
		}
		// Preserve historical leaf nodes/dumps for existing direct accesses.
		var field = place as CheckedFieldPlace;
		if (syntax.aggregate == null && field != null) {
			if (field.aggregate is CheckedLocalPlace) {
				return new CheckedFieldReferenceExpression (syntax.span, ((CheckedLocalPlace) field.aggregate).local, field.field);
			}
			if (field.aggregate is CheckedDereferencePlace) {
				return new CheckedIndirectFieldReference (syntax.span, ((CheckedDereferencePlace) field.aggregate).pointer, field.field);
			}
		}
		return new CheckedLoadExpression (syntax.span, place);
	}

	private bool field_access_allowed(FieldSymbol field, SourceSpan span) {
		var native_field = field as StructFieldSymbol;
		if (native_field == null || !native_field.is_private) {
			return true;
		}
		var receiver = checking_function == null ? null : checking_function.implicit_receiver;
		if (receiver != null && receiver.semantic_type.instance_type == native_field.containing_type.semantic_type) {
			return true;
		}
		fail (span, "private field '%s.%s' is accessible only within its declaring Class".printf (native_field.containing_type.name, field.name));
		return false;
	}

	private CheckedPlace? check_field_place(FieldAccessExpressionSyntax syntax, ValueScope values, bool read = true) {
		if (syntax.aggregate is ParenthesizedExpressionSyntax) {
			ExpressionSyntax base_expression = syntax.aggregate;
			while (base_expression is ParenthesizedExpressionSyntax) {
				base_expression = ((ParenthesizedExpressionSyntax) base_expression).expression;
			}
			var name = base_expression as NameExpressionSyntax;
			return check_field_place (name == null
				    ? new FieldAccessExpressionSyntax.projection (base_expression, syntax.dot, syntax.field_name)
				    : new FieldAccessExpressionSyntax (name.identifier, syntax.dot, syntax.field_name), values, read);
		}
		if (syntax.aggregate != null) {
			if (syntax.indirect) {
				fail (syntax.dot.span, "nested struct subobjects use '.' field access");
				return null;
			}
			var aggregate_type = place_context_type (syntax.aggregate, values);
			if (aggregate_type is ClassType) {
				var owner = instance_for (aggregate_type) as ClassSymbol;
				var field = owner == null ? null : owner.find_field (syntax.field_name.spelling ());
				if (field == null) {
					fail (syntax.field_name.span, "unknown field in projected Class receiver");
					return null;
				}
				if (!field_access_allowed (field, syntax.field_name.span)) {
					return null;
				}
				if (field.semantic_type is StringType) {
					fail (syntax.aggregate.span, "nested field base requires an exact StructType Place for stored text loans; a projected Class receiver has only a temporary loan");
					return null;
				}
				if (!read) {
					fail (syntax.span, "projected Class field mutation requires a complete enclosing receiver loan");
					return null;
				}
				var reference = check_expression (syntax.aggregate, values, aggregate_type, OwnershipUse.RECEIVER_BORROW);
				if (reference == null) {
					return null;
				}
				return new CheckedObjectFieldPlace (syntax.span, upcast_class (reference, field.containing_type.semantic_type), field);
			}
			var aggregate = check_place_syntax (syntax.aggregate, values, read);
			if (aggregate == null) {
				return null;
			}
			if (aggregate.semantic_type is GenericStructApplicationType) {
				return check_generic_projection (syntax, aggregate);
			}
			var owner = instance_for (aggregate.semantic_type) as StructSymbol;
			if (owner == null) {
				fail (syntax.aggregate.span, "nested field base requires an exact StructType Place");
				return null;
			}
			var field = owner.find_field (syntax.field_name.spelling ());
			if (field == null) {
				fail (syntax.field_name.span, "unknown field '%s' in struct '%s'".printf (syntax.field_name.spelling (), owner.name));
				return null;
			}
			if (!field_access_allowed (field, syntax.field_name.span)) {
				return null;
			}
			if (field.containing_type is StructSymbol && field.is_owned_field) {
				fail (syntax.span, "owning record Resource field access and extraction are deferred; move the whole local");
				return null;
			}
			return new CheckedFieldPlace (syntax.span, aggregate, field);
		}
		if (syntax.identifier.kind == TokenKind.THIS) {
			var receiver = check_this (syntax.identifier.span, values);
			if (receiver == null) {
				return null;
			}
			if (syntax.indirect) {
				fail (syntax.dot.span, "'this' uses '.' member access; it is not a source pointer");
				return null;
			}
			var structure = instance_for (receiver.receiver.semantic_type.instance_type);
			var field = structure.find_field (syntax.field_name.spelling ());
			if (field == null) {
				fail (syntax.field_name.span, "unknown field '%s' in struct '%s'; method values are unsupported".printf (syntax.field_name.spelling (), structure.name));
				return null;
			}
			if (!field_access_allowed (field, syntax.field_name.span)) {
				return null;
			}
			if (field_state != null && field.containing_type != structure) {
				fail (syntax.span, "inherited fields are initialized by base init; constructor body access is excluded from this subset");
				return null;
			}
			if (read && field_state != null && !field_state.is_definite (field.ordinal)) {
				fail (syntax.span, "constructor '%s.init': field '%s' read before definite initialization".printf (structure.name, field.name));
				return null;
			}
			return new CheckedReceiverFieldPlace (syntax.span, upcast_class (receiver, field.containing_type.receiver_type), field);
		}
		string name = syntax.identifier.spelling ();
		var symbol = values.lookup (name);
		if (symbol is IterationElementSymbol) {
			fail (syntax.span, "foreach element fields are inspected through a call-scoped readonly helper");
			return null;
		}
		if (symbol == null) {
			fail (syntax.identifier.span, "unknown name '%s'".printf (name));
			return null;
		}
		if (syntax.indirect) {
			CheckedExpression pointer = (symbol is LocalSymbol) ? (CheckedExpression) new CheckedLocalReferenceExpression (syntax.identifier.span, (LocalSymbol) symbol) : new CheckedParameterReferenceExpression (syntax.identifier.span, (ParameterSymbol) symbol);
			if (!pointer.semantic_type.is_struct_pointer ()) {
				fail (syntax.identifier.span, "indirect field access requires a native struct pointer local or parameter");
				return null;
			}
			if (((TypedPointerType) pointer.semantic_type).pointee is GenericStructApplicationType) {
				return check_generic_projection (syntax, new CheckedDereferencePlace (syntax.identifier.span, pointer));
			}
			var structure = instance_for (((TypedPointerType) pointer.semantic_type).pointee);
			var field = structure.find_field (syntax.field_name.spelling ());
			if (field == null) {
				fail (syntax.field_name.span, "unknown field '%s' in %s '%s'".printf (syntax.field_name.spelling (), (structure is ClassSymbol) ? "class" : "struct", structure.name));
				return null;
			}
			if (!field_access_allowed (field, syntax.field_name.span)) {
				return null;
			}
			if (field.containing_type is StructSymbol && field.is_owned_field) {
				fail (syntax.span, "owning record Resource field access and extraction are deferred; move the whole local");
				return null;
			}
			return new CheckedFieldPlace (syntax.span, new CheckedDereferencePlace (syntax.identifier.span, pointer), field);
		}
		var local = symbol as LocalSymbol;
		if (local != null && local.is_record_owner) {
			record_root_event (GenericOwnershipEventKind.READ, local, syntax.span);
		}
		if (!read && local != null && pending_record_borrows.find (local)) {
			fail (syntax.span, "record mutation overlaps an active borrowed record argument");
			return null;
		}
		if (!read && local != null && local.is_struct_parameter) {
			fail (syntax.span, "by-value struct parameter storage is read-only; copy to a local before mutation");
			return null;
		}
		var parameter = symbol as ParameterSymbol;
		var type = local != null ? local.semantic_type : parameter == null ? null : parameter.semantic_type;
		if (local != null && type is GenericStructApplicationType) {
			return check_generic_projection (syntax, new CheckedLocalPlace (syntax.identifier.span, local));
		}
		if (!(type is ClassType) && (local == null || !(type is StructType))) {
			fail (syntax.identifier.span, "field access requires a local struct variable");
			return null;
		}
		var structure = instance_for (type);
		var field = structure.find_field (syntax.field_name.spelling ());
		if (field == null) {
			fail (syntax.field_name.span, "unknown field '%s' in %s '%s'".printf (syntax.field_name.spelling (), (structure is ClassSymbol) ? "class" : "struct", structure.name));
			return null;
		}
		if (!field_access_allowed (field, syntax.field_name.span)) {
			return null;
		}
		if (type is ClassType) {
			CheckedExpression reference = object_reference (syntax.identifier.span, local, parameter);
			return new CheckedObjectFieldPlace (syntax.span, upcast_class (reference, field.containing_type.semantic_type), field);
		}
		if (field.containing_type is StructSymbol && field.is_owned_field) {
			fail (syntax.span, "owning record Resource field access and extraction are deferred; move the whole local");
			return null;
		}
		return new CheckedFieldPlace (syntax.span, new CheckedLocalPlace (syntax.identifier.span, local), field);
	}

	private CheckedPlace? check_generic_projection(FieldAccessExpressionSyntax syntax, CheckedPlace aggregate) {
		var application = (GenericStructApplicationType) aggregate.semantic_type;
		var field = application.definition.find_field (syntax.field_name.spelling ());
		if (field == null) {
			fail (syntax.field_name.span, "unknown field '%s' in struct '%s'".printf (syntax.field_name.spelling (), application.display_name ()));
			return null;
		}
		return new CheckedGenericStructFieldPlace (syntax.span, aggregate, field);
	}

	private bool require_storable_borrow(CheckedExpression expression, LocalSymbol destination) {
		// Every text-slice producer is a deep borrowed parameter. The per-write
		// text-origin proof follows backing storage, not this local descriptor.
		if (destination.semantic_type.is_text_slice () || !destination.semantic_type.is_lexically_borrowed_value ()) {
			return true;
		}
		var provenance = BorrowProvenance.for_expression (expression);
		if (provenance.outlives (destination.lexical_region)) {
			return true;
		}
		fail (expression.span, "borrow from '%s' cannot be stored in %s '%s' because '%s' has a shorter lexical lifetime".printf (provenance.origin.name, (destination.semantic_type is ClassType) ? "object reference" : (destination.semantic_type is SliceType) ? "slice" : "pointer", destination.name, provenance.origin.name));
		return false;
	}

	private LocalSymbol? array_base(IndexExpressionSyntax syntax, ValueScope values) {
		var name = syntax.container as NameExpressionSyntax;
		var local = name == null ? null : values.lookup (name.identifier.spelling ()) as LocalSymbol;
		return (local != null && local.semantic_type is ArrayType) ? local : null;
	}

	private CheckedSliceElementPlace? check_slice_place(IndexExpressionSyntax syntax, CheckedExpression slice, ValueScope values) {
		uint loan_depth = pending_field_borrows.length;
		if (slice is CheckedOwnedFieldBorrow || slice is CheckedStructProjectionValue) {
			reserve_receiver_loans (slice);
		}
		var index = check_expression (syntax.subscript, values);
		while (pending_field_borrows.length > loan_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		if (index == null) {
			return null;
		}
		if (!(index.semantic_type is IntegerType)) {
			fail (index.span, "slice index must be a scalar IntegerType");
			return null;
		}
		var result = new CheckedSliceElementPlace (syntax.span, slice, index);
		read_buffer_place (result);
		return result;
	}

	private CheckedPlace? check_indexed_place(IndexExpressionSyntax syntax, ValueScope values, bool read = true) {
		if (array_base (syntax, values) != null) {
			return check_array_place (syntax, values);
		}
		var slice = check_expression (syntax.container, values, null, OwnershipUse.BUFFER_VIEW);
		if (slice == null) {
			return null;
		}
		if (slice.semantic_type is StringType) {
			fail (syntax.span, "string contents are immutable; indexing and element writes are unsupported");
			return null;
		}
		if (!read && slice is CheckedLocalReferenceExpression && ((CheckedLocalReferenceExpression) slice).local.enum_inspection_root != null) {
			fail (syntax.span, "enum inspection array view is read-only");
			return null;
		}
		if (slice.semantic_type is SliceType) {
			return check_slice_place (syntax, slice, values);
		}
		var literal = syntax as VectorExtractExpressionSyntax;
		fail (literal == null ? syntax.container.span : literal.open_bracket.span, "vector lanes are not assignment targets; use insert()");
		return null;
	}

	private CheckedExpression? check_slice_form(CallExpressionSyntax syntax, ValueScope values) {
		bool length = syntax.identifier.kind == TokenKind.LEN;
		if (length ? syntax.arguments.length != 1 : syntax.arguments.length != 1 && syntax.arguments.length != 3) {
			fail (syntax.span, length ? "len requires exactly one array local or slice expression" : "slice requires an array local and optionally start, count");
			return null;
		}
		var name = syntax.arguments[0] as NameExpressionSyntax;
		var local = name == null ? null : values.lookup (name.identifier.spelling ()) as LocalSymbol;
		var array = local == null ? null : local.semantic_type as ArrayType;
		if (length) {
			if (array != null) {
				return new CheckedLengthExpression (syntax.span, types.i32_type, local, null);
			}
			var operand = check_expression (syntax.arguments[0], values, null, OwnershipUse.BUFFER_VIEW);
			if (operand == null) {
				return null;
			}
			if (!(operand.semantic_type is SliceType)) {
				fail (operand.span, "len requires a direct fixed-array local or SliceType expression");
				return null;
			}
			return new CheckedLengthExpression (syntax.span, types.i32_type, null, operand);
		}
		if (array == null) {
			fail (syntax.arguments[0].span, "slice source must be a direct fixed-array local; no decay, pointer construction or subslicing");
			return null;
		}
		CheckedExpression? start = null;
		CheckedExpression? count = null;
		if (syntax.arguments.length == 3) {
			start = check_expression (syntax.arguments[1], values);
			if (start == null) {
				return null;
			}
			count = check_expression (syntax.arguments[2], values);
			if (count == null) {
				return null;
			}
			if (!(start.semantic_type is IntegerType) || !(count.semantic_type is IntegerType)) {
				fail (syntax.span, "slice start and count must each be a scalar IntegerType");
				return null;
			}
			var first = start as CheckedIntegerExpression;
			var extent = count as CheckedIntegerExpression;
			if (first != null && !first.value.fits_nonnegative ((uint64) array.length)) {
				fail (start.span, "slice start is outside [0, %d]".printf (array.length));
				return null;
			}
			if (extent != null && (!extent.value.fits_nonnegative ((uint64) array.length) || (first != null && extent.value.bits > (uint64) array.length - first.value.bits))) {
				fail (count.span, "slice count exceeds the non-negative remaining array extent");
				return null;
			}
		}
		if (syntax != direct_loan_argument) {
			exposed_suspension_arrays.insert (local, true);
		}
		return new CheckedSliceFromArrayExpression (syntax.span, local, types.slice_of (array.element_type), start, count);
	}

	// Type inspection only, including explicit constructors and parentheses.
	private SemanticType? slice_element_context(ExpressionSyntax syntax, ValueScope values) {
		if (syntax is ParenthesizedExpressionSyntax) {
			return slice_element_context (((ParenthesizedExpressionSyntax) syntax).expression, values);
		}
		var name = syntax as NameExpressionSyntax;
		if (name != null) {
			var symbol = values.lookup (name.identifier.spelling ());
			var type = (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
			return (type is SliceType) ? ((SliceType) type).element_type : null;
		}
		var call = syntax as CallExpressionSyntax;
		if (call != null && call.identifier.kind == TokenKind.SLICE && call.arguments.length > 0) {
			var source = call.arguments[0] as NameExpressionSyntax;
			var local = source == null ? null : values.lookup (source.identifier.spelling ()) as LocalSymbol;
			return (local != null && local.semantic_type is ArrayType) ? ((ArrayType) local.semantic_type).element_type : null;
		}
		return null;
	}

	private CheckedArrayElementPlace? check_array_place(IndexExpressionSyntax syntax, ValueScope values) {
		var local = array_base (syntax, values);
		if (local == null) {
			var literal = syntax as VectorExtractExpressionSyntax;
			fail (literal == null ? syntax.container.span : literal.open_bracket.span, "vector lanes are not assignment targets; use insert()");
			return null;
		}
		var index = check_expression (syntax.subscript, values);
		if (index == null) {
			return null;
		}
		if (!(index.semantic_type is IntegerType)) {
			fail (index.span, "array index must be a scalar IntegerType");
			return null;
		}
		var constant = index as CheckedIntegerExpression;
		var array = (ArrayType) local.semantic_type;
		if (constant != null && !constant.value.fits_nonnegative ((uint64) array.length - 1)) {
			fail (index.span, "array index %s is outside [0, %d)".printf (constant.value.to_string (), array.length));
			return null;
		}
		return new CheckedArrayElementPlace (syntax.span, local, index);
	}

	private CheckedDereferencePlace? check_dereference(DereferenceExpressionSyntax syntax, ValueScope values, bool copy_context = false) {
		var pointer = check_expression (syntax.pointer, values, null, OwnershipUse.RECEIVER_BORROW);
		if (pointer == null) {
			return null;
		}
		var type = pointer.semantic_type as TypedPointerType;
		if (type == null || (!type.pointee.is_directly_dereferenceable_value_type () && !(copy_context && type.pointee.is_struct_storage () && !type.pointee.is_parameterized ()))) {
			fail (syntax.span, "dereference requires a typed pointer to an integer, f32, or numeric vector value, found '%s'".printf (pointer.semantic_type.display_name ()));
			return null;
		}
		return new CheckedDereferencePlace (syntax.span, pointer);
	}

	private CheckedPlace? check_volatile_place(ExpressionSyntax syntax, ValueScope values) {
		CheckedPlace? place = null;
		if (syntax is ParenthesizedExpressionSyntax) {
			return check_volatile_place (((ParenthesizedExpressionSyntax) syntax).expression, values);
		}
		if (syntax is IndexExpressionSyntax) {
			place = check_indexed_place ((IndexExpressionSyntax) syntax, values);
		} else if (syntax is DereferenceExpressionSyntax) {
			place = check_dereference ((DereferenceExpressionSyntax) syntax, values);
		} else {
			fail (syntax.span, "volatile access requires an indexed typed array/view or a checked typed-pointer dereference");
			return null;
		}
		if (place == null) {
			return null;
		}
		if (!VolatileAccessContract.supports (place.semantic_type)) {
			fail (syntax.span, "volatile access supports exactly u32 and u64 memory places");
			return null;
		}
		return place;
	}

	private CheckedExpression? check_borrow(AddressOfExpressionSyntax syntax, ValueScope values) {
		if (values.lookup (syntax.identifier.spelling ()) is ConstantSymbol) {
			fail (syntax.span, "constant has no storage or address");
			return null;
		}
		var local = values.lookup (syntax.identifier.spelling ()) as LocalSymbol;
		if (local != null && local.semantic_type is TypeParameterType) {
			fail (syntax.span, ownable_parameter (local.semantic_type) ? "address-of an Ownable parameter is deferred; generic pointers are unsupported" : "address-of a GEN1_PLAIN_COPY local is deferred; generic pointers are unsupported");
			return null;
		}
		if (local != null && local.semantic_type is GenericStructApplicationType && local.semantic_type.is_parameterized ()) {
			fail (syntax.span, "parameterized generic Struct* is deferred; only fully concrete generic struct pointers are supported");
			return null;
		}
		if (local == null || !local.semantic_type.is_typed_data_pointee ()) {
			fail (syntax.span, "address borrow requires a direct local integer, f32, numeric vector, or native struct variable");
			return null;
		}
		if (local.is_struct_parameter) {
			fail (syntax.span, "by-value struct parameter storage is read-only; address borrow requires a mutable local copy");
			return null;
		}
		local.address_taken = true;
		if (local.is_record_owner) {
			fail (syntax.span, "owning record address exposure is deferred");
			return null;
		}
		return new CheckedAddressOfExpression (syntax.span, local, types.pointer_to (local.semantic_type));
	}

	// Read type declarations only: no checked nodes, ownership effects,
	// diagnostics, or evaluation occur here. Literal-only trees stay untyped.
	// Do not cross a comparison or call-argument boundary with result context.
	private static SemanticType? context_type(SemanticType? type, bool floating) {
		return floating ? (SemanticType?) (type as FloatingType) : type as IntegerType;
	}

	private IntegerType? integer_context(ExpressionSyntax syntax, ValueScope values, bool vector_element = false) {
		return numeric_context (syntax, values, vector_element, false) as IntegerType;
	}

	private FloatingType? floating_context(ExpressionSyntax syntax, ValueScope values) {
		return numeric_context (syntax, values, false, true) as FloatingType;
	}

	private SemanticType? numeric_context(ExpressionSyntax syntax, ValueScope values, bool vector_element, bool floating) {
		if (syntax is TextMemberExpressionSyntax) {
			return vector_element ? null : context_type (place_context_type (syntax, values), floating);
		}
		if (syntax is FieldAccessExpressionSyntax) {
			var constant = qualified_constant ((FieldAccessExpressionSyntax) syntax, values);
			if (constant != null) {
				return vector_element ? null : context_type (constant.semantic_type, floating);
			}
		}
		var dot = syntax as VectorDotExpressionSyntax;
		if (dot != null) {
			if (floating && !vector_element && (dot.keyword.kind == TokenKind.DOT_F32 || dot.keyword.kind == TokenKind.MAC_F32)) {
				return numeric_context (dot.operands[dot.keyword.kind == TokenKind.MAC_F32 ? 1 : 0], values, true, true) ?? types.f32_type;
			}
			if (vector_element) {
				return null;
			}
			if (dot.destination != null) {
				return context_type (types.resolve (dot.destination.spelling ()), floating);
			}
			return dot.keyword.kind == TokenKind.MAC_WRAP ? numeric_context (dot.operands[0], values, false, floating) : null;
		}
		var dsp = syntax as DspExpressionSyntax;
		if (dsp != null) {
			if (dsp.destination != null) {
				return vector_element ? types.resolve (dsp.destination.spelling ()) as IntegerType : null;
			}
			return numeric_context (dsp.first, values, vector_element, floating) ?? numeric_context (dsp.second, values, vector_element, floating);
		}
		var conversion = syntax as ConversionExpressionSyntax;
		if (conversion != null) {
			var vector = conversion.destination as VectorTypeSyntax;
			return context_type ((vector_element ? (vector == null ? null : types.resolve (vector.element_type.spelling ())) : (vector != null ? null : types.resolve (conversion.destination.spelling ()))), floating);
		}
		// Extraction supplies the same scalar literal context as an exact
		// scalar local/call, without checking or evaluating the base twice.
		var dereference = syntax as DereferenceExpressionSyntax;
		if (dereference != null) {
			var pointer = dereference.pointer;
			while (pointer is ParenthesizedExpressionSyntax) {
				pointer = ((ParenthesizedExpressionSyntax) pointer).expression;
			}
			SemanticType? type = null;
			if (pointer is NameExpressionSyntax) {
				var symbol = values.lookup (((NameExpressionSyntax) pointer).identifier.spelling ());
				type = (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
			} else if (pointer is AddressOfExpressionSyntax) {
				var local = values.lookup (((AddressOfExpressionSyntax) pointer).identifier.spelling ()) as LocalSymbol;
				var pointee = local == null ? null : local.semantic_type;
				return context_type ((vector_element ? ((pointee is VectorType) ? ((VectorType) pointee).element_type : null) : pointee), floating);
			}
			var pointee = (type is TypedPointerType) ? ((TypedPointerType) type).pointee : null;
			return context_type ((vector_element ? ((pointee is VectorType) ? ((VectorType) pointee).element_type : null) : pointee), floating);
		}
		var extract = syntax as IndexExpressionSyntax;
		if (extract != null) {
			var local = array_base (extract, values);
			if (local != null) {
				var element = ((ArrayType) local.semantic_type).element_type;
				return context_type ((vector_element ? ((element is VectorType) ? ((VectorType) element).element_type : null) : element), floating);
			}
			var element = slice_element_context (extract.container, values);
			if (element != null) {
				return context_type ((vector_element ? ((element is VectorType) ? ((VectorType) element).element_type : null) : element), floating);
			}
			return vector_element ? null : numeric_context (extract.container, values, true, floating);
		}
		var primitive = syntax as VectorPrimitiveExpressionSyntax;
		if (primitive != null && vector_element) {
			if (primitive.keyword.kind == TokenKind.SPLAT) {
				return numeric_context (primitive.operands[0], values, false, floating);
			}
			return numeric_context (primitive.operands[primitive.keyword.kind == TokenKind.SELECT ? 1 : 0], values, true, floating);
		}
		if (syntax is ParenthesizedExpressionSyntax) {
			return numeric_context (((ParenthesizedExpressionSyntax) syntax).expression, values, vector_element, floating);
		}
		if (syntax is NameExpressionSyntax) {
			var token = ((NameExpressionSyntax) syntax).identifier;
			var symbol = values.lookup (token.spelling ()) ?? values.lookup (resolve_name (token.span, token.spelling (), false));
			var type = (symbol is ConstantSymbol) ? ((ConstantSymbol) symbol).semantic_type : (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
			return context_type ((vector_element ? ((type is VectorType) ? ((VectorType) type).element_type : null) : type), floating);
		}
		if (syntax is CallExpressionSyntax) {
			if (((CallExpressionSyntax) syntax).identifier.kind == TokenKind.LEN) {
				return vector_element ? null : types.i32_type;
			}
			var call = (CallExpressionSyntax) syntax;
			if (call.identifier.spelling () == "volatile_load" && call.receiver == null && call.receiver_place == null && call.arguments.length == 1) {
				var argument = call.arguments[0];
				SemanticType? type;
				if (argument is DereferenceExpressionSyntax) {
					var pointer = place_context_type (((DereferenceExpressionSyntax) argument).pointer, values) as TypedPointerType;
					type = pointer == null ? null : pointer.pointee;
				} else {
					type = place_context_type (argument, values);
				}
				return type == null || !VolatileAccessContract.supports (type) ? null : context_type (type, floating);
			}
			var function = context_callable (call, values);
			var type = function == null ? null : function.return_type;
			// Literal context follows an explicitly substituted concrete result.
			// This lookup supplies no capabilities and never contextualizes to T.
			var generic = function as GenericFunctionSymbol;
			if (generic != null && type is TypeParameterType && !ownable_parameter (type) && call.type_arguments.length == 0) {
				type = inferred_call_context (call, values);
			}
			if (generic != null && type is TypeParameterType && call.type_arguments.length == generic.type_parameters.length) {
				foreach (var parameter in generic.type_parameters) {
					if (parameter.semantic_type != type) {
						continue;
					}
					var argument = call.type_arguments[parameter.ordinal];
					if (vector_element && argument is VectorTypeSyntax) {
						return context_type (types.resolve (((VectorTypeSyntax) argument).element_type.spelling ()), floating);
					}
					type = types.resolve (argument.spelling ());
					break;
				}
			}
			return context_type ((vector_element ? ((type is VectorType) ? ((VectorType) type).element_type : null) : type), floating);
		}
		if (syntax is FieldAccessExpressionSyntax) {
			var field = (FieldAccessExpressionSyntax) syntax;
			var member_type = field_context_type (field, values);
			return context_type (vector_element ? ((member_type is VectorType) ? ((VectorType) member_type).element_type : null) : member_type, floating);
		}
		if (syntax is PrefixExpressionSyntax) {
			var prefix = (PrefixExpressionSyntax) syntax;
			return resolve_prefix_operator (prefix.operator_token.kind) == PrefixOperator.NOT ? null : numeric_context (prefix.operand, values, vector_element, floating);
		}
		if (syntax is BinaryExpressionSyntax) {
			var binary = (BinaryExpressionSyntax) syntax;
			if (is_shift_token (binary.operator_token.kind)) {
				return numeric_context (binary.left, values, vector_element, floating);
			}
			var kind = resolve_binary_operator (binary.operator_token.kind);
			if (kind.is_arithmetic () || kind.is_bitwise ()) {
				return numeric_context (binary.left, values, vector_element, floating) ?? numeric_context (binary.right, values, vector_element, floating);
			}
		}
		return null;
	}

	private bool require_numeric_operand(CheckedExpression expression, string operator_name) {
		if (expression.semantic_type is TypeParameterType) {
			fail (expression.span, "GEN1_PLAIN_COPY permits value transport only; numeric operator '%s' on a type parameter is unsupported at definition checking".printf (operator_name));
			return false;
		}
		// Retain established int diagnostics for nonnumeric operands.
		return expression.semantic_type is IntegerType || expression.semantic_type is FloatingType || require_operand (expression, types.int_type, operator_name);
	}

	private bool require_c_scalar_capability(SemanticType type, SourceSpan span) {
		if (type is ClosureHandleType) {
			fail (span, "native Closure/CheckedClosure carriers cannot cross a raw C boundary; use the retained adapter");
			return false;
		}
		if (type is VectorType) {
			fail (span, "C ABI vectors are not supported yet");
			return false;
		}
		if (type is FloatingType && !(type is F64Type) && !(type is F32Type)) {
			fail (span, "C ABI %s is not supported yet".printf (type.display_name ()));
			return false;
		}
		if (type is IntegerType && type != types.int_type && ((IntegerType) type).bit_width != 64) {
			fail (span, "exact-width C integer channels are not supported yet");
			return false;
		}
		return true;
	}

	private bool require_operand(CheckedExpression expression, SemanticType expected, string operator_name) {
		if (expression.semantic_type == expected) {
			return true;
		}
		fail (expression.span, "operator '%s' requires %s '%s' operand, found '%s'".printf (operator_name, expected == types.int_type ? "an" : "a", expected.display_name (), expression.semantic_type.display_name ()));
		return false;
	}

	private bool require_member_capability(Symbol? symbol, SourceSpan span) {
		SemanticType? type = (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
		if (type is TypeParameterType) {
			fail (span, ownable_parameter (type) ? "Ownable grants no field, method or property capability; member access on a type parameter is unsupported" : "GEN1_PLAIN_COPY has no field, method or property capability; member access on a type parameter is unsupported");
			return false;
		}
		return true;
	}

	private static bool indexed_member_projection(ExpressionSyntax syntax) {
		var current = syntax;
		while (current is FieldAccessExpressionSyntax) {
			var field = (FieldAccessExpressionSyntax) current;
			if (field.aggregate == null) {
				return false;
			}
			current = field.aggregate;
		}
		return current is IndexExpressionSyntax;
	}

	private CheckedExpression? check_member_receiver(Token receiver_token, Token? member_operator, SourceSpan span, ValueScope values, string member_kind, out NativeInstanceSymbol? structure, ExpressionSyntax? projection = null, bool readonly_receiver = false) {
		structure = null;
		if (projection != null) {
			var type = place_context_type (projection, values);
			if (type is ClassType) {
				var reference = check_expression (projection, values, type, OwnershipUse.RECEIVER_BORROW);
				if (reference == null) {
					return null;
				}
				structure = instance_for (type);
				if (structure == null) {
					return null;
				}
				return new CheckedObjectReceiverExpression (projection.span, reference, structure.receiver_type);
			}
			var place = check_place_syntax (projection, values);
			if (place == null) {
				return null;
			}
			structure = instance_for (place.semantic_type) as StructSymbol;
			if (structure == null) {
				fail (span, "indexed member receiver requires an exact addressable struct Place");
				return null;
			}
			if (!require_mutable_struct_place (place, span)) {
				return null;
			}
			return new CheckedReceiverAddressExpression.projection (projection.span, place, structure.receiver_type);
		}
		CheckedExpression? receiver = null;
		var receiver_symbol = values.lookup (receiver_token.spelling ());
		if (!require_member_capability (receiver_symbol, span)) {
			return null;
		}
		if (member_operator != null && member_operator.kind != TokenKind.DOT) {
			fail (member_operator.span, "%s receiver must be a direct struct local or 'this'; pointer receiver calls are unsupported".printf (member_kind));
			return null;
		}
		if (receiver_token.kind == TokenKind.THIS) {
			var self = check_this (receiver_token.span, values);
			if (self == null) {
				return null;
			}
			if (self.receiver.semantic_type.mode == ReceiverMode.INITIALIZING) {
				fail (span, "this.%s calls are unsupported in constructors; receiver is still initializing".printf (member_kind));
				return null;
			}
			receiver = self;
			structure = instance_for (self.receiver.semantic_type.instance_type);
		} else {
			var local = receiver_symbol as LocalSymbol;
			var parameter = receiver_symbol as ParameterSymbol;
			var type = local != null ? local.semantic_type : parameter == null ? null : parameter.semantic_type;
			if (!(type is ClassType) && (local == null || !(type is StructType))) {
				fail (receiver_token.span, "%s receiver must be a direct struct local or 'this'; pointer and arbitrary expression receivers are unsupported".printf (member_kind));
				return null;
			}
			structure = instance_for (type);
			if (structure == null) {
				return null;
			}
			if (type is ClassType) {
				CheckedExpression reference = object_reference (receiver_token.span, local, parameter);
				receiver = new CheckedObjectReceiverExpression (receiver_token.span, reference, structure.receiver_type);
			} else {
				if (local.is_struct_parameter) {
					fail (span, "by-value struct parameter storage is read-only; member receivers require a mutable local copy");
					return null;
				}
				local.address_taken = true;
				receiver = new CheckedReceiverAddressExpression (receiver_token.span, local, structure.receiver_type);
			}
		}
		foreach (var owner_type in pending_field_borrows) {
			if (!readonly_receiver && field_overlap (structure.semantic_type, owner_type)) {
				fail (span, "temporary owned-field borrow overlaps a later containing-object member call; finish the borrow first");
				return null;
			}
		}
		return receiver;
	}

	// Native callable objects use their nominal Class contract and the ordinary
	// method receiver channel. No raw code/context pointer or new ownership
	// authority is manufactured by the concise invocation spelling.
	private ClassSymbol? callable_binding(Token name, ValueScope values) {
		// Existing source has separate free-call lookup; keep that precedence
		// when a local happens to share an already declared function name.
		if (find_function (name) != null) {
			return null;
		}
		var symbol = values.lookup (name.spelling ());
		SemanticType? type = (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
		return (type is ClassType) ? instance_for (type) as ClassSymbol : null;
	}

	private GenericArray<CheckedExpression>? check_call(CallExpressionSyntax syntax, ValueScope values, bool requires_value, out DirectCallableSymbol? target, out CheckedExpression? receiver, out GenericArray<SemanticType> type_arguments, bool acquire_owned = false, bool discard_success = false) {
		var result = check_observed_call (syntax, values, requires_value, out target, out receiver, out type_arguments, acquire_owned, discard_success);
		if (tooling != null && result != null) {
			tooling.reference (syntax.identifier.span, target);
			if (syntax.receiver != null) {
				tooling.reference (syntax.receiver.span, values.lookup (syntax.receiver.spelling ()));
			}
		}
		return result;
	}

	// A projected receiver keeps every enclosing owner alive until the call
	// consumes its receiver and all arguments have finished evaluation.
	private void reserve_receiver_loans(CheckedExpression? receiver) {
		if (receiver is CheckedStructArgument) {
			var argument = (CheckedStructArgument) receiver;
			var observed = argument.producer as CheckedStructCallResult;
			var getter = observed == null ? null : observed.target as PropertyGetterSymbol;
			if (argument.producer.contract.mode == StructValueMode.BORROW_VALUE && getter != null && getter.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				pending_field_borrows.add (getter.property_symbol.declaring_type.semantic_type);
				reserve_receiver_loans (observed.receiver);
			}
		} else if (receiver is CheckedStructProjectionValue) {
			var projection = (CheckedStructProjectionValue) receiver;
			if (projection.source.contract.mode != StructValueMode.BORROW_VALUE || !(projection.semantic_type is ClassType || projection.semantic_type is HandleType || projection.semantic_type is SliceType)) {
				return;
			}
			CheckedStructProducer source = projection.source;
			while (source is CheckedStructProjectionProducer) {
				source = ((CheckedStructProjectionProducer) source).source;
			}
			var observed = source as CheckedStructCallResult;
			var getter = observed == null ? null : observed.target as PropertyGetterSymbol;
			if (getter != null) {
				pending_field_borrows.add (getter.property_symbol.declaring_type.semantic_type);
				reserve_receiver_loans (observed.receiver);
			}
		} else if (receiver is CheckedClassUpcast) {
			reserve_receiver_loans (((CheckedClassUpcast) receiver).reference);
		} else if (receiver is CheckedObjectReceiverExpression) {
			reserve_receiver_loans (((CheckedObjectReceiverExpression) receiver).reference);
		} else if (receiver is CheckedPropertyGetExpression) {
			var observed = (CheckedPropertyGetExpression) receiver;
			if (!observed.property_symbol.is_borrowed) {
				return;
			}
			var property = observed.property_symbol;
			(property.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (property.declaring_type.semantic_type);
			reserve_receiver_loans (observed.receiver);
		} else if (receiver is CheckedOwnedFieldBorrow) {
			var observed = (CheckedOwnedFieldBorrow) receiver;
			pending_field_borrows.add (observed.field.containing_type.semantic_type);
			var source = observed.source as CheckedObjectFieldPlace;
			if (source != null) {
				reserve_receiver_loans (source.reference);
			}
		}
	}

	private GenericArray<CheckedExpression>? check_observed_call(CallExpressionSyntax syntax, ValueScope values, bool requires_value, out DirectCallableSymbol? target, out CheckedExpression? receiver, out GenericArray<SemanticType> type_arguments, bool acquire_owned = false, bool discard_success = false) {
		string name = syntax.identifier.spelling ();
		type_arguments = new GenericArray<SemanticType> ();
		receiver = null;
		target = null;
		var imported = imported_member (syntax, values, out target);
		if (imported != null) {
			if (target == null || !check_exception_effect (((FunctionSymbol) target).throws_type, syntax.span)) {
				return null;
			}
			return check_resolved_call (imported, values, requires_value, target, null, out type_arguments, acquire_owned, discard_success);
		}
		if (syntax.receiver_place != null) {
			NativeInstanceSymbol? structure;
			receiver = check_member_receiver (syntax.identifier, syntax.member_operator, syntax.span, values, "method", out structure, syntax.receiver_place);
			if (receiver == null) {
				return null;
			}
			target = resolve_class_method (structure, syntax);
			if (target == null) {
				fail (syntax.identifier.span, "unknown method '%s' in struct '%s'".printf (name, structure.name));
				return null;
			}
		} else if (syntax.receiver != null && values.lookup (syntax.receiver.spelling ()) == null && module_names.contains (syntax.receiver.spelling ())) {
			target = function_names.lookup (resolve_name (syntax.identifier.span, syntax.receiver.spelling () + "." + name, false));
		} else if (syntax.receiver != null) {
			var receiver_symbol = values.lookup (syntax.receiver.spelling ());
			bool class_receiver = (receiver_symbol is LocalSymbol) ? ((LocalSymbol) receiver_symbol).semantic_type is ClassType : (receiver_symbol is ParameterSymbol) ? ((ParameterSymbol) receiver_symbol).semantic_type is ClassType : (receiver_symbol is ReceiverSymbol) ? ((ReceiverSymbol) receiver_symbol).semantic_type.instance_type is ClassType : find_instance (syntax.receiver) is ClassSymbol;
			if (class_receiver && (name == "init" || name == "deinit")) {
				fail (syntax.span, name == "deinit" ? "destructor deinit cannot be invoked explicitly" : "Type.init construction is only permitted as a fresh class local initializer or direct owned object return");
				return null;
			}
			NativeInstanceSymbol? structure;
			receiver = check_member_receiver (syntax.receiver, syntax.member_operator, syntax.span, values, "method", out structure);
			if (receiver == null) {
				return null;
			}
			target = resolve_class_method (structure, syntax);
			if (target == null) {
				fail (syntax.identifier.span, "unknown method '%s' in %s '%s'".printf (name, (structure is ClassSymbol) ? "class" : "struct", structure.name));
				return null;
			}
		} else if (callable_binding (syntax.identifier, values) != null) {
			NativeInstanceSymbol? structure;
			receiver = check_member_receiver (syntax.identifier, null, syntax.span, values, "callable", out structure);
			if (receiver == null) {
				return null;
			}
			target = structure.find_method ("invoke");
			if (target == null) {
				fail (syntax.identifier.span, "callable class '%s' requires a typed invoke method".printf (structure.name));
				return null;
			}
		} else {
			// The only free-call name lookup; no member fallback.
			target = function_names.lookup (resolve_name (syntax.identifier.span, name, false));
		}
		if (target == null) {
			fail (syntax.identifier.span, "unknown function '%s'".printf (name));
			return null;
		}
		var internal_method = target as MethodSymbol;
		if (internal_method != null) {
			foreach (var property in internal_method.declaring_type.properties) {
				if (property.factory == internal_method) {
					fail (syntax.span, "compiler-owned lazy factory is not a source-callable method; observe the property");
					return null;
				}
			}
		}
		if (checking_function != null && checking_function.async_body != null) {
			foreach (var parameter in target.parameters) {
				if (GenericBorrowTypes.symbolic (parameter.semantic_type) && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
					fail (syntax.span, "generic borrowing requires a synchronous caller; async loans and coroutine frames are deferred");
					return null;
				}
			}
		}
		if (target is FunctionSymbol && ((FunctionSymbol) target).async_body != null && !requires_value) {
			fail (syntax.span, "ignored async task requires a named unique owner or a consuming await");
			return null;
		}
		if (target is FunctionSymbol && ((FunctionSymbol) target).async_body == null && ((FunctionSymbol) target).throws_type != null && !check_exception_effect (((FunctionSymbol) target).throws_type, syntax.span)) {
			return null;
		}
		if (target is MethodSymbol && receiver != null) {
			if (checking_lifecycle != null && ((MethodSymbol) target).dispatch_kind != ClassDispatchKind.DIRECT) {
				fail (syntax.span, "virtual dispatch is unavailable during construction or destruction");
				return null;
			}
			receiver = upcast_class (receiver, ((MethodSymbol) target).receiver.semantic_type);
		}
		// An omitted-argument call commits its temporary ownership proof only
		// after inference, capabilities and every ordinary argument check pass.
		var incoming_flow = generic_owner_flow;
		bool inferred = target is GenericFunctionSymbol && syntax.type_arguments.length == 0;
		uint borrow_depth = pending_field_borrows.length;
		uint receiver_lazy_depth = pending_lazy_borrows.length;
		if (inferred && incoming_flow != null) {
			generic_owner_flow = new SemanticOwnershipFlow (syntax.span);
		}
		var address_receiver = receiver as CheckedReceiverAddressExpression;
		var receiver_borrow = address_receiver == null || address_receiver.receiver_place == null ? null : place_field_borrow (address_receiver.receiver_place);
		if (receiver_borrow != null) {
			pending_field_borrows.add (receiver_borrow.field.containing_type.semantic_type);
		}
		reserve_receiver_loans (receiver);
		var arguments = check_resolved_call (syntax, values, requires_value, target, receiver, out type_arguments, acquire_owned, discard_success);
		while (pending_field_borrows.length > borrow_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		while (pending_lazy_borrows.length > receiver_lazy_depth) {
			pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
		}
		if (inferred && incoming_flow != null) {
			var fragment = generic_owner_flow;
			generic_owner_flow = incoming_flow;
			if (arguments != null) {
				incoming_flow.append (fragment);
			}
		}
		if (arguments != null) {
			with_call (target, receiver, arguments);
		}
		if (arguments != null && generic_owner_flow != null && target is FunctionSymbol && ((FunctionSymbol) target).async_body == null && ((FunctionSymbol) target).throws_type != null) {
			generic_owner_flow.effect (((FunctionSymbol) target).throws_type, syntax.span);
		}
		return arguments;
	}

	private GenericArray<CheckedExpression>? check_resolved_call(CallExpressionSyntax syntax, ValueScope values, bool requires_value, DirectCallableSymbol target, CheckedExpression? receiver, out GenericArray<SemanticType> type_arguments, bool acquire_owned, bool discard_success = false) {
		string name = target.name;
		type_arguments = new GenericArray<SemanticType> ();
		var generic = target as GenericFunctionSymbol;
		GenericCallInference? inference = null;
		var checked_arguments = new GenericArray<CheckedNode?> ();
		var argument_flows = new GenericArray<SemanticOwnershipFlow?> ();
		uint reservation_depth = enum_reservations.length;
		TypeSubstitution? substitution = null;
		if (generic == null && syntax.type_arguments.length != 0 && (!(target is MethodSymbol) || ((MethodSymbol) target).generic_method_instance == null)) {
			fail (syntax.span, "non-generic function '%s' does not accept type arguments".printf (name));
			return null;
		}
		if (generic != null) {
			if (syntax.type_arguments.length == 0) {
				if (!check_argument_count (syntax, target)) {
					return null;
				}
				inference = new GenericCallInference (generic);
				if (!infer_call_arguments (syntax, values, generic, inference, checked_arguments, argument_flows)) {
					return null;
				}
				var inferred = inference.complete (syntax.span);
				if (inferred == null) {
					fail (inference.diagnostic.span, inference.diagnostic.message);
					return null;
				}
				type_arguments = inferred;
			} else {
				if (syntax.type_arguments.length != generic.type_parameters.length) {
					fail (syntax.span, "generic function '%s' expects %u type arguments, provided %u; supply the full ordered list".printf (name, generic.type_parameters.length, syntax.type_arguments.length));
					return null;
				}
				for (int t = 0; t < syntax.type_arguments.length; t++) {
					var argument = resolve_type (syntax.type_arguments[t]);
					if (argument == null || !check_generic_argument (generic.type_parameters[t], argument, syntax.type_arguments[t].span)) {
						return null;
					}
					type_arguments.add (argument);
				}
			}
			substitution = new TypeSubstitution ((element) => types.slice_of (element), types.substitute_function, substitute_class, substitute_closure);
			for (int t = 0; t < type_arguments.length; t++) {
				var argument = type_arguments[t];
				var span = inference == null ? syntax.type_arguments[t].span : inference.argument_span (generic.type_parameters[t]);
				if (inference != null && !check_generic_argument (generic.type_parameters[t], argument, span)) {
					return null;
				}
				if (generic.element_obligations.contains (generic.type_parameters[t].semantic_type) && !GenericSliceObligations.accepts (argument, copy_fields, element_premise)) {
					fail (span, "type argument '%s' does not satisfy the signature-derived mutable slice element-storage obligation for '%s'".printf (argument.display_name (), generic.type_parameters[t].name));
					return null;
				}
				substitution.bind (generic.type_parameters[t].semantic_type, argument);
			}
		}
		if (generic != null) {
			foreach (var requirement in generic.capability_requirements) {
				var parameter = requirement.type_parameter;
				var argument = type_arguments[parameter.ordinal];
				if (!GenericCapabilityAuthority.satisfies (argument, requirement.capability.identity)) {
					var span = inference == null ? syntax.type_arguments[parameter.ordinal].span : inference.argument_span (parameter);
					fail (span, "type argument '%s' does not satisfy capability '%s' required by type parameter '%s' of generic function '%s'".printf (argument.display_name (), requirement.capability.name, parameter.name, generic.name));
					return null;
				}
			}
			class_function_requests.add (new GenericClassFunctionRequest (generic, checking_function as GenericFunctionSymbol, new TypeArgumentVector (type_arguments)));
		}
		if (generic != null) {
			foreach (var parameter in target.parameters) {
				var signature = substitution.apply (parameter.semantic_type) as FunctionValueType;
				if (signature == null) {
					continue;
				}
				if (!FunctionValueType.supported_result (signature.result_type, signature.result_contract)) {
					fail (syntax.span, "specialized callable result requires a supported exact value and ownership contract");
					return null;
				}
				try {
					signature.complete_records (copy_fields);
				} catch (StructLeafError error) {
					fail (syntax.span, error.message);
					return null;
				}
			}
		}
		var native = target as FunctionSymbol;
		if (native != null && native.result_contract == ResultOwnershipContract.OWNED_TRANSFER && !acquire_owned && !(discard_success && native.throws_type != null && native.return_type is SliceType)) {
			fail (syntax.span, "native result carries ownership responsibility; it requires a fresh owned local or compatible rearm and cannot be discarded, captured unmanaged, returned directly, or passed inline");
			return null;
		}
		var imported = target as CFunctionSymbol;
		if (imported != null && imported.metadata.owned_result != null && !acquire_owned) {
			fail (syntax.span, "foreign result carries ownership responsibility; it requires a direct 'owned %s' local initializer and cannot be captured as raw, discarded, returned, or passed to calls".printf (imported.return_type.display_name ()));
			return null;
		}
		var receiver_origin = receiver;
		while (receiver_origin is CheckedClassUpcast) {
			receiver_origin = ((CheckedClassUpcast) receiver_origin).reference;
		}
		var object_receiver = receiver_origin as CheckedObjectReceiverExpression;
		var receiver_local = object_receiver == null ? null : object_receiver.reference as CheckedLocalReferenceExpression;
		bool owned_receiver = receiver_local != null && receiver_local.local.object_owner != null;
		if (owned_receiver) {
			active_object_receivers.add (receiver_local.local);
		}
		var arguments = check_arguments (syntax, values, target, requires_value, substitution, inference == null ? null : checked_arguments, inference == null ? null : argument_flows);
		while (enum_reservations.length > reservation_depth) {
			var source = enum_reservations[reservation_depth];
			if (arguments != null && generic_owner_flow != null) {
				generic_owner_flow.move (source, source.name, syntax.span);
			}
			enum_reservations.remove_index (reservation_depth);
		}
		if (owned_receiver) {
			active_object_receivers.remove_index (active_object_receivers.length - 1);
		}
		return arguments;
	}

	private bool check_generic_argument(TypeParameterSymbol parameter, SemanticType argument, SourceSpan span) {
		if (parameter.transport_mode == GenericTransportMode.PLAIN_COPY && !GenericArgumentTypes.plain_copy (argument, copy_fields, copy_premise)) {
			fail (span, "GEN-1 type argument '%s' is unsupported: requires a lifetime-neutral GEN1_PLAIN_COPY value; void, handles, objects, noncopyable records, slices, arrays and typed pointers are deferred".printf (argument.display_name ()));
			return false;
		}
		return true;
	}

	private bool infer_call_arguments(CallExpressionSyntax syntax, ValueScope values, GenericFunctionSymbol target, GenericCallInference inference, GenericArray<CheckedNode?> checked_arguments, GenericArray<SemanticOwnershipFlow?> argument_flows) {
		uint borrow_depth = pending_field_borrows.length;
		for (int i = 0; i < syntax.arguments.length; i++) {
			checked_arguments.add (null);
			argument_flows.add (null);
			var formal_slice = target.parameters[i].semantic_type as SliceType;
			var parameter = inference.parameter_for (formal_slice == null ? target.parameters[i].semantic_type : formal_slice.element_type);
			if (formal_slice != null && parameter != null) {
				if (target.parameters[i].pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					var argument = syntax.arguments[i];
					while (argument is ParenthesizedExpressionSyntax) {
						argument = ((ParenthesizedExpressionSyntax) argument).expression;
					}
					LocalSymbol? owner = null;
					if (argument is MoveExpressionSyntax) {
						owner = check_move_source ((MoveExpressionSyntax) argument, values);
					} else if (argument is NameExpressionSyntax) {
						owner = values.lookup (((NameExpressionSyntax) argument).identifier.spelling ()) as LocalSymbol;
					}
					var actual = owner == null ? null : owner.semantic_type as SliceType;
					if (actual == null || !owner.is_buffer_owner) {
						fail (argument.span, "owned T[] inference requires an exact named array owner and explicit move; inline producers are unsupported");
						return false;
					}
					if (!inference.observe (parameter, actual.element_type, i, argument.span)) {
						fail (inference.diagnostic.span, inference.diagnostic.message);
						return false;
					}
					continue;
				}
				var incoming_flow = generic_owner_flow;
				if (incoming_flow != null) {
					generic_owner_flow = new SemanticOwnershipFlow (syntax.arguments[i].span);
				}
				// Check once without element context, preserving the complete view
				// and its transactional effects at this written argument position.
				var view = check_expression (syntax.arguments[i], values, null, OwnershipUse.UNMANAGED, target.parameters[i]);
				if (incoming_flow != null) {
					argument_flows[i] = generic_owner_flow;
					generic_owner_flow = incoming_flow;
				}
				if (view == null) {
					return false;
				}
				var actual_slice = view.semantic_type as SliceType;
				if (actual_slice == null) {
					fail (view.span, "generic T[] argument requires an exact slice view; fixed arrays require explicit slice(...)");
					return false;
				}
				checked_arguments[i] = view;
				if (view is CheckedOwnedFieldBorrow || view is CheckedStructProjectionValue) {
					reserve_receiver_loans (view);
				}
				if (!inference.observe (parameter, actual_slice.element_type, i, syntax.arguments[i].span)) {
					fail (inference.diagnostic.span, inference.diagnostic.message);
					return false;
				}
				continue;
			}
			if (parameter == null && !target.parameters[i].semantic_type.is_parameterized ()) {
				var incoming_flow = generic_owner_flow;
				if (incoming_flow != null) {
					generic_owner_flow = new SemanticOwnershipFlow (syntax.arguments[i].span);
				}
				var checked = check_argument (syntax.arguments[i], values, target.name, target.parameters[i], target.parameters[i].semantic_type, i);
				if (incoming_flow != null) {
					argument_flows[i] = generic_owner_flow;
					generic_owner_flow = incoming_flow;
				}
				if (checked == null) {
					return false;
				}
				checked_arguments[i] = checked;
				if (checked is CheckedOwnedFieldBorrow || checked is CheckedStructProjectionValue) {
					reserve_receiver_loans (checked);
				}
				continue;
			}
			var argument = syntax.arguments[i];
			while (argument is ParenthesizedExpressionSyntax) {
				argument = ((ParenthesizedExpressionSyntax) argument).expression;
			}
			// A cached inferred producer must not bypass loan source admission.
			if (target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !check_generic_borrow_source (argument, values)) {
				return false;
			}
			SemanticType? candidate = null;
			// Names expose already-checked semantic identities, including types
			// outside generic transport. Observing a Place/owner never loads,
			// borrows or consumes it; ordinary argument checking remains below.
			if (argument is NameExpressionSyntax) {
				var symbol = values.lookup (((NameExpressionSyntax) argument).identifier.spelling ());
				candidate = (symbol is LocalSymbol) ? ((LocalSymbol) symbol).semantic_type : (symbol is ParameterSymbol) ? ((ParameterSymbol) symbol).semantic_type : null;
				if (candidate == null && symbol == null && target.parameters[i].semantic_type is FunctionValueType) {
					var code = find_function (((NameExpressionSyntax) argument).identifier) as FunctionSymbol;
					if (code != null && !(code is GenericFunctionSymbol) && !(code is MethodSymbol) && code.async_body == null && code.throws_type == null) {
						var inputs = new GenericArray<SemanticType> ();
						var contracts = new GenericArray<PointerParameterContract> ();
						foreach (var input in code.parameters) {
							inputs.add (input.semantic_type);
							contracts.add (input.pointer_contract);
						}
						candidate = types.function_value (code.return_type, inputs, contracts, code.result_contract);
					}
				}
			} else if (argument is MoveExpressionSyntax && target.parameters[i].pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				var source = check_move_source ((MoveExpressionSyntax) argument, values);
				if (source == null) {
					return false;
				}
				candidate = source.semantic_type;
			} else if (argument is FieldAccessExpressionSyntax) {
				var type = field_context_type ((FieldAccessExpressionSyntax) argument, values);
				if (type != null && type.is_struct_storage ()) {
					candidate = type;
				}
			} else if (argument is IndexExpressionSyntax) {
				var type = place_context_type (argument, values);
				if (type != null && type.is_struct_storage ()) {
					candidate = type;
				}
			}
			if (candidate == null) {
				var incoming_flow = generic_owner_flow;
				if (incoming_flow != null) {
					generic_owner_flow = new SemanticOwnershipFlow (argument.span);
				}
				var call = argument as CallExpressionSyntax;
				CheckedNode? checked;
				if (argument is DereferenceExpressionSyntax) {
					var source = check_dereference ((DereferenceExpressionSyntax) argument, values, true);
					checked = source == null ? null : source.semantic_type.is_struct_storage () ? (CheckedNode) new CheckedStructSnapshot (argument.span, source, CopyabilityAuthority.value_copy (source.semantic_type, copy_fields, copy_premise)) : new CheckedLoadExpression (argument.span, source);
				} else {
					checked = call != null && call.identifier.kind != TokenKind.SLICE && call.identifier.kind != TokenKind.LEN ? check_value_call (call, values, true, true) : check_expression (argument, values);
				}
				if (incoming_flow != null) {
					argument_flows[i] = generic_owner_flow;
					generic_owner_flow = incoming_flow;
				}
				if (checked == null) {
					return false;
				}
				if (checked is CheckedEnumProducer) {
					candidate = ((CheckedEnumProducer) checked).semantic_type;
					checked_arguments[i] = new CheckedEnumArgument (argument.span, target.parameters[i], (CheckedEnumProducer) checked);
				} else {
					candidate = (checked is CheckedStructProducer) ? ((CheckedStructProducer) checked).semantic_type : ((CheckedExpression) checked).semantic_type;
				}
				if (!(checked is CheckedEnumProducer) && target.parameters[i].pointer_contract != PointerParameterContract.OWNED_TRANSFER) {
					checked_arguments[i] = checked;
				}
			}
			if (!inference.observe_type (target.parameters[i].semantic_type, candidate, i, syntax.arguments[i].span)) {
				fail (inference.diagnostic.span, inference.diagnostic.message);
				return false;
			}
		}
		while (pending_field_borrows.length > borrow_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		return true;
	}

	private bool check_argument_count(CallExpressionSyntax syntax, DirectCallableSymbol target) {
		uint minimum = CallerInformation.minimum_arguments (target);
		if (syntax.arguments.length < minimum || syntax.arguments.length > target.parameters.length) {
			fail (syntax.span, minimum == target.parameters.length ? "function '%s' expects %u arguments, provided %u".printf (target.name, target.parameters.length, syntax.arguments.length) : "function '%s' expects %u through %u arguments, provided %u".printf (target.name, minimum, target.parameters.length, syntax.arguments.length));
			return false;
		}
		return true;
	}

	private bool commit_record_arguments(GenericArray<CheckedExpression> arguments) {
		var record_moves = new HashTable<LocalSymbol, bool> (direct_hash, direct_equal);
		foreach (var argument in arguments) {
			var record = argument as CheckedStructArgument;
			var moved = record == null ? null : record.producer as CheckedStructMoveProducer;
			if (moved == null) {
				continue;
			}
			if (record_moves.contains (moved.source)) {
				fail (argument.span, "duplicate record MOVE_VALUE argument for '%s'".printf (moved.source.name));
				return false;
			}
			record_moves.insert (moved.source, true);
			record_all_events (GenericOwnershipEventKind.MOVE, moved.source, argument.span);
			if (diagnostic != null) {
				return false;
			}
		}
		return true;
	}

	private CheckedExpression? check_argument(ExpressionSyntax syntax, ValueScope values, string name, ParameterSymbol parameter, SemanticType expected, int index, bool task_creation = false) {
		if (parameter.requires_nonnull && checking_function != null && !nonnull_definitions.find (checking_function)) {
			nonnull_definitions.add (checking_function);
		}
		if (syntax is CallExpressionSyntax && is_shared_call ((CallExpressionSyntax) syntax) && ((CallExpressionSyntax) syntax).identifier.spelling () == "shared_borrow") {
			return check_shared_call ((CallExpressionSyntax) syntax, values, false, parameter);
		}
		if (parameter.semantic_type is TypeParameterType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
			while (syntax is ParenthesizedExpressionSyntax) {
				syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
			}
			if (!GenericBorrowTypes.accepts (expected)) {
				fail (syntax.span, "generic borrowed T requires an exact nominal Resource or Class specialization");
				return null;
			}
			if (!check_generic_borrow_source (syntax, values)) {
				return null;
			}
		}
		if (expected is EnumType) {
			var producer = check_enum_producer (syntax, values, (EnumType) expected, false, true);
			return producer == null ? null : new CheckedEnumArgument (syntax.span, parameter, producer);
		}
		if (expected.is_struct_storage ()) {
			var producer = parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.BORROW_VALUE ? check_struct_borrow (syntax, values, expected) : check_struct_producer (syntax, values, expected, true);
			if (producer == null) {
				return null;
			}
			return new CheckedStructArgument (syntax.span, parameter, producer);
		}
		if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
			if (task_creation) {
				while (syntax is ParenthesizedExpressionSyntax) {
					syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
				}
			}
			var move_syntax = syntax as MoveExpressionSyntax;
			if (task_creation && move_syntax == null && !(syntax is NullPointerExpressionSyntax)) {
				var producer = (expected is SliceType) ? check_buffer_producer (syntax, values, (SliceType) expected) : check_expression (syntax, values, expected, OwnershipUse.ACQUIRE);
				var cleanup = (expected is HandleType) ? handle_types.lookup (expected).cleanup : null;
				if (producer == null) {
					return null;
				}
				if (producer.semantic_type != expected || ((expected is SliceType) ? !producer.owns_buffer : !(producer is CheckedCallExpression) || producer.owned_cleanup != cleanup)) {
					fail (syntax.span, "fresh async owned capture requires an exact owned buffer/Resource producer and declared cleanup");
					return null;
				}
				return new CheckedOwnedArgument (syntax.span, parameter, cleanup, null, null, expected, producer);
			}
			if (move_syntax == null && !(syntax is NullPointerExpressionSyntax)) {
				fail (syntax.span, "owned parameter '%s' requires explicit 'move owner' or null; unmanaged and borrowed values carry no transferable responsibility".printf (parameter.name));
				return null;
			}
			if ((expected is TypeParameterType || expected is SliceType) && move_syntax == null) {
				fail (syntax.span, "Ownable T requires explicit move; generic null construction is unsupported");
				return null;
			}
			// A consumer commits named buffer/generic moves only after every
			// argument succeeds. Nested completed consumers commit separately.
			bool previous_capture = enum_buffer_capture;
			enum_buffer_capture = true;
			var transfer = move_syntax == null ? null : check_move (move_syntax, values);
			enum_buffer_capture = previous_capture;
			if (move_syntax != null && transfer == null) {
				return null;
			}
			var generic_target = function_names.lookup (name) as GenericFunctionSymbol;
			bool symbolic_class = generic_target != null && parameter.semantic_type is ClassType;
			bool heap_generic = (parameter.semantic_type is TypeParameterType || symbolic_class) && transfer != null && transfer.object_owner != null && transfer.source.heap_object;
			if (heap_generic && checking_function != null && checking_function.async_body != null) {
				fail (syntax.span, "heap generic consumption requires a synchronous caller");
				return null;
			}
			if (!heap_generic && !symbolic_class && transfer != null && transfer.object_owner != null && transfer.source.heap_object != parameter.heap_object) {
				fail (syntax.span, "owned Class argument changed the parameter's resolved heap or lexical allocation origin");
				return null;
			}
			var object_owner = instance_for (expected) as ClassSymbol;
			var cleanup = object_owner == null && !(expected is TypeParameterType) && !(expected is SliceType) ? handle_types.lookup (expected).cleanup : null;
			if (transfer != null && (transfer.semantic_type != expected && !((parameter.heap_object || symbolic_class) && transfer.source.heap_object && transfer.semantic_type is ClassType && expected is ClassType && ((ClassType) transfer.semantic_type).derives_from ((ClassType) expected)) || transfer.cleanup != cleanup)) {
				fail (syntax.span, "owned argument %d of '%s' requires exact type '%s' and its cleanup contract, found '%s'".printf (index + 1, name, expected.display_name (), transfer.semantic_type.display_name ()));
				return null;
			}
			var result = new CheckedOwnedArgument (syntax.span, parameter, cleanup, transfer, object_owner, expected);
			if (heap_generic) {
				heap_generic_order.add (result);
				heap_generic_requests.insert (result, (GenericFunctionSymbol) function_names.lookup (name));
			} else if ((parameter.semantic_type is TypeParameterType || symbolic_class) && transfer != null && transfer.object_owner != null) {
				var target = function_names.lookup (name) as GenericFunctionSymbol;
				if (target != null) {
					lexical_generic_order.add (result);
					lexical_generic_requests.insert (result, target);
				}
			}
			return result;
		}
		return check_expression (syntax, values, expected, OwnershipUse.UNMANAGED, parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE ? parameter : null);
	}

	private GenericArray<CheckedExpression>? check_arguments(CallExpressionSyntax syntax, ValueScope values, DirectCallableSymbol target, bool requires_value, TypeSubstitution? substitution = null, GenericArray<CheckedNode?>? checked_arguments = null, GenericArray<SemanticOwnershipFlow?>? argument_flows = null) {
		string name = target.name;
		var signal_method = target as MethodSymbol;
		var signal_syntax = signal_method == null ? null : method_syntax.lookup (signal_method);
		bool signal = signal_syntax != null && signal_syntax.is_signal;
		if (signal != syntax.signal_emission || signal && (requires_value || checking_function == null || checking_function.implicit_receiver == null || checking_function.implicit_receiver.semantic_type != signal_method.declaring_type.receiver_type || syntax.receiver == null || syntax.receiver.spelling () != "this")) {
			fail (syntax.span, "only the defining Class emits its signal using emit name(args)");
			return null;
		}
		if (target is FunctionSymbol && ((FunctionSymbol) target).foreign_import != null && ((FunctionSymbol) target).foreign_import.root.api.active_personalities == 0) {
			fail (syntax.span, "call requires an unselected foreign personality: " + name);
			return null;
		}
		if (!check_argument_count (syntax, target)) {
			return null;
		}
		if (requires_value && target.return_type == types.void_type && (!(target is FunctionSymbol) || ((FunctionSymbol) target).async_body == null)) {
			fail (syntax.span, "void function '%s' cannot be used as a value".printf (name));
			return null;
		}
		Diagnostic? completion_error;
		var completed = CallerInformation.complete (syntax, target, types, out completion_error);
		if (completed == null) {
			fail (completion_error.span, completion_error.message);
			return null;
		}
		uint reservation_depth = enum_reservations.length;
		uint borrow_depth = pending_field_borrows.length;
		uint record_loan_depth = pending_record_borrows.length;
		uint shared_borrow_depth = shared_borrow_guards.length;
		uint lazy_borrow_depth = pending_lazy_borrows.length;
		var arguments = new GenericArray<CheckedExpression> ();
		for (int i = 0; i < syntax.arguments.length; i++) {
			var expected = substitution == null ? target.parameters[i].semantic_type : substitution.apply (target.parameters[i].semantic_type);
			var parameter = target.parameters[i];
			var cached = checked_arguments == null ? null : checked_arguments[i];
			var move_syntax = syntax.arguments[i] as MoveExpressionSyntax;
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && move_syntax != null) {
				var source = values.lookup (move_syntax.source.spelling ()) as LocalSymbol;
				if (source != null && source.semantic_type == expected) {
					foreach (var prior in arguments) {
						var owned_argument = prior as CheckedOwnedArgument;
						if (owned_argument != null && owned_argument.transfer != null && owned_argument.transfer.source == source) {
							fail (move_syntax.span, "use of moved owned value '%s'".printf (source.name));
							return null;
						}
					}
				}
			}
			CheckedExpression? argument = (cached is CheckedStructProducer) ? new CheckedStructArgument (syntax.arguments[i].span, parameter, (CheckedStructProducer) cached) : (cached as CheckedExpression);
			if (argument == null) {
				var previous_loan_argument = direct_loan_argument;
				if (target is FunctionSymbol && ((FunctionSymbol) target).async_body != null && syntax == direct_await_creation && expected is SliceType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
					direct_loan_argument = syntax.arguments[i];
					while (direct_loan_argument is ParenthesizedExpressionSyntax) {
						direct_loan_argument = ((ParenthesizedExpressionSyntax) direct_loan_argument).expression;
					}
				}
				argument = check_argument (syntax.arguments[i], values, name, parameter, expected, i, target is FunctionSymbol && ((FunctionSymbol) target).async_body != null);
				direct_loan_argument = previous_loan_argument;
			} else if (generic_owner_flow != null && argument_flows[i] != null) {
				generic_owner_flow.append (argument_flows[i]);
			}
			if (argument == null) {
				return null;
			}
			if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER && !(parameter.semantic_type is TypeParameterType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE)) {
				argument = upcast_class (argument, expected);
			}
			if (argument.semantic_type != expected) {
				fail (argument.span, "argument %d of function '%s' expects type '%s', provided '%s'".printf (i + 1, name, expected.display_name (), argument.semantic_type.display_name ()));
				return null;
			}
			var transfer = (argument is CheckedOwnedArgument) ? ((CheckedOwnedArgument) argument).transfer : null;
			if (transfer != null) {
				foreach (var prior in arguments) {
					var owned_argument = prior as CheckedOwnedArgument;
					if (owned_argument != null && owned_argument.transfer != null && owned_argument.transfer.source == transfer.source) {
						fail (syntax.arguments[i].span, "use of moved owned value '%s'".printf (transfer.source.name));
						return null;
					}
				}
			}
			foreach (var prior in arguments) {
				var captured = prior as CheckedOwnedBorrowValue;
				var incoming = argument as CheckedOwnedArgument;
				var reverse = argument as CheckedOwnedBorrowValue;
				var outgoing = prior as CheckedOwnedArgument;
				if (captured != null && captured.semantic_type is CallbackType && incoming != null && incoming.transfer != null && incoming.transfer.source == captured.source || reverse != null && reverse.semantic_type is CallbackType && outgoing != null && outgoing.transfer != null && outgoing.transfer.source == reverse.source) {
					fail (syntax.span, "captured callback borrow overlaps transfer of its Closure owner");
					return null;
				}
			}
			arguments.add (argument);
			var record_argument = argument as CheckedStructArgument;
			var record_loan = record_argument == null ? null : record_argument.producer as CheckedStructBorrowSnapshot;
			var record_place = record_loan == null ? null : record_loan.source as CheckedLocalPlace;
			if (record_place != null) {
				pending_record_borrows.add (record_place.local);
			}
			if (argument is CheckedOwnedFieldBorrow || argument is CheckedStructProjectionValue || argument is CheckedStructArgument) {
				reserve_receiver_loans (argument);
			}
			var property_borrow = argument as CheckedPropertyGetExpression;
			if (property_borrow != null && property_borrow.property_symbol.is_borrowed) {
				(property_borrow.property_symbol.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (property_borrow.property_symbol.declaring_type.semantic_type);
			}
			if (argument is CheckedSlotsValue && ((CheckedSlotsValue) argument).action == OwnerSlotsAction.BORROW) {
				var slot = (CheckedSlotsValue) argument;
				var function = target as FunctionSymbol;
				if (function == null || (function.kind != CallableKind.FUNCTION && function.kind != CallableKind.METHOD) || function is GenericFunctionSymbol || function.async_body != null || function.throws_type != null || !ReadonlyInspection.copied_result (function.return_type, copy_fields)) {
					fail (syntax.span, "indexed owner inspection requires a synchronous nonthrowing concrete native function or method with a copied result");
					return null;
				}
				if (foreach_depth != 0 || function.kind == CallableKind.METHOD) {
					readonly_inspection.require (function);
				}
				pending_field_borrows.add (slot.field.containing_type.semantic_type);
			}
		}
		foreach (var argument in completed) {
			arguments.add (argument);
		}
		if (!commit_record_arguments (arguments)) {
			return null;
		}
		while (enum_reservations.length > reservation_depth) {
			var source = enum_reservations[reservation_depth];
			if (generic_owner_flow != null) {
				CheckedOwnedArgument? outgoing = null;
				foreach (var argument in arguments) {
					var owned = argument as CheckedOwnedArgument;
					if (owned != null && owned.transfer != null && owned.transfer.source == source) {
						outgoing = owned;
					}
				}
				generic_owner_flow.move (source, source.name, syntax.span, target, outgoing == null ? -1 : outgoing.parameter.ordinal);
			}
			enum_reservations.remove_index (reservation_depth);
		}
		// Direct views remain live through all argument evaluation. A copied
		// element or completed inner call has no such outstanding view.
		foreach (var argument in arguments) {
			var borrow = argument as CheckedOwnedBufferBorrow;
			if (generic_owner_flow != null && borrow != null) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, borrow.source, borrow.source.name, argument.span);
			}
			var owner_borrow = argument as CheckedOwnedBorrowValue;
			if (generic_owner_flow != null && owner_borrow != null && owner_borrow.source.is_generic_owner) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, owner_borrow.source, owner_borrow.source.name, argument.span);
			}
		}
		foreach (var owner_type in pending_field_borrows) {
			var native = target as FunctionSymbol;
			bool scoped_method = false;
			if (native != null && native.kind == CallableKind.METHOD) {
				foreach (var argument in arguments) {
					var slot = argument as CheckedSlotsValue;
					if (slot != null && slot.action == OwnerSlotsAction.BORROW) {
						scoped_method = true;
					}
				}
			}
			bool receiver_overlap = !scoped_method && native != null && !(native is ConstructorSymbol) && native.implicit_receiver != null && field_overlap (native.implicit_receiver.semantic_type.instance_type, owner_type);
			foreach (var argument in arguments) {
				if (field_overlap (argument.semantic_type, owner_type)) {
					receiver_overlap = true;
				}
			}
			if (receiver_overlap) {
				fail (syntax.span, "temporary owned-field borrow overlaps a possibly aliasing containing-object argument or receiver; finish the borrow before passing the object");
				return null;
			}
		}
		while (pending_field_borrows.length > borrow_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		foreach (var owner_type in pending_lazy_borrows) {
			var native = target as FunctionSymbol;
			bool overlap = native != null && native.implicit_receiver != null && field_overlap (native.implicit_receiver.semantic_type.instance_type, owner_type);
			foreach (var argument in arguments) {
				if (field_overlap (argument.semantic_type, owner_type)) {
					overlap = true;
				}
			}
			if (overlap) {
				fail (syntax.span, "receiver-owned lazy loan overlaps a containing-owner call or transfer");
				return null;
			}
		}
		while (pending_lazy_borrows.length > lazy_borrow_depth) {
			pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
		}
		while (shared_borrow_guards.length > shared_borrow_depth) {
			shared_borrow_guards.remove_index (shared_borrow_guards.length - 1);
		}
		while (pending_record_borrows.length > record_loan_depth) {
			pending_record_borrows.remove_index (pending_record_borrows.length - 1);
		}
		return arguments;
	}

	private CheckedIntegerExpression? check_integer(IntegerLiteralExpressionSyntax literal, SourceSpan span, IntegerType type, bool negative = false) {
		if (negative && !type.is_signed) {
			fail (span, "unary '-' is not supported for unsigned integer type '%s'".printf (type.display_name ()));
			return null;
		}
		var value = AstraIntegerValue.from_decimal_magnitude (type, literal.literal.spelling (), negative);
		if (value == null) {
			fail (span, "integer literal is out of range for '%s'".printf (type.display_name ()));
			return null;
		}
		return new CheckedIntegerExpression.typed (span, type, value);
	}

	private bool thread_capture_type(SemanticType type, HashTable<SemanticType, bool> seen, bool mailbox_graph = false, bool affinity_only = false) {
		if (type is ClassType && ((ClassType) type).thread_bound) {
			return false;
		}
		if (affinity_only && type is ClosureHandleType) {
			if (seen.contains (type)) {
				return true;
			}
			seen.insert (type, true);
			return thread_capture_type (((ClosureHandleType) type).environment_type, seen, mailbox_graph, true);
		}
		var shared = type as SharedHandleType;
		if (shared != null && affinity_only) {
			return thread_capture_type (shared.payload_type, seen, mailbox_graph, true);
		}
		if (shared != null) {
			var payload = instance_for (shared.payload_type) as ClassSymbol;
			return payload != null && shared.payload_type.monitored && !shared.payload_type.thread_bound && (payload.allocation_policy == null || payload.allocation_policy.kind == Astra.Source.AllocationKind.CONTEXT && payload.allocation_policy.context_mode == "owned-concurrent") && thread_capture_type (shared.payload_type, seen, mailbox_graph, affinity_only);
		}

		if (type is ClosureHandleType && ((ClosureHandleType) type).actor) {
			return !mailbox_graph && ((ClosureHandleType) type).supported ();
		}
		if (type is HandleType) {
			var context = ((HandleType) type).context_mode;
			return context != "" ? context == "owned-concurrent" : affinity_only;
		}
		if (type is RawPointerType || type is TypedPointerType) {
			return false;
		}
		if (type is StringType || FunctionValueType.scalar (type) || type is VectorType) {
			return true;
		}
		if (seen.contains (type)) {
			return true;
		}
		seen.insert (type, true);
		if (type is ContextBytesType && ((ContextBytesType) type).context_mode != "owned-concurrent") {
			return false;
		}
		if (type is SliceType) {
			return thread_capture_type (((SliceType) type).element_type, seen, mailbox_graph, affinity_only);
		}
		if (type is OwnerSlotsType) {
			return thread_capture_type (((OwnerSlotsType) type).element, seen, mailbox_graph, affinity_only);
		}
		var owner = instance_for (type);
		if (owner == null) {
			return false;
		}
		var object_class = owner as ClassSymbol;
		if (object_class != null && object_class.allocation_policy != null) {
			var policy = object_class.allocation_policy;
			if (policy.kind == AllocationKind.CONTEXT ? policy.context_mode != "owned-concurrent" : !affinity_only) {
				return false;
			}
		}
		if (!affinity_only && object_class != null && ((ClassType) type).intrinsically_shared && !((ClassType) type).monitored) {
			return false;
		}
		if (object_class != null && object_class.polymorphic) {
			foreach (var instance in instance_types.get_values ()) {
				var derived = instance as ClassSymbol;
				if (derived == null || derived == object_class) {
					continue;
				}
				for (var parent = derived.parent_class; parent != null; parent = parent.parent_class) {
					if (parent == object_class) {
						if (!thread_capture_type (derived.semantic_type, seen, mailbox_graph, affinity_only)) {
							return false;
						}
						break;
					}
				}
			}
		}
		foreach (var field in owner.fields) {
			if (!thread_capture_type (field.semantic_type, seen, mailbox_graph, affinity_only)) {
				return false;
			}
		}
		return object_class == null || object_class.parent_class == null || thread_capture_type (object_class.parent_class.semantic_type, seen, mailbox_graph, affinity_only);
	}
	private bool closure_capture_type(SemanticType type, HashTable<SemanticType, bool> seen) {
		if (type is RawPointerType || type is TypedPointerType) {
			return false;
		}
		if (type is HandleType || type is StringType || FunctionValueType.scalar (type) || type is VectorType) {
			return true;
		}
		if (seen.contains (type)) {
			return true;
		}
		seen.insert (type, true);
		if (type is SliceType) {
			return closure_capture_type (((SliceType) type).element_type, seen);
		}
		if (type is OwnerSlotsType) {
			return closure_capture_type (((OwnerSlotsType) type).element, seen);
		}
		var owner = instance_for (type);
		if (owner != null) {
			foreach (var field in owner.fields) {
				if (!closure_capture_type (field.semantic_type, seen)) {
					return false;
				}
			}
			var object_class = owner as ClassSymbol;
			return object_class == null || object_class.parent_class == null || closure_capture_type (object_class.parent_class.semantic_type, seen);
		}
		var fields = copy_fields (type);
		if (fields == null) {
			return false;
		}
		foreach (var field in fields) {
			if (!closure_capture_type (field, seen)) {
				return false;
			}
		}
		return true;
	}
	private GenericArray<CheckedExpression>? check_indirect_arguments(CallExpressionSyntax call, ValueScope values, CallableSignature type, int first, string kind, out GenericArray<ParameterSymbol> channels) {
		uint reservation_depth = enum_reservations.length;
		uint record_depth = pending_record_borrows.length;
		uint borrow_depth = pending_field_borrows.length;
		uint lazy_depth = pending_lazy_borrows.length;
		uint named_depth = pending_callable_borrows.length;
		uint transfer_depth = pending_callable_transfers.length;
		channels = new GenericArray<ParameterSymbol> ();
		if (type.has_owner_channels ()) {
			for (int p = 0; p < type.parameter_types.length; p++) {
				var channel = new ParameterSymbol (call.span, call.identifier.span, type.parameter_types[p], p, type.parameter_contract (p), "$channel%d".printf (p));
				channel.heap_object = CallableRecordGroups.heap_parameter (type, p);
				if (type.parameter_types[p].is_struct_storage ()) {
					channel.struct_value_contract = new StructValueContract (type.parameter_types[p], type.parameter_contract (p) == PointerParameterContract.BORROWED_NOESCAPE ? StructValueMode.BORROW_VALUE : struct_value_mode (type.parameter_types[p]));
				}
				channels.add (channel);
			}
		}
		var arguments = new GenericArray<CheckedExpression> ();
		for (int i = 0; i < type.parameter_types.length; i++) {
			CheckedExpression? argument;
			if (type.parameter_types[i].is_struct_storage ()) {
				var producer = type.parameter_contract (i) == PointerParameterContract.BORROWED_NOESCAPE ? check_struct_borrow (call.arguments[i + first], values, type.parameter_types[i]) : check_struct_producer (call.arguments[i + first], values, type.parameter_types[i], true);
				argument = producer == null ? null : new CheckedStructArgument (call.arguments[i + first].span, null, producer);
			} else {
				argument = channels.length == 0 ? check_expression (call.arguments[i + first], values, type.parameter_types[i]) : check_argument (call.arguments[i + first], values, call.identifier.spelling (), channels[i], type.parameter_types[i], i);
			}
			if (argument is CheckedOwnedBorrowValue) {
				pending_callable_borrows.add (((CheckedOwnedBorrowValue) argument).source);
			}
			var transfer = argument as CheckedOwnedArgument;
			if (transfer != null && transfer.transfer != null) {
				pending_callable_transfers.add (transfer.transfer.source);
			}
			if (argument is CheckedSlotsValue) {
				fail (argument.span, "indirect indexed inspection requires a declared readonly callable contract");
				return null;
			}
			if (argument is CheckedOwnedFieldBorrow || argument is CheckedStructProjectionValue || argument is CheckedStructArgument) {
				reserve_receiver_loans (argument);
			}
			var loan = argument as CheckedPropertyGetExpression;
			if (loan != null && loan.property_symbol.is_borrowed) {
				(loan.property_symbol.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (loan.property_symbol.declaring_type.semantic_type);
			}
			if (argument == null) {
				return null;
			}
			if (argument.semantic_type != type.parameter_types[i]) {
				fail (argument.span, kind == "Fn" ? "function value argument requires its exact scalar type" : "closure invocation argument requires its exact scalar signature type");
				return null;
			}
			var record_argument = argument as CheckedStructArgument;
			var record_loan = record_argument == null ? null : record_argument.producer as CheckedStructBorrowSnapshot;
			var record_place = record_loan == null ? null : record_loan.source as CheckedLocalPlace;
			if (record_place != null) {
				pending_record_borrows.add (record_place.local);
			}
			arguments.add (argument);
		}
		foreach (var owner_type in pending_field_borrows) {
			var closure = type as ClosureHandleType;
			if (closure != null && field_overlap (closure.environment_type, owner_type)) {
				fail (call.span, "borrowed argument overlaps a possibly aliasing closure environment");
				return null;
			}
			foreach (var argument in arguments) {
				if (field_overlap (argument.semantic_type, owner_type)) {
					fail (call.span, "temporary owned-field borrow overlaps a containing-object indirect argument");
					return null;
				}
			}
		}
		foreach (var owner_type in pending_lazy_borrows) {
			var closure = type as ClosureHandleType;
			if (closure != null && field_overlap (closure.environment_type, owner_type)) {
				fail (call.span, "lazy loan overlaps a possibly aliasing closure environment");
				return null;
			}
			foreach (var argument in arguments) {
				if (field_overlap (argument.semantic_type, owner_type)) {
					fail (call.span, "receiver-owned lazy loan overlaps a containing-owner indirect argument");
					return null;
				}
			}
		}
		while (pending_field_borrows.length > borrow_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		while (pending_lazy_borrows.length > lazy_depth) {
			pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
		}
		while (pending_callable_borrows.length > named_depth) {
			pending_callable_borrows.remove_index (pending_callable_borrows.length - 1);
		}
		while (pending_record_borrows.length > record_depth) {
			pending_record_borrows.remove_index (pending_record_borrows.length - 1);
		}
		while (pending_callable_transfers.length > transfer_depth) {
			pending_callable_transfers.remove_index (pending_callable_transfers.length - 1);
		}
		while (enum_reservations.length > reservation_depth) {
			var source = enum_reservations[reservation_depth];
			if (!source.is_generic_owner) {
				reservation_depth++;
				continue;
			}
			if (generic_owner_flow != null) {
				foreach (var argument in arguments) {
					var outgoing = argument as CheckedOwnedArgument;
					if (outgoing != null && outgoing.transfer != null && outgoing.transfer.source == source) {
						generic_owner_flow.move (source, source.name, call.span, type as Object, outgoing.parameter.ordinal);
					}
				}
			}
			enum_reservations.remove_index (reservation_depth);
		}
		return arguments;
	}

	private ClosureHandleType substitute_closure(ClosureHandleType original, ClassType environment, GenericArray<SemanticType> parameters, SemanticType result) {
		var contracts = new GenericArray<PointerParameterContract> ();
		for (int p = 0; p < parameters.length; p++) {
			contracts.add (original.parameter_contract (p));
		}
		return closure_type (environment, result, parameters, handle_types.lookup (original).span, original.throws_type, original.threaded, original.actor, contracts, original.result_contract);
	}
	private ClosureHandleType closure_type(ClassType environment, SemanticType result, GenericArray<SemanticType> parameters, SourceSpan span, ClassType? throws_type = null, bool threaded = false, bool actor = false, GenericArray<PointerParameterContract>? contracts = null, ResultOwnershipContract result_contract = ResultOwnershipContract.UNMANAGED) {
		foreach (var symbol in shared_handle_inventory) {
			var prior = symbol.semantic_type as ClosureHandleType;
			if (prior == null || prior.actor != actor || prior.threaded != threaded || prior.environment_type != environment || prior.throws_type != throws_type || prior.result_type != result || prior.result_contract != result_contract || prior.parameter_types.length != parameters.length) {
				continue;
			}
			bool same = true;
			for (int p = 0; p < parameters.length; p++) {
				if (parameters[p] != prior.parameter_types[p] || prior.parameter_contract (p) != (contracts == null ? PointerParameterContract.UNMANAGED : contracts[p])) {
					same = false;
				}
			}
			if (same) {
				return prior;
			}
		}
		var type = new ClosureHandleType (environment, result, parameters, throws_type, threaded, actor, contracts, result_contract);
		var cleanup = new CForeignCleanupContract ("astra.native." + type.name, span);
		var symbol = new HandleSymbol.closure (span, type, cleanup, shared_handle_inventory.length);
		shared_handle_inventory.add (symbol);
		handle_types.insert (type, symbol);
		return type;
	}
	private static bool is_closure_call(CallExpressionSyntax call) {
		return call.receiver == null && call.receiver_place == null && (call.identifier.spelling () == "actor_bind" || call.identifier.spelling () == "thread_bind" || call.identifier.spelling () == "closure_bind" || call.identifier.spelling () == "checked_closure_bind" || call.identifier.spelling () == "closure_invoke" || (call.identifier.spelling () == "thread_start" || call.identifier.spelling () == "thread_join" || call.identifier.spelling () == "thread_cancel" || call.identifier.spelling () == "retained_signal_register" || call.identifier.spelling () == "retained_signal_revoke" || call.identifier.spelling () == "retained_signal_observe" || call.identifier.spelling () == "retained_register" || call.identifier.spelling () == "retained_dispatch" || call.identifier.spelling () == "retained_revoke" || call.identifier.spelling () == "retained_observe"));
	}
	private CheckedStatement? check_actor_send(CallExpressionSyntax call, ValueScope values) {
		var action = call.identifier.spelling () == "actor_send" ? ActorAction.SEND : call.identifier.spelling () == "actor_shutdown" ? ActorAction.SHUTDOWN : ActorAction.CANCEL;
		if (checking_function == null || checking_function.async_body != null || checking_function is GenericFunctionSymbol || call.type_arguments.length != 0 || call.arguments.length != (action == ActorAction.SEND ? 2 : 1)) {
			fail (call.span, "Actor operations require synchronous exact typed sender and message arity");
			return null;
		}
		var syntax = call.arguments[0] as NameExpressionSyntax;
		var binding = syntax == null ? null : values.lookup (syntax.identifier.spelling ());
		CheckedExpression? sender = null;
		if (binding is LocalSymbol && ((LocalSymbol) binding).is_owned && ((LocalSymbol) binding).cleanup != null) {
			sender = new CheckedLocalReferenceExpression (syntax.span, (LocalSymbol) binding);
		} else if (binding is ParameterSymbol && ((ParameterSymbol) binding).pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
			sender = new CheckedParameterReferenceExpression (syntax.span, (ParameterSymbol) binding);
		}
		var type = sender == null ? null : sender.semantic_type as ClosureHandleType;
		if (type == null || !type.actor || !type.supported ()) {
			fail (call.span, "Actor operation requires a live owned sender or exact borrowed sender parameter");
			return null;
		}
		if (exception_root == null || exception_root.constructor == null || exception_root.constructor.throws_type != null || exception_root.constructor.parameters.length != 1 || !(exception_root.constructor.parameters[0].semantic_type is StringType) || !check_exception_effect ((ClassType) exception_root.semantic_type, call.span)) {
			if (diagnostic == null) {
				fail (call.span, "Actor admission requires nominated Error with a nonthrowing one-string constructor");
			}
			return null;
		}
		CheckedExpression? scalar = null;
		LocalSymbol? message = null;
		if (action == ActorAction.SEND) {
			if (type.actor_message is ClassType) {
				var moved = call.arguments[1] as MoveExpressionSyntax;
				var incoming = moved == null ? null : check_move (moved, values);
				if (incoming == null || incoming.semantic_type != type.actor_message || !incoming.source.heap_object || incoming.object_owner == null || incoming.object_owner.polymorphic) {
					if (diagnostic == null) {
						fail (call.span, "Actor send consumes one explicit move of the exact independently heap-owned message on every outcome");
					}
					return null;
				}
				message = incoming.source;
			} else {
				scalar = check_expression (call.arguments[1], values, type.actor_message);
				if (scalar == null || scalar.semantic_type != type.actor_message) {
					if (diagnostic == null) {
						fail (call.span, "Actor scalar message requires its exact copied scalar type");
					}
					return null;
				}
			}
		}
		return new CheckedActorSend (call.span, action, sender, scalar, message, (ClassType) exception_root.semantic_type);
	}
	private CheckedNode? check_closure_call(CallExpressionSyntax call, ValueScope values, bool acquire, bool allow_struct = false) {
		if (checking_function != null && checking_function.async_body != null) {
			fail (call.span, "Closure operations require a synchronous caller");
			return null;
		}
		if (call.type_arguments.length != 0) {
			fail (call.span, "Closure operations infer their exact environment and signature");
			return null;
		}
		if (call.identifier.spelling () == "actor_bind" || call.identifier.spelling () == "thread_bind" || call.identifier.spelling () == "closure_bind" || call.identifier.spelling () == "checked_closure_bind") {
			bool actor = call.identifier.spelling () == "actor_bind";
			bool checked_target = call.identifier.spelling () == "checked_closure_bind";
			bool threaded = call.identifier.spelling () == "thread_bind";
			if (!acquire || call.arguments.length != (actor ? 4 : 2)) {
				fail (call.span, "closure_bind requires a fresh owned destination, one moved heap environment and a named native code function");
				return null;
			}
			var move_syntax = call.arguments[0] as MoveExpressionSyntax;
			var moved = move_syntax == null ? null : check_move (move_syntax, values);
			if (moved == null || !moved.source.heap_object || moved.object_owner == null || moved.object_owner.polymorphic || !(moved.semantic_type is ClassType) || !ClosureHandleType.supports_environment ((ClassType) moved.semantic_type, threaded || actor)) {
				if (diagnostic == null) {
					fail (call.span, "closure_bind environment requires explicit move of an exact nonpolymorphic nongeneric independently heap-allocated Class owner");
				}
				return null;
			}
			if (((ClassType) moved.semantic_type).concurrency_policy_identity == 16 && !actor) {
				fail (call.span, "Actor receivers transfer exclusively into actor_bind");
				return null;
			}
			if (!closure_capture_type (moved.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
				fail (call.span, "closure environment and owned child captures cannot contain unmanaged raw or typed pointers");
				return null;
			}
			var code_syntax = call.arguments[1];
			FunctionSymbol? target = null;
			if (code_syntax is NameExpressionSyntax) {
				var token = ((NameExpressionSyntax) code_syntax).identifier;
				if (values.lookup (token.spelling ()) == null) {
					target = find_function (token) as FunctionSymbol;
				}
			} else if (code_syntax is FieldAccessExpressionSyntax) {
				var field = (FieldAccessExpressionSyntax) code_syntax;
				if (field.aggregate == null && values.lookup (field.identifier.spelling ()) == null && module_names.contains (field.identifier.spelling ())) {
					target = function_names.lookup (resolve_name (code_syntax.span, field.identifier.spelling () + "." + field.field_name.spelling (), false)) as FunctionSymbol;
				}
			}
			if (target == null || target is MethodSymbol || target is GenericFunctionSymbol || target.async_body != null || (checked_target ? target.throws_type == null : target.throws_type != null) || !FunctionValueType.supported_result (target.return_type, target.result_contract) || target.parameters.length < 1 || target.parameters.length > 5 || target.parameters[0].semantic_type != moved.semantic_type || target.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				fail (code_syntax.span, checked_target ? "checked closure code requires an exact throwing native function with first borrowed environment parameter and copied scalar result/arguments" : "closure code requires an exact nonthrowing native function with first borrowed environment parameter and copied scalar result/arguments");
				return null;
			}
			var parameters = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			for (int p = 1; p < target.parameters.length; p++) {
				var parameter = target.parameters[p];
				if (actor ? !(FunctionValueType.scalar (parameter.semantic_type) && parameter.pointer_contract == PointerParameterContract.UNMANAGED || parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && parameter.heap_object) : !((FunctionValueType.scalar (parameter.semantic_type) || !threaded && parameter.semantic_type.is_struct_storage ()) && parameter.pointer_contract == PointerParameterContract.UNMANAGED || !threaded && (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && (parameter.semantic_type is ClassType || parameter.semantic_type.get_type () == typeof (HandleType) || parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.BORROW_VALUE) || parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (parameter.semantic_type.get_type () == typeof (HandleType) || parameter.semantic_type is ClassType && parameter.heap_object)))) {
					fail (code_syntax.span, "closure code arguments require exact copied scalar types");
					return null;
				}
				parameters.add (parameter.semantic_type);
				contracts.add (actor ? PointerParameterContract.UNMANAGED : parameter.pointer_contract);
			}
			if (threaded && (!thread_capture_type (moved.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal)) || target.return_type != types.int_type || parameters.length != 1 || parameters[0] != types.int_type)) {
				fail (call.span, "thread_bind requires a Send environment without thread-bound, raw-pointer or unqualified shared captures, and an int,int nonthrowing target");
				return null;
			}
			ActorBindingSpec? spec = null;
			if (actor) {
				var capacity = call.arguments[2] as IntegerLiteralExpressionSyntax;
				var name = call.arguments[3] as TextLiteralExpressionSyntax;
				int slots = 0;
				var label = new StringBuilder ();
				if (name != null) {
					if (name.payload.byte_length < 1 || name.payload.byte_length > 15) {
						fail (call.span, "Actor executor name requires 1..15 printable ASCII bytes");
						return null;
					}
					for (int b = 0; b < name.payload.byte_length; b++) {
						uint8 code = name.payload.byte_at (b);
						if (code < 32 || code > 126) {
							fail (call.span, "Actor executor name cannot contain NUL, control or non-ASCII bytes");
							return null;
						}
						label.append_c ((char) code);
					}
				}
				if (capacity == null || !int.try_parse (capacity.literal.spelling (), out slots) || name == null) {
					fail (call.span, "actor_bind requires literal mailbox capacity and executor name");
					return null;
				}
				spec = new ActorBindingSpec (slots, label.str);
				if (!spec.valid () || ((ClassType) moved.semantic_type).concurrency_policy_identity != 16 || target.return_type != types.int_type || parameters.length != 1 || !thread_capture_type (moved.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true) || !thread_capture_type (parameters[0], new HashTable<SemanticType, bool> (direct_hash, direct_equal), true)) {
					fail (call.span, "Actor binding requires exclusive Actor receiver, Send message, nonthrowing int handler, bounded FIFO and named executor; sender cycles are refused");
					return null;
				}
			}
			var type = closure_type ((ClassType) moved.semantic_type, target.return_type, parameters, call.span, target.throws_type, threaded, actor, contracts, target.result_contract);
			if (!type.supported ()) {
				fail (call.span, "unsupported native closure or Actor handler profile");
				return null;
			}
			return new CheckedClosureBind (call.span, type, moved.source, target, handle_types.lookup (type).cleanup, spec);
		}
		if (call.identifier.spelling ().has_prefix ("retained_") || call.identifier.spelling ().has_prefix ("thread_")) {
			return check_retained_call (call, values);
		}
		if (call.arguments.length < 1) {
			fail (call.span, "closure_invoke requires a borrowed typed closure and its exact scalar arguments");
			return null;
		}
		var syntax = call.arguments[0] as NameExpressionSyntax;
		var binding = syntax == null ? null : values.lookup (syntax.identifier.spelling ());
		CheckedExpression? callee = null;
		if (binding is LocalSymbol && ((LocalSymbol) binding).is_owned && ((LocalSymbol) binding).cleanup != null && ((LocalSymbol) binding).semantic_type is ClosureHandleType) {
			callee = new CheckedLocalReferenceExpression (syntax.span, (LocalSymbol) binding);
		} else if (binding is ParameterSymbol && ((ParameterSymbol) binding).pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && ((ParameterSymbol) binding).semantic_type is ClosureHandleType) {
			callee = new CheckedParameterReferenceExpression (syntax.span, (ParameterSymbol) binding);
		}
		var type = callee == null ? null : callee.semantic_type as ClosureHandleType;
		if (type == null || type.threaded || type.actor || call.arguments.length != type.parameter_types.length + 1) {
			fail (call.span, "closure_invoke requires a live exact typed closure local or borrowed parameter and exact arity");
			return null;
		}
		uint guard_depth = shared_borrow_guards.length;
		if (binding is LocalSymbol) {
			shared_borrow_guards.add ((LocalSymbol) binding);
		}
		GenericArray<ParameterSymbol> channels;
		var arguments = check_indirect_arguments (call, values, type, 1, "Closure", out channels);
		if (arguments == null) {
			return null;
		}
		while (shared_borrow_guards.length > guard_depth) {
			shared_borrow_guards.remove_index (shared_borrow_guards.length - 1);
		}
		if (type.throws_type != null && !check_exception_effect (type.throws_type, call.span)) {
			return null;
		}
		var invocation = new CheckedClosureCall (call.span, type, callee, arguments);
		invocation.owned_producer = callable_owned_result (type, type.result_type, call.span, acquire);
		if (diagnostic != null) {
			return null;
		}
		foreach (var channel in channels) {
			invocation.channel_parameters.add (channel);
		}
		return indirect_result (invocation, allow_struct);
	}

	private CheckedExpression? check_retained_call(CallExpressionSyntax call, ValueScope values) {
		string name = call.identifier.spelling ();
		RetainedAction action;
		switch (name) {
		case "retained_signal_register": action = RetainedAction.SIGNAL_REGISTER;
			break;
		case "retained_signal_revoke": action = RetainedAction.SIGNAL_REVOKE;
			break;
		case "retained_signal_observe": action = RetainedAction.SIGNAL_OBSERVE;
			break;
		case "thread_start": action = RetainedAction.THREAD_START;
			break;
		case "thread_join": action = RetainedAction.THREAD_JOIN;
			break;
		case "thread_cancel": action = RetainedAction.THREAD_CANCEL;
			break;
		case "retained_register": action = RetainedAction.REGISTER;
			break;
		case "retained_dispatch": action = RetainedAction.DISPATCH;
			break;
		case "retained_revoke": action = RetainedAction.REVOKE;
			break;
		case "retained_observe": action = RetainedAction.OBSERVE;
			break;
			default: fail (call.span, "unsupported retained callback operation or convention");
			return null;
		}
		if (RetainedContracts.signal (action) && foreign_selection >= 0 && (foreign_selection & ForeignClassPolicy.GOBJECT) == 0) {
			fail (call.span, "typed retained signal requires the selected GObject personality");
			return null;
		}
		if (call.arguments.length != RetainedContracts.arity (action) + 1) {
			fail (call.span, "retained callback operation requires exact arity");
			return null;
		}
		var syntax = call.arguments[0] as NameExpressionSyntax;
		var binding = syntax == null ? null : values.lookup (syntax.identifier.spelling ());
		CheckedExpression? callee = null;
		if (binding is LocalSymbol && ((LocalSymbol) binding).is_owned && ((LocalSymbol) binding).cleanup != null) {
			callee = new CheckedLocalReferenceExpression (syntax.span, (LocalSymbol) binding);
		} else if (binding is ParameterSymbol && ((ParameterSymbol) binding).pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
			callee = new CheckedParameterReferenceExpression (syntax.span, (ParameterSymbol) binding);
		}
		if (callee == null || !RetainedContracts.accepts (action, callee.semantic_type)) {
			fail (call.span, RetainedContracts.signal (action) ? "typed retained signal requires a live nonthrowing void Closure with supported copied scalar inputs" : "retained callback requires a live exact owned or borrowed Closure<Env,int,int>; raw C callbacks, checked targets and other conventions are unsupported");
			return null;
		}
		uint depth = shared_borrow_guards.length;
		if (binding is LocalSymbol) {
			shared_borrow_guards.add ((LocalSymbol) binding);
		}
		var arguments = new GenericArray<CheckedExpression> ();
		var type = (ClosureHandleType) callee.semantic_type;
		if (!thread_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), false, true)) {
			fail (call.span, "retained callback cannot capture thread-bound state");
			return null;
		}
		for (int p = 1; p < call.arguments.length; p++) {
			var argument = check_expression (call.arguments[p], values, types.int_type);
			if (argument == null) {
				return null;
			}
			if (argument.semantic_type != types.int_type) {
				fail (argument.span, "retained callback requires exact int argument");
				return null;
			}
			arguments.add (argument);
		}
		while (shared_borrow_guards.length > depth) {
			shared_borrow_guards.remove_index (shared_borrow_guards.length - 1);
		}
		return new CheckedRetainedOperation (call.span, action, callee, arguments, types.int_type);
	}

	private SharedHandleType shared_type(ClassType payload, bool is_weak, SourceSpan span) {
		foreach (var symbol in shared_handle_inventory) {
			var prior = symbol.semantic_type as SharedHandleType;
			if (prior != null && prior.payload_type == payload && prior.is_weak == is_weak) {
				return prior;
			}
		}
		var type = new SharedHandleType (payload, is_weak);
		var cleanup = new CForeignCleanupContract ("astra.native." + type.name, span);
		var symbol = new HandleSymbol.shared (span, type, cleanup, shared_handle_inventory.length);
		shared_handle_inventory.add (symbol);
		handle_types.insert (type, symbol);
		return type;
	}
	private bool intrinsic_shared_call(CallExpressionSyntax call, ValueScope values) {
		if (call.receiver == null || call.receiver_place != null || call.arguments.length != 0 || (call.identifier.spelling () != "clone" && call.identifier.spelling () != "downgrade" && call.identifier.spelling () != "upgrade")) {
			return false;
		}
		var symbol = values.lookup (call.receiver.spelling ());
		SemanticType? type = null;
		if (symbol is LocalSymbol) {
			type = ((LocalSymbol) symbol).semantic_type;
		} else if (symbol is ParameterSymbol) {
			type = ((ParameterSymbol) symbol).semantic_type;
		}
		return type is ClosureHandleType && ((ClosureHandleType) type).actor || type is SharedHandleType || type is ClassType && ((ClassType) type).intrinsically_shared;
	}
	private static bool is_shared_call(CallExpressionSyntax call) {
		if (call.receiver != null || call.receiver_place != null) {
			return false;
		}
		string name = call.identifier.spelling ();
		return name == "actor_clone" || name == "shared_acquire" || name == "shared_clone" || name == "shared_downgrade" || name == "weak_clone" || name == "weak_upgrade" || name == "shared_borrow" || name == "singleton_shutdown";
	}
	private CheckedSharedOperation? check_shared_call(CallExpressionSyntax call, ValueScope values, bool acquire, ParameterSymbol? borrower = null) {
		if (checking_function != null && checking_function.async_body != null) {
			fail (call.span, "Shared/Weak operations require a synchronous single-threaded caller");
			return null;
		}
		bool member = intrinsic_shared_call (call, values);
		if ((!member && call.arguments.length != 1) || call.type_arguments.length != 0) {
			fail (call.span, "Shared/Weak operation requires one exact owner operand");
			return null;
		}
		string name = call.identifier.spelling ();
		ExpressionSyntax argument_syntax = member ? (ExpressionSyntax) new NameExpressionSyntax (call.receiver) : call.arguments[0];
		if (member) {
			var symbol = values.lookup (call.receiver.spelling ());
			SemanticType type;
			if (symbol is LocalSymbol) {
				type = ((LocalSymbol) symbol).semantic_type;
			} else {
				type = ((ParameterSymbol) symbol).semantic_type;
			}
			name = name == "upgrade" ? "weak_upgrade" : name == "downgrade" ? "shared_downgrade" : type is SharedHandleType && ((SharedHandleType) type).is_weak ? "weak_clone" : "shared_clone";
		}
		if (name == "shared_acquire") {
			var syntax = argument_syntax as MoveExpressionSyntax;
			var move = syntax == null ? null : check_move (syntax, values);
			if (move == null || !move.source.heap_object || move.object_owner == null || !(move.semantic_type is ClassType) || (((ClassType) move.semantic_type).is_interface || ((ClassType) move.semantic_type).concurrency_policy_identity == 16)) {
				if (diagnostic == null) {
					fail (call.span, "shared_acquire requires explicit move of an independently allocated exact Class owner");
				}
				return null;
			}
			if (!acquire) {
				fail (call.span, "shared acquisition requires a fresh owned binding");
				return null;
			}
			var type = shared_type ((ClassType) move.semantic_type, false, call.span);
			return new CheckedSharedOperation (call.span, type, SharedAction.ACQUIRE, new CheckedLocalReferenceExpression (move.span, move.source), move.source, handle_types.lookup (type).cleanup);
		}
		ExpressionSyntax operand_syntax = argument_syntax;
		while (operand_syntax is ParenthesizedExpressionSyntax) {
			operand_syntax = ((ParenthesizedExpressionSyntax) operand_syntax).expression;
		}
		CheckedExpression? operand = null;
		LocalSymbol? source = null;
		if (operand_syntax is NameExpressionSyntax) {
			var symbol = values.lookup (((NameExpressionSyntax) operand_syntax).identifier.spelling ());
			if (symbol is LocalSymbol) {
				source = (LocalSymbol) symbol;
				operand = new CheckedLocalReferenceExpression (operand_syntax.span, source);
			} else if (symbol is ParameterSymbol && ((ParameterSymbol) symbol).pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
				operand = new CheckedParameterReferenceExpression (operand_syntax.span, (ParameterSymbol) symbol);
			}
		} else if (operand_syntax is FieldAccessExpressionSyntax) {
			var place = check_field_place ((FieldAccessExpressionSyntax) operand_syntax, values);
			if (place != null) {
				operand = new CheckedLoadExpression (operand_syntax.span, place);
			}
		}
		if (source != null && !source.is_owned) {
			fail (call.span, "Shared/Weak operations require an owned handle local or a borrowed parameter");
			return null;
		}
		var actor = operand == null ? null : operand.semantic_type as ClosureHandleType;
		if (actor != null && actor.actor) {
			if (!acquire || (name != "actor_clone" && name != "shared_clone")) {
				fail (call.span, "Actor sender supports explicit clone into one fresh owner");
				return null;
			}
			return new CheckedSharedOperation (call.span, actor, SharedAction.CLONE, operand, source, handle_types.lookup (actor).cleanup);
		}
		var input = operand == null ? null : operand.semantic_type as SharedHandleType;
		var intrinsic = operand == null ? null : operand.semantic_type as ClassType;
		if (intrinsic != null && intrinsic.intrinsically_shared) {
			if (name == "singleton_shutdown") {
				if (!acquire || !SharedContracts.matches (SharedAction.SINGLETON_SHUTDOWN, intrinsic, intrinsic)) {
					fail (call.span, "singleton_shutdown requires a live exact process Singleton owner and a fresh owning result");
					return null;
				}
				return new CheckedSharedOperation (call.span, intrinsic, SharedAction.SINGLETON_SHUTDOWN, operand, source, null);
			}
			if (!acquire || (name != "shared_clone" && name != "shared_downgrade")) {
				fail (call.span, "intrinsic shared handles support explicit clone and downgrade into a fresh owner");
				return null;
			}
			SemanticType result = name == "shared_clone" ? (SemanticType) intrinsic : shared_type (intrinsic, true, call.span);
			return new CheckedSharedOperation (call.span, result, name == "shared_clone" ? SharedAction.CLONE : SharedAction.DOWNGRADE, operand, source, (result is ClassType) ? null : handle_types.lookup (result).cleanup);
		}

		if (input == null) {
			if (diagnostic == null) {
				fail (call.span, "Shared/Weak operation requires a live typed handle local, borrowed parameter or receiver field");
			}
			return null;
		}
		SharedAction action = name == "shared_clone" ? SharedAction.CLONE : name == "shared_downgrade" ? SharedAction.DOWNGRADE : name == "weak_clone" ? SharedAction.WEAK_CLONE : name == "weak_upgrade" ? SharedAction.UPGRADE : SharedAction.BORROW;
		SemanticType result = action == SharedAction.BORROW || action == SharedAction.UPGRADE && input.payload_type.intrinsically_shared ? (SemanticType) input.payload_type : shared_type (input.payload_type, action == SharedAction.DOWNGRADE || action == SharedAction.WEAK_CLONE, call.span);
		if (!SharedContracts.matches (action, input, result)) {
			fail (call.span, "Shared/Weak operation has incompatible strong/weak handle capability");
			return null;
		}
		if (action == SharedAction.BORROW) {
			if (operand is CheckedLoadExpression) {
				fail (call.span, "shared payload projection from a field requires an explicit strong clone local before borrowing");
				return null;
			}
			if (borrower == null || borrower.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrower.semantic_type != result) {
				fail (call.span, "shared_borrow is a call-scoped exact Class borrowed argument; it cannot be stored or returned");
				return null;
			}
			if (source != null) {
				shared_borrow_guards.add (source);
			}
		} else if (!acquire) {
			fail (call.span, "Shared/Weak producer requires a fresh owned binding or move consumer");
			return null;
		}
		return new CheckedSharedOperation (call.span, result, action, operand, source, action == SharedAction.BORROW || (result is ClassType) ? null : handle_types.lookup (result).cleanup, borrower);
	}

	private LocalSymbol? check_move_source(MoveExpressionSyntax syntax, ValueScope values) {
		if (syntax.fields.length != 0) {
			fail (syntax.span, "projected owner move requires a fresh named local destination; moving ownership out of an owned field directly into another destination is unsupported");
			return null;
		}
		var symbol = values.lookup (syntax.source.spelling ());
		var source = symbol as LocalSymbol;
		if (source != null && source.semantic_type is HandleType && ((HandleType) source.semantic_type).context_mode == "scoped-affine") {
			fail (syntax.span, "scoped allocator authority cannot escape or transfer its backing loan");
			return null;
		}
		if (source != null && source.is_buffer_owner && !scoped_backing_access (source, values.region, syntax.span)) {
			return null;
		}
		if (source != null && pending_callable_borrows.find (source)) {
			fail (syntax.span, "owner transfer overlaps an active borrowed callable argument");
			return null;
		}
		if (source != null && pending_callable_transfers.find (source)) {
			fail (syntax.span, "owner transfer overlaps an already captured callable argument");
			return null;
		}
		if (source != null && shared_borrow_guards.find (source)) {
			fail (syntax.span, "shared payload borrow forbids moving its backing strong handle during the call");
			return null;
		}
		var parameter = symbol as ParameterSymbol;
		if (source == null || !source.is_owned) {
			if (parameter != null && GenericBorrowTypes.symbolic (parameter.semantic_type) && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
				fail (syntax.source.span, "borrowed T cannot be moved; it has no ownership responsibility");
				return null;
			}
			bool nominal = (source != null && source.semantic_type is HandleType) || (parameter != null && parameter.semantic_type is HandleType);
			bool object_reference = (source != null && source.semantic_type is ClassType) || (parameter != null && parameter.semantic_type is ClassType);
			string message = object_reference ? "object ownership transfer requires an owned ClassType binding; '%s' is nontransferable" : nominal ? "move source '%s' must be an owned nominal handle local or parameter" : "move source '%s' must be an owned void* local";
			fail (syntax.source.span, message.printf (syntax.source.spelling ()));
			return null;
		}
		foreach (var owner_type in pending_lazy_borrows) {
			if (field_overlap (source.semantic_type, owner_type)) {
				fail (syntax.span, "receiver move overlaps an active lazy-cache loan");
				return null;
			}
		}
		foreach (var receiver in active_object_receivers) {
			if (receiver == source) {
				fail (syntax.span, "method receiver cannot consume the same owned ClassType binding '%s'".printf (source.name));
				return null;
			}
		}
		return source;
	}

	private bool tracked_generic_storage_owner(LocalSymbol source) {
		return source.is_generic_owner || source.is_buffer_owner || (checking_function is GenericFunctionSymbol && source.incoming_parameter != null && source.semantic_type is ClassType && source.is_owned);
	}

	private CheckedOwnershipMove? check_move(MoveExpressionSyntax syntax, ValueScope values, bool returned = false) {
		if (syntax.fields.length != 0) {
			fail (syntax.span, "projected owner move requires a fresh named local destination; moving ownership out of an owned field directly into another destination is unsupported");
			return null;
		}
		var record = values.lookup (syntax.source.spelling ()) as LocalSymbol;
		if (record != null && record.is_record_owner) {
			fail (syntax.span, "whole owning record move requires a fresh local destination; field extraction and transport are deferred");
			return null;
		}
		var source = check_move_source (syntax, values);
		if (source == null) {
			return null;
		}
		if (source.enum_inspection_root != null || enum_reservations.find (source)) {
			fail (syntax.span, "owner is an inspection view or reserved by an unfinished enum consumer");
			return null;
		}
		if ((enum_buffer_capture && tracked_generic_storage_owner (source)) || (enum_scalar_capture && source.is_owned)) {
			enum_reservations.add (source);
			if (generic_owner_flow != null) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, source, source.name, syntax.span);
			}
			return new CheckedOwnershipMove (syntax.span, source);
		}
		if (tracked_generic_storage_owner (source) && generic_owner_flow != null) {
			generic_owner_flow.move (source, source.name, syntax.span, null, -1, returned);
		}
		return new CheckedOwnershipMove (syntax.span, source);
	}

	private static int bounded_lane_literal(Token token) {
		int ordinal = 0;
		string spelling = token.spelling ();
		for (int i = 0; i < spelling.length; i++) {
			// Every supported ordinal/count is <= 16. Never overflow on syntax.
			if (ordinal > 16) {
				break;
			}
			ordinal = ordinal * 10 + (spelling[i] - '0');
		}
		return ordinal;
	}

	private VectorLaneIndex? check_lane_index(Token token, VectorType type) {
		int ordinal = bounded_lane_literal (token);
		if (ordinal >= type.lane_count) {
			fail (token.span, "vector lane index '%s' is out of range for '%s'; expected 0 through %d".printf (token.spelling (), type.display_name (), type.lane_count - 1));
			return null;
		}
		return new VectorLaneIndex (token.span, ordinal);
	}

	private CheckedVectorMemoryExpression? check_vector_memory(CallExpressionSyntax call, ValueScope values, bool store) {
		if (call.receiver != null || call.receiver_place != null || call.type_arguments.length != 0 || call.arguments.length != 4) {
			fail (call.span, "vector memory requires view, int offset, lanes/value and alignment");
			return null;
		}
		var alignment = call.arguments[3] as IntegerLiteralExpressionSyntax;
		var lanes = store ? null : call.arguments[2] as IntegerLiteralExpressionSyntax;
		if (alignment == null || (!store && lanes == null)) {
			fail (call.span, "vector lanes and alignment require decimal literals");
			return null;
		}
		var view = check_expression (call.arguments[0], values);
		var offset = check_expression (call.arguments[1], values);
		var stored = store ? check_expression (call.arguments[2], values) : null;
		if (view == null || offset == null || (store && stored == null)) {
			return null;
		}
		var slice = view.semantic_type as SliceType;
		int count = store ? 0 : bounded_lane_literal (lanes.literal);
		if (store && stored.semantic_type is VectorType) {
			count = ((VectorType) stored.semantic_type).lane_count;
		}
		if (slice == null || !VectorType.supports (slice.element_type, count) || slice.element_type.kind == TypeKind.BOOL) {
			fail (call.span, "vector memory requires a bounded numeric scalar view and supported lane count");
			return null;
		}
		var contract = new VectorMemoryContract (types.vector_of (slice.element_type, count), (uint) bounded_lane_literal (alignment.literal), store);
		var error = contract.type_error (view.semantic_type, offset.semantic_type, stored == null ? null : stored.semantic_type, contract.vector_type);
		if (error != null) {
			fail (call.span, error);
			return null;
		}
		return new CheckedVectorMemoryExpression (call.span, contract, view, offset, stored);
	}

	private CheckedExpression? check_vector_dot(VectorDotExpressionSyntax syntax, ValueScope values) {
		VectorDotKind kind;
		switch (syntax.keyword.kind) {
		case TokenKind.DOT_WRAP: kind = VectorDotKind.INTEGER_WRAP_DOT;
			break;
		case TokenKind.MAC_WRAP: kind = VectorDotKind.INTEGER_WRAP_MAC;
			break;
		case TokenKind.DOT_F32: kind = VectorDotKind.F32_DOT;
			break;
		case TokenKind.MAC_F32: kind = VectorDotKind.F32_MAC;
			break;
			default: assert_not_reached ();
		}
		// Check each runtime operand once, in source order. The destination
		// never changes the mathematical source type or accumulator typing.
		CheckedExpression? accumulator = null;
		if (kind.is_mac ()) {
			accumulator = check_expression (syntax.operands[0], values);
			if (accumulator == null) {
				return null;
			}
		}
		int offset = kind.is_mac () ? 1 : 0;
		var first = check_expression (syntax.operands[offset], values);
		if (first == null) {
			return null;
		}
		var second = check_expression (syntax.operands[offset + 1], values);
		if (second == null) {
			return null;
		}
		var floating_vector = first.semantic_type as VectorType;
		if (!kind.is_integer () && floating_vector != null && floating_vector.element_type.kind == TypeKind.F64) {
			kind = kind.is_mac () ? VectorDotKind.F64_MAC : VectorDotKind.F64_DOT;
		}
		SemanticType? destination = accumulator == null ? (kind == VectorDotKind.F64_DOT ? (SemanticType) types.f64_type : types.f32_type) : accumulator.semantic_type;
		if (syntax.destination != null) {
			destination = resolve_type (syntax.destination);
			if (destination == null) {
				return null;
			}
			if (!(destination is IntegerType)) {
				fail (syntax.destination.span, "dot_wrap accumulator type must be a scalar IntegerType");
				return null;
			}
		}
		string? error = kind.type_error (first.semantic_type, first.semantic_type, second.semantic_type, destination, accumulator == null ? null : accumulator.semantic_type);
		if (error != null) {
			fail (syntax.span, "'%s': %s".printf (syntax.keyword.spelling (), error));
			return null;
		}
		return new CheckedVectorDotExpression (syntax.span, kind, first.semantic_type, destination, accumulator, first, second);
	}

	private static DspPrimitiveKind dsp_kind(TokenKind token) {
		switch (token) {
		case TokenKind.SAT_ADD: return DspPrimitiveKind.SAT_ADD;
		case TokenKind.SAT_SUB: return DspPrimitiveKind.SAT_SUB;
		case TokenKind.WIDEN_LOW: return DspPrimitiveKind.WIDEN_LOW;
		case TokenKind.WIDEN_HIGH: return DspPrimitiveKind.WIDEN_HIGH;
		case TokenKind.PACK_WRAP: return DspPrimitiveKind.PACK_WRAP;
		case TokenKind.PACK_SAT: return DspPrimitiveKind.PACK_SAT;
		case TokenKind.INTERLEAVE_LOW: return DspPrimitiveKind.INTERLEAVE_LOW;
		case TokenKind.INTERLEAVE_HIGH: return DspPrimitiveKind.INTERLEAVE_HIGH;
			default: assert_not_reached ();
		}
	}

	private CheckedExpression? check_dsp(DspExpressionSyntax syntax, ValueScope values, SemanticType? expected_type) {
		var kind = dsp_kind (syntax.keyword.kind);
		SemanticType? context = null;
		if (kind.is_saturation ()) {
			// Same declared-type lookahead and result context as ordinary +/−.
			context = (expected_type as IntegerType) ?? integer_context (syntax.first, values) ?? integer_context (syntax.second, values);
			context = context ?? (expected_type as VectorType);
		} else if (!kind.is_widen () && !kind.is_pack ()) {
			context = expected_type as VectorType;
		}
		var first = check_expression (syntax.first, values, context);
		if (first == null) {
			return null;
		}
		var second = syntax.second == null ? null : check_expression (syntax.second, values, context);
		if (syntax.second != null && second == null) {
			return null;
		}
		IntegerType? destination = null;
		SemanticType result = first.semantic_type;
		if (syntax.destination != null) {
			var resolved = resolve_type (syntax.destination);
			if (resolved == null) {
				return null;
			}
			destination = resolved as IntegerType;
			if (destination == null) {
				fail (syntax.destination.span, "DSP destination must be a scalar IntegerType");
				return null;
			}
			var vector = first.semantic_type as VectorType;
			if (vector == null || !(vector.element_type is IntegerType)) {
				fail (first.span, "widen/pack source must be an integer VectorType");
				return null;
			}
			int lanes = kind.is_widen () ? vector.lane_count / 2 : vector.lane_count * 2;
			var shape = types.vector_of (destination, lanes);
			if (shape == null) {
				fail (syntax.span, "unsupported DSP result VectorType '%s<%d>'".printf (destination.display_name (), lanes));
				return null;
			}
			result = shape;
		}
		string? error = kind.type_error (first.semantic_type, second == null ? null : second.semantic_type, result, destination);
		if (error != null) {
			fail (syntax.span, "'%s': %s".printf (syntax.keyword.spelling (), error));
			return null;
		}
		return new CheckedDspExpression (syntax.span, kind, first.semantic_type, result, first, second, destination);
	}

	private CheckedExpression? check_vector_primitive(VectorPrimitiveExpressionSyntax syntax, ValueScope values, SemanticType? expected_type) {
		var expected = expected_type as VectorType;
		if (syntax.keyword.kind == TokenKind.SPLAT) {
			int count = bounded_lane_literal (syntax.indices[0]);
			if (count == 0) {
				fail (syntax.indices[0].span, "splat lane count must be positive");
				return null;
			}
			var operand = check_expression (syntax.operands[0], values, expected == null ? null : expected.element_type);
			if (operand == null) {
				return null;
			}
			var type = types.vector_of (operand.semantic_type, count);
			if (type == null) {
				fail (syntax.span, "splat requires a supported scalar element and VEC-1 vector shape (2, 4, 8, or 16 lanes; numeric payload at most 128 bits)");
				return null;
			}
			if (expected != null && type != expected) {
				fail (syntax.span, "splat expects exact vector type '%s', found '%s'; no implicit element conversion".printf (expected.display_name (), type.display_name ()));
				return null;
			}
			return new CheckedVectorSplatExpression (syntax.span, type, operand, count, syntax.indices[0].span);
		}
		if (syntax.keyword.kind == TokenKind.SELECT) {
			var mask = check_expression (syntax.operands[0], values);
			var true_value = check_expression (syntax.operands[1], values, expected);
			if (mask == null || true_value == null) {
				return null;
			}
			var type = true_value.semantic_type as VectorType;
			var false_value = check_expression (syntax.operands[2], values, type);
			if (false_value == null) {
				return null;
			}
			var mask_type = mask.semantic_type as VectorType;
			if (mask_type == null || !mask_type.is_mask) {
				fail (mask.span, "select mask must have type bool<N>; scalar mask broadcast is unsupported");
				return null;
			}
			if (type == null || false_value.semantic_type != type) {
				fail (syntax.span, "select data operands must have the same exact VectorType");
				return null;
			}
			if (mask_type.lane_count != type.lane_count) {
				fail (mask.span, "select mask lane count must match the data vectors");
				return null;
			}
			return new CheckedVectorSelectExpression (syntax.span, type, mask, true_value, false_value);
		}
		var vector = check_expression (syntax.operands[0], values, expected);
		if (vector == null) {
			return null;
		}
		var type = vector.semantic_type as VectorType;
		if (type == null) {
			fail (vector.span, "'%s' requires a vector value".printf (syntax.keyword.spelling ()));
			return null;
		}
		if (syntax.keyword.kind == TokenKind.INSERT) {
			var index = check_lane_index (syntax.indices[0], type);
			var replacement = check_expression (syntax.operands[1], values, type.element_type);
			if (index == null || replacement == null) {
				return null;
			}
			if (replacement.semantic_type != type.element_type) {
				fail (replacement.span, "insert replacement expects exact element type '%s', found '%s'".printf (type.element_type.display_name (), replacement.semantic_type.display_name ()));
				return null;
			}
			return new CheckedVectorInsertExpression (syntax.span, type, vector, index, replacement);
		}
		assert (syntax.keyword.kind == TokenKind.SHUFFLE);
		if (syntax.indices.length != type.lane_count) {
			fail (syntax.span, "shuffle for '%s' requires exactly %d lane selectors, found %u".printf (type.display_name (), type.lane_count, syntax.indices.length));
			return null;
		}
		var indices = new GenericArray<VectorLaneIndex> ();
		foreach (var token in syntax.indices) {
			var index = check_lane_index (token, type);
			if (index == null) {
				return null;
			}
			indices.add (index);
		}
		return new CheckedVectorShuffleExpression (syntax.span, type, vector, new VectorLaneSelectors (indices));
	}

	private CheckedExpression? check_buffer_producer(ExpressionSyntax syntax, ValueScope values, SliceType type) {
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		var incoming = (syntax is AwaitExpressionSyntax) ? check_task_await ((AwaitExpressionSyntax) syntax, values, true) : (syntax is MoveExpressionSyntax) ? check_move ((MoveExpressionSyntax) syntax, values) : check_expression (syntax, values, type, OwnershipUse.ACQUIRE);
		if (incoming == null) {
			return null;
		}
		if (incoming.semantic_type != type || !incoming.owns_buffer) {
			fail (syntax.span, "owned buffer requires a new allocation, explicit move, or exact owned buffer result");
			return null;
		}
		return incoming;
	}

	private CheckedNode? indirect_result(CheckedExpression invocation, bool allow_struct) {
		if (!invocation.semantic_type.is_struct_storage ()) {
			return invocation;
		}
		if (!allow_struct) {
			fail (invocation.span, "indirect record result requires its exact bounded record consumer");
			return null;
		}
		return new CheckedStructInvocationResult (invocation, struct_value_mode (invocation.semantic_type));
	}

	private CheckedNode? check_value_call(CallExpressionSyntax call, ValueScope values, bool acquire_owned, bool allow_struct = false, bool allow_void = false) {
		var result = check_observed_value_call (call, values, acquire_owned, allow_struct);
		if (result is CheckedExpression && ((CheckedExpression) result).semantic_type.kind == TypeKind.VOID && !allow_void) {
			fail (call.span, "void callable invocation requires a statement; it produces no value");
			return null;
		}
		return result;
	}
	private CheckedNode? check_observed_value_call(CallExpressionSyntax call, ValueScope values, bool acquire_owned, bool allow_struct) {
		if (call.receiver == null && call.receiver_place == null && (call.identifier.spelling () == "task_in" || call.identifier.spelling () == "checked_task_in") && find_function (call.identifier) == null && values.lookup (call.identifier.spelling ()) == null) {
			bool checked_admission = call.identifier.spelling () == "checked_task_in";
			if (!allow_struct || call.arguments.length != 2 || call.type_arguments.length != 0 || !(call.arguments[0] is NameExpressionSyntax) || !(call.arguments[1] is CallExpressionSyntax)) {
				fail (call.span, "task_in requires a named allocator context and one fresh typed task creation");
				return null;
			}
			var selected = check_expression (call.arguments[0], values, null, OwnershipUse.NULL_COMPARISON, null, true);
			if (selected == null) {
				return null;
			}
			var context_type = selected.semantic_type as HandleType;
			if (context_type == null || context_type.context_mode == "") {
				fail (call.arguments[0].span, "task frame selection requires an exact allocator backing contract");
				return null;
			}
			var anchor = values.lookup (((NameExpressionSyntax) call.arguments[0]).identifier.spelling ()) as LocalSymbol;
			uint depth = pending_callable_borrows.length;
			if (anchor != null) {
				pending_callable_borrows.add (anchor);
			}
			var creation = check_value_call ((CallExpressionSyntax) call.arguments[1], values, true, true) as CheckedTaskCreate;
			while (pending_callable_borrows.length > depth) {
				pending_callable_borrows.remove_index (pending_callable_borrows.length - 1);
			}
			if (creation == null) {
				if (diagnostic == null) {
					fail (call.arguments[1].span, "task_in selects storage for one fresh async call");
				}
				return null;
			}
			if (creation.allocation_context != null || creation.loans.length != 0 || creation.target.async_body.runtime.threaded && context_type.context_mode != "owned-concurrent") {
				fail (call.span, "selected worker frames require concurrent backing; nested placement and borrowed suspension loans require separate authority");
				return null;
			}
			if (checked_admission) {
				if (!check_exception_effect (creation.target.async_body.runtime.error_type, call.span)) {
					return null;
				}
				foreach (var input in creation.arguments) {
					var argument = input as CheckedOwnedArgument;
					var record = input as CheckedStructArgument;
					var enumeration = input as CheckedEnumArgument;
					if (enumeration != null && EnumValueAuthority.owns (enumeration.producer.definition, enum_definition_for) || argument != null && !(argument.semantic_type is ClassType || argument.semantic_type is HandleType || argument.semantic_type is SliceType)) {
						fail (input.span, "checked frame admission requires copied values or exact Class/Resource/buffer/record captures");
						return null;
					}
					if (record != null && record.producer.contract.mode == StructValueMode.MOVE_VALUE) {
						var moved = record.producer as CheckedStructMoveProducer;
						if (moved == null) {
							fail (input.span, "checked record frame input requires an exact named whole-record move");
							return null;
						}
						record_all_events (GenericOwnershipEventKind.ACQUIRE, moved.source, input.span);
					}
					if (argument != null && argument.transfer != null) {
						var source = argument.transfer.source;
						if (source.semantic_type != argument.semantic_type || source.requires_nonnull || source.incoming_parameter != null && source.incoming_parameter.requires_nonnull) {
							fail (input.span, "checked frame input requires an exact nullable source slot");
							return null;
						}
						if (generic_owner_flow != null && tracked_generic_storage_owner (source)) {
							generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, source, source.name, input.span);
						}
					}
				}
				if (generic_owner_flow != null) {
					generic_owner_flow.effect (creation.target.async_body.runtime.error_type, call.span);
				}
			}
			return new CheckedTaskCreate (call.span, creation.target, creation.arguments, selected, checked_admission);
		}
		if (slots_call (call, values) && call.identifier.spelling () == "take" && ((OwnerSlotsType) field_context_type ((FieldAccessExpressionSyntax) call.receiver_place, values)).element is StructType) {
			if (!allow_struct || call.arguments.length != 1 || call.type_arguments.length != 0) {
				fail (call.span, "record slot take requires one index and a complete value consumer");
				return null;
			}
			var store = check_slots_place (call.receiver_place, values);
			if (store == null || !slots_mutation (store, call.span)) {
				return null;
			}
			var index = check_slot_operand (store, call.arguments[0], values);
			if (index == null || index.semantic_type != types.int_type) {
				if (diagnostic == null) {
					fail (call.span, "record slot index requires int/i32");
				}
				return null;
			}
			return new CheckedSlotsRecordRead (call.span, store, index, true, struct_value_mode (((OwnerSlotsType) store.semantic_type).element));
		}
		if (slots_call (call, values) && call.identifier.spelling () == "take") {
			if (!acquire_owned || call.arguments.length != 1 || call.type_arguments.length != 0) {
				fail (call.span, "owner-slot take requires one index and a fresh owned local");
				return null;
			}
			var store = check_slots_place (call.receiver_place, values);
			if (store == null || !slots_mutation (store, call.span)) {
				return null;
			}
			var index = check_slot_operand (store, call.arguments[0], values);
			if (index == null) {
				return null;
			}
			if (index.semantic_type != types.int_type) {
				fail (index.span, "owner-slot take index requires int/i32");
				return null;
			}
			var element = ((OwnerSlotsType) store.semantic_type).element;
			var resource = handle_types.lookup (element);
			return new CheckedSlotsTake (call.span, store, index, element, instance_for (element) as ClassSymbol, resource == null ? null : resource.cleanup);
		}
		if (is_closure_call (call)) {
			return check_closure_call (call, values, acquire_owned, allow_struct);
		}
		if (is_shared_call (call) || intrinsic_shared_call (call, values)) {
			return check_shared_call (call, values, acquire_owned);
		}
		if (call.receiver == null) {
			var binding = values.lookup (call.identifier.spelling ());
			FunctionValueType? type = (binding is LocalSymbol) ? (((LocalSymbol) binding).semantic_type as FunctionValueType) : (binding is ParameterSymbol) ? (((ParameterSymbol) binding).semantic_type as FunctionValueType) : null;
			if (type != null) {
				if (call.type_arguments.length != 0 || call.arguments.length != type.parameter_types.length) {
					fail (call.span, "function value invocation requires its exact arity and no type arguments");
					return null;
				}
				var callee = check_expression (new NameExpressionSyntax (call.identifier), values, type, (type is CallbackType) ? OwnershipUse.RECEIVER_BORROW : OwnershipUse.UNMANAGED);
				if (callee == null) {
					return null;
				}
				GenericArray<ParameterSymbol> channels;
				var arguments = check_indirect_arguments (call, values, type, 0, "Fn", out channels);
				if (arguments == null) {
					return null;
				}
				var invocation = new CheckedFunctionValueCall (call.span, type, callee, arguments);
				invocation.owned_producer = callable_owned_result (type, type.result_type, call.span, acquire_owned);
				if (diagnostic != null) {
					return null;
				}
				foreach (var channel in channels) {
					invocation.channel_parameters.add (channel);
				}
				return indirect_result (invocation, allow_struct);
			}
		}
		if (async_operation_call (call, values)) {
			return check_async_operation (call, values, true);
		}
		if (call.receiver != null && values.lookup (call.receiver.spelling ()) == null && !module_names.contains (call.receiver.spelling ()) && find_named (call.receiver) is EnumType && call.member_operator.kind == TokenKind.DOT) {
			if (!allow_struct) {
				fail (call.span, "enum construction requires a bounded value consumer");
				return null;
			}
			var type = resolve_enum_application ((EnumType) find_named (call.receiver), call.qualifier_arguments, call.span);
			return type == null ? null : check_enum_constructor (call, values, enum_definition_for (type));
		}
		var context = generic_call_contexts.lookup (call);
		if (context != null) {
			if (!allow_struct && context.result is CheckedStructProducer) {
				fail (call.span, "struct call result requires copy initialization, assignment, exact struct argument or return");
				return null;
			}
			if (!allow_struct && context.result is CheckedEnumProducer) {
				fail (call.span, "enum call result requires a bounded value consumer");
				return null;
			}
			generic_call_contexts.remove (call);
			if (context.flow != null) {
				assert (generic_owner_flow != null);
				generic_owner_flow.append (context.flow);
			}
			return context.result;
		}
		DirectCallableSymbol? target;
		CheckedExpression? receiver;
		GenericArray<SemanticType> type_arguments;
		var arguments = check_call (call, values, true, out target, out receiver, out type_arguments, acquire_owned);
		if (arguments == null) {
			return null;
		}
		if (target is FunctionSymbol && ((FunctionSymbol) target).async_body != null) {
			if (!allow_struct) {
				fail (call.span, "task creation requires a unique inferred local or consuming await");
				return null;
			}
			var creation = new CheckedTaskCreate (call.span, (FunctionSymbol) target, arguments);
			for (int p = 0; p < target.parameters.length; p++) {
				var parameter = target.parameters[p];
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					continue;
				}
				var view = arguments[p] as CheckedSliceFromArrayExpression;
				if (direct_await_creation != call || checking_function == null || checking_function.async_body == null || view == null || view.local.incoming_parameter != null || exposed_suspension_arrays.contains (view.local)) {
					fail (arguments[p].span, "borrowed async capture requires a fresh directly awaited child and sealed fixed parent-local array view; stored, started, external and aliased borrows are excluded");
					return null;
				}
				var loan = new CheckedSuspensionLoan (new SuspensionLoanIdentity (), p, view.local, view);
				creation.loans.add (loan);
				suspension_loans.add (loan);
			}
			return creation;
		}
		var generic = target as GenericFunctionSymbol;
		var substitution = new TypeSubstitution ((element) => types.slice_of (element), types.substitute_function, substitute_class, substitute_closure);
		if (generic != null) {
			for (int t = 0; t < type_arguments.length; t++) {
				substitution.bind (generic.type_parameters[t].semantic_type, type_arguments[t]);
			}
		}
		var result_type = substitution.apply (target.return_type);
		if (result_type is EnumType) {
			if (!allow_struct) {
				fail (call.span, "enum call result requires a bounded value consumer");
				return null;
			}
			if (!(target is FunctionSymbol)) {
				fail (call.span, "enum producer requires an exact native callable");
				return null;
			}
			var result = new CheckedEnumCallResult (call.span, enum_definition_for ((EnumType) result_type), (FunctionSymbol) target, arguments, receiver);
			result.type_arguments = generic == null ? null : type_arguments;
			return result;
		}
		if (result_type.is_struct_storage ()) {
			if (!allow_struct) {
				fail (call.span, "struct call result requires copy initialization, assignment, exact struct argument or return");
				return null;
			}
			if (target is CFunctionSymbol && ((CFunctionSymbol) target).metadata.record_abi == CRecordAbi.VALUE_LP64) {
				return new CheckedCStructCallResult (call.span, (CFunctionSymbol) target, arguments);
			}
			var native = target as FunctionSymbol;
			if (native == null || native.result_contract == ResultOwnershipContract.OWNED_TRANSFER || (generic == null && native.struct_result_contract == null)) {
				fail (call.span, "struct producer requires an exact native COPY_VALUE result");
				return null;
			}
			bool moving = native.struct_result_contract != null && native.struct_result_contract.mode == StructValueMode.MOVE_VALUE;
			if (!moving && !check_copyable_type (result_type, call.span)) {
				return null;
			}
			return new CheckedStructCallResult (call.span, native, arguments, receiver, moving ? Copyability.NOT_COPYABLE : Copyability.COPYABLE, result_type, generic == null ? null : type_arguments);
		}
		var native_target = target as FunctionSymbol;
		var source_type = checking_function == null || checking_function.implicit_receiver == null ? null : checking_function.implicit_receiver.semantic_type.instance_type as ClassType;
		var target_type = native_target == null || native_target.implicit_receiver == null ? null : native_target.implicit_receiver.semantic_type.instance_type as ClassType;
		if (source_type != null && source_type.monitored && !(checking_function is LifecycleSymbol) && target_type != null && target_type.monitored && !(native_target is LifecycleSymbol) && !self_receiver (receiver, checking_function.implicit_receiver)) {
			fail (call.span, "cross-object monitor nesting requires a qualified ordered-lock operation");
			return null;
		}
		if (generic == null) {
			return new CheckedCallExpression (call.span, target, arguments, receiver);
		}
		var result = new CheckedGenericCall (call.span, generic, type_arguments, arguments, result_type);
		if (result_type is ClassType && generic.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			owned_call_heap_result (result);
			if (diagnostic != null) {
				return null;
			}
		}
		if (generic.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			result.owned_producer = new OwnedValueProducer (OwnedProducerKind.NATIVE_OWNED_CALL, result_type, (result_type is HandleType) ? handle_types.lookup (result_type).cleanup : null, instance_for (result_type) as ClassSymbol);
		}
		return result;
	}

	private CheckedExpression? check_expression(ExpressionSyntax syntax, ValueScope values, SemanticType? expected_type = null, OwnershipUse ownership_use = OwnershipUse.UNMANAGED, ParameterSymbol? borrowed_parameter = null, bool pointer_comparison = false) {
		var result = check_observed_expression ((ExpressionSyntax?) imported_property_call (syntax, values) ?? syntax, values, expected_type, ownership_use, borrowed_parameter, pointer_comparison);
		if (tooling != null && result != null) {
			tooling.expression (syntax, result);
		}
		return result;
	}

	private CheckedExpression? check_observed_expression(ExpressionSyntax syntax, ValueScope values, SemanticType? expected_type = null, OwnershipUse ownership_use = OwnershipUse.UNMANAGED, ParameterSymbol? borrowed_parameter = null, bool pointer_comparison = false) {
		if (syntax is NameExpressionSyntax) {
			var captured = values.lookup (((NameExpressionSyntax) syntax).identifier.spelling ()) as LocalSymbol;
			if (captured != null && pending_callable_transfers.find (captured)) {
				fail (syntax.span, "owned value is already captured by an unfinished callable argument");
				return null;
			}
		}
		if (expected_type is FunctionValueType && (syntax is NameExpressionSyntax || syntax is FieldAccessExpressionSyntax)) {
			FunctionSymbol? target = null;
			if (syntax is NameExpressionSyntax) {
				var token = ((NameExpressionSyntax) syntax).identifier;
				if (values.lookup (token.spelling ()) == null) {
					target = find_function (token) as FunctionSymbol;
				}
			} else {
				var field = (FieldAccessExpressionSyntax) syntax;
				if (field.aggregate == null && values.lookup (field.identifier.spelling ()) == null && module_names.contains (field.identifier.spelling ())) {
					target = function_names.lookup (resolve_name (syntax.span, field.identifier.spelling () + "." + field.field_name.spelling (), false)) as FunctionSymbol;
				}
			}
			if (target != null) {
				var type = (FunctionValueType) expected_type;
				if (target is MethodSymbol || target is GenericFunctionSymbol || target.async_body != null || target.throws_type != null || target.result_contract != type.result_contract || target.return_type != type.result_type || (type.result_contract == ResultOwnershipContract.OWNED_TRANSFER && type.result_type is ClassType && !target.heap_result) || target.parameters.length != type.parameter_types.length) {
					fail (syntax.span, "function address requires an exact nonthrowing native copied-scalar signature");
					return null;
				}
				for (int i = 0; i < target.parameters.length; i++) {
					if (target.parameters[i].semantic_type != type.parameter_types[i] || target.parameters[i].pointer_contract != type.parameter_contract (i) || CallableRecordGroups.heap_parameter (type, i) && !target.parameters[i].heap_object) {
						bool owning_record = type.parameter_types[i].is_struct_storage () && struct_value_mode (type.parameter_types[i]) == StructValueMode.MOVE_VALUE;
						fail (syntax.span, type.has_owner_channels () || owning_record ? "function address parameter requires exact type and ownership channel identity" : "function address parameter requires exact copied scalar identity");
						return null;
					}
				}
				return new CheckedFunctionAddress (syntax.span, type, target);
			}
		}
		if (syntax is FieldAccessExpressionSyntax) {
			var constant = qualified_constant ((FieldAccessExpressionSyntax) syntax, values);
			if (constant != null) {
				return new CheckedConstantReference (syntax.span, constant);
			}
		}
		if (syntax is Utf8FactoryExpressionSyntax) {
			var operation = (Utf8FactoryExpressionSyntax) syntax;
			var input = values.lookup (operation.input.spelling ()) as ParameterSymbol;
			if (checking_function == null || !checking_function.utf8_factory || checking_function.parameters.length != 1 || input != checking_function.parameters[0] || !(input.semantic_type is SliceType) || ((SliceType) input.semantic_type).element_type != types.u8_type || input.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				fail (syntax.span, "UTF-8 boundary requires its exact annotated borrowed byte parameter");
				return null;
			}
			return new CheckedUtf8FactoryExpression (syntax.span, operation.validates ? (SemanticType) types.bool_type : types.string_type, input, operation.validates);
		}
		if (syntax is AwaitExpressionSyntax) {
			return check_task_await ((AwaitExpressionSyntax) syntax, values);
		}
		if (syntax is NameExpressionSyntax) {
			var local = values.lookup (((NameExpressionSyntax) syntax).identifier.spelling ()) as LocalSymbol;
			if (local != null && (local.semantic_type is TaskType || local.semantic_type is ExecutorType)) {
				fail (syntax.span, "Task/executor is unique: use an explicit move or its dedicated task operation; copying, escape and ordinary arguments are unsupported");
				return null;
			}
		}
		if (syntax is HeapObjectConstructionSyntax) {
			fail (syntax.span, "heap class construction currently requires an owned local or var destination");
			return null;
		}
		if (syntax is TextLiteralExpressionSyntax) {
			return new CheckedTextExpression (syntax.span, types.string_type, ((TextLiteralExpressionSyntax) syntax).payload);
		}
		if (syntax is TextMemberExpressionSyntax) {
			var member = (TextMemberExpressionSyntax) syntax;
			if ((place_context_type (member.receiver, values) ?? types.void_type).is_struct_storage ()) {
				return check_field (expression_member (member), values);
			}
			return check_text_member (syntax.span, member.receiver, member.member, values);
		}
		if (syntax is BufferAllocationSyntax) {
			var allocation = (BufferAllocationSyntax) syntax;
			var element = resolve_type (allocation.element_type);
			if (element == null) {
				return null;
			}
			if ((element is TypeParameterType) ? !element_premise ((TypeParameterType) element) : !BufferElementTypes.supports (element, copy_fields)) {
				fail (allocation.element_type.span, (element is TypeParameterType) ? "generic allocation requires an exact signature-derived element premise" : "BUFFER-1 element requires concrete fixed storage, defined zero, trivial destruction and copyable element semantics");
				return null;
			}
			if (ownership_use != OwnershipUse.ACQUIRE) {
				fail (syntax.span, "runtime array allocation creates an owner; an owning destination is required");
				return null;
			}
			CheckedExpression? allocation_context = null;
			ContextBytesType? context_bytes = null;
			uint context_borrow_depth = pending_callable_borrows.length;
			if (allocation.allocation_context != null) {
				var name = allocation.allocation_context as NameExpressionSyntax;
				if (name == null) {
					fail (allocation.allocation_context.span, "byte allocation requires a named context value or borrowed context parameter");
					return null;
				}
				allocation_context = check_expression (name, values, null, OwnershipUse.NULL_COMPARISON, null, true);
				var allocator = allocation_context == null ? null : allocation_context.semantic_type as HandleType;
				context_bytes = allocator == null ? null : types.context_bytes_of (allocator);
				if (element != types.u8_type || context_bytes == null) {
					fail (syntax.span, "context byte allocation requires u8 elements and an exact owned allocator contract");
					return null;
				}
				var owner = values.lookup (name.identifier.spelling ()) as LocalSymbol;
				if (owner != null) {
					pending_callable_borrows.add (owner);
				}
			}
			var count = check_expression (allocation.count, values, types.int_type);
			if (count == null) {
				return null;
			}
			if (count.semantic_type != types.int_type) {
				fail (count.span, "runtime array count requires int/i32");
				return null;
			}
			if (count is CheckedIntegerExpression && ((CheckedIntegerExpression) count).value.negative) {
				fail (count.span, "runtime array count must be non-negative");
				return null;
			}
			CheckedCallStatement? failure_call = null;
			if (allocation.failure_call != null) {
				var direct = allocation.failure_call;
				while (direct is ParenthesizedExpressionSyntax) {
					direct = ((ParenthesizedExpressionSyntax) direct).expression;
				}
				var call = direct as CallExpressionSyntax;
				if (call == null) {
					fail (direct.span, "allocation failure action requires a direct call");
					return null;
				}
				// Check a distinct terminal path even for a constant zero request.
				// Its explicit moves never change the success continuation's facts.
				if (generic_owner_flow != null) {
					generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, call.span);
				}
				DirectCallableSymbol? target;
				CheckedExpression? receiver;
				GenericArray<SemanticType> type_arguments;
				uint pending_depth = pending_field_borrows.length;
				foreach (var container in allocation_containers) {
					pending_field_borrows.add (container);
				}
				var arguments = check_call (call, values, false, out target, out receiver, out type_arguments);
				while (pending_field_borrows.length > pending_depth) {
					pending_field_borrows.remove_index (pending_field_borrows.length - 1);
				}
				if (generic_owner_flow != null) {
					generic_owner_flow.jump (GenericOwnershipEventKind.RETURN, call.span);
					generic_owner_flow.end ();
				}
				if (arguments == null) {
					return null;
				}
				if (target.return_type != types.void_type) {
					fail (call.span, "allocation failure action must return exact void");
					return null;
				}
				failure_call = (target is GenericFunctionSymbol) ? (CheckedCallStatement) new CheckedGenericCallStatement (call.span, (GenericFunctionSymbol) target, type_arguments, arguments) : new CheckedCallStatement (call.span, target, arguments, receiver);
			}
			while (pending_callable_borrows.length > context_borrow_depth) {
				pending_callable_borrows.remove_index (pending_callable_borrows.length - 1);
			}
			return new CheckedOwnedBufferAllocate (syntax.span, (SliceType?) context_bytes ?? types.slice_of (element), count, failure_call, allocation_context);
		}
		var dot = syntax as VectorDotExpressionSyntax;
		if (dot != null) {
			return check_vector_dot (dot, values);
		}
		var dsp = syntax as DspExpressionSyntax;
		if (dsp != null) {
			return check_dsp (dsp, values, expected_type);
		}
		var conversion = syntax as ConversionExpressionSyntax;
		if (conversion != null) {
			// A conversion is a source-typing boundary: its destination and
			// surrounding expected type never contextualize the operand.
			var operand = check_expression (conversion.operand, values);
			if (operand == null) {
				return null;
			}
			var destination = checking_constant ? resolve_constant_type (conversion.destination, values) : resolve_type (conversion.destination, values);
			if (destination == null) {
				return null;
			}
			var source = operand.semantic_type;
			if (source is TypeParameterType || destination is TypeParameterType) {
				fail (syntax.span, "casts to or from a GEN1_PLAIN_COPY type parameter are unsupported");
				return null;
			}
			var float_kind = (source is F32Type) ? FloatConversionKind.FLOAT_WIDEN : FloatConversionKind.FLOAT_NARROW;
			if (float_kind.accepts (source, destination)) {
				return new CheckedFloatConversionExpression (syntax.span, source, destination, float_kind, operand);
			}
			var numeric_kind = NumericConversionKind.select (source, destination);
			if (numeric_kind != NumericConversionKind.INVALID) {
				return new CheckedNumericConversionExpression (syntax.span, source, destination, numeric_kind, operand, numeric_kind.policy ());
			}
			if (IntegerConversion.element_type (source) == null) {
				fail (conversion.operand.span, "unsupported integer conversion source type '%s'; 'as' requires an integer scalar or integer vector".printf (source.display_name ()));
				return null;
			}
			if (IntegerConversion.element_type (destination) == null) {
				fail (conversion.destination.span, "unsupported integer conversion destination type '%s'; 'as' requires an integer scalar or integer vector".printf (destination.display_name ()));
				return null;
			}
			if ((source is VectorType) != (destination is VectorType)) {
				fail (syntax.span, "integer conversion cannot convert between scalar and vector types");
				return null;
			}
			if (!IntegerConversion.accepts (source, destination)) {
				fail (syntax.span, "integer vector conversion requires equal lane counts, found '%s' and '%s'".printf (source.display_name (), destination.display_name ()));
				return null;
			}
			return new CheckedIntegerConversionExpression (syntax.span, source, destination, operand);
		}
		var primitive = syntax as VectorPrimitiveExpressionSyntax;
		if (primitive != null) {
			return check_vector_primitive (primitive, values, expected_type);
		}
		var extract = syntax as IndexExpressionSyntax;
		if (extract != null) {
			if (slots_candidate (extract.container, values)) {
				var store = check_slots_place (extract.container, values);
				if (store == null) {
					return null;
				}
				if (borrowed_parameter == null || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != ((OwnerSlotsType) store.semantic_type).element) {
					fail (syntax.span, "indexed owner-slot use requires a direct exact-Class borrowed inspection argument; extraction, escape and mutation are unsupported");
					return null;
				}
				var index = check_slot_operand (store, extract.subscript, values);
				if (index == null) {
					return null;
				}
				if (index.semantic_type != types.int_type) {
					fail (index.span, "owner-slot index requires int/i32");
					return null;
				}
				return new CheckedSlotsValue (syntax.span, borrowed_parameter.semantic_type, store, OwnerSlotsAction.BORROW, index, borrowed_parameter);
			}
			if (array_base (extract, values) != null) {
				var place = check_array_place (extract, values);
				return place == null ? null : new CheckedLoadExpression (syntax.span, place);
			}
			var vector = check_expression (extract.container, values, null, OwnershipUse.BUFFER_VIEW);
			if (vector == null) {
				return null;
			}
			if (vector.semantic_type is SliceType) {
				var place = check_slice_place (extract, vector, values);
				return place == null ? null : new CheckedLoadExpression (syntax.span, place);
			}
			var type = vector.semantic_type as VectorType;
			if (vector.semantic_type is StringType) {
				fail (extract.span, "string indexing is unsupported in TEXT-1");
				return null;
			}
			if (type == null) {
				fail (extract.container.span, "lane extraction requires a vector value");
				return null;
			}
			var literal = extract.subscript as IntegerLiteralExpressionSyntax;
			if (literal == null) {
				fail (extract.subscript.span, "vector lane index must be one unsuffixed non-negative decimal integer literal; dynamic indexing is unsupported");
				return null;
			}
			var index = check_lane_index (literal.literal, type);
			return index == null ? null : new CheckedVectorExtractExpression (syntax.span, type.element_type, vector, index);
		}
		var reduction = syntax as VectorReductionExpressionSyntax;
		if (reduction != null) {
			var operand = check_expression (reduction.operand, values);
			if (operand == null) {
				return null;
			}
			var op = reduction.keyword.kind == TokenKind.ALL ? VectorReductionOperator.ALL : VectorReductionOperator.ANY;
			if (!op.accepts (operand.semantic_type, types.bool_type)) {
				fail (syntax.span, "'%s' requires a bool<N> mask, found '%s'".printf (op.spelling (), operand.semantic_type.display_name ()));
				return null;
			}
			return new CheckedVectorReductionExpression (syntax.span, types.bool_type, op, operand);
		}
		if (syntax is MoveExpressionSyntax) {
			var source = values.lookup (((MoveExpressionSyntax) syntax).source.spelling ()) as ParameterSymbol;
			if (source != null && source.substituted_copy) {
				return new CheckedParameterReferenceExpression (syntax.span, source);
			}
			fail (syntax.span, "move requires a fresh owned local, an owned native parameter, or an owned native return");
			return null;
		}
		if (syntax is AddressOfExpressionSyntax) {
			return check_borrow ((AddressOfExpressionSyntax) syntax, values);
		}
		if (syntax is DereferenceExpressionSyntax) {
			var place = check_dereference ((DereferenceExpressionSyntax) syntax, values);
			return place == null ? null : new CheckedLoadExpression (syntax.span, place);
		}
		var field_access = syntax as FieldAccessExpressionSyntax;
		if (field_access != null) {
			if (field_access.aggregate != null && slots_candidate (field_access.aggregate, values)) {
				if (field_access.field_name.spelling () != "capacity") {
					fail (syntax.span, "owner-slot storage exposes only readonly capacity");
					return null;
				}
				var store = check_slots_place (field_access.aggregate, values);
				return store == null ? null : new CheckedSlotsValue (syntax.span, types.int_type, store, OwnerSlotsAction.CAPACITY);
			}
			var expression = check_field (field_access, values);
			var property_borrow = expression as CheckedPropertyGetExpression;
			if (property_borrow != null && property_borrow.property_symbol.is_borrowed && (borrowed_parameter == null ? ownership_use != OwnershipUse.NULL_COMPARISON && ownership_use != OwnershipUse.RECEIVER_BORROW : borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != property_borrow.semantic_type)) {
				fail (syntax.span, "borrowed property result requires an exact temporary borrowed argument, receiver or null comparison; storing, copying and escape are unsupported");
				return null;
			}
			var projection = expression as CheckedStructProjectionValue;
			if (projection != null && projection.source.contract.mode == StructValueMode.BORROW_VALUE && (projection.semantic_type is ClassType || projection.semantic_type is HandleType || projection.semantic_type is SliceType) && (borrowed_parameter == null ? ownership_use != OwnershipUse.NULL_COMPARISON && ownership_use != OwnershipUse.RECEIVER_BORROW && !(projection.semantic_type is SliceType && ownership_use == OwnershipUse.BUFFER_VIEW) : borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != projection.semantic_type)) {
				fail (syntax.span, "owning record leaf observation requires an exact bounded borrowed use; storing, copying and escape are unsupported");
				return null;
			}
			var load = expression as CheckedLoadExpression;
			var receiver_field = load == null ? null : load.source as CheckedReceiverFieldPlace;
			var object_field = load == null ? null : load.source as CheckedObjectFieldPlace;
			var field = receiver_field != null ? receiver_field.field : object_field == null ? null : object_field.field;
			if (field != null && field.semantic_type is OwnerSlotsType) {
				fail (syntax.span, "owner-slot descriptor is field-only and cannot be copied, borrowed as a value or exposed");
				return null;
			}
			if (field != null && field.is_owned_field) {
				if (borrowed_parameter == null && !(field.owns_buffer ? ownership_use == OwnershipUse.BUFFER_VIEW : ownership_use == OwnershipUse.NULL_COMPARISON || field.owns_child && ownership_use == OwnershipUse.RECEIVER_BORROW)) {
					fail (syntax.span, (field.owns_child ? "owned child field use requires a temporary borrowed argument or null comparison, or an exact bounded receiver" : field.owns_buffer ? "owned buffer field use requires a temporary borrowed view; copying and escaping are unsupported" : "owned Resource field use requires a temporary borrowed argument or null comparison; copying and escaping are unsupported"));
					return null;
				}
				var borrowed = new CheckedOwnedFieldBorrow (syntax.span, load.source, field, borrowed_parameter);
				borrowed.borrow_region = values.region;
				return borrowed;
			}
			return expression;
		}
		var call = syntax as CallExpressionSyntax;
		if (call != null) {
			if (call.identifier.spelling () == "load_vector" && call.receiver == null && call.receiver_place == null) {
				return check_vector_memory (call, values, false);
			}
			if (call.identifier.spelling () == "volatile_load" && call.receiver == null && call.receiver_place == null) {
				if (call.arguments.length != 1 || call.type_arguments.length != 0) {
					fail (syntax.span, "volatile_load requires one typed memory place");
					return null;
				}
				var place = check_volatile_place (call.arguments[0], values);
				return place == null ? null : new CheckedLoadExpression (syntax.span, place, new VolatileAccessContract (place.semantic_type));
			}
			if (call.identifier.kind == TokenKind.LEN && call.arguments.length == 1 && slots_candidate (call.arguments[0], values)) {
				var store = check_slots_place (call.arguments[0], values);
				return store == null ? null : new CheckedSlotsValue (syntax.span, types.int_type, store, OwnerSlotsAction.LENGTH);
			}
			if (slots_call (call, values) && call.identifier.spelling () == "take") {
				return check_value_call (call, values, ownership_use == OwnershipUse.ACQUIRE) as CheckedExpression;
			}
			if (slots_call (call, values)) {
				var store = check_slots_place (call.receiver_place, values);
				if (store == null) {
					return null;
				}
				if (call.identifier.spelling () != "reserve" || call.arguments.length != 1 || !slots_mutation (store, syntax.span)) {
					if (diagnostic == null) {
						fail (syntax.span, "owner-slot value operation requires reserve(int); append is a statement");
					}
					return null;
				}
				var requested = check_slot_operand (store, call.arguments[0], values);
				if (requested == null) {
					return null;
				}
				if (requested.semantic_type != types.int_type) {
					fail (requested.span, "owner-slot reserve requires int/i32");
					return null;
				}
				return new CheckedSlotsValue (syntax.span, types.bool_type, store, OwnerSlotsAction.RESERVE, requested);
			}
			if (call.receiver_place is FieldAccessExpressionSyntax && !indexed_member_projection (call.receiver_place) && !(place_context_type (call.receiver_place, values) is ClassType)) {
				fail (syntax.span, "method invocation on a nested struct subobject is unsupported");
				return null;
			}
			if (call.identifier.kind == TokenKind.SLICE || call.identifier.kind == TokenKind.LEN) {
				return check_slice_form (call, values);
			}
			return check_value_call (call, values, ownership_use == OwnershipUse.ACQUIRE) as CheckedExpression;
		}
		if (syntax is NullPointerExpressionSyntax) {
			if (expected_type is TypeParameterType) {
				fail (syntax.span, "null cannot be contextualized to a GEN1_PLAIN_COPY type parameter");
				return null;
			}
			if (expected_type is SliceType) {
				fail (syntax.span, "a slice has no null state; construct a zero-length view instead");
				return null;
			}
			return new CheckedNullPointerExpression (syntax.span, (expected_type != null && expected_type.is_nullable_pointer_value ()) ? expected_type : types.raw_pointer_type);
		}
		var boolean = syntax as BooleanLiteralExpressionSyntax;
		if (boolean != null) {
			return new CheckedBooleanExpression (syntax.span, types.bool_type, boolean.literal.kind == TokenKind.TRUE ? BooleanLiteral.TRUE : BooleanLiteral.FALSE);
		}
		if (syntax is FloatLiteralExpressionSyntax) {
			string spelling = ((FloatLiteralExpressionSyntax) syntax).literal.spelling ();
			char suffix = spelling[spelling.length - 1];
			bool single = suffix == 'f' || suffix == 'F';
			bool double_precision = suffix == 'd' || suffix == 'D';
			FloatingType type = single ? (FloatingType) types.f32_type : double_precision ? (FloatingType) types.f64_type : (expected_type as FloatingType) ?? types.f32_type;
			if (single || double_precision) {
				spelling = spelling.substring (0, spelling.length - 1);
			}
			var value = BinaryFloatValue.from_decimal (type.format, spelling);
			assert (value != null);
			return new CheckedFloatExpression (syntax.span, type, value);
		}
		if (syntax is IntegerLiteralExpressionSyntax) {
			return check_integer ((IntegerLiteralExpressionSyntax) syntax, syntax.span, (expected_type as IntegerType) ?? types.i32_type);
		}
		if (syntax is NameExpressionSyntax) {
			if (((NameExpressionSyntax) syntax).identifier.kind == TokenKind.THIS) {
				if (check_this (syntax.span, values) != null) {
					fail (syntax.span, "'this' is a nonnull, non-owning receiver; only 'this.field' and 'this.method(...)' are supported, not pointer values or null comparisons");
				}
				return null;
			}
			string name = ((NameExpressionSyntax) syntax).identifier.spelling ();
			var symbol = values.lookup (name) ?? values.lookup (resolve_name (syntax.span, name, false));
			if (symbol is IterationElementSymbol) {
				var iteration = ((IterationElementSymbol) symbol).iteration;
				if (!active_loops.find (iteration.target) || borrowed_parameter == null || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != ((OwnerSlotsType) iteration.store.semantic_type).element) {
					fail (syntax.span, "foreach element is a call-scoped readonly inspection view; copying, moving and escape are unsupported");
					return null;
				}
				var value = new CheckedSlotsValue (syntax.span, borrowed_parameter.semantic_type, iteration.store, OwnerSlotsAction.BORROW, new CheckedLocalReferenceExpression (syntax.span, iteration.index), borrowed_parameter, iteration);
				return value;
			}
			if (symbol is ConstantSymbol) {
				return new CheckedConstantReference (syntax.span, (ConstantSymbol) symbol);
			}
			if (symbol == null) {
				fail (syntax.span, "unknown name '%s'".printf (name));
				return null;
			}
			if (symbol is LocalSymbol) {
				var owner = (LocalSymbol) symbol;
				if (owner.is_buffer_owner && !scoped_backing_access (owner, values.region, syntax.span)) {
					return null;
				}
				if (owner.enum_inspection_root != null && (borrowed_parameter != null || ownership_use != OwnershipUse.BUFFER_VIEW)) {
					fail (syntax.span, "enum inspection view is nonescaping and cannot enter a mutable slice parameter");
					return null;
				}
				if (owner.is_buffer_owner) {
					if (borrowed_parameter == null && ownership_use != OwnershipUse.BUFFER_VIEW) {
						fail (syntax.span, "owned buffer cannot be copied or stored as an escaping slice; use explicit move or a temporary slice borrow");
						return null;
					}
					if (generic_owner_flow != null) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, owner, owner.name, syntax.span);
					}
					return new CheckedOwnedBufferBorrow (syntax.span, owner, borrowed_parameter);
				}
				if (owner.is_generic_owner) {
					if (borrowed_parameter == null || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || !GenericBorrowTypes.symbolic (borrowed_parameter.semantic_type)) {
						fail (syntax.span, "Ownable T cannot be copied or used as a plain value; use explicit move of owned binding '%s'".printf (name));
						return null;
					}
					if (generic_owner_flow != null) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, owner, owner.name, syntax.span);
					}
					return new CheckedOwnedBorrowValue (syntax.span, owner, borrowed_parameter);
				}
				if (owner.object_owner != null && borrowed_parameter == null && !pointer_comparison) {
					fail (syntax.span, "persistent alias from owned ClassType binding '%s' is unsupported; use a temporary borrowed parameter, field or method".printf (name));
					return null;
				}
				if (((LocalSymbol) symbol).is_owned && borrowed_parameter != null) {
					if (owner.semantic_type is ClosureHandleType && borrowed_parameter.semantic_type is CallbackType && !((CallbackType) borrowed_parameter.semantic_type).matches_closure (owner.semantic_type)) {
						fail (syntax.span, "captured callback requires an exact nonthrowing synchronous copied-scalar Closure signature");
						return null;
					}
					return new CheckedOwnedBorrowValue (syntax.span, (LocalSymbol) symbol, borrowed_parameter);
				}
				if (((LocalSymbol) symbol).cleanup != null && ownership_use != OwnershipUse.NULL_COMPARISON) {
					fail (syntax.span, "owned local '%s' cannot be copied, returned, or passed to calls; OWN-1 permits only null comparison and automatic lexical cleanup".printf (name));
					return null;
				}
				if (((LocalSymbol) symbol).semantic_type is ArrayType) {
					fail (syntax.span, "whole-array values, copying and equality are unsupported; access an element");
					return null;
				}
				if (((LocalSymbol) symbol).semantic_type.kind == TypeKind.STRUCT) {
					fail (syntax.span, "whole-struct values are not supported yet; access a field");
					return null;
				}
				return new CheckedLocalReferenceExpression (syntax.span, (LocalSymbol) symbol);
			}
			// Slice and object-reference copies retain lexical authority; no result/storage escape is admitted.
			var parameter = (ParameterSymbol) symbol;
			if (parameter.semantic_type is ClosureHandleType && borrowed_parameter != null && borrowed_parameter.semantic_type is CallbackType) {
				var callback = (CallbackType) borrowed_parameter.semantic_type;
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || !callback.matches_closure (parameter.semantic_type)) {
					fail (syntax.span, "captured callback forwarding requires an exact borrowed synchronous nonthrowing Closure");
					return null;
				}
				return new CheckedCallbackParameterView (syntax.span, callback, parameter, borrowed_parameter);
			}
			if (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is StringType) && !(parameter.semantic_type is SliceType) && !(parameter.semantic_type is ClassType) && borrowed_parameter == null && !pointer_comparison && !(ownership_use == OwnershipUse.RECEIVER_BORROW && (ForeignApiTypes.scalar_pointee (parameter.semantic_type) != null || parameter.semantic_type is CallbackType))) {
				fail (syntax.span, "borrowed parameter '%s' cannot be stored, returned, or forwarded to an unmanaged parameter; only equality and direct borrowed/noescape forwarding are permitted".printf (name));
				return null;
			}
			return new CheckedParameterReferenceExpression (syntax.span, parameter);
		}
		if (syntax is ParenthesizedExpressionSyntax) {
			// Precedence is already in the tree. Retain the inner source span.
			return check_expression (((ParenthesizedExpressionSyntax) syntax).expression, values, expected_type, ownership_use, borrowed_parameter, pointer_comparison);
		}
		if (syntax is PrefixExpressionSyntax) {
			var prefix = (PrefixExpressionSyntax) syntax;
			var operator_kind = resolve_prefix_operator (prefix.operator_token.kind);
			// Inspect syntax before checking the operand: 2^(N-1) can form
			// signed MIN, never an ordinary positive signed constant.
			var literal_form = prefix.operand;
			while (literal_form is ParenthesizedExpressionSyntax) {
				literal_form = ((ParenthesizedExpressionSyntax) literal_form).expression;
			}
			if ((operator_kind == PrefixOperator.POSITIVE || operator_kind == PrefixOperator.NEGATIVE) && literal_form is IntegerLiteralExpressionSyntax) {
				return check_integer ((IntegerLiteralExpressionSyntax) literal_form, syntax.span, (expected_type as IntegerType) ?? types.i32_type, operator_kind == PrefixOperator.NEGATIVE);
			}
			var operand = check_expression (prefix.operand, values, operator_kind == PrefixOperator.NOT ? null : expected_type);
			if (operand == null) {
				return null;
			}
			if (operand.semantic_type is TypeParameterType && ((TypeParameterType) operand.semantic_type).explicit_capabilities.length != 0) {
				if (operator_kind != PrefixOperator.BIT_NOT) {
					fail (syntax.span, "unary operator '%s' is not authorized by any GEN-CAP-1 capability".printf (operator_kind.spelling ()));
					return null;
				}
				return check_capability_operation (syntax.span, GenericOperationKind.BIT_NOT, (TypeParameterType) operand.semantic_type, operand);
			}
			if (operand.semantic_type is TypeParameterType) {
				fail (syntax.span, "GEN1_PLAIN_COPY permits value transport only; unary operators on a type parameter are unsupported");
				return null;
			}
			if (operator_kind == PrefixOperator.BIT_NOT && !operator_kind.accepts (operand.semantic_type, operand.semantic_type)) {
				fail (syntax.span, "unary '~' requires an integer scalar or vector, found '%s'".printf (operand.semantic_type.display_name ()));
				return null;
			}
			if (!(operand.semantic_type is VectorType) && (operator_kind == PrefixOperator.NOT ? !require_operand (operand, types.bool_type, operator_kind.spelling ()) : !require_numeric_operand (operand, operator_kind.spelling ()))) {
				return null;
			}
			if (!operator_kind.accepts (operand.semantic_type, operand.semantic_type)) {
				if (operand.semantic_type is VectorType && (operator_kind != PrefixOperator.NEGATIVE || ((VectorType) operand.semantic_type).is_mask)) {
					fail (syntax.span, "unary '%s' is not supported for '%s'".printf (operator_kind.spelling (), operand.semantic_type.display_name ()));
					return null;
				}
				fail (syntax.span, "unary '-' is not supported for unsigned integer type '%s'".printf (operand.semantic_type.display_name ()));
				return null;
			}
			if (operand is CheckedFloatExpression) {
				var value = ((CheckedFloatExpression) operand).value;
				return new CheckedFloatExpression (syntax.span, operand.semantic_type, operator_kind == PrefixOperator.NEGATIVE ? value.negated () : value);
			}
			return new CheckedPrefixExpression (syntax.span, operand.semantic_type, operator_kind, operand);
		}
		var short_circuit = syntax as ShortCircuitExpressionSyntax;
		if (short_circuit != null) {
			var operator_kind = short_circuit.operator_token.kind == TokenKind.AMPERSAND_AMPERSAND ? ShortCircuitOperator.AND : ShortCircuitOperator.OR;
			// Runtime suppression never suppresses static RHS analysis.
			var left = check_expression (short_circuit.left, values);
			bool incoming_reachable = field_state != null && field_state.reachable;
			var constant_left = left as CheckedBooleanExpression;
			if (field_state != null && constant_left != null && ((operator_kind == ShortCircuitOperator.AND && constant_left.literal == BooleanLiteral.FALSE) || (operator_kind == ShortCircuitOperator.OR && constant_left.literal == BooleanLiteral.TRUE))) {
				field_state.reachable = false;
			}
			int truth = generic_truth (left);
			if (truth != -1 && operator_kind == ShortCircuitOperator.OR) {
				truth = 1 - truth;
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, syntax.span, truth);
			}
			var right = check_expression (short_circuit.right, values);
			if (generic_owner_flow != null) {
				generic_owner_flow.end ();
			}
			if (field_state != null) {
				field_state.reachable = incoming_reachable;
			}
			if (left == null || right == null || !require_operand (left, types.bool_type, operator_kind.spelling ()) || !require_operand (right, types.bool_type, operator_kind.spelling ())) {
				return null;
			}
			return new CheckedShortCircuitExpression (syntax.span, types.bool_type, operator_kind, left, right);
		}
		if (syntax is ComparisonChainSyntax) {
			var chain = (ComparisonChainSyntax) syntax;
			SemanticType? context = null;
			foreach (var operand in chain.operands) {
				context = (SemanticType?) floating_context (operand, values) ?? integer_context (operand, values);
				if (context != null) {
					break;
				}
			}
			var operands = new GenericArray<CheckedExpression> ();
			var operators = new GenericArray<BinaryOperator> ();
			FieldInitializationState? before_tail = null;
			for (int i = 0; i < chain.operands.length; i++) {
				if (i >= 2) {
					if (i == 2 && field_state != null) {
						before_tail = field_state.copy ();
					}
					if (generic_owner_flow != null) {
						generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, chain.operands[i].span);
					}
				}
				var operand = check_expression (chain.operands[i], values, context);
				if (operand == null) {
					return null;
				}
				if (!(operand.semantic_type is IntegerType || operand.semantic_type is FloatingType) || (operands.length != 0 && operand.semantic_type != operands[0].semantic_type)) {
					fail (operand.span, "comparison chain requires one exact scalar numeric type; vectors and implicit promotions are unsupported");
					return null;
				}
				operands.add (operand);
				context = operand.semantic_type;
			}
			for (int i = 2; i < chain.operands.length; i++) {
				if (generic_owner_flow != null) {
					generic_owner_flow.end ();
				}
			}
			if (before_tail != null) {
				field_state = before_tail;
			}
			foreach (var operation in chain.operators) {
				operators.add (resolve_binary_operator (operation.kind));
			}
			return new CheckedComparisonChain (syntax.span, types.bool_type, operands, operators);
		}
		if (syntax is BinaryExpressionSyntax) {
			var binary = (BinaryExpressionSyntax) syntax;
			if (enum_context_type (binary.left, values) != null || enum_context_type (binary.right, values) != null) {
				if (binary.operator_token.kind != TokenKind.EQUAL_EQUAL && binary.operator_token.kind != TokenKind.BANG_EQUAL) {
					fail (syntax.span, "enums support only payload-free equality and inequality");
					return null;
				}
				var left = check_enum_producer (binary.left, values);
				var right = left == null ? null : check_enum_producer (binary.right, values, left.semantic_type);
				if (right == null) {
					return null;
				}
				if (!left.definition.payload_free) {
					fail (syntax.span, "payload enum equality is unsupported");
					return null;
				}
				return new CheckedEnumEquality (syntax.span, types.bool_type, left, right, binary.operator_token.kind == TokenKind.BANG_EQUAL);
			}
			if (is_shift_token (binary.operator_token.kind)) {
				return check_shift (binary, values, expected_type);
			}
			var operator_kind = resolve_binary_operator (binary.operator_token.kind);
			IntegerType? context = (operator_kind.is_arithmetic () || operator_kind.is_bitwise ()) ? expected_type as IntegerType : null;
			context = context ?? integer_context (binary.left, values) ?? integer_context (binary.right, values);
			// Preserve an available vector expectation for explicit splats in
			// arithmetic/bitwise forms. Scalar literals cannot broadcast implicitly.
			SemanticType? operand_context = (SemanticType?) context ?? ((operator_kind.is_arithmetic () || operator_kind.is_bitwise ()) ? expected_type as VectorType : null);
			var float_context = (operator_kind.is_arithmetic () ? expected_type as FloatingType : null) ?? floating_context (binary.left, values) ?? floating_context (binary.right, values);
			operand_context = (SemanticType?) float_context ?? operand_context;
			var left = check_expression (binary.left, values, operand_context, operator_kind.is_equality () && is_null_syntax (binary.right) ? OwnershipUse.NULL_COMPARISON : OwnershipUse.UNMANAGED, null, operator_kind.is_equality ());
			if (left == null || (!(left.semantic_type is VectorType) && !((left.semantic_type is TypeParameterType) && ((TypeParameterType) left.semantic_type).explicit_capabilities.length != 0) && !operator_kind.is_equality () && !operator_kind.is_bitwise () && !require_numeric_operand (left, operator_kind.spelling ()))) {
				return null;
			}
			// A checked whole-vector operand supplies exact context for an
			// explicit RHS splat, including comparisons after a memory load.
			var right = check_expression (binary.right, values, (SemanticType?) (left.semantic_type as VectorType) ?? (SemanticType?) (left.semantic_type as FloatingType) ?? operand_context, operator_kind.is_equality () && is_null_syntax (binary.left) ? OwnershipUse.NULL_COMPARISON : OwnershipUse.UNMANAGED, null, operator_kind.is_equality ());
			if (right == null || (!(right.semantic_type is VectorType) && !((right.semantic_type is TypeParameterType) && ((TypeParameterType) right.semantic_type).explicit_capabilities.length != 0) && !operator_kind.is_equality () && !operator_kind.is_bitwise () && !require_numeric_operand (right, operator_kind.spelling ()))) {
				return null;
			}
			if (operator_kind.is_equality ()) {
				if (left is CheckedNullPointerExpression && right.semantic_type.is_nullable_pointer_value ()) {
					left = new CheckedNullPointerExpression (left.span, right.semantic_type);
				}
				if (right is CheckedNullPointerExpression && left.semantic_type.is_nullable_pointer_value ()) {
					right = new CheckedNullPointerExpression (right.span, left.semantic_type);
				}
			}
			if (operator_kind == BinaryOperator.REMAINDER && (left.semantic_type is FloatingType || right.semantic_type is FloatingType)) {
				fail (binary.operator_token.span, "operator '%%' is not supported for %s".printf (((left.semantic_type is FloatingType) ? left.semantic_type : right.semantic_type).display_name ()));
				return null;
			}
			if (left.semantic_type is TypeParameterType || right.semantic_type is TypeParameterType) {
				var parameter = (left.semantic_type as TypeParameterType) ?? (TypeParameterType) right.semantic_type;
				if (parameter.explicit_capabilities.length == 0) {
					fail (binary.operator_token.span, "GEN1_PLAIN_COPY permits value transport only; operator '%s' on a type parameter is unsupported at generic definition checking".printf (operator_kind.spelling ()));
					return null;
				}
				var operation = GenericOperationKind.from_binary (operator_kind);
				if (operation == null) {
					fail (binary.operator_token.span, "operator '%s' is not authorized by any GEN-CAP-1 capability".printf (operator_kind.spelling ()));
					return null;
				}
				return check_capability_operation (syntax.span, operation, parameter, left, right);
			}
			SemanticType result_type = (operator_kind.is_arithmetic () || operator_kind.is_bitwise ()) ? left.semantic_type : (left.semantic_type is VectorType) ? (SemanticType) types.vector_of (types.bool_type, ((VectorType) left.semantic_type).lane_count) : types.bool_type;
			if (left.semantic_type is VectorType && left.semantic_type == right.semantic_type && ((VectorType) left.semantic_type).element_type is IntegerType && (operator_kind == BinaryOperator.DIVIDE || operator_kind == BinaryOperator.REMAINDER)) {
				fail (binary.operator_token.span, "integer vector division and remainder are unsupported in VEC-1");
				return null;
			}
			if (!operator_kind.accepts (left.semantic_type, right.semantic_type, result_type)) {
				if (operator_kind.is_bitwise ()) {
					fail (binary.operator_token.span, "operator '%s' requires exactly matching integer or bool scalar/vector operands, found '%s' and '%s'".printf (operator_kind.spelling (), left.semantic_type.display_name (), right.semantic_type.display_name ()));
					return null;
				}
				fail (binary.operator_token.span, "operator '%s' requires matching non-void operands, found '%s' and '%s'".printf (operator_kind.spelling (), left.semantic_type.display_name (), right.semantic_type.display_name ()));
				return null;
			}
			return new CheckedBinaryExpression (syntax.span, result_type, operator_kind, left, right);
		}
		assert_not_reached ();
	}

	private CheckedExpression? check_capability_operation(SourceSpan span, GenericOperationKind operation, TypeParameterType parameter, CheckedExpression left, CheckedExpression? right = null) {
		var capability = capability_names.resolve (operation.capability ().spelling ());
		if (!parameter.explicit_capabilities.contains (capability.identity)) {
			fail (span, "operator '%s' requires explicit capability '%s' on type parameter '%s' at generic definition checking".printf (operation.spelling (), capability.name, parameter.name));
			return null;
		}
		SemanticType result = operation.is_comparison () ? types.bool_type : (SemanticType) parameter;
		if (!operation.accepts (parameter, left.semantic_type, right == null ? null : right.semantic_type, result)) {
			if (operation.is_shift ()) {
				fail (span, "generic shift requires the exact constrained type parameter as value and a concrete scalar IntegerType count; generic counts are unsupported");
			} else if (left is CheckedIntegerExpression || left is CheckedFloatExpression || right is CheckedIntegerExpression || right is CheckedFloatExpression) {
				fail (span, "generic literals cannot be contextualized to constrained type parameter '%s'; supply an exact %s value".printf (parameter.name, parameter.name));
			} else {
				fail (span, "generic operator '%s' requires operands of the exact same type parameter; found '%s' and '%s'".printf (operation.spelling (), left.semantic_type.display_name (), right == null ? "none" : right.semantic_type.display_name ()));
			}
			return null;
		}
		return new CheckedGenericCapabilityOperation (span, result, operation, parameter, capability, left, right);
	}

	private static bool is_shift_token(TokenKind kind) {
		return kind == TokenKind.SHIFT_LEFT || kind == TokenKind.SHIFT_RIGHT;
	}

	private CheckedExpression? check_shift(BinaryExpressionSyntax syntax, ValueScope values, SemanticType? expected_type) {
		var kind = syntax.operator_token.kind == TokenKind.SHIFT_LEFT ? IntegerShiftKind.LEFT : IntegerShiftKind.RIGHT;
		var operand = check_expression (syntax.left, values, expected_type);
		if (operand == null) {
			return null;
		}
		// Count gets its own default/declared integer context, never the
		// value/result context. Both source expressions are checked once.
		var count = check_expression (syntax.right, values);
		if (count == null) {
			return null;
		}
		if (operand.semantic_type is TypeParameterType && ((TypeParameterType) operand.semantic_type).explicit_capabilities.length != 0) {
			return check_capability_operation (syntax.span, kind == IntegerShiftKind.LEFT ? GenericOperationKind.SHIFT_LEFT : GenericOperationKind.SHIFT_RIGHT, (TypeParameterType) operand.semantic_type, operand, count);
		}
		if (!kind.accepts (operand.semantic_type, count.semantic_type, operand.semantic_type)) {
			fail (syntax.operator_token.span, "shift requires an integer scalar/vector value and a scalar integer count, found '%s' and '%s'".printf (operand.semantic_type.display_name (), count.semantic_type.display_name ()));
			return null;
		}
		var immediate = count as CheckedIntegerExpression;
		var element = IntegerShiftKind.element_type (operand.semantic_type);
		if (!checking_constant && immediate != null && !AstraIntegerValue.valid_shift_count (element, immediate.value)) {
			fail (count.span, "shift count must be in 0..%u for '%s', found %s".printf (element.bit_width - 1, operand.semantic_type.display_name (), immediate.value.to_string ()));
			return null;
		}
		return new CheckedIntegerShiftExpression (syntax.span, operand.semantic_type, kind, operand, count);
	}

	private static bool is_null_syntax(ExpressionSyntax syntax) {
		while (syntax is ParenthesizedExpressionSyntax) {
			syntax = ((ParenthesizedExpressionSyntax) syntax).expression;
		}
		return syntax is NullPointerExpressionSyntax;
	}

	private static PrefixOperator resolve_prefix_operator(TokenKind kind) {
		switch (kind) {
		case TokenKind.PLUS:
			return PrefixOperator.POSITIVE;
		case TokenKind.MINUS:
			return PrefixOperator.NEGATIVE;
		case TokenKind.TILDE: return PrefixOperator.BIT_NOT;
		case TokenKind.BANG:
			return PrefixOperator.NOT;
			default:
			assert_not_reached ();
		}
	}

	private static BinaryOperator resolve_binary_operator(TokenKind kind) {
		switch (kind) {
		case TokenKind.AMPERSAND: return BinaryOperator.BIT_AND;
		case TokenKind.PIPE: return BinaryOperator.BIT_OR;
		case TokenKind.CARET: return BinaryOperator.BIT_XOR;
		case TokenKind.PLUS:
			return BinaryOperator.ADD;
		case TokenKind.MINUS:
			return BinaryOperator.SUBTRACT;
		case TokenKind.STAR:
			return BinaryOperator.MULTIPLY;
		case TokenKind.SLASH:
			return BinaryOperator.DIVIDE;
		case TokenKind.PERCENT:
			return BinaryOperator.REMAINDER;
		case TokenKind.LESS:
			return BinaryOperator.LESS;
		case TokenKind.LESS_EQUAL:
			return BinaryOperator.LESS_EQUAL;
		case TokenKind.GREATER:
			return BinaryOperator.GREATER;
		case TokenKind.GREATER_EQUAL:
			return BinaryOperator.GREATER_EQUAL;
		case TokenKind.EQUAL_EQUAL:
			return BinaryOperator.EQUAL;
		case TokenKind.BANG_EQUAL:
			return BinaryOperator.NOT_EQUAL;
			default:
			assert_not_reached ();
		}
	}
}
}
