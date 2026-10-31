// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;

namespace Astra.Core {
public errordomain CoreError {
	INVALID_CHECKED_MODEL,
	INVALID_IR
}

public abstract class CoreNode : Object {
	public SourceSpan span { get; private set; }

	protected CoreNode (SourceSpan span) {
		this.span = span;
	}
}

// Attached foreign boundary only. The program owns the native target;
// this weak reference never creates a function/body ownership cycle.
public class CoreCExport : CoreNode {
	private WeakRef native_target;
	public CoreFunction? target { owned get { return (CoreFunction?) native_target.get (); } }
	private string external_identifier;
	public string external_symbol { get { return external_identifier; } }
	public SourceSpan name_span { get; private set; }
	public ForeignAbi abi { get; private set; }
	public int ordinal { get; private set; }
	public CRecordAbi record_abi { get; private set; }
	public CBoolAbi bool_abi { get; internal set; }
	private CBoolAbi admitted_bool_abi;
	public bool bool_policy_valid() {
		return bool_abi == admitted_bool_abi && bool_abi.valid ();
	}

	internal CoreCExport (SourceSpan span, SourceSpan name_span, CoreFunction target, string external_symbol, ForeignAbi abi, int ordinal, CRecordAbi record_abi = CRecordAbi.NONE, CBoolAbi bool_abi = CBoolAbi.NONE) {
		base (span);
		this.bool_abi = admitted_bool_abi = bool_abi;
		this.name_span = name_span;
		this.native_target = WeakRef (target);
		this.external_identifier = external_symbol;
		this.abi = abi;
		this.ordinal = ordinal;
		this.record_abi = record_abi;
	}
}

// Stage-owned responsibility with foreign cleanup or exact native class
// lifetime authority. No ABI, syntax or predecessor identity is retained.
public class CoreCleanupContract : Object {
	private WeakRef record_identity;
	public CoreStruct? record_type { owned get { return (CoreStruct?) record_identity.get (); } }
	internal CoreCleanupContract.for_record (CoreStruct record, int ordinal) {
		this.record_identity = WeakRef (record);
		this.identifier = "";
		this.symbol_span = record.name_span;
		this.ordinal = ordinal;
	}
	public BufferValueShape? buffer_shape { get; internal set; }
	public SliceType? buffer_type { get { return buffer_shape == null ? null : buffer_shape.slice_type; } }
	public bool is_buffer { get { return buffer_type != null; } }
	// A symbolic buffer group carries no target layout or allocator identity.
	public bool is_symbolic_buffer { get { return is_buffer && buffer_type.is_parameterized (); } }
	internal CoreCleanupContract.for_buffer (BufferValueShape shape, SourceSpan span, int ordinal) {
		this.buffer_shape = shape;
		this.identifier = "";
		this.symbol_span = span;
		this.ordinal = ordinal;
	}
	// Parameterized responsibility, never a concrete destructor or ABI contract.
	public TypeParameterType? type_parameter { get; private set; }
	internal CoreCleanupContract.for_parameter (TypeParameterType type, SourceSpan span, int ordinal) {
		this.type_parameter = type;
		this.identifier = "";
		this.symbol_span = span;
		this.ordinal = ordinal;
	}
	public ClosureHandleType? closure_type { get; internal set; }
	private WeakRef closure_environment_identity;
	public CoreClass? closure_environment { owned get { return (CoreClass?) closure_environment_identity.get (); } internal set { closure_environment_identity = WeakRef (value); } }
	public SharedHandleType? shared_type { get; internal set; }
	private WeakRef shared_payload_identity;
	public CoreClass? shared_payload { owned get { return (CoreClass?) shared_payload_identity.get (); } internal set { shared_payload_identity = WeakRef (value); } }
	private WeakRef class_identity;
	public bool is_heap_object { get; private set; default = false; }
	public bool is_object { get; private set; default = false; }
	public bool is_symbolic_object { get { return is_object && object_class != null && object_class.semantic_type.is_parameterized (); } }
	public CoreClass? object_class { owned get { return (CoreClass?) class_identity.get (); } }
	public CoreDestructor? destructor { owned get { return object_class == null ? null : object_class.destructor; } }

	internal CoreCleanupContract.for_object (CoreClass object_class, int ordinal, bool heap = false) {
		this.is_heap_object = heap;
		this.is_object = true;
		this.class_identity = WeakRef (object_class);
		this.identifier = "";
		this.symbol_span = object_class.name_span;
		this.ordinal = ordinal;
	}

	private string identifier;
	public string external_symbol { get { return identifier; } }
	public SourceSpan symbol_span { get; private set; }
	public int ordinal { get; internal set; }

	internal CoreCleanupContract (string external_symbol, SourceSpan symbol_span, int ordinal) {
		this.identifier = external_symbol;
		this.symbol_span = symbol_span;
		this.ordinal = ordinal;
	}
}

public class CoreProgram : CoreNode {
	public GenericArray<ClassTypeArgument> class_type_arguments { get; private set; default = new GenericArray<ClassTypeArgument> (); }
	public GenericArray<ExactClassDefinitionIdentity> generic_classes { get; private set; default = new GenericArray<ExactClassDefinitionIdentity> (); }
	public SemanticType? exception_bool_type { get; internal set; }
	public GenericArray<EnumDefinition> enums { get; private set; default = new GenericArray<EnumDefinition> (); }
	public GenericArray<Astra.Text.TextBytes> text_literals { get; private set; default = new GenericArray<Astra.Text.TextBytes> (); }
	public GenericArray<CoreGenericStruct> generic_structs { get; private set; default = new GenericArray<CoreGenericStruct> (); }
	public GenericArray<CoreGenericFunction> generic_functions { get; private set; default = new GenericArray<CoreGenericFunction> (); }
	public GenericArray<CoreFunction> all_definitions() {
		var result = new GenericArray<CoreFunction> ();
		foreach (var function in functions) {
			result.add (function);
		}
		foreach (var function in generic_functions) {
			result.add (function);
		}
		return result;
	}
	public GenericArray<CoreClass> classes { get; private set; default = new GenericArray<CoreClass> (); }
	public GenericArray<CoreClass> class_applications { get; private set; default = new GenericArray<CoreClass> (); }
	public GenericArray<CoreMethod> method_applications { get; private set; default = new GenericArray<CoreMethod> (); }

	public GenericArray<CoreNativeInstance> native_instances() {
		var result = new GenericArray<CoreNativeInstance> ();
		foreach (var instance in structs) {
			result.add (instance);
		}
		foreach (var instance in classes) {
			result.add (instance);
		}
		return result;
	}

	public GenericArray<CoreHandle> handles { get; private set; }
	public GenericArray<CoreCleanupContract> cleanups { get; private set; }
	public GenericArray<CoreStruct> structs { get; private set; }
	public GenericArray<CoreFunction> functions { get; private set; }
	public GenericArray<CoreCFunction> c_functions { get; private set; }
	public GenericArray<CoreCExport> c_exports { get; private set; }

	internal CoreProgram (SourceSpan span, GenericArray<CoreFunction> functions, GenericArray<CoreCFunction>? c_functions = null, GenericArray<CoreCExport>? c_exports = null, GenericArray<CoreStruct>? structs = null, GenericArray<CoreCleanupContract>? cleanups = null, GenericArray<CoreHandle>? handles = null) {
		base (span);
		this.handles = handles ?? new GenericArray<CoreHandle> ();
		this.cleanups = cleanups ?? new GenericArray<CoreCleanupContract> ();
		this.functions = functions;
		this.c_functions = c_functions ?? new GenericArray<CoreCFunction> ();
		this.structs = structs ?? new GenericArray<CoreStruct> ();
		this.c_exports = c_exports ?? new GenericArray<CoreCExport> ();
	}
}

// Independent foreign declaration identity, without a body or native ABI data.
public class CoreCFunction : CoreNode {
	// Full stage parameter identity/contract; parameter_types remains a verified mirror.
	public GenericArray<CoreParameter> parameters { get; private set; }
	public CoreCleanupContract? owned_cleanup { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public CForeignMetadata metadata { get; private set; }
	public string external_symbol { get { return metadata.external_symbol; } }
	public SourceSpan name_span { get; private set; }
	public ForeignAbi abi { get; private set; }
	public SemanticType return_type { get; private set; }
	public GenericArray<SemanticType> parameter_types { get; private set; }
	public int ordinal { get; private set; }

	internal CoreCFunction (SourceSpan span, SourceSpan name_span, string name, CForeignMetadata metadata, ForeignAbi abi, SemanticType return_type, GenericArray<SemanticType> parameter_types, int ordinal, CoreCleanupContract? owned_cleanup = null, GenericArray<CoreParameter>? parameters = null) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.metadata = metadata.copy ();
		this.owned_cleanup = owned_cleanup;
		this.abi = abi;
		this.return_type = return_type;
		this.parameter_types = parameter_types;
		this.parameters = parameters ?? new GenericArray<CoreParameter> ();
		if (parameters == null) {
			for (int p = 0; p < parameter_types.length; p++) {
				this.parameters.add (new CoreParameter (span, name_span, "", parameter_types[p], p));
			}
		}
		this.ordinal = ordinal;
	}
}

public class CoreFunction : CoreNode {
	public NativeDeclarationSignature? native_declaration { get; internal set; }
	private NativeDeclarationSignature? native_declaration_origin;
	internal void bind_native_declaration(NativeDeclarationSignature declaration) throws CoreError {
		if (native_declaration_origin != null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("native declaration cannot be rebound");
		}
		native_declaration = native_declaration_origin = declaration;
	}
	internal bool native_declaration_valid() {
		return native_declaration == native_declaration_origin;
	}
	public uint floating_policy { get; internal set; default = 0; }
	private uint floating_policy_origin;
	private bool floating_policy_bound;
	internal void bind_floating_policy(uint permissions) {
		floating_policy = permissions;
		if (!floating_policy_bound) {
			floating_policy_origin = permissions;
			floating_policy_bound = true;
		}
	}
	public bool floating_policy_valid() {
		return floating_policy == floating_policy_origin && Astra.Semantic.FloatingPointPolicy.valid (floating_policy);
	}
	public bool nonnull_result { get; private set; default = false; }
	internal void mark_nonnull_result() {
		nonnull_result = true;
	}
	public bool utf8_factory { get; internal set; default = false; }
	public AsyncBodyContract? async_body { get; internal set; }
	public bool heap_result { get; internal set; default = false; }
	public ClassType? throws_type { get; internal set; }
	public ClassDispatchKind dispatch_kind { get; internal set; default = ClassDispatchKind.DIRECT; }
	public int virtual_slot { get; internal set; default = -1; }
	public StructValueContract? struct_result_contract { get; internal set; }
	public GenericFunctionInstance? generic_instance { get; internal set; }
	public CoreResultObjectStorage? result_storage { get; internal set; }
	public CallableKind kind { get { return (this is CorePropertyGetter) ? CallableKind.PROPERTY_GETTER : (this is CorePropertySetter) ? CallableKind.PROPERTY_SETTER : (this is CoreConstructor) ? CallableKind.CONSTRUCTOR : (this is CoreDestructor) ? CallableKind.DESTRUCTOR : (this is CoreMethod) ? CallableKind.METHOD : CallableKind.FUNCTION; } }
	public CoreReceiver? implicit_receiver { get { return (this is CorePropertyAccessor) ? ((CorePropertyAccessor) this).receiver : (this is CoreMethod) ? ((CoreMethod) this).receiver : (this is CoreLifecycle) ? ((CoreLifecycle) this).receiver : null; } }
	public GenericArray<CoreObjectStorage> object_storage { get; private set; default = new GenericArray<CoreObjectStorage> (); }
	public CoreCleanupContract? owned_cleanup { get; private set; }
	public ResultOwnershipContract result_contract { get { return this is CorePropertyGetter && ((CorePropertyGetter) this).property_member.is_borrowed ? ResultOwnershipContract.RECEIVER_BORROW : (return_type is StringType) ? ((this is CorePropertyGetter) ? ResultOwnershipContract.RECEIVER_TEXT : ResultOwnershipContract.STATIC_TEXT) : owned_cleanup == null ? ResultOwnershipContract.UNMANAGED : ResultOwnershipContract.OWNED_TRANSFER; } }
	public GenericArray<CoreOwnedLocal> owned_locals { get; private set; default = new GenericArray<CoreOwnedLocal> (); }
	public string name { get { return identifier; } }
	private string identifier;
	public SourceSpan name_span { get; private set; }
	public SemanticType return_type { get; internal set; }
	public GenericArray<CoreParameter> parameters { get; private set; }
	public GenericArray<CoreFieldPlace> field_places { get; private set; }
	public GenericArray<CoreLocalPlace> locals { get; private set; }
	public CoreBlock body { get; private set; }

	internal CoreFunction (SourceSpan span, SourceSpan name_span, string name, SemanticType return_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body, CoreCleanupContract? owned_cleanup = null) {
		base (span);
		this.owned_cleanup = owned_cleanup;
		this.name_span = name_span;
		this.identifier = name;
		this.return_type = return_type;
		this.parameters = parameters;
		if (return_type.is_struct_storage ()) {
			this.struct_result_contract = new StructValueContract (return_type);
		}
		this.field_places = new GenericArray<CoreFieldPlace> ();
		this.locals = locals;
		this.body = body;
	}
}

// Containment in exactly one function's parameter array defines ownership.
// References retain this identity directly; no parent cycle is necessary.
public class CoreParameter : CoreNode {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}
	public bool heap_object { get; internal set; default = false; }
	public StructValueContract? struct_value_contract { get; internal set; }
	public PointerParameterContract pointer_contract { get; private set; }
	public string name { get { return identifier; } }
	private string identifier;
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; internal set; }
	public int ordinal { get; private set; }

	internal CoreParameter (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, PointerParameterContract pointer_contract = PointerParameterContract.UNMANAGED) {
		base (span);
		this.pointer_contract = pointer_contract;
		if (semantic_type.is_struct_storage ()) {
			this.struct_value_contract = new StructValueContract (semantic_type);
		}
		this.name_span = name_span;
		this.identifier = name;
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
	}
}

// Storage authority, independent of values and any physical realization.
public abstract class CorePlace : CoreNode {
	public SemanticType semantic_type { get; internal set; }

	// Addressability is authoritative storage capability, not a layout hint.
	public bool is_promotable() {
		if (semantic_type is EnumType || semantic_type is ArrayType || semantic_type.is_struct_storage ()) {
			return false;
		}
		var field = this as CoreFieldPlace;
		if (field != null) {
			var local = field.root_local ();
			return local != null && !local.address_taken;
		}
		return (this is CoreLocalPlace) && !((CoreLocalPlace) this).address_taken && semantic_type.kind != TypeKind.STRUCT;
	}

	protected CorePlace (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}
}

// Containment in exactly one function's locals array defines ownership.
public class CoreLocalPlace : CorePlace {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}
	public Astra.Text.TextLoanExtent? text_extent { get; internal set; }
	public bool text_loan { get; internal set; default = false; }
	public CoreParameter? incoming_parameter { get; private set; }
	public bool address_taken { get; private set; }
	public string name { get { return identifier; } }
	private string identifier;
	public SourceSpan name_span { get; private set; }
	public int ordinal { get; private set; }

	internal CoreLocalPlace (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, bool address_taken = false, CoreParameter? incoming_parameter = null) {
		base (span, semantic_type);
		this.incoming_parameter = incoming_parameter;
		this.address_taken = address_taken;
		this.name_span = name_span;
		this.identifier = name;
		this.ordinal = ordinal;
	}
}

// A structured, ordered container, with no control-flow identity or edges.
public class CoreBlock : CoreNode {
	public Astra.Text.TextLoanExtent? text_extent { get; internal set; }
	public GenericArray<CoreStatement> statements { get; private set; }

	internal CoreBlock (SourceSpan span, GenericArray<CoreStatement> statements) {
		base (span);
		this.statements = statements;
	}
}

public abstract class CoreStatement : CoreNode {
	protected CoreStatement (SourceSpan span) {
		base (span);
	}
}

// A source lexical block uses the same scope/cleanup authority as if/while bodies.
public class CoreScope : CoreStatement {
	public CoreBlock body { get; private set; }

	internal CoreScope (SourceSpan span, CoreBlock body) {
		base (span);
		this.body = body;
	}
}
public class CoreWithContract : CoreNode {
	public CoreLocalPlace source { get; private set; }
	public ReceiverType receiver_type { get; private set; }
	public CoreWithContract (SourceSpan span, CoreLocalPlace source, ReceiverType receiver_type) {
		base (span);
		this.source = source;
		this.receiver_type = receiver_type;
	}
}
public class CoreWithScope : CoreScope {
	public CoreWithContract contract { get; internal set; }
	public CoreLocalPlace source { get; private set; }
	public CoreWithScope (SourceSpan span, CoreWithContract contract, CoreBlock body) {
		base (span, body);
		this.contract = contract;
		this.source = contract.source;
	}
}
public class CoreWithReference : CoreValue {
	public CoreWithContract contract { get; internal set; }
	public CoreWithReference (SourceSpan span, CoreWithContract contract) {
		base (span, contract.source.semantic_type);
		this.contract = contract;
	}
}

public class CoreIf : CoreStatement {
	public CoreValue condition { get; private set; }
	public CoreBlock then_block { get; private set; }
	public CoreBlock? else_block { get; private set; }

	internal CoreIf (SourceSpan span, CoreValue condition, CoreBlock then_block, CoreBlock? else_block) {
		base (span);
		this.condition = condition;
		this.then_block = then_block;
		this.else_block = else_block;
	}
}

// Core-owned structured target identity, independent of checked nodes and
// CFG blocks. Its owning while has no back-reference from this target.
public class CoreLoopTarget : CoreNode {
	public int ordinal { get; private set; }

	internal CoreLoopTarget (SourceSpan span, int ordinal) {
		base (span);
		this.ordinal = ordinal;
	}
}

public class CoreWhile : CoreStatement {
	public CoreSequenceIteration? sequence { get; internal set; }
	public bool has_sequence { get; private set; }
	public CoreIterationContract? iteration { get; internal set; }
	public bool has_iteration { get; private set; }
	public CoreLoopTarget target { get; private set; }
	public CoreValue condition { get; private set; }
	public CoreBlock body { get; private set; }
	public bool has_step { get; private set; }
	public CoreBlock? step { get; internal set; }

	internal CoreWhile (SourceSpan span, CoreLoopTarget target, CoreValue condition, CoreBlock body, CoreBlock? step = null, CoreIterationContract? iteration = null, CoreSequenceIteration? sequence = null) {
		base (span);
		this.target = target;
		this.condition = condition;
		this.body = body;
		this.step = step;
		this.has_step = step != null;
		this.iteration = iteration;
		this.has_iteration = iteration != null;
		this.sequence = sequence;
		this.has_sequence = sequence != null;
	}
}

public class CoreSequenceIteration : CoreNode {
	public bool is_iterator { get; private set; }
	private WeakRef advance_method;
	private WeakRef current_method;
	public CoreMethod? advance { owned get { return (CoreMethod?) advance_method.get (); } }
	public CoreMethod? current { owned get { return (CoreMethod?) current_method.get (); } }
	public CoreLoopTarget target { get; private set; }
	public CoreValue source { get; private set; }
	public CoreLocalPlace? index { get; private set; }
	public CoreLocalPlace binding { get; private set; }
	internal CoreSequenceIteration (SourceSpan span, CoreLoopTarget target, CoreValue source, CoreLocalPlace index, CoreLocalPlace binding) {
		base (span);
		this.target = target;
		this.source = source;
		this.index = index;
		this.binding = binding;
	}
	internal CoreSequenceIteration.iterator (SourceSpan span, CoreLoopTarget target, CoreValue source, CoreLocalPlace binding, CoreMethod advance, CoreMethod current) {
		base (span);
		this.is_iterator = true;
		this.target = target;
		this.source = source;
		this.binding = binding;
		this.advance_method = WeakRef (advance);
		this.current_method = WeakRef (current);
	}
}

public class CoreIterationContract : CoreNode {
	public CoreLocalPlace? binding { get; private set; }
	public CoreLoopTarget target { get; private set; }
	public CoreIndirectFieldPlace store { get; private set; }
	public CoreLocalPlace index { get; private set; }
	internal CoreIterationContract (SourceSpan span, CoreLoopTarget target, CoreIndirectFieldPlace store, CoreLocalPlace index, CoreLocalPlace? binding = null) {
		base (span);
		this.target = target;
		this.store = store;
		this.index = index;
		this.binding = binding;
	}
}

public class CoreBreak : CoreStatement {
	private WeakRef loop_target;
	public CoreLoopTarget? target { owned get { return (CoreLoopTarget?) loop_target.get (); } }

	internal CoreBreak (SourceSpan span, CoreLoopTarget target) {
		base (span);
		this.loop_target = WeakRef (target);
	}
}

public class CoreContinue : CoreStatement {
	private WeakRef loop_target;
	public CoreLoopTarget? target { owned get { return (CoreLoopTarget?) loop_target.get (); } }

	internal CoreContinue (SourceSpan span, CoreLoopTarget target) {
		base (span);
		this.loop_target = WeakRef (target);
	}
}

// Programs own functions. Weak call targets prevent recursive ownership
// cycles and become null if a detached callee expires.
public class CoreValueStatement : CoreStatement {
	public CoreValue value { get; private set; }
	internal CoreValueStatement (SourceSpan span, CoreValue value) {
		base (span);
		this.value = value;
	}
}

public class CoreCallStatement : CoreStatement {
	public CoreValue? receiver { get; private set; }
	private WeakRef callee;
	public CoreFunction? target { owned get { return (CoreFunction?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }

	internal CoreCallStatement (SourceSpan span, CoreFunction target, GenericArray<CoreValue> arguments, CoreValue? receiver = null) {
		base (span);
		this.callee = WeakRef (target);
		this.receiver = receiver;
		this.arguments = arguments;
	}
}

// Conservatively effectful C boundary; only the program owns the target.
public class CoreCCallStatement : CoreStatement {
	private WeakRef callee;
	public CoreCFunction? target { owned get { return (CoreCFunction?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }

	internal CoreCCallStatement (SourceSpan span, CoreCFunction target, GenericArray<CoreValue> arguments) {
		base (span);
		this.callee = WeakRef (target);
		this.arguments = arguments;
	}
}

public class CoreReturn : CoreStatement {
	public CoreValue? value { get; private set; }

	internal CoreReturn (SourceSpan span, CoreValue? value) {
		base (span);
		this.value = value;
	}
}

// Responsibility is separate from ordinary scalar Place identity. The
// containing CoreBlock is the normalized checked LexicalRegion authority.
public class CoreOwnedLocal : CoreNode {
	public GenericArray<CoreFieldPlace> record_fields { get; private set; default = new GenericArray<CoreFieldPlace> (); }
	public CoreObjectStorage? object_storage { get; private set; }
	public CoreLocalPlace place { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	private WeakRef lexical_scope;
	public CoreBlock? scope { owned get { return (CoreBlock?) lexical_scope.get (); } }

	internal CoreOwnedLocal (SourceSpan span, CoreLocalPlace place, CoreCleanupContract cleanup, CoreBlock scope, CoreObjectStorage? object_storage = null) {
		base (span);
		this.place = place;
		this.object_storage = object_storage;
		this.cleanup = cleanup;
		this.lexical_scope = WeakRef (scope);
	}
}

// Transfer retains responsibility and exact identities until CFG flow validation.
public class CoreOwnershipTransfer : CoreStatement {
	public CoreOwnedLocal source { get; private set; }
	public CoreOwnedLocal destination { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }

	internal CoreOwnershipTransfer (SourceSpan span, CoreOwnedLocal source, CoreOwnedLocal destination, CoreCleanupContract cleanup) {
		base (span);
		this.source = source;
		this.destination = destination;
		this.cleanup = cleanup;
	}
}

// A fresh result in an existing slot; scope, contract and cleanup rank stay fixed.
public class CoreOwnershipRearm : CoreStatement {
	public CoreOwnedLocal? source { get; private set; }
	internal CoreOwnershipRearm.from_owner (SourceSpan span, CoreOwnedLocal owner, CoreOwnedLocal source, CoreCleanupContract cleanup) {
		base (span);
		this.owner = owner;
		this.source = source;
		this.cleanup = cleanup;
	}
	public CoreOwnedLocal owner { get; private set; }
	public CoreValue? producer { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }

	internal CoreOwnershipRearm (SourceSpan span, CoreOwnedLocal owner, CoreValue producer, CoreCleanupContract cleanup) {
		base (span);
		this.owner = owner;
		this.producer = producer;
		this.cleanup = cleanup;
	}
}

// Explicit discharge, separate from compiler-generated lexical cleanup.
public class CoreOwnershipRelease : CoreStatement {
	public CoreOwnedLocal owner { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }

	internal CoreOwnershipRelease (SourceSpan span, CoreOwnedLocal owner, CoreCleanupContract cleanup) {
		base (span);
		this.owner = owner;
		this.cleanup = cleanup;
	}
}

public class CoreAcquireParameter : CoreInitialize {
	internal CoreAcquireParameter (SourceSpan span, CoreOwnedLocal owner, CoreParameter parameter) {
		base (span, owner.place, new CoreParameterValue (span, parameter), owner);
	}
}

public class CoreOwnedArgumentValue : CoreValue {
	public CoreValue? producer { get; private set; }
	public CoreOwnedLocal? source { get; private set; }
	public CoreParameter parameter { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }

	internal CoreOwnedArgumentValue (SourceSpan span, CoreParameter parameter, CoreCleanupContract cleanup, CoreOwnedLocal? source, SemanticType? substituted_type = null, CoreValue? producer = null) {
		base (span, substituted_type ?? parameter.semantic_type);
		this.producer = producer;
		this.parameter = parameter;
		this.cleanup = cleanup;
		this.source = source;
	}
}

public class CoreOwnershipReturn : CoreStatement {
	public CoreValue? producer { get; private set; }
	public ObjectResultProvenance provenance { get; private set; }
	public CoreOwnedLocal? source { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }

	internal CoreOwnershipReturn (SourceSpan span, SemanticType semantic_type, CoreCleanupContract cleanup, CoreOwnedLocal? source, CoreValue? producer = null, ObjectResultProvenance provenance = ObjectResultProvenance.NONE) {
		base (span);
		this.semantic_type = semantic_type;
		this.cleanup = cleanup;
		this.source = source;
		this.producer = producer;
		this.provenance = provenance;
	}
}

public class CoreInitialize : CoreStatement {
	// An explicit Acquire event, armed only after value evaluation returns.
	public CoreOwnedLocal? acquisition { get; private set; }
	public CorePlace target { get; private set; }
	public CoreValue value { get; private set; }

	internal CoreInitialize (SourceSpan span, CorePlace target, CoreValue value, CoreOwnedLocal? acquisition = null) {
		base (span);
		this.acquisition = acquisition;
		this.target = target;
		this.value = value;
	}
}

public class CoreStore : CoreStatement {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public CorePlace target { get; private set; }
	public CoreValue value { get; private set; }

	internal CoreStore (SourceSpan span, CorePlace target, CoreValue value, VolatileAccessContract? access = null) {
		base (span);
		volatile_access = access;
		volatile_enabled = access != null;
		this.target = target;
		this.value = value;
	}
}

public abstract class CoreValue : CoreNode {
	public Astra.Text.TextLoanIntent? text_loan_intent { get; internal set; }
	public SemanticType semantic_type { get; private set; }

	protected CoreValue (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}
}

public class CoreCallValue : CoreValue {
	public CoreObjectStorage? candidate_storage { get; internal set; }
	public CoreResultObjectStorage? result_storage { get; internal set; }
	public CoreValue? receiver { get; private set; }
	private WeakRef callee;
	public CoreFunction? target { owned get { return (CoreFunction?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }

	internal CoreCallValue (SourceSpan span, SemanticType semantic_type, CoreFunction target, GenericArray<CoreValue> arguments, CoreValue? receiver = null) {
		base (span, semantic_type);
		this.callee = WeakRef (target);
		this.receiver = receiver;
		this.arguments = arguments;
	}
}

// Conservatively effectful C boundary; only the program owns the target.
public class CoreCCallValue : CoreValue {
	private WeakRef callee;
	public CoreCFunction? target { owned get { return (CoreCFunction?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }

	internal CoreCCallValue (SourceSpan span, SemanticType semantic_type, CoreCFunction target, GenericArray<CoreValue> arguments) {
		base (span, semantic_type);
		this.callee = WeakRef (target);
		this.arguments = arguments;
	}
}

public class CoreNullPointerValue : CoreValue {
	internal CoreNullPointerValue (SourceSpan span, SemanticType semantic_type) {
		base (span, semantic_type);
	}
}

public class CoreBooleanValue : CoreValue {
	public BooleanLiteral literal { get; private set; }

	internal CoreBooleanValue (SourceSpan span, SemanticType semantic_type, BooleanLiteral literal) {
		base (span, semantic_type);
		this.literal = literal;
	}
}

public class CoreVectorDotValue : CoreValue {
	public VectorDotKind dot_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CoreValue? accumulator { get; private set; }
	public CoreValue first { get; private set; }
	public CoreValue second { get; private set; }

	internal CoreVectorDotValue (SourceSpan span, VectorDotKind dot_kind, SemanticType source_type, SemanticType destination_type, CoreValue? accumulator, CoreValue first, CoreValue second) {
		base (span, destination_type);
		this.dot_kind = dot_kind;
		this.source_type = source_type;
		this.accumulator = accumulator;
		this.first = first;
		this.second = second;
	}
}

public class CoreDspValue : CoreValue {
	public DspPrimitiveKind primitive_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public IntegerType? destination_element { get; private set; }
	public CoreValue first { get; private set; }
	public CoreValue? second { get; private set; }

	internal CoreDspValue (SourceSpan span, DspPrimitiveKind primitive_kind, SemanticType source_type, SemanticType destination_type, CoreValue first, CoreValue? second, IntegerType? destination_element = null) {
		base (span, destination_type);
		this.primitive_kind = primitive_kind;
		this.source_type = source_type;
		this.destination_element = destination_element;
		this.first = first;
		this.second = second;
	}
}

// Direction owns the invalid-count trap contract; width and count type
// derive from exact retained values, with no independently mutable copy.
public class CoreIntegerShiftValue : CoreValue {
	public IntegerShiftKind shift_kind { get; private set; }
	public CoreValue operand { get; private set; }
	public CoreValue count { get; private set; }
	public uint element_bit_width { get { return IntegerShiftKind.element_type (semantic_type).bit_width; } }

	internal CoreIntegerShiftValue (SourceSpan span, SemanticType semantic_type, IntegerShiftKind shift_kind, CoreValue operand, CoreValue count) {
		base (span, semantic_type);
		this.shift_kind = shift_kind;
		this.operand = operand;
		this.count = count;
	}
}

public class CoreNumericConversionValue : CoreValue {
	public NumericConversionPolicy policy { get; private set; }
	public NumericConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CoreValue operand { get; private set; }

	internal CoreNumericConversionValue (SourceSpan span, SemanticType source_type, SemanticType destination_type, NumericConversionKind conversion_kind, CoreValue operand, NumericConversionPolicy policy) {
		base (span, destination_type);
		this.policy = policy;
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}
}

public class CoreFloatConversionValue : CoreValue {
	public FloatConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CoreValue operand { get; private set; }

	internal CoreFloatConversionValue (SourceSpan span, SemanticType source_type, SemanticType destination_type, FloatConversionKind conversion_kind, CoreValue operand) {
		base (span, destination_type);
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}
}

public class CoreIntegerConversionValue : CoreValue {
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CoreValue operand { get; private set; }

	internal CoreIntegerConversionValue (SourceSpan span, SemanticType source_type, SemanticType destination_type, CoreValue operand) {
		base (span, destination_type);
		this.source_type = source_type;
		this.operand = operand;
	}
}

public class CoreVectorSplatValue : CoreValue {
	public CoreValue operand { get; private set; }
	public int lane_count { get; private set; }
	public SourceSpan lane_count_span { get; private set; }

	internal CoreVectorSplatValue (SourceSpan span, SemanticType semantic_type, CoreValue operand, int lane_count, SourceSpan lane_count_span) {
		base (span, semantic_type);
		this.operand = operand;
		this.lane_count = lane_count;
		this.lane_count_span = lane_count_span;
	}
}

public class CoreVectorExtractValue : CoreValue {
	public CoreValue vector { get; private set; }
	public VectorLaneIndex index { get; private set; }

	internal CoreVectorExtractValue (SourceSpan span, SemanticType semantic_type, CoreValue vector, VectorLaneIndex index) {
		base (span, semantic_type);
		this.vector = vector;
		this.index = index.copy ();
	}
}

public class CoreVectorInsertValue : CoreValue {
	public CoreValue vector { get; private set; }
	public VectorLaneIndex index { get; private set; }
	public CoreValue replacement { get; private set; }

	internal CoreVectorInsertValue (SourceSpan span, SemanticType semantic_type, CoreValue vector, VectorLaneIndex index, CoreValue replacement) {
		base (span, semantic_type);
		this.vector = vector;
		this.index = index.copy ();
		this.replacement = replacement;
	}
}

public class CoreVectorShuffleValue : CoreValue {
	public CoreValue vector { get; private set; }
	public VectorLaneSelectors selectors { get; private set; }

	internal CoreVectorShuffleValue (SourceSpan span, SemanticType semantic_type, CoreValue vector, VectorLaneSelectors selectors) {
		base (span, semantic_type);
		this.vector = vector;
		this.selectors = selectors.copy ();
	}
}

public class CoreVectorMemoryValue : CoreValue {
	public VectorMemoryContract contract { get; private set; }
	public CoreValue view { get; private set; }
	public CoreValue offset { get; private set; }
	public CoreValue? stored { get; private set; }
	internal CoreVectorMemoryValue (SourceSpan span, VectorMemoryContract contract, CoreValue view, CoreValue offset, CoreValue? stored) {
		base (span, contract.vector_type);
		this.contract = contract.copy ();
		this.view = view;
		this.offset = offset;
		this.stored = stored;
	}
}

public class CoreVectorMemoryStatement : CoreStatement {
	public CoreVectorMemoryValue operation { get; private set; }
	internal CoreVectorMemoryStatement (SourceSpan span, CoreVectorMemoryValue operation) {
		base (span);
		this.operation = operation;
	}
}

public class CoreVectorSelectValue : CoreValue {
	public CoreValue mask { get; private set; }
	public CoreValue true_value { get; private set; }
	public CoreValue false_value { get; private set; }

	internal CoreVectorSelectValue (SourceSpan span, SemanticType semantic_type, CoreValue mask, CoreValue true_value, CoreValue false_value) {
		base (span, semantic_type);
		this.mask = mask;
		this.true_value = true_value;
		this.false_value = false_value;
	}
}

public class CoreVectorConstructValue : CoreValue {
	public GenericArray<CoreValue> lanes { get; private set; }

	internal CoreVectorConstructValue (SourceSpan span, SemanticType semantic_type, GenericArray<CoreValue> lanes) {
		base (span, semantic_type);
		this.lanes = lanes;
	}
}

public class CoreVectorReductionValue : CoreValue {
	public VectorReductionOperator operator_kind { get; private set; }
	public CoreValue operand { get; private set; }

	internal CoreVectorReductionValue (SourceSpan span, SemanticType semantic_type, VectorReductionOperator operator_kind, CoreValue operand) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}
}

public class CoreFloatValue : CoreValue {
	public BinaryFloatValue value { get; private set; }

	internal CoreFloatValue (SourceSpan span, SemanticType semantic_type, BinaryFloatValue value) {
		base (span, semantic_type);
		this.value = value;
	}
}

public class CoreIntegerValue : CoreValue {
	public AstraIntegerValue value { get; private set; }

	internal CoreIntegerValue (SourceSpan span, SemanticType semantic_type, AstraIntValue value) {
		base (span, semantic_type);
		this.value = value.in_type (semantic_type as IntegerType);
	}

	internal CoreIntegerValue.typed (SourceSpan span, SemanticType semantic_type, AstraIntegerValue value) {
		base (span, semantic_type);
		this.value = value;
	}
}

public class CoreParameterValue : CoreValue {
	public CoreParameter parameter { get; private set; }

	internal CoreParameterValue (SourceSpan span, CoreParameter parameter) {
		base (span, parameter.semantic_type);
		this.parameter = parameter;
	}
}

public class CoreOwnedBorrowValue : CoreValue {
	public CoreOwnedLocal source { get; private set; }
	public CoreParameter parameter { get; private set; }

	internal CoreOwnedBorrowValue (SourceSpan span, CoreOwnedLocal source, CoreParameter parameter) {
		base (span, CallbackType.borrowed_type (source.place.semantic_type, parameter.semantic_type));
		this.source = source;
		this.parameter = parameter;
	}
}

public class CoreLoadValue : CoreValue {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public CorePlace source { get; private set; }

	internal CoreLoadValue (SourceSpan span, CorePlace source, VolatileAccessContract? access = null) {
		base (span, source.semantic_type);
		volatile_access = access;
		volatile_enabled = access != null;
		this.source = source;
	}
}

public class CorePrefixValue : CoreValue {
	public PrefixOperator operator_kind { get; private set; }
	public CoreValue operand { get; private set; }

	internal CorePrefixValue (SourceSpan span, SemanticType semantic_type, PrefixOperator operator_kind, CoreValue operand) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}
}

// Evaluates left first and right only on the required path.
public class CoreShortCircuitValue : CoreValue {
	public ShortCircuitOperator operator_kind { get; private set; }
	public CoreValue left { get; private set; }
	public CoreValue right { get; private set; }

	internal CoreShortCircuitValue (SourceSpan span, SemanticType semantic_type, ShortCircuitOperator operator_kind, CoreValue left, CoreValue right) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.left = left;
		this.right = right;
	}
}

public class CoreComparisonChain : CoreValue {
	public GenericArray<CoreValue> operands { get; private set; }
	public GenericArray<BinaryOperator> operators { get; private set; }
	public int operand_count { get; private set; }
	internal CoreComparisonChain (SourceSpan span, SemanticType result, GenericArray<CoreValue> operands, GenericArray<BinaryOperator> operators) {
		base (span, result);
		this.operands = operands;
		this.operators = operators;
		this.operand_count = operands.length;
	}
}

public class CoreBinaryValue : CoreValue {
	public BinaryOperator operator_kind { get; private set; }
	public CoreValue left { get; private set; }
	public CoreValue right { get; private set; }

	internal CoreBinaryValue (SourceSpan span, SemanticType semantic_type, BinaryOperator operator_kind, CoreValue left, CoreValue right) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.left = left;
		this.right = right;
	}
}
}

namespace Astra.Core {
public class CoreFunctionAddress : CoreValue {
	private WeakRef callee;
	public CoreFunction? target { owned get { return (CoreFunction?) callee.get (); } }
	internal CoreFunctionAddress (SourceSpan span, FunctionValueType type, CoreFunction target) {
		base (span, type);
		callee = WeakRef (target);
	}
}
public interface CoreInvocation : Object {
	public abstract CoreCleanupContract? result_cleanup();
}

public class CoreFunctionValueCall : CoreValue, CoreInvocation {
	public CoreCleanupContract? owned_cleanup { get; private set; }
	public CoreCleanupContract? result_cleanup() {
		return owned_cleanup;
	}
	// Call-owned channel declarations; these are never function inputs or bodies.
	public GenericArray<CoreParameter> channel_parameters { get; private set; default = new GenericArray<CoreParameter> (); }
	public CoreValue callee { get; private set; }
	public GenericArray<CoreValue> arguments { get; private set; }
	internal CoreFunctionValueCall (SourceSpan span, FunctionValueType type, CoreValue callee, GenericArray<CoreValue> arguments, CoreCleanupContract? owned_cleanup = null) {
		base (span, type.result_type);
		this.callee = callee;
		this.arguments = arguments;
		this.owned_cleanup = owned_cleanup;
	}
}
}
