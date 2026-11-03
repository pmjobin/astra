// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;

namespace Astra.Cfg {
public errordomain CfgError {
	INVALID_CORE,
	INVALID_CFG
}

public abstract class CfgNode : Object {
	public SourceSpan span { get; protected set; }

	protected CfgNode (SourceSpan span) {
		this.span = span;
	}

}

// Attached foreign boundary only. The program owns the native target;
// this weak reference never creates a function/body ownership cycle.
public class CfgCExport : CfgNode {
	private WeakRef native_target;
	public CfgFunction? target { owned get { return (CfgFunction?) native_target.get (); } }
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

	internal CfgCExport (SourceSpan span, SourceSpan name_span, CfgFunction target, string external_symbol, ForeignAbi abi, int ordinal, CRecordAbi record_abi = CRecordAbi.NONE, CBoolAbi bool_abi = CBoolAbi.NONE) {
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
public class CfgCleanupContract : Object {
	private WeakRef record_identity;
	public CfgStruct? record_type { owned get { return (CfgStruct?) record_identity.get (); } }
	internal CfgCleanupContract.for_record (CfgStruct record, int ordinal) {
		this.record_identity = WeakRef (record);
		this.identifier = "";
		this.symbol_span = record.name_span;
		this.ordinal = ordinal;
	}
	public BufferValueShape? buffer_shape { get; private set; }
	public SliceType? buffer_type { get { return buffer_shape == null ? null : buffer_shape.slice_type; } }
	public bool is_buffer { get { return buffer_shape != null; } }
	internal CfgCleanupContract.for_buffer (BufferValueShape shape, SourceSpan span, int ordinal) {
		this.buffer_shape = shape;
		this.identifier = "";
		this.symbol_span = span;
		this.ordinal = ordinal;
	}
	public ClosureHandleType? closure_type { get; internal set; }
	private WeakRef closure_environment_identity;
	public CfgClass? closure_environment { owned get { return (CfgClass?) closure_environment_identity.get (); } internal set { closure_environment_identity = WeakRef (value); } }
	public SharedHandleType? shared_type { get; internal set; }
	private WeakRef shared_payload_identity;
	public CfgClass? shared_payload { owned get { return (CfgClass?) shared_payload_identity.get (); } internal set { shared_payload_identity = WeakRef (value); } }
	private WeakRef class_identity;
	public bool is_heap_object { get; private set; default = false; }
	public bool is_object { get; private set; default = false; }
	public CfgClass? object_class { owned get { return (CfgClass?) class_identity.get (); } }
	public CfgDestructor? destructor { owned get { return object_class == null ? null : object_class.destructor; } }

	internal CfgCleanupContract.for_object (CfgClass object_class, int ordinal, bool heap = false) {
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
	public int ordinal { get; private set; }

	internal CfgCleanupContract (string external_symbol, SourceSpan symbol_span, int ordinal) {
		this.identifier = external_symbol;
		this.symbol_span = symbol_span;
		this.ordinal = ordinal;
	}

}

public class CfgProgram : CfgNode {
	public GenericArray<ClassTypeArgument> class_type_arguments { get; private set; default = new GenericArray<ClassTypeArgument> (); }
	public GenericArray<EnumDefinition> enums { get; private set; default = new GenericArray<EnumDefinition> (); }
	public GenericArray<Astra.Text.TextBytes> text_literals { get; private set; default = new GenericArray<Astra.Text.TextBytes> (); }
	public GenericArray<CfgClass> classes { get; private set; default = new GenericArray<CfgClass> (); }

	public GenericArray<CfgNativeInstance> native_instances() {
		var result = new GenericArray<CfgNativeInstance> ();
		foreach (var instance in structs) {
			result.add (instance);
		}
		foreach (var instance in classes) {
			result.add (instance);
		}
		return result;
	}

	public GenericArray<CfgHandle> handles { get; private set; }
	public GenericArray<CfgCleanupContract> cleanups { get; private set; }
	public GenericArray<CfgStruct> structs { get; private set; }
	public GenericArray<CfgFunction> functions { get; private set; }
	public GenericArray<CfgCFunction> c_functions { get; private set; }
	public GenericArray<CfgCExport> c_exports { get; private set; }

	internal CfgProgram (SourceSpan span, GenericArray<CfgFunction> functions, GenericArray<CfgCFunction>? c_functions = null, GenericArray<CfgCExport>? c_exports = null, GenericArray<CfgStruct>? structs = null, GenericArray<CfgCleanupContract>? cleanups = null, GenericArray<CfgHandle>? handles = null) {
		base (span);
		this.handles = handles ?? new GenericArray<CfgHandle> ();
		this.cleanups = cleanups ?? new GenericArray<CfgCleanupContract> ();
		this.functions = functions;
		this.c_functions = c_functions ?? new GenericArray<CfgCFunction> ();
		this.structs = structs ?? new GenericArray<CfgStruct> ();
		this.c_exports = c_exports ?? new GenericArray<CfgCExport> ();
	}

}

// Independent foreign declaration identity, without a body or native ABI data.
public class CfgCFunction : CfgNode {
	// Full stage parameter identity/contract; parameter_types remains a verified mirror.
	public GenericArray<CfgParameter> parameters { get; private set; }
	public CfgCleanupContract? owned_cleanup { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public CForeignMetadata metadata { get; private set; }
	public string external_symbol { get { return metadata.external_symbol; } }
	public SourceSpan name_span { get; private set; }
	public ForeignAbi abi { get; private set; }
	public SemanticType return_type { get; private set; }
	public GenericArray<SemanticType> parameter_types { get; private set; }
	public int ordinal { get; private set; }

	internal CfgCFunction (SourceSpan span, SourceSpan name_span, string name, CForeignMetadata metadata, ForeignAbi abi, SemanticType return_type, GenericArray<SemanticType> parameter_types, int ordinal, CfgCleanupContract? owned_cleanup = null, GenericArray<CfgParameter>? parameters = null) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.metadata = metadata.copy ();
		this.owned_cleanup = owned_cleanup;
		this.abi = abi;
		this.return_type = return_type;
		this.parameter_types = parameter_types;
		this.parameters = parameters ?? new GenericArray<CfgParameter> ();
		if (parameters == null) {
			for (int p = 0; p < parameter_types.length; p++) {
				this.parameters.add (new CfgParameter (span, name_span, "", parameter_types[p], p));
			}
		}
		this.ordinal = ordinal;
	}

}

public class CfgFunction : CfgNode {
	public NativeDeclarationSignature? native_declaration { get; internal set; }
	private NativeDeclarationSignature? native_declaration_origin;
	internal void bind_native_declaration(NativeDeclarationSignature declaration) throws CfgError {
		if (native_declaration_origin != null) {
			throw new CfgError.INVALID_CORE ("native declaration cannot be rebound");
		}
		native_declaration = native_declaration_origin = declaration;
	}

	internal bool native_declaration_valid() {
		return native_declaration == native_declaration_origin;
	}

	internal bool declaration_only() {
		return native_declaration != null && native_declaration_valid () && name_span.file.native_interface &&
		       blocks.length == 1 && blocks[0] == entry && entry.instructions.length == 0 &&
		       entry.terminator is CfgNativeDeclaration && locals.length == 0 && field_places.length == 0 && object_storage.length == 0;
	}

	private GenericArray<CfgEvaluateInstruction> vector_effects = new GenericArray<CfgEvaluateInstruction> ();
	private GenericArray<CfgBlock> vector_blocks = new GenericArray<CfgBlock> ();
	private GenericArray<int> vector_positions = new GenericArray<int> ();
	public void retain_vector_memory(CfgEvaluateInstruction operation, CfgBlock block) {
		vector_effects.add (operation);
		vector_blocks.add (block);
		vector_positions.add ((int) block.instructions.length - 1);
	}

	internal void verify_vector_memory() throws CfgError {
		for (int i = 0; i < vector_effects.length; i++) {
			var block = vector_blocks[i];
			int position = vector_positions[i];
			if (!blocks.find (block) || position < 0 || position >= block.instructions.length || block.instructions[position] != vector_effects[i]) {
				throw new CfgError.INVALID_CFG ("vector memory lost its ordered bounds/effect position");
			}
			int count = 0;
			foreach (var candidate in blocks) {
				foreach (var operation in candidate.instructions) {
					if (operation == vector_effects[i]) {
						count++;
					}
				}
			}
			if (count != 1) {
				throw new CfgError.INVALID_CFG ("vector memory effect must occur once");
			}
		}
	}

	public uint floating_policy { get; internal set; default = 0; }
	private uint floating_policy_origin;
	private bool floating_policy_bound;
	public void bind_floating_policy(uint permissions) {
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
	public GenericArray<CfgExceptionHandler> handlers { get; private set; default = new GenericArray<CfgExceptionHandler> (); }
	public bool heap_result { get; internal set; default = false; }
	public ClassType? throws_type { get; internal set; }
	public ClassDispatchKind dispatch_kind { get; internal set; default = ClassDispatchKind.DIRECT; }
	public int virtual_slot { get; internal set; default = -1; }
	public GenericArray<CfgEnumSlot> enum_slots { get; private set; default = new GenericArray<CfgEnumSlot> (); }
	public GenericArray<StructBoundaryGroup> struct_parameters { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public StructValueShape? struct_result { get; internal set; }
	public CfgResultObjectStorage? result_storage { get; internal set; }
	public CallableKind kind { get { return (this is CfgPropertyGetter) ? CallableKind.PROPERTY_GETTER : (this is CfgPropertySetter) ? CallableKind.PROPERTY_SETTER : (this is CfgConstructor) ? CallableKind.CONSTRUCTOR : (this is CfgDestructor) ? CallableKind.DESTRUCTOR : (this is CfgMethod) ? CallableKind.METHOD : CallableKind.FUNCTION; } }
	public CfgReceiver? implicit_receiver { get { return (this is CfgPropertyAccessor) ? ((CfgPropertyAccessor) this).receiver : (this is CfgMethod) ? ((CfgMethod) this).receiver : (this is CfgLifecycle) ? ((CfgLifecycle) this).receiver : null; } }
	public GenericArray<CfgObjectStorage> object_storage { get; private set; default = new GenericArray<CfgObjectStorage> (); }
	public CfgCleanupContract? owned_cleanup { get; private set; }
	public ResultOwnershipContract result_contract { get { return this is CfgPropertyGetter && ((CfgPropertyGetter) this).property_member.is_borrowed ? ResultOwnershipContract.RECEIVER_BORROW : (return_type is StringType) ? ((this is CfgPropertyGetter) ? ResultOwnershipContract.RECEIVER_TEXT : ResultOwnershipContract.STATIC_TEXT) : owned_cleanup == null ? ResultOwnershipContract.UNMANAGED : ResultOwnershipContract.OWNED_TRANSFER; } }
	public string name { get { return identifier; } }
	private string identifier;
	public SourceSpan name_span { get; private set; }
	public SemanticType return_type { get; private set; }
	public int ordinal { get; private set; }
	public GenericArray<CfgParameter> parameters { get; private set; }
	public GenericArray<CfgFieldPlace> field_places { get; private set; }
	public GenericArray<CfgLocalPlace> locals { get; private set; }
	public GenericArray<CfgTemporaryPlace> temporaries { get; private set; }
	public GenericArray<CfgBlock> blocks { get; private set; }
	public CfgBlock entry { get; private set; }

	internal CfgFunction (SourceSpan span, SourceSpan name_span, string name, SemanticType return_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry, CfgCleanupContract? owned_cleanup = null) {
		base (span);
		this.owned_cleanup = owned_cleanup;
		this.name_span = name_span;
		this.identifier = name;
		this.return_type = return_type;
		this.ordinal = ordinal;
		this.parameters = parameters;
		this.field_places = new GenericArray<CfgFieldPlace> ();
		this.locals = locals;
		temporaries = new GenericArray<CfgTemporaryPlace> ();
		this.blocks = blocks;
		this.entry = entry;
	}

}

// Array containment defines declaration ownership, without parent cycles.
public class CfgParameter : CfgNode {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}

	public bool heap_object { get; internal set; default = false; }
	public PointerParameterContract pointer_contract { get; private set; }
	public string name { get { return identifier; } }
	private string identifier;
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }

	internal CfgParameter (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, PointerParameterContract pointer_contract = PointerParameterContract.UNMANAGED) {
		base (span);
		this.pointer_contract = pointer_contract;
		this.name_span = name_span;
		this.identifier = name;
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
	}

}

public abstract class CfgPlace : CfgNode {
	public SemanticType semantic_type { get; private set; }

	// Addressability is authoritative storage capability, not a layout hint.
	public bool is_promotable() {
		if (semantic_type is EnumType) {
			return false;
		}
		if (semantic_type is ArrayType || semantic_type is StructType) {
			return false;
		}
		var field = this as CfgFieldPlace;
		if (field != null) {
			if (semantic_type is SliceType) {
				return false;
			}
			var local = field.root_local ();
			return local != null && !local.address_taken;
		}
		return semantic_type.kind != TypeKind.STRUCT && (this is CfgTemporaryPlace || (this is CfgLocalPlace && !((CfgLocalPlace) this).address_taken));
	}

	protected CfgPlace (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}

}

// CFG-owned storage authority; neither a Core identity nor a value.
public class CfgLocalPlace : CfgPlace {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}

	public GenericArray<StructLeafPath> record_order { get; private set; default = new GenericArray<StructLeafPath> (); }
	public Astra.Text.TextLoanExtent? text_extent { get; internal set; }
	public bool text_loan { get; internal set; default = false; }
	public CfgBufferOwnerGroup? buffer_group { get; private set; }
	public StructBoundaryGroup? struct_parameter { get; internal set; }
	public CfgObjectStorage? object_storage { get; internal set; }
	public CfgParameter? incoming_parameter { get; private set; }
	public CfgCleanupContract? cleanup { get; private set; }
	public bool address_taken { get; private set; }
	public string name { get { return identifier; } }
	private string identifier;
	public SourceSpan name_span { get; private set; }
	public int ordinal { get; private set; }

	internal CfgLocalPlace (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, bool address_taken = false, CfgCleanupContract? cleanup = null, CfgParameter? incoming_parameter = null) {
		base (span, semantic_type);
		this.incoming_parameter = incoming_parameter;
		this.cleanup = cleanup;
		if (cleanup != null && cleanup.is_buffer) {
			this.buffer_group = new CfgBufferOwnerGroup (span, cleanup.buffer_shape);
		}
		this.address_taken = address_taken;
		this.name_span = name_span;
		this.identifier = name;
		this.ordinal = ordinal;
	}

}

// Function-owned normalization storage. No source name, LocalSymbol, or
// upstream Place identity; ordinal is per-function construction order.
public class CfgTemporaryPlace : CfgPlace {
	public int ordinal { get; private set; }

	internal CfgTemporaryPlace (SourceSpan span, SemanticType semantic_type, int ordinal) {
		base (span, semantic_type);
		this.ordinal = ordinal;
	}

}

public class CfgBlock : CfgNode {
	public GenericArray<Astra.Text.TextLoanIntent> text_exits { get; private set; default = new GenericArray<Astra.Text.TextLoanIntent> (); }
	public int ordinal { get; private set; }
	public GenericArray<CfgInstruction> instructions { get; private set; }
	private CfgTerminator? completed_terminator;
	public bool is_complete { get { return completed_terminator != null; } }
	public CfgTerminator terminator {
		get {
			assert (completed_terminator != null);
			return completed_terminator;
		}
	}

	// Completed blocks retain the original constructor and read-only API.
	internal CfgBlock (SourceSpan span, int ordinal, GenericArray<CfgInstruction> instructions, CfgTerminator terminator) {
		base (span);
		this.ordinal = ordinal;
		this.instructions = instructions;
		this.completed_terminator = terminator;
	}

	// Reserve identity for forward targets. Only the builder uses incomplete
	// blocks; verification rejects them before graph consumers can run.
	internal CfgBlock.reserve (SourceSpan span, int ordinal) {
		base (span);
		this.ordinal = ordinal;
		this.instructions = new GenericArray<CfgInstruction> ();
	}

	internal void complete(SourceSpan span, CfgTerminator terminator) throws CfgError {
		if (is_complete) {
			throw new CfgError.INVALID_CFG ("internal CFG construction error: block #%d already has a terminator", ordinal);
		}
		this.span = span;
		this.completed_terminator = terminator;
	}

}

// Consumes the immediately preceding owned C-call result exactly once.
public class CfgOwnershipRearmInstruction : CfgInstruction {
	public CfgLocalPlace? source { get; private set; }
	internal CfgOwnershipRearmInstruction.from_owner (SourceSpan span, CfgLocalPlace owner, CfgLocalPlace source, CfgCleanupContract cleanup) {
		base (span);
		this.owner = owner;
		this.source = source;
		this.cleanup = cleanup;
	}
	public CfgLocalPlace owner { get; private set; }
	public CfgValue? value { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }

	internal CfgOwnershipRearmInstruction (SourceSpan span, CfgLocalPlace owner, CfgValue value, CfgCleanupContract cleanup) {
		base (span);
		this.owner = owner;
		this.value = value;
		this.cleanup = cleanup;
	}

}

// Instructions execute in array order, then the separate terminator runs.
// Ordered, effectful, resultless; null skips the foreign call.
public class CfgOwnershipReleaseInstruction : CfgInstruction {
	public CfgLocalPlace owner { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }

	internal CfgOwnershipReleaseInstruction (SourceSpan span, CfgLocalPlace owner, CfgCleanupContract cleanup) {
		base (span);
		this.owner = owner;
		this.cleanup = cleanup;
	}

}

public class CfgCleanupInstruction : CfgInstruction {
	public CfgLocalPlace? record_owner { get; internal set; }
	public bool record_final { get; internal set; }
	public CfgValue value { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }

	internal CfgCleanupInstruction (SourceSpan span, CfgValue value, CfgCleanupContract cleanup) {
		base (span);
		this.value = value;
		this.cleanup = cleanup;
	}

}

public abstract class CfgInstruction : CfgNode {
	protected CfgInstruction (SourceSpan span) {
		base (span);
	}

}

// Calls are conservatively effectful, ordered instructions, never successors.
public class CfgCallInstruction : CfgInstruction {
	public bool readonly_required { get; internal set; }
	private bool original_readonly_required;
	internal void bind_readonly_context(bool required) {
		readonly_required = required;
		original_readonly_required = required;
	}

	internal bool readonly_context_valid() {
		return readonly_required == original_readonly_required;
	}

	public GenericArray<CfgStructBoundaryMove> record_moves { get; private set; default = new GenericArray<CfgStructBoundaryMove> (); }
	public CfgEvaluatedValue? exception_result { get; internal set; }
	public CfgEvaluatedValue? success_result { get; internal set; }
	private CfgEnumSlot? original_enum_result;
	private GenericArray<CfgValue> original_enum_arguments = new GenericArray<CfgValue> ();
	public CfgEnumSlot? enum_result { get; internal set; }
	public void bind_enum_result(CfgEnumSlot? slot) {
		enum_result = slot;
		original_enum_result = slot;
	}

	internal bool matches_enum_channels() {
		if (enum_result != original_enum_result || arguments.length != original_enum_arguments.length) {
			return false;
		}
		for (int a = 0; a < arguments.length; a++) {
			if ((arguments[a] is CfgEnumArgument || original_enum_arguments[a] is CfgEnumArgument) && arguments[a] != original_enum_arguments[a]) {
				return false;
			}
		}
		return true;
	}

	public CfgBufferResults? buffer_result { get; internal set; }
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public CfgStructCallResults? struct_result { get; internal set; }
	public CfgObjectStorage? candidate_storage { get; internal set; }
	public CfgResultObjectStorage? result_storage { get; internal set; }
	public CfgValue? receiver { get; private set; }
	private WeakRef callee;
	public CfgFunction? target { owned get { return (CfgFunction?) callee.get (); } }
	public GenericArray<CfgValue> arguments { get; private set; }
	public CfgCallResultValue? result { get; private set; }

	internal CfgCallInstruction (SourceSpan span, CfgFunction target, GenericArray<CfgValue> arguments, CfgCallResultValue? result, CfgValue? receiver = null) {
		base (span);
		this.callee = WeakRef (target);
		this.receiver = receiver;
		this.arguments = arguments;
		foreach (var argument in arguments) {
			original_enum_arguments.add (argument);
		}
		this.result = result;
	}

}

// Conservatively effectful C boundary; only the program owns the target.
public class CfgCCallInstruction : CfgInstruction {
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public CfgStructCallResults? struct_result { get; internal set; }
	private WeakRef callee;
	public CfgCFunction? target { owned get { return (CfgCFunction?) callee.get (); } }
	public GenericArray<CfgValue> arguments { get; private set; }
	public CfgCallResultValue? result { get; private set; }

	internal CfgCCallInstruction (SourceSpan span, CfgCFunction target, GenericArray<CfgValue> arguments, CfgCallResultValue? result) {
		base (span);
		this.callee = WeakRef (target);
		this.arguments = arguments;
		this.result = result;
	}

}

// Evaluate a potentially trapping tree at this exact instruction position,
// before a later call or expression region. Uses may cross blocks when
// the definition precedes every path to the use. No backlink or Place.
public class CfgEvaluateInstruction : CfgInstruction {
	public CfgValue value { get; private set; }
	public CfgEvaluatedValue result { get; private set; }

	internal CfgEvaluateInstruction (SourceSpan span, CfgValue value, CfgEvaluatedValue result) {
		base (span);
		this.value = value;
		this.result = result;
	}

}

// Operands are evaluated in order before this pure, whole-value primitive.
public class CfgVectorDotInstruction : CfgEvaluateInstruction {
	internal CfgVectorDotInstruction (SourceSpan span, VectorDotKind dot_kind, SemanticType source_type, SemanticType destination_type, CfgValue? accumulator, CfgValue first, CfgValue second) {
		base (span, new CfgVectorDotValue (span, dot_kind, source_type, destination_type, accumulator, first, second), new CfgEvaluatedValue (span, destination_type));
	}

}

public class CfgDspInstruction : CfgEvaluateInstruction {
	internal CfgDspInstruction (SourceSpan span, DspPrimitiveKind primitive_kind, SemanticType source_type, SemanticType destination_type, CfgValue first, CfgValue? second, IntegerType? destination_element = null) {
		base (span, new CfgDspValue (span, primitive_kind, source_type, destination_type, first, second, destination_element), new CfgEvaluatedValue (span, destination_type));
	}

}

// One ordered, potentially trapping scalar/vector operation after both
// operands have been evaluated. The count remains a scalar Astra value.
public class CfgIntegerShiftInstruction : CfgEvaluateInstruction {
	internal CfgIntegerShiftInstruction (SourceSpan span, SemanticType semantic_type, IntegerShiftKind shift_kind, CfgValue operand, CfgValue count) {
		base (span, new CfgIntegerShiftValue (span, semantic_type, shift_kind, operand, count), new CfgEvaluatedValue (span, semantic_type));
	}

}

// The result is the same scalar value, with proof of the exact destination
// range. Ordered execution traps before any later effect or conversion.
public class CfgNumericGuard : CfgEvaluateInstruction {
	public SemanticType destination_type { get; private set; }
	public NumericConversionPolicy policy { get; private set; }

	internal CfgNumericGuard (SourceSpan span, SemanticType destination_type, CfgValue operand, NumericConversionPolicy policy) {
		base (span, operand, new CfgEvaluatedValue (span, operand.semantic_type));
		this.destination_type = destination_type;
		this.policy = policy;
	}

}

public class CfgNumericConversionInstruction : CfgEvaluateInstruction {
	internal CfgNumericConversionInstruction (SourceSpan span, SemanticType source_type, SemanticType destination_type, NumericConversionKind conversion_kind, CfgValue operand, NumericConversionPolicy policy) {
		base (span, new CfgNumericConversionValue (span, source_type, destination_type, conversion_kind, operand, policy), new CfgEvaluatedValue (span, destination_type));
	}

}

// Evaluate the sole operand before the pure conversion; no Place or transfer.
public class CfgFloatConversionInstruction : CfgEvaluateInstruction {
	internal CfgFloatConversionInstruction (SourceSpan span, SemanticType source_type, SemanticType destination_type, FloatConversionKind conversion_kind, CfgValue operand) {
		base (span, new CfgFloatConversionValue (span, source_type, destination_type, conversion_kind, operand), new CfgEvaluatedValue (span, destination_type));
	}

}

public class CfgIntegerConversionInstruction : CfgEvaluateInstruction {
	internal CfgIntegerConversionInstruction (SourceSpan span, SemanticType source_type, SemanticType destination_type, CfgValue operand) {
		base (span, new CfgIntegerConversionValue (span, source_type, destination_type, operand), new CfgEvaluatedValue (span, destination_type));
	}

}

// Ordered pointer exposure; responsibility is validated without a transition.
public class CfgVectorSplatInstruction : CfgEvaluateInstruction {
	internal CfgVectorSplatInstruction (SourceSpan span, SemanticType type, CfgValue operand, int lane_count, SourceSpan lane_count_span) {
		base (span, new CfgVectorSplatValue (span, type, operand, lane_count, lane_count_span), new CfgEvaluatedValue (span, type));
	}

}

public class CfgVectorExtractInstruction : CfgEvaluateInstruction {
	internal CfgVectorExtractInstruction (SourceSpan span, SemanticType type, CfgValue vector, VectorLaneIndex index) {
		base (span, new CfgVectorExtractValue (span, type, vector, index), new CfgEvaluatedValue (span, type));
	}

}

public class CfgVectorInsertInstruction : CfgEvaluateInstruction {
	internal CfgVectorInsertInstruction (SourceSpan span, SemanticType type, CfgValue vector, VectorLaneIndex index, CfgValue replacement) {
		base (span, new CfgVectorInsertValue (span, type, vector, index, replacement), new CfgEvaluatedValue (span, type));
	}

}

public class CfgVectorShuffleInstruction : CfgEvaluateInstruction {
	internal CfgVectorShuffleInstruction (SourceSpan span, SemanticType type, CfgValue vector, VectorLaneSelectors selectors) {
		base (span, new CfgVectorShuffleValue (span, type, vector, selectors), new CfgEvaluatedValue (span, type));
	}

}

public class CfgVectorSelectInstruction : CfgEvaluateInstruction {
	internal CfgVectorSelectInstruction (SourceSpan span, SemanticType type, CfgValue mask, CfgValue true_value, CfgValue false_value) {
		base (span, new CfgVectorSelectValue (span, type, mask, true_value, false_value), new CfgEvaluatedValue (span, type));
	}

}

public class CfgVectorConstructInstruction : CfgEvaluateInstruction {
	internal CfgVectorConstructInstruction (SourceSpan span, SemanticType type, GenericArray<CfgValue> lanes) {
		base (span, new CfgVectorConstructValue (span, type, lanes), new CfgEvaluatedValue (span, type));
	}

}

public class CfgVectorReductionInstruction : CfgEvaluateInstruction {
	internal CfgVectorReductionInstruction (SourceSpan span, SemanticType type, VectorReductionOperator op, CfgValue operand) {
		base (span, new CfgVectorReductionValue (span, type, op, operand), new CfgEvaluatedValue (span, type));
	}

}

public class CfgOwnedBorrowInstruction : CfgInstruction {
	public CfgOwnedBorrowValue result { get; private set; }

	internal CfgOwnedBorrowInstruction (SourceSpan span, CfgOwnedBorrowValue result) {
		base (span);
		this.result = result;
	}

}

// Concrete Resource acquisition into memory. Capturing a named owner also
// consumes its responsibility; no field state or generic cleanup enters CFG.
public class CfgResourceCapture : CfgEvaluateInstruction {
	public CfgLocalPlace? source { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }
	internal CfgResourceCapture (SourceSpan span, CfgValue value, CfgLocalPlace? source, CfgCleanupContract cleanup) {
		base (span, value, new CfgEvaluatedValue (span, value.semantic_type));
		this.source = source;
		this.cleanup = cleanup;
	}

}
public class CfgRecordTake : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	public CfgFieldPlace field { get; private set; }
	public CfgLocalPlace destination { get; private set; }
	internal CfgRecordTake (SourceSpan span, CfgLocalPlace source, CfgFieldPlace field, CfgLocalPlace destination) {
		base (span);
		this.source = source;
		this.field = field;
		this.destination = destination;
	}

}
public class CfgRecordReplace : CfgInstruction {
	public CfgLocalPlace owner { get; private set; }
	public CfgFieldPlace field { get; private set; }
	public CfgLocalPlace? source { get; private set; }
	public CfgValue incoming { get; private set; }
	internal CfgRecordReplace (SourceSpan span, CfgLocalPlace owner, CfgFieldPlace field, CfgLocalPlace? source, CfgValue incoming) {
		base (span);
		this.owner = owner;
		this.field = field;
		this.source = source;
		this.incoming = incoming;
	}

}

public class CfgOwnershipTransferInstruction : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	public CfgLocalPlace destination { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }

	internal CfgOwnershipTransferInstruction (SourceSpan span, CfgLocalPlace source, CfgLocalPlace destination, CfgCleanupContract cleanup) {
		base (span);
		this.source = source;
		this.destination = destination;
		this.cleanup = cleanup;
	}

}

public class CfgAcquireParameter : CfgInitialize {
	internal CfgAcquireParameter (SourceSpan span, CfgLocalPlace owner, CfgParameter parameter) {
		base (span, owner, new CfgParameterValue (span, parameter), owner);
	}

}

// Compiler-only pending responsibility: capture is semantic MOVE, commit
// is the physical null definition. The callee is never retained here.
public class CfgPendingOwnedArgument : CfgEvaluatedValue {
	public bool fresh_staged { get; private set; }
	private WeakRef invocation = WeakRef (null);
	public CfgInstruction? consumer { owned get { return (CfgInstruction?) invocation.get (); } internal set { invocation.set (value); } }
	public bool exceptional_abort { get; internal set; }
	public CfgLocalPlace? source { get; private set; }
	public CfgParameter parameter { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }

	internal CfgPendingOwnedArgument (SourceSpan span, CfgParameter parameter, CfgCleanupContract cleanup, CfgLocalPlace? source, bool fresh_staged = false) {
		base (span, parameter.semantic_type);
		this.fresh_staged = fresh_staged;
		this.parameter = parameter;
		this.cleanup = cleanup;
		this.source = source;
	}

}

public class CfgOwnedArgumentCapture : CfgInstruction {
	public CfgPendingOwnedArgument transfer { get; private set; }

	internal CfgOwnedArgumentCapture (SourceSpan span, CfgPendingOwnedArgument transfer) {
		base (span);
		this.transfer = transfer;
	}

}

public class CfgOwnedCallTransferCommit : CfgInstruction {
	private WeakRef invocation;
	public CfgInstruction? call { owned get { return (CfgInstruction?) invocation.get (); } }
	public GenericArray<CfgPendingOwnedArgument> transfers { get; private set; }

	internal CfgOwnedCallTransferCommit (SourceSpan span, CfgInstruction call, GenericArray<CfgPendingOwnedArgument> transfers) {
		base (span);
		this.invocation = WeakRef (call);
		this.transfers = transfers;
	}

}

public class CfgOwnedReturnValue : CfgEvaluatedValue {
	public CfgValue? producer { get; private set; }
	public ObjectResultProvenance provenance { get; private set; }
	public CfgLocalPlace? source { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }

	internal CfgOwnedReturnValue (SourceSpan span, SemanticType semantic_type, CfgCleanupContract cleanup, CfgLocalPlace? source, CfgValue? producer = null, ObjectResultProvenance provenance = ObjectResultProvenance.NONE) {
		base (span, semantic_type);
		this.cleanup = cleanup;
		this.source = source;
		this.producer = producer;
		this.provenance = provenance;
	}

}

public class CfgOwnershipReturnInstruction : CfgInstruction {
	public CfgOwnedReturnValue result { get; private set; }

	internal CfgOwnershipReturnInstruction (SourceSpan span, CfgOwnedReturnValue result) {
		base (span);
		this.result = result;
	}

}

public class CfgOwnershipReturn : CfgReturn {
	internal CfgOwnershipReturn (SourceSpan span, CfgOwnedReturnValue value) {
		base (span, value);
	}

}

public class CfgInitialize : CfgInstruction {
	public CfgLocalPlace? acquisition { get; private set; }
	public CfgPlace target { get; private set; }
	public CfgValue value { get; private set; }

	internal CfgInitialize (SourceSpan span, CfgPlace target, CfgValue value, CfgLocalPlace? acquisition = null) {
		base (span);
		this.acquisition = acquisition;
		this.target = target;
		this.value = value;
	}

}

// Validate a captured memory Place without loading a value or writing storage.
public class CfgValidatePlace : CfgInstruction {
	public CfgPlace place { get; private set; }
	internal CfgValidatePlace (SourceSpan span, CfgPlace place) {
		base (span);
		this.place = place;
	}

}

public class CfgStore : CfgInstruction {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public CfgPlace target { get; private set; }
	public CfgValue value { get; private set; }

	internal CfgStore (SourceSpan span, CfgPlace target, CfgValue value, VolatileAccessContract? access = null) {
		base (span);
		volatile_access = access;
		volatile_enabled = access != null;
		this.target = target;
		this.value = value;
	}

}

public abstract class CfgTerminator : CfgNode {
	protected CfgTerminator (SourceSpan span) {
		base (span);
	}

	// Terminator semantics are the sole edge authority. Returned arrays
	// are traversal snapshots, never independently stored mutable edges.
	public abstract GenericArray<CfgBlock> successors();
}

public class CfgBranch : CfgTerminator {
	// Functions own blocks. Terminators describe topology without owning
	// successor blocks, including backedges and detached/expired targets.
	private WeakRef successor;
	public CfgBlock? target { owned get { return (CfgBlock?) successor.get (); } }

	internal CfgBranch (SourceSpan span, CfgBlock target) {
		base (span);
		this.successor = WeakRef (target);
	}

	public override GenericArray<CfgBlock> successors() {
		var result = new GenericArray<CfgBlock> ();
		var block = target;
		if (block != null) {
			result.add (block);
		}
		return result;
	}

}

public class CfgConditionalBranch : CfgTerminator {
	public CfgValue condition { get; private set; }
	private WeakRef true_successor;
	private WeakRef false_successor;
	public CfgBlock? true_target { owned get { return (CfgBlock?) true_successor.get (); } }
	public CfgBlock? false_target { owned get { return (CfgBlock?) false_successor.get (); } }

	internal CfgConditionalBranch (SourceSpan span, CfgValue condition, CfgBlock true_target, CfgBlock false_target) {
		base (span);
		this.condition = condition;
		this.true_successor = WeakRef (true_target);
		this.false_successor = WeakRef (false_target);
	}

	public override GenericArray<CfgBlock> successors() {
		var result = new GenericArray<CfgBlock> ();
		var yes = true_target;
		var no = false_target;
		if (yes != null) {
			result.add (yes);
		}
		if (no != null) {
			result.add (no);
		}
		return result;
	}

}

public class CfgReturn : CfgTerminator {
	public CfgValue? value { get; private set; }

	internal CfgReturn (SourceSpan span, CfgValue? value) {
		base (span);
		this.value = value;
	}

	public override GenericArray<CfgBlock> successors() {
		return new GenericArray<CfgBlock> ();
	}

}

// Reaching the structured body's end; legality belongs to flow checking.
// There is deliberately no value field and no conversion to CfgReturn.
public class CfgFunctionEnd : CfgTerminator {
	internal CfgFunctionEnd (SourceSpan span) {
		base (span);
	}

	public override GenericArray<CfgBlock> successors() {
		return new GenericArray<CfgBlock> ();
	}

}

public class CfgNativeDeclaration : CfgFunctionEnd {
	internal CfgNativeDeclaration (SourceSpan span) {
		base (span);
	}

}

public abstract class CfgValue : CfgNode {
	public Astra.Text.TextLoanIntent? text_loan_intent { get; internal set; }
	public SemanticType semantic_type { get; private set; }

	protected CfgValue (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}

}

// The defining call owns its result. Uses retain this value identity, which
// has no back reference to the instruction (and cannot form a cycle).
public class CfgCallResultValue : CfgValue {
	internal CfgCallResultValue (SourceSpan span, SemanticType semantic_type) {
		base (span, semantic_type);
	}

}

public class CfgEvaluatedValue : CfgValue {
	internal CfgEvaluatedValue (SourceSpan span, SemanticType semantic_type) {
		base (span, semantic_type);
	}

}

public class CfgNullPointerValue : CfgValue {
	internal CfgNullPointerValue (SourceSpan span, SemanticType semantic_type) {
		base (span, semantic_type);
	}

}

public class CfgBooleanValue : CfgValue {
	public BooleanLiteral literal { get; private set; }

	internal CfgBooleanValue (SourceSpan span, SemanticType semantic_type, BooleanLiteral literal) {
		base (span, semantic_type);
		this.literal = literal;
	}

}

public class CfgVectorDotValue : CfgValue {
	public VectorDotKind dot_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CfgValue? accumulator { get; private set; }
	public CfgValue first { get; private set; }
	public CfgValue second { get; private set; }

	internal CfgVectorDotValue (SourceSpan span, VectorDotKind dot_kind, SemanticType source_type, SemanticType destination_type, CfgValue? accumulator, CfgValue first, CfgValue second) {
		base (span, destination_type);
		this.dot_kind = dot_kind;
		this.source_type = source_type;
		this.accumulator = accumulator;
		this.first = first;
		this.second = second;
	}

}

public class CfgDspValue : CfgValue {
	public DspPrimitiveKind primitive_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public IntegerType? destination_element { get; private set; }
	public CfgValue first { get; private set; }
	public CfgValue? second { get; private set; }

	internal CfgDspValue (SourceSpan span, DspPrimitiveKind primitive_kind, SemanticType source_type, SemanticType destination_type, CfgValue first, CfgValue? second, IntegerType? destination_element = null) {
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
public class CfgIntegerShiftValue : CfgValue {
	public IntegerShiftKind shift_kind { get; private set; }
	public CfgValue operand { get; private set; }
	public CfgValue count { get; private set; }
	public uint element_bit_width { get { return IntegerShiftKind.element_type (semantic_type).bit_width; } }

	internal CfgIntegerShiftValue (SourceSpan span, SemanticType semantic_type, IntegerShiftKind shift_kind, CfgValue operand, CfgValue count) {
		base (span, semantic_type);
		this.shift_kind = shift_kind;
		this.operand = operand;
		this.count = count;
	}

}

public class CfgNumericConversionValue : CfgValue {
	public NumericConversionPolicy policy { get; private set; }
	public NumericConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CfgValue operand { get; private set; }

	internal CfgNumericConversionValue (SourceSpan span, SemanticType source_type, SemanticType destination_type, NumericConversionKind conversion_kind, CfgValue operand, NumericConversionPolicy policy) {
		base (span, destination_type);
		this.policy = policy;
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}

}

public class CfgFloatConversionValue : CfgValue {
	public FloatConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CfgValue operand { get; private set; }

	internal CfgFloatConversionValue (SourceSpan span, SemanticType source_type, SemanticType destination_type, FloatConversionKind conversion_kind, CfgValue operand) {
		base (span, destination_type);
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}

}

public class CfgIntegerConversionValue : CfgValue {
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CfgValue operand { get; private set; }

	internal CfgIntegerConversionValue (SourceSpan span, SemanticType source_type, SemanticType destination_type, CfgValue operand) {
		base (span, destination_type);
		this.source_type = source_type;
		this.operand = operand;
	}

}

public class CfgVectorSplatValue : CfgValue {
	public CfgValue operand { get; private set; }
	public int lane_count { get; private set; }
	public SourceSpan lane_count_span { get; private set; }

	internal CfgVectorSplatValue (SourceSpan span, SemanticType semantic_type, CfgValue operand, int lane_count, SourceSpan lane_count_span) {
		base (span, semantic_type);
		this.operand = operand;
		this.lane_count = lane_count;
		this.lane_count_span = lane_count_span;
	}

}

public class CfgVectorExtractValue : CfgValue {
	public CfgValue vector { get; private set; }
	public VectorLaneIndex index { get; private set; }

	internal CfgVectorExtractValue (SourceSpan span, SemanticType semantic_type, CfgValue vector, VectorLaneIndex index) {
		base (span, semantic_type);
		this.vector = vector;
		this.index = index.copy ();
	}

}

public class CfgVectorInsertValue : CfgValue {
	public CfgValue vector { get; private set; }
	public VectorLaneIndex index { get; private set; }
	public CfgValue replacement { get; private set; }

	internal CfgVectorInsertValue (SourceSpan span, SemanticType semantic_type, CfgValue vector, VectorLaneIndex index, CfgValue replacement) {
		base (span, semantic_type);
		this.vector = vector;
		this.index = index.copy ();
		this.replacement = replacement;
	}

}

public class CfgVectorShuffleValue : CfgValue {
	public CfgValue vector { get; private set; }
	public VectorLaneSelectors selectors { get; private set; }

	internal CfgVectorShuffleValue (SourceSpan span, SemanticType semantic_type, CfgValue vector, VectorLaneSelectors selectors) {
		base (span, semantic_type);
		this.vector = vector;
		this.selectors = selectors.copy ();
	}

}

public class CfgVectorMemoryValue : CfgValue {
	public VectorMemoryContract contract { get; private set; }
	public CfgValue view { get; private set; }
	public CfgValue offset { get; private set; }
	public CfgValue? stored { get; private set; }
	internal CfgVectorMemoryValue (SourceSpan span, VectorMemoryContract contract, CfgValue view, CfgValue offset, CfgValue? stored) {
		base (span, contract.vector_type);
		this.contract = contract.copy ();
		this.view = view;
		this.offset = offset;
		this.stored = stored;
	}

}

public class CfgVectorSelectValue : CfgValue {
	public CfgValue mask { get; private set; }
	public CfgValue true_value { get; private set; }
	public CfgValue false_value { get; private set; }

	internal CfgVectorSelectValue (SourceSpan span, SemanticType semantic_type, CfgValue mask, CfgValue true_value, CfgValue false_value) {
		base (span, semantic_type);
		this.mask = mask;
		this.true_value = true_value;
		this.false_value = false_value;
	}

}

public class CfgVectorConstructValue : CfgValue {
	public GenericArray<CfgValue> lanes { get; private set; }

	internal CfgVectorConstructValue (SourceSpan span, SemanticType semantic_type, GenericArray<CfgValue> lanes) {
		base (span, semantic_type);
		this.lanes = lanes;
	}

}

public class CfgVectorReductionValue : CfgValue {
	public VectorReductionOperator operator_kind { get; private set; }
	public CfgValue operand { get; private set; }

	internal CfgVectorReductionValue (SourceSpan span, SemanticType semantic_type, VectorReductionOperator operator_kind, CfgValue operand) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}

}

public class CfgFloatValue : CfgValue {
	public BinaryFloatValue value { get; private set; }

	internal CfgFloatValue (SourceSpan span, SemanticType semantic_type, BinaryFloatValue value) {
		base (span, semantic_type);
		this.value = value;
	}

}

public class CfgIntegerValue : CfgValue {
	public AstraIntegerValue value { get; private set; }

	internal CfgIntegerValue (SourceSpan span, SemanticType semantic_type, AstraIntValue value) {
		base (span, semantic_type);
		this.value = value.in_type (semantic_type as IntegerType);
	}

	internal CfgIntegerValue.typed (SourceSpan span, SemanticType semantic_type, AstraIntegerValue value) {
		base (span, semantic_type);
		this.value = value;
	}
}

public class CfgParameterValue : CfgValue {
	public CfgParameter parameter { get; private set; }

	internal CfgParameterValue (SourceSpan span, CfgParameter parameter) {
		base (span, parameter.semantic_type);
		this.parameter = parameter;
	}

}

public class CfgOwnedBorrowValue : CfgValue {
	public CfgLocalPlace source { get; private set; }
	public CfgParameter? parameter { get; private set; }

	internal CfgOwnedBorrowValue (SourceSpan span, CfgLocalPlace source, CfgParameter? parameter) {
		base (span, ContextBytesType.borrowed_type (CallbackType.borrowed_type (source.semantic_type, parameter == null ? null : parameter.semantic_type), parameter == null ? null : parameter.semantic_type));
		this.source = source;
		this.parameter = parameter;
	}

}

public class CfgLoadValue : CfgValue {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public CfgPlace source { get; private set; }

	internal CfgLoadValue (SourceSpan span, CfgPlace source, VolatileAccessContract? access = null) {
		base (span, source.semantic_type);
		volatile_access = access;
		volatile_enabled = access != null;
		this.source = source;
	}

}

public class CfgPrefixValue : CfgValue {
	public PrefixOperator operator_kind { get; private set; }
	public CfgValue operand { get; private set; }

	internal CfgPrefixValue (SourceSpan span, SemanticType semantic_type, PrefixOperator operator_kind, CfgValue operand) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}

}

public class CfgBinaryValue : CfgValue {
	public BinaryOperator operator_kind { get; private set; }
	public CfgValue left { get; private set; }
	public CfgValue right { get; private set; }

	internal CfgBinaryValue (SourceSpan span, SemanticType semantic_type, BinaryOperator operator_kind, CfgValue left, CfgValue right) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.left = left;
		this.right = right;
	}

}
}

namespace Astra.Cfg {
public class CfgFunctionAddress : CfgValue {
	private WeakRef callee;
	public CfgFunction? target { owned get { return (CfgFunction?) callee.get (); } }
	internal CfgFunctionAddress (SourceSpan span, FunctionValueType type, CfgFunction target) {
		base (span, type);
		callee = WeakRef (target);
	}

}
public interface CfgInvocation : Object {
	public abstract CfgCleanupContract? result_cleanup();
}

public class CfgFunctionValueCall : CfgValue, CfgInvocation {
	public CfgCleanupContract? owned_cleanup { get; private set; }
	public CfgCleanupContract? result_cleanup() {
		return owned_cleanup;
	}

	public GenericArray<CfgStructBoundaryMove> record_moves { get; private set; default = new GenericArray<CfgStructBoundaryMove> (); }
	// Call-owned channel declarations; these are never function inputs or bodies.
	public GenericArray<CfgParameter> channel_parameters { get; private set; default = new GenericArray<CfgParameter> (); }
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public CfgValue callee { get; private set; }
	public GenericArray<CfgValue> arguments { get; private set; }
	internal CfgFunctionValueCall (SourceSpan span, FunctionValueType type, CfgValue callee, GenericArray<CfgValue> arguments, CfgCleanupContract? owned_cleanup = null) {
		base (span, type.result_type);
		this.callee = callee;
		this.arguments = arguments;
		this.owned_cleanup = owned_cleanup;
	}

}
}
