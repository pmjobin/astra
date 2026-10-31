// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;

namespace Astra.Ssa {
public errordomain SsaError {
	INVALID_CFG,
	INVALID_SSA
}

public abstract class SsaNode : Object {
	public SourceSpan span { get; private set; }

	protected SsaNode (SourceSpan span) {
		this.span = span;
	}
}

// Attached foreign boundary only. The program owns the native target;
// this weak reference never creates a function/body ownership cycle.
public class SsaCExport : SsaNode {
	private WeakRef native_target;
	public SsaFunction? target { owned get { return (SsaFunction?) native_target.get (); } }
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

	internal SsaCExport (SourceSpan span, SourceSpan name_span, SsaFunction target, string external_symbol, ForeignAbi abi, int ordinal, CRecordAbi record_abi = CRecordAbi.NONE, CBoolAbi bool_abi = CBoolAbi.NONE) {
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
public class SsaCleanupContract : Object {
	public BufferValueShape? buffer_shape { get; private set; }
	public SliceType? buffer_type { get { return buffer_shape == null ? null : buffer_shape.slice_type; } }
	public bool is_buffer { get { return buffer_shape != null; } }
	internal SsaCleanupContract.for_buffer (BufferValueShape shape, SourceSpan span, int ordinal) {
		this.buffer_shape = shape;
		this.identifier = "";
		this.symbol_span = span;
		this.ordinal = ordinal;
	}
	public ClosureHandleType? closure_type { get; internal set; }
	private WeakRef closure_environment_identity;
	public SsaClass? closure_environment { owned get { return (SsaClass?) closure_environment_identity.get (); } internal set { closure_environment_identity = WeakRef (value); } }
	public SharedHandleType? shared_type { get; internal set; }
	private WeakRef shared_payload_identity;
	public SsaClass? shared_payload { owned get { return (SsaClass?) shared_payload_identity.get (); } internal set { shared_payload_identity = WeakRef (value); } }
	private WeakRef class_identity;
	public bool is_heap_object { get; private set; default = false; }
	public bool is_object { get; private set; default = false; }
	public SsaClass? object_class { owned get { return (SsaClass?) class_identity.get (); } }
	public SsaDestructor? destructor { owned get { return object_class == null ? null : object_class.destructor; } }

	internal SsaCleanupContract.for_object (SsaClass object_class, int ordinal, bool heap = false) {
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

	internal SsaCleanupContract (string external_symbol, SourceSpan symbol_span, int ordinal) {
		this.identifier = external_symbol;
		this.symbol_span = symbol_span;
		this.ordinal = ordinal;
	}
}

public class SsaProgram : SsaNode {
	public GenericArray<ClassTypeArgument> class_type_arguments { get; private set; default = new GenericArray<ClassTypeArgument> (); }
	public GenericArray<EnumDefinition> enums { get; private set; default = new GenericArray<EnumDefinition> (); }
	public GenericArray<Astra.Text.TextBytes> text_literals { get; private set; default = new GenericArray<Astra.Text.TextBytes> (); }
	public GenericArray<SsaClass> classes { get; private set; default = new GenericArray<SsaClass> (); }

	public GenericArray<SsaNativeInstance> native_instances() {
		var result = new GenericArray<SsaNativeInstance> ();
		foreach (var instance in structs) {
			result.add (instance);
		}
		foreach (var instance in classes) {
			result.add (instance);
		}
		return result;
	}

	public GenericArray<SsaHandle> handles { get; private set; }
	public GenericArray<SsaCleanupContract> cleanups { get; private set; }
	public GenericArray<SsaStruct> structs { get; private set; }
	public GenericArray<SsaFunction> functions { get; private set; }
	public GenericArray<SsaCFunction> c_functions { get; private set; }
	public GenericArray<SsaCExport> c_exports { get; private set; }

	internal SsaProgram (SourceSpan span, GenericArray<SsaFunction> functions, GenericArray<SsaCFunction>? c_functions = null, GenericArray<SsaCExport>? c_exports = null, GenericArray<SsaStruct>? structs = null, GenericArray<SsaCleanupContract>? cleanups = null, GenericArray<SsaHandle>? handles = null) {
		base (span);
		this.handles = handles ?? new GenericArray<SsaHandle> ();
		this.cleanups = cleanups ?? new GenericArray<SsaCleanupContract> ();
		this.functions = functions;
		this.c_functions = c_functions ?? new GenericArray<SsaCFunction> ();
		this.c_exports = c_exports ?? new GenericArray<SsaCExport> ();
		this.structs = structs ?? new GenericArray<SsaStruct> ();
	}
}

// Independent foreign declaration identity, without a body or native ABI data.
public class SsaCFunction : SsaNode {
	// Full stage parameter identity/contract; parameter_types remains a verified mirror.
	public GenericArray<SsaFunctionParameter> parameters { get; private set; }
	public SsaCleanupContract? owned_cleanup { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public CForeignMetadata metadata { get; private set; }
	public string external_symbol { get { return metadata.external_symbol; } }
	public SourceSpan name_span { get; private set; }
	public ForeignAbi abi { get; private set; }
	public SemanticType return_type { get; private set; }
	public GenericArray<SemanticType> parameter_types { get; private set; }
	public int ordinal { get; private set; }

	internal SsaCFunction (SourceSpan span, SourceSpan name_span, string name, CForeignMetadata metadata, ForeignAbi abi, SemanticType return_type, GenericArray<SemanticType> parameter_types, int ordinal, SsaCleanupContract? owned_cleanup = null, GenericArray<SsaFunctionParameter>? parameters = null) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.metadata = metadata.copy ();
		this.owned_cleanup = owned_cleanup;
		this.abi = abi;
		this.return_type = return_type;
		this.parameter_types = parameter_types;
		this.parameters = parameters ?? new GenericArray<SsaFunctionParameter> ();
		if (parameters == null) {
			for (int p = 0; p < parameter_types.length; p++) {
				this.parameters.add (new SsaFunctionParameter (span, name_span, "", parameter_types[p], p));
			}
		}
		this.ordinal = ordinal;
	}
}

public class SsaFunction : SsaNode {
	public NativeDeclarationSignature? native_declaration { get; internal set; }
	private NativeDeclarationSignature? native_declaration_origin;
	internal void bind_native_declaration(NativeDeclarationSignature declaration) throws SsaError {
		if (native_declaration_origin != null) {
			throw new SsaError.INVALID_CFG ("native declaration cannot be rebound");
		}
		native_declaration = native_declaration_origin = declaration;
	}
	internal bool native_declaration_valid() {
		return native_declaration == native_declaration_origin;
	}
	internal bool declaration_only() {
		return native_declaration != null && native_declaration_valid () && name_span.file.native_interface &&
		       blocks.length == 1 && blocks[0] == entry && entry.instructions.length == 0 && entry.parameters.length == 0 &&
		       entry.terminator is SsaNativeDeclaration && storage.length == 0 && object_storage.length == 0 && heap_owners.length == 0;
	}
	public FunctionEffectFacts? effect_facts { get; internal set; }
	public NativeOptimizerEvidence? checked_native_optimizer { get; private set; }
	internal void bind_native_optimizer(NativeOptimizerEvidence evidence) throws SsaError {
		if (!declaration_only () || evidence.symbol != native_declaration.identity.symbol || evidence.signature != native_declaration.identity.signature_shape || module_import_symbol != evidence.symbol || checked_native_optimizer != null) {
			throw new SsaError.INVALID_SSA ("native optimizer evidence requires its exact typed bound declaration once");
		}
		checked_native_optimizer = evidence;
	}
	internal FunctionEffectFacts? checked_native_effects() {
		if (checked_native_optimizer == null || !declaration_only () || module_import_symbol != checked_native_optimizer.symbol || native_declaration.identity.symbol != checked_native_optimizer.symbol || native_declaration.identity.signature_shape != checked_native_optimizer.signature) {
			return null;
		}
		return checked_native_optimizer.facts ();
	}
	public GenericArray<SsaObjectStorage> stack_objects { get; private set; default = new GenericArray<SsaObjectStorage> (); }
	public GenericArray<SsaSharedElisionPlan> shared_elisions { get; private set; default = new GenericArray<SsaSharedElisionPlan> (); }
	private GenericArray<SsaVectorMemoryInstruction> vector_effects = new GenericArray<SsaVectorMemoryInstruction> ();
	private GenericArray<SsaBlock> vector_blocks = new GenericArray<SsaBlock> ();
	private GenericArray<int> vector_positions = new GenericArray<int> ();
	public void retain_vector_memory(SsaVectorMemoryInstruction operation, SsaBlock block) {
		vector_effects.add (operation);
		vector_blocks.add (block);
		vector_positions.add ((int) block.instructions.length - 1);
	}
	internal void verify_vector_memory() throws SsaError {
		for (int i = 0; i < vector_effects.length; i++) {
			var block = vector_blocks[i];
			int position = vector_positions[i];
			if (!blocks.find (block) || position < 0 || position >= block.instructions.length || block.instructions[position] != vector_effects[i]) {
				throw new SsaError.INVALID_SSA ("vector memory lost its ordered bounds/effect position");
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
				throw new SsaError.INVALID_SSA ("vector memory effect must occur once");
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
	private GenericArray<SsaCleanupInstruction> required_cleanups = new GenericArray<SsaCleanupInstruction> ();
	private GenericArray<SsaBlock> cleanup_blocks = new GenericArray<SsaBlock> ();
	private GenericArray<int> cleanup_positions = new GenericArray<int> ();
	internal void retain_cleanup_effect(SsaCleanupInstruction instruction, SsaBlock block) {
		required_cleanups.add (instruction);
		cleanup_blocks.add (block);
		cleanup_positions.add ((int) block.instructions.length - 1);
	}
	internal void verify_cleanup_effects() throws SsaError {
		for (int i = 0; i < required_cleanups.length; i++) {
			var block = cleanup_blocks[i];
			int position = cleanup_positions[i];
			if (!blocks.find (block) || position < 0 || position >= block.instructions.length || block.instructions[position] != required_cleanups[i]) {
				throw new SsaError.INVALID_SSA ("required cleanup lost its exact original disposal position");
			}
			int occurrences = 0;
			foreach (var candidate in blocks) {
				foreach (var instruction in candidate.instructions) {
					if (instruction == required_cleanups[i]) {
						occurrences++;
					}
				}
			}
			if (occurrences != 1) {
				throw new SsaError.INVALID_SSA ("required cleanup must occur exactly once at its source disposal edge");
			}
		}
	}
	private GenericArray<SsaInstruction> volatile_effects = new GenericArray<SsaInstruction> ();
	private GenericArray<SsaBlock> volatile_blocks = new GenericArray<SsaBlock> ();
	private GenericArray<int> volatile_positions = new GenericArray<int> ();
	internal void retain_volatile_effect(SsaInstruction instruction, SsaBlock block) {
		volatile_effects.add (instruction);
		volatile_blocks.add (block);
		volatile_positions.add ((int) block.instructions.length - 1);
	}
	internal void verify_volatile_effects() throws SsaError {
		for (int i = 0; i < volatile_effects.length; i++) {
			var block = volatile_blocks[i];
			int position = volatile_positions[i];
			if (!blocks.find (block) || position < 0 || position >= block.instructions.length || block.instructions[position] != volatile_effects[i]) {
				throw new SsaError.INVALID_SSA ("volatile effects lost their exact source operation order");
			}
		}
		int expected = 0;
		foreach (var block in blocks) {
			foreach (var instruction in block.instructions) {
				var load = instruction as SsaLoadInstruction;
				var store = instruction as SsaStoreInstruction;
				if ((load != null && load.volatile_access != null) || (store != null && store.volatile_access != null)) {
					if (!volatile_effects.find (instruction)) {
						throw new SsaError.INVALID_SSA ("volatile effect has no source operation authority");
					}
					expected++;
				}
			}
		}
		if (expected != volatile_effects.length) {
			throw new SsaError.INVALID_SSA ("volatile effects lost a required source operation");
		}
	}
	private string? import_symbol;
	public string? module_import_symbol { get { return import_symbol; } }
	public void bind_module_import(string symbol) throws SsaError {
		if (module_import_symbol != null && module_import_symbol != symbol) {
			throw new SsaError.INVALID_SSA ("native import identity cannot be rebound");
		}
		import_symbol = symbol;
	}
	private GenericArray<SsaNonNullUse> nonnull_uses = new GenericArray<SsaNonNullUse> ();
	internal bool has_nonnull_uses { get { return nonnull_uses.length != 0; } }
	internal void retain_nonnull_use(SsaNonNullUse use) {
		nonnull_uses.add (use);
	}
	internal void verify_nonnull_uses() throws SsaError {
		foreach (var use in nonnull_uses) {
			int count = 0;
			foreach (var block in blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] == use) {
						count++;
						if (!use.at_original_write (block, i)) {
							throw new SsaError.INVALID_SSA ("nonnull proof obligation moved from its original write position");
						}
					}
				}
			}
			if (count != 1) {
				throw new SsaError.INVALID_SSA ("nonnull local write lost its exact retained proof obligation");
			}
		}
	}
	public bool nonnull_result { get; private set; default = false; }
	internal void mark_nonnull_result() {
		nonnull_result = true;
	}
	public bool utf8_factory { get; internal set; default = false; }
	public AsyncBodyContract? async_body { get; internal set; }
	private GenericArray<SsaTextLoanUse> text_uses = new GenericArray<SsaTextLoanUse> ();
	public void retain_text_use(SsaTextLoanUse use) {
		text_uses.add (use);
	}
	internal void verify_text_uses() throws SsaError {
		foreach (var use in text_uses) {
			bool present = false;
			foreach (var block in blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction == use) {
						present = true;
					}
				}
			}
			if (!present) {
				throw new SsaError.INVALID_SSA ("stored text use lost exact original loan association");
			}
		}
	}
	private GenericArray<SsaExceptionDisposition> exception_dispositions = new GenericArray<SsaExceptionDisposition> ();
	public void retain_exception_disposition(SsaNode effect, SsaValue value) {
		exception_dispositions.add (new SsaExceptionDisposition (effect, value));
	}
	internal void verify_exception_dispositions() throws SsaError {
		foreach (var binding in exception_dispositions) {
			bool present = false;
			foreach (var block in blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction == binding.effect) {
						present = true;
					}
				}
				if (block.terminator == binding.effect) {
					present = true;
				}
			}
			var cleanup = binding.effect as SsaCleanupInstruction;
			var returned = binding.effect as SsaExceptionReturn;
			if (!present || (cleanup != null ? cleanup.value != binding.value : returned != null ? returned.value != binding.value : true)) {
				throw new SsaError.INVALID_SSA ("exception disposition lost exact original active catch owner/edge");
			}
		}
	}
	public GenericArray<SsaExceptionHandler> handlers { get; private set; default = new GenericArray<SsaExceptionHandler> (); }
	public GenericArray<SsaFrameCatchOwner> frame_catch_owners { get; private set; default = new GenericArray<SsaFrameCatchOwner> (); }
	public GenericArray<SsaTaskOwner> task_owners { get; private set; default = new GenericArray<SsaTaskOwner> (); }
	public GenericArray<SsaHeapOwner> heap_owners { get; private set; default = new GenericArray<SsaHeapOwner> (); }
	public bool heap_result { get; internal set; default = false; }
	public GenericArray<SsaTextLoan> text_loans { get; private set; default = new GenericArray<SsaTextLoan> (); }
	public ClassType? throws_type { get; internal set; }
	public ClassDispatchKind dispatch_kind { get; internal set; default = ClassDispatchKind.DIRECT; }
	public int virtual_slot { get; internal set; default = -1; }
	internal GenericArray<SsaEnumProjectionContract> enum_projections = new GenericArray<SsaEnumProjectionContract> ();
	public GenericArray<SsaEnumSlot> enum_slots { get; private set; default = new GenericArray<SsaEnumSlot> (); }
	public GenericArray<SsaBufferStorage> buffer_storage { get; private set; default = new GenericArray<SsaBufferStorage> (); }
	public GenericArray<SsaBufferParameter> buffer_parameters { get; private set; default = new GenericArray<SsaBufferParameter> (); }
	public GenericArray<StructBoundaryGroup> struct_parameters { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public StructValueShape? struct_result { get; internal set; }
	public SsaResultObjectStorage? result_storage { get; internal set; }
	public CallableKind kind { get { return (this is SsaPropertyGetter) ? CallableKind.PROPERTY_GETTER : (this is SsaPropertySetter) ? CallableKind.PROPERTY_SETTER : (this is SsaConstructor) ? CallableKind.CONSTRUCTOR : (this is SsaDestructor) ? CallableKind.DESTRUCTOR : (this is SsaMethod) ? CallableKind.METHOD : CallableKind.FUNCTION; } }
	public SsaReceiver? implicit_receiver { get { return (this is SsaPropertyAccessor) ? ((SsaPropertyAccessor) this).receiver : (this is SsaMethod) ? ((SsaMethod) this).receiver : (this is SsaLifecycle) ? ((SsaLifecycle) this).receiver : null; } }
	public GenericArray<SsaObjectStorage> object_storage { get; private set; default = new GenericArray<SsaObjectStorage> (); }
	public SsaCleanupContract? owned_cleanup { get; private set; }
	public ResultOwnershipContract result_contract { get { return this is SsaPropertyGetter && ((SsaPropertyGetter) this).property_member.is_borrowed ? ResultOwnershipContract.RECEIVER_BORROW : (return_type is StringType) ? ((this is SsaPropertyGetter) ? ResultOwnershipContract.RECEIVER_TEXT : ResultOwnershipContract.STATIC_TEXT) : owned_cleanup == null ? ResultOwnershipContract.UNMANAGED : ResultOwnershipContract.OWNED_TRANSFER; } }
	public GenericArray<SsaAddressableLocal> storage { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	public SemanticType return_type { get; private set; }
	public int ordinal { get; private set; }
	public GenericArray<SsaFunctionParameter> parameters { get; private set; }
	public GenericArray<SsaBlock> blocks { get; private set; }
	public SsaBlock entry { get; private set; }

	internal SsaFunction (SourceSpan span, SourceSpan name_span, string name, SemanticType return_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry, SsaCleanupContract? owned_cleanup = null) {
		base (span);
		this.owned_cleanup = owned_cleanup;
		this.name_span = name_span;
		this.identifier = name;
		this.return_type = return_type;
		this.ordinal = ordinal;
		this.parameters = parameters;
		this.blocks = blocks;
		this.entry = entry;
		this.storage = new GenericArray<SsaAddressableLocal> ();
	}
}

public class SsaBlock : SsaNode {
	public GenericArray<Astra.Text.TextLoanIntent> text_exits { get; private set; default = new GenericArray<Astra.Text.TextLoanIntent> (); }
	public int ordinal { get; private set; }
	// Copied provenance only; downstream edges use SSA block identity.
	public int source_ordinal { get; private set; }
	public GenericArray<SsaBlockParameter> parameters { get; private set; }
	public GenericArray<SsaInstruction> instructions { get; private set; }
	private SsaTerminator? completed_terminator;
	public bool is_complete { get { return completed_terminator != null; } }
	public SsaTerminator terminator {
		get {
			assert (completed_terminator != null);
			return completed_terminator;
		}
	}

	// Reserve forward targets, then publish only after write-once completion.
	internal SsaBlock (SourceSpan span, int ordinal, int source_ordinal) {
		base (span);
		this.ordinal = ordinal;
		this.source_ordinal = source_ordinal;
		parameters = new GenericArray<SsaBlockParameter> ();
		instructions = new GenericArray<SsaInstruction> ();
	}

	internal void complete(SsaTerminator terminator) throws SsaError {
		if (is_complete) {
			throw new SsaError.INVALID_SSA ("internal SSA construction error: block #%d already has a terminator", ordinal);
		}
		completed_terminator = terminator;
	}
}

public abstract class SsaValue : SsaNode {
	public SemanticType semantic_type { get; private set; }

	protected SsaValue (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}
}

public abstract class SsaDefinition : SsaValue {
	public int ordinal { get; private set; }

	protected SsaDefinition (SourceSpan span, SemanticType semantic_type, int ordinal) {
		base (span, semantic_type);
		this.ordinal = ordinal;
	}
}

public class SsaFunctionParameter : SsaDefinition {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}
	public bool heap_object { get; internal set; default = false; }
	public PointerParameterContract pointer_contract { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }

	internal SsaFunctionParameter (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, PointerParameterContract pointer_contract = PointerParameterContract.UNMANAGED) {
		base (span, semantic_type, ordinal);
		this.pointer_contract = pointer_contract;
		this.name_span = name_span;
		this.identifier = name;
	}
}

public enum SsaPromotionOrigin {
	SOURCE_LOCAL,
	FIELD,
	TEMPORARY
}

public class SsaBlockParameter : SsaDefinition {
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	// Debug origin and deterministic ordering, never a storage identity.
	public SsaPromotionOrigin origin_kind { get; private set; }
	public int origin_ordinal { get; private set; }
	public int source_field_ordinal { get; private set; default = -1; }
	public int[] source_field_path;

	public int compare_field_path(SsaBlockParameter previous) {
		for (int i = 0; i < int.min (source_field_path.length, previous.source_field_path.length); i++) {
			if (source_field_path[i] != previous.source_field_path[i]) {
				return source_field_path[i] < previous.source_field_path[i] ? -1 : 1;
			}
		}
		return source_field_path.length - previous.source_field_path.length;
	}
	public int source_local_ordinal { get { return origin_kind == SsaPromotionOrigin.TEMPORARY ? -1 : origin_ordinal; } }

	internal SsaBlockParameter (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, int source_local_ordinal) {
		base (span, semantic_type, ordinal);
		this.name_span = name_span;
		this.identifier = name;
		this.origin_kind = SsaPromotionOrigin.SOURCE_LOCAL;
		this.origin_ordinal = source_local_ordinal;
	}

	// Scalar debug provenance only: no field symbol, struct type or Place.
	internal SsaBlockParameter.field (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, int local_ordinal, int field_ordinal, int[]? field_path = null) {
		base (span, semantic_type, ordinal);
		this.name_span = name_span;
		this.identifier = name;
		this.origin_kind = SsaPromotionOrigin.FIELD;
		this.origin_ordinal = local_ordinal;
		this.source_field_ordinal = field_ordinal;
		this.source_field_path = field_path == null ? new int[] {
			field_ordinal
		} : field_path;
	}

	internal SsaBlockParameter.temporary (SourceSpan span, SemanticType semantic_type, int ordinal, int temporary_ordinal) {
		base (span, semantic_type, ordinal);
		this.name_span = span;
		this.identifier = "";
		this.origin_kind = SsaPromotionOrigin.TEMPORARY;
		this.origin_ordinal = temporary_ordinal;
	}
}

public class SsaInstructionResult : SsaDefinition {
	internal SsaInstructionResult (SourceSpan span, SemanticType semantic_type, int ordinal) {
		base (span, semantic_type, ordinal);
	}
}

public class SsaFloatConstant : SsaValue {
	public BinaryFloatValue value { get; private set; }

	internal SsaFloatConstant (SourceSpan span, SemanticType semantic_type, BinaryFloatValue value) {
		base (span, semantic_type);
		this.value = value;
	}
}

public class SsaIntegerConstant : SsaValue {
	public AstraIntegerValue value { get; private set; }

	internal SsaIntegerConstant (SourceSpan span, SemanticType semantic_type, AstraIntValue value) {
		base (span, semantic_type);
		this.value = value.in_type (semantic_type as IntegerType);
	}

	internal SsaIntegerConstant.typed (SourceSpan span, SemanticType semantic_type, AstraIntegerValue value) {
		base (span, semantic_type);
		this.value = value;
	}
}

public class SsaNullPointerConstant : SsaValue {
	internal SsaNullPointerConstant (SourceSpan span, SemanticType semantic_type) {
		base (span, semantic_type);
	}
}

public class SsaBooleanConstant : SsaValue {
	public BooleanLiteral literal { get; private set; }

	internal SsaBooleanConstant (SourceSpan span, SemanticType semantic_type, BooleanLiteral literal) {
		base (span, semantic_type);
		this.literal = literal;
	}
}

// Ordered, effectful, resultless; null skips the foreign call.
public class SsaCleanupInstruction : SsaInstruction {
	private WeakRef replacement_identity;
	public SsaRecordReplace? record_replacement { owned get { return (SsaRecordReplace?) replacement_identity.get (); } internal set { replacement_identity = WeakRef (value); } }
	public SsaValue value { get; private set; }
	public SsaCleanupContract cleanup { get; private set; }

	internal SsaCleanupInstruction (SourceSpan span, SsaValue value, SsaCleanupContract cleanup) {
		base (span, null, -1);
		this.value = value;
		this.cleanup = cleanup;
	}
}

public abstract class SsaInstruction : SsaNode {
	public SsaInstructionResult? result { get; private set; }

	protected SsaInstruction (SourceSpan span, SemanticType? semantic_type, int ordinal) {
		base (span);
		result = semantic_type == null ? null : new SsaInstructionResult (span, semantic_type, ordinal);
	}
}

// Verifier-only obligation at an explicit qualified local write. Promotion
// can remove the slot, but cannot erase this ordered use of its input value.
public class SsaNonNullUse : SsaInstruction {
	private WeakRef original_block;
	private int original_position;
	public SsaValue value { get; private set; }
	public int source_ordinal { get; private set; }
	internal SsaNonNullUse (SourceSpan span, SsaValue value, int source_ordinal, SsaBlock block, int position) {
		base (span, null, -1);
		this.value = value;
		this.source_ordinal = source_ordinal;
		this.original_block = WeakRef (block);
		this.original_position = position;
	}
	internal bool at_original_write(SsaBlock block, int position) {
		return original_block.get () == block && original_position == position;
	}
}

// Array order is execution order. A void call has no definition; an unused
// non-void call still owns its result. Only the program owns the callee.
public enum SsaOwnedResultUse {
	NONE,
	DISCARD,
	ACQUIRE,
	REARM,
	FORWARD
}

// Transfer proof copied after CFG flow validation. These fields describe
// ordinary pointer definitions; they are never runtime values or ABI inputs.
public abstract class SsaOwnedTransfer : SsaNode {
	public SsaObjectStorage? source_storage { get; private set; }
	public SsaValue value { get; private set; }
	public SsaCleanupContract cleanup { get; private set; }
	public int source_ordinal { get; private set; }
	public SsaNullPointerConstant? source_after_commit { get; private set; }

	internal SsaOwnedTransfer (SourceSpan span, SsaValue value, SsaCleanupContract cleanup, int source_ordinal, SsaNullPointerConstant? source_after_commit, SsaObjectStorage? source_storage = null) {
		base (span);
		this.value = value;
		this.cleanup = cleanup;
		this.source_ordinal = source_ordinal;
		this.source_after_commit = source_after_commit;
		this.source_storage = source_storage;
	}
}
public class SsaOwnedArgument : SsaOwnedTransfer {
	public SsaFunctionParameter parameter { get; private set; }
	internal SsaOwnedArgument (SourceSpan span, SsaFunctionParameter parameter, SsaValue value, SsaCleanupContract cleanup, int source_ordinal, SsaNullPointerConstant? source_after_commit, SsaObjectStorage? source_storage = null) {
		base (span, value, cleanup, source_ordinal, source_after_commit, source_storage);
		this.parameter = parameter;
	}
}
public class SsaCallableOwnedArgument : SsaOwnedTransfer {
	public int ordinal { get; private set; }
	internal SsaCallableOwnedArgument (SourceSpan span, int ordinal, SsaValue value, SsaCleanupContract cleanup, int source_ordinal, SsaNullPointerConstant? source_after_commit, SsaObjectStorage? source_storage = null) {
		base (span, value, cleanup, source_ordinal, source_after_commit, source_storage);
		this.ordinal = ordinal;
	}
}

public class SsaOwnershipReturn : SsaReturn {
	public ObjectResultProvenance provenance { get; private set; }
	public SsaFunctionParameter? source_parameter { get; private set; }
	internal SsaOwnershipReturn (SourceSpan span, SsaValue value, ObjectResultProvenance provenance = ObjectResultProvenance.NONE, SsaFunctionParameter? source_parameter = null) {
		base (span, value);
		this.provenance = provenance;
		this.source_parameter = source_parameter;
	}
}

public class SsaCallInstruction : SsaInstruction {
	public bool readonly_required { get; internal set; }
	private bool original_readonly_required;
	internal void bind_readonly_context(bool required) {
		readonly_required = required;
		original_readonly_required = required;
	}
	internal bool readonly_context_valid() {
		return readonly_required == original_readonly_required;
	}
	private WeakRef exact_identity;
	public SsaFunction? exact_target { owned get { return (SsaFunction?) exact_identity.get (); } internal set { exact_identity = WeakRef (value); } }
	public GenericArray<SsaStructBoundaryMove> record_moves { get; private set; default = new GenericArray<SsaStructBoundaryMove> (); }
	private WeakRef owned_success_identity = WeakRef (null);
	public SsaCallSuccess? owned_success { owned get { return (SsaCallSuccess?) owned_success_identity.get (); } internal set { owned_success_identity.set (value); } }
	public GenericArray<SsaOwnedArgumentReservation> reservations { get; private set; default = new GenericArray<SsaOwnedArgumentReservation> (); }
	public SsaInstructionResult? exception_result { get; internal set; }
	private SsaEnumSlot? original_enum_result;
	private GenericArray<SsaValue> original_enum_arguments = new GenericArray<SsaValue> ();
	public SsaEnumSlot? enum_result { get; internal set; }
	public void bind_enum_result(SsaEnumSlot? slot) {
		enum_result = slot;
		original_enum_result = slot;
	}
	internal bool matches_enum_channels() {
		if (enum_result != original_enum_result || arguments.length != original_enum_arguments.length) {
			return false;
		}
		for (int a = 0; a < arguments.length; a++) {
			if ((arguments[a] is SsaEnumArgument || original_enum_arguments[a] is SsaEnumArgument) && arguments[a] != original_enum_arguments[a]) {
				return false;
			}
		}
		return true;
	}
	public SsaBufferPair? buffer_result { get; internal set; }
	public GenericArray<SsaBufferArgument> buffer_arguments { get; private set; default = new GenericArray<SsaBufferArgument> (); }
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public SsaStructCallResults? struct_result { get; internal set; }
	public SsaObjectStorage? candidate_storage { get; internal set; }
	public SsaResultObjectStorage? result_storage { get; internal set; }
	public SsaValue? receiver { get; private set; }
	public SsaOwnedResultUse owned_result_use { get; internal set; default = SsaOwnedResultUse.NONE; }
	public GenericArray<SsaOwnedArgument> owned_arguments { get; private set; default = new GenericArray<SsaOwnedArgument> (); }
	private WeakRef callee;
	public SsaFunction? target { owned get { return (SsaFunction?) callee.get (); } }
	public GenericArray<SsaValue> arguments { get; private set; }

	internal SsaCallInstruction (SourceSpan span, SemanticType? semantic_type, int ordinal, SsaFunction target, GenericArray<SsaValue> arguments, SsaValue? receiver = null) {
		base (span, semantic_type, ordinal);
		this.callee = WeakRef (target);
		this.receiver = receiver;
		this.arguments = arguments;
		foreach (var argument in arguments) {
			original_enum_arguments.add (argument);
		}
	}
}

// Conservatively effectful C boundary; only the program owns the target.
public class SsaCCallInstruction : SsaInstruction {
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public SsaStructCallResults? struct_result { get; internal set; }
	private WeakRef callee;
	public SsaCFunction? target { owned get { return (SsaCFunction?) callee.get (); } }
	public GenericArray<SsaValue> arguments { get; private set; }

	internal SsaCCallInstruction (SourceSpan span, SemanticType? semantic_type, int ordinal, SsaCFunction target, GenericArray<SsaValue> arguments) {
		base (span, semantic_type, ordinal);
		this.callee = WeakRef (target);
		this.arguments = arguments;
	}
}

public class SsaVectorDotInstruction : SsaInstruction {
	public VectorDotKind dot_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return result.semantic_type; } }
	public SsaValue? accumulator { get; private set; }
	public SsaValue first { get; private set; }
	public SsaValue second { get; private set; }

	internal SsaVectorDotInstruction (SourceSpan span, VectorDotKind dot_kind, SemanticType source_type, SemanticType destination_type, int ordinal, SsaValue? accumulator, SsaValue first, SsaValue second) {
		base (span, destination_type, ordinal);
		this.dot_kind = dot_kind;
		this.source_type = source_type;
		this.accumulator = accumulator;
		this.first = first;
		this.second = second;
	}
}

public class SsaDspInstruction : SsaInstruction {
	public DspPrimitiveKind primitive_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return result.semantic_type; } }
	public IntegerType? destination_element { get; private set; }
	public SsaValue first { get; private set; }
	public SsaValue? second { get; private set; }

	internal SsaDspInstruction (SourceSpan span, DspPrimitiveKind primitive_kind, SemanticType source_type, SemanticType destination_type, int ordinal, SsaValue first, SsaValue? second, IntegerType? destination_element = null) {
		base (span, destination_type, ordinal);
		this.primitive_kind = primitive_kind;
		this.source_type = source_type;
		this.destination_element = destination_element;
		this.first = first;
		this.second = second;
	}
}

// Direction owns the invalid-count trap contract; width and count type
// derive from exact retained values, with no independently mutable copy.
public class SsaIntegerShiftInstruction : SsaInstruction {
	public IntegerShiftKind shift_kind { get; private set; }
	public SsaValue operand { get; private set; }
	public SsaValue count { get; private set; }
	public uint element_bit_width { get { return IntegerShiftKind.element_type (result.semantic_type).bit_width; } }

	internal SsaIntegerShiftInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, IntegerShiftKind shift_kind, SsaValue operand, SsaValue count) {
		base (span, semantic_type, ordinal);
		this.shift_kind = shift_kind;
		this.operand = operand;
		this.count = count;
	}
}

// A normal floating scalar definition whose producer proves truncation fits.
public class SsaNumericGuard : SsaInstruction {
	public SemanticType destination_type { get; private set; }
	public SsaValue operand { get; private set; }
	public NumericConversionPolicy policy { get; private set; }

	internal SsaNumericGuard (SourceSpan span, SemanticType destination_type, SsaValue operand, int ordinal, NumericConversionPolicy policy) {
		base (span, operand.semantic_type, ordinal);
		this.destination_type = destination_type;
		this.operand = operand;
		this.policy = policy;
	}
}

public class SsaNumericConversionInstruction : SsaInstruction {
	public NumericConversionPolicy policy { get; private set; }
	public NumericConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return result.semantic_type; } }
	public SsaValue operand { get; private set; }

	internal SsaNumericConversionInstruction (SourceSpan span, SemanticType source_type, SemanticType destination_type, NumericConversionKind conversion_kind, int ordinal, SsaValue operand, NumericConversionPolicy policy) {
		base (span, destination_type, ordinal);
		this.policy = policy;
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}
}

public class SsaFloatConversionInstruction : SsaInstruction {
	public FloatConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return result.semantic_type; } }
	public SsaValue operand { get; private set; }

	internal SsaFloatConversionInstruction (SourceSpan span, SemanticType source_type, SemanticType destination_type, FloatConversionKind conversion_kind, int ordinal, SsaValue operand) {
		base (span, destination_type, ordinal);
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}
}

public class SsaIntegerConversionInstruction : SsaInstruction {
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return result.semantic_type; } }
	public SsaValue operand { get; private set; }

	internal SsaIntegerConversionInstruction (SourceSpan span, SemanticType source_type, SemanticType destination_type, int ordinal, SsaValue operand) {
		base (span, destination_type, ordinal);
		this.source_type = source_type;
		this.operand = operand;
	}
}

public class SsaVectorSplatInstruction : SsaInstruction {
	public SsaValue operand { get; private set; }
	public int lane_count { get; private set; }
	public SourceSpan lane_count_span { get; private set; }

	internal SsaVectorSplatInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, SsaValue operand, int lane_count, SourceSpan lane_count_span) {
		base (span, semantic_type, ordinal);
		this.operand = operand;
		this.lane_count = lane_count;
		this.lane_count_span = lane_count_span;
	}
}

public class SsaVectorExtractInstruction : SsaInstruction {
	public SsaValue vector { get; private set; }
	public VectorLaneIndex index { get; private set; }

	internal SsaVectorExtractInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, SsaValue vector, VectorLaneIndex index) {
		base (span, semantic_type, ordinal);
		this.vector = vector;
		this.index = index.copy ();
	}
}

public class SsaVectorInsertInstruction : SsaInstruction {
	public SsaValue vector { get; private set; }
	public VectorLaneIndex index { get; private set; }
	public SsaValue replacement { get; private set; }

	internal SsaVectorInsertInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, SsaValue vector, VectorLaneIndex index, SsaValue replacement) {
		base (span, semantic_type, ordinal);
		this.vector = vector;
		this.index = index.copy ();
		this.replacement = replacement;
	}
}

public class SsaVectorShuffleInstruction : SsaInstruction {
	public SsaValue vector { get; private set; }
	public VectorLaneSelectors selectors { get; private set; }

	internal SsaVectorShuffleInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, SsaValue vector, VectorLaneSelectors selectors) {
		base (span, semantic_type, ordinal);
		this.vector = vector;
		this.selectors = selectors.copy ();
	}
}

public class SsaVectorMemoryInstruction : SsaInstruction {
	public VectorMemoryContract contract { get; private set; }
	public SsaValue view { get; private set; }
	public SsaValue offset { get; private set; }
	public SsaValue? stored { get; private set; }
	internal SsaVectorMemoryInstruction (SourceSpan span, VectorMemoryContract contract, SsaValue view, SsaValue offset, SsaValue? stored, int ordinal) {
		base (span, contract.vector_type, ordinal);
		this.contract = contract.copy ();
		this.view = view;
		this.offset = offset;
		this.stored = stored;
	}
}

public class SsaVectorSelectInstruction : SsaInstruction {
	public SsaValue mask { get; private set; }
	public SsaValue true_value { get; private set; }
	public SsaValue false_value { get; private set; }

	internal SsaVectorSelectInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, SsaValue mask, SsaValue true_value, SsaValue false_value) {
		base (span, semantic_type, ordinal);
		this.mask = mask;
		this.true_value = true_value;
		this.false_value = false_value;
	}
}

public class SsaVectorConstructInstruction : SsaInstruction {
	public GenericArray<SsaValue> lanes { get; private set; }

	internal SsaVectorConstructInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, GenericArray<SsaValue> lanes) {
		base (span, semantic_type, ordinal);
		this.lanes = lanes;
	}
}

public class SsaVectorReductionInstruction : SsaInstruction {
	public VectorReductionOperator operator_kind { get; private set; }
	public SsaValue operand { get; private set; }

	internal SsaVectorReductionInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, VectorReductionOperator operator_kind, SsaValue operand) {
		base (span, semantic_type, ordinal);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}
}

public class SsaPrefixInstruction : SsaInstruction {
	public PrefixOperator operator_kind { get; private set; }
	public SsaValue operand { get; private set; }

	internal SsaPrefixInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, PrefixOperator operator_kind, SsaValue operand) {
		base (span, semantic_type, ordinal);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}
}

public class SsaBinaryInstruction : SsaInstruction {
	public BinaryOperator operator_kind { get; private set; }
	public SsaValue left { get; private set; }
	public SsaValue right { get; private set; }

	internal SsaBinaryInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, BinaryOperator operator_kind, SsaValue left, SsaValue right) {
		base (span, semantic_type, ordinal);
		this.operator_kind = operator_kind;
		this.left = left;
		this.right = right;
	}
}

// Each edge is owned by one terminator. Functions own blocks; weak targets
// prevent graph cycles from becoming reference-counting cycles. A detached
// or expired target is invalid and is diagnosed before graph traversal.
public class SsaEdge : Object {
	private WeakRef successor;
	public SsaBlock? target { owned get { return (SsaBlock?) successor.get (); } }
	public GenericArray<SsaValue> arguments { get; private set; }

	internal SsaEdge (SsaBlock target, GenericArray<SsaValue> arguments) {
		this.successor = WeakRef (target);
		this.arguments = arguments;
	}
}

public abstract class SsaTerminator : SsaNode {
	protected SsaTerminator (SourceSpan span) {
		base (span);
	}

	// Fresh traversal snapshot, derived solely from terminator-owned edges.
	public GenericArray<SsaBlock> successors() {
		var result = new GenericArray<SsaBlock> ();
		if (this is SsaEnumDispatch) {
			var dispatch = (SsaEnumDispatch) this;
			foreach (var branch in dispatch.cases) {
				if (branch.edge.target != null) {
					result.add (branch.edge.target);
				}
			}
			if (dispatch.invalid_edge.target != null) {
				result.add (dispatch.invalid_edge.target);
			}
			return result;
		}
		var allocation = this as SsaBufferAllocationBranch;
		if (allocation != null) {
			if (allocation.success_edge.target != null) {
				result.add (allocation.success_edge.target);
			}
			if (allocation.failure_edge.target != null) {
				result.add (allocation.failure_edge.target);
			}
			return result;
		}
		var branch = this as SsaBranch;
		var conditional = this as SsaConditionalBranch;
		if (branch != null && branch.edge.target != null) {
			result.add (branch.edge.target);
		} else if (conditional != null) {
			if (conditional.true_edge.target != null) {
				result.add (conditional.true_edge.target);
			}
			if (conditional.false_edge.target != null) {
				result.add (conditional.false_edge.target);
			}
		}
		return result;
	}
}

public class SsaBranch : SsaTerminator {
	public SsaEdge edge { get; private set; }

	internal SsaBranch (SourceSpan span, SsaEdge edge) {
		base (span);
		this.edge = edge;
	}
}

public class SsaConditionalBranch : SsaTerminator {
	public SsaValue condition { get; private set; }
	public SsaEdge true_edge { get; private set; }
	public SsaEdge false_edge { get; private set; }

	internal SsaConditionalBranch (SourceSpan span, SsaValue condition, SsaEdge true_edge, SsaEdge false_edge) {
		base (span);
		this.condition = condition;
		this.true_edge = true_edge;
		this.false_edge = false_edge;
	}
}

public class SsaReturn : SsaTerminator {
	public SsaValue? value { get; private set; }

	internal SsaReturn (SourceSpan span, SsaValue? value) {
		base (span);
		this.value = value;
	}
}

public class SsaFunctionEnd : SsaTerminator {
	internal SsaFunctionEnd (SourceSpan span) {
		base (span);
	}
}

public class SsaNativeDeclaration : SsaFunctionEnd {
	internal SsaNativeDeclaration (SourceSpan span) {
		base (span);
	}
}
}

namespace Astra.Ssa {
public class SsaFunctionAddress : SsaValue {
	private WeakRef callee;
	public SsaFunction? target { owned get { return (SsaFunction?) callee.get (); } }
	internal SsaFunctionAddress (SourceSpan span, FunctionValueType type, SsaFunction target) {
		base (span, type);
		callee = WeakRef (target);
	}
}
public class SsaCallbackView : SsaValue {
	public SsaValue closure { get; internal set; }
	internal SsaCallbackView (SourceSpan span, CallbackType type, SsaValue source) {
		base (span, type);
		closure = source;
	}
}
public class SsaCallableBorrowArgument : Object {
	public int ordinal { get; private set; }
	public SsaValue value { get; private set; }
	public SsaHeapOwner? source_owner { get; private set; }
	internal SsaCallableBorrowArgument (int ordinal, SsaValue value, SsaHeapOwner? owner) {
		this.ordinal = ordinal;
		this.value = value;
		source_owner = owner;
	}
}
public interface SsaCallableInvocation : Object {
	public abstract SsaCleanupContract? result_cleanup();
	public abstract SsaValue? owned_result_value();
	public abstract GenericArray<SsaStructBoundaryMove> record_moves { get; }
	public abstract GenericArray<SsaValue> arguments { get; }
	public abstract GenericArray<SsaCallableBorrowArgument> borrowed_arguments { get; }
	public abstract GenericArray<SsaCallableOwnedArgument> owned_arguments { get; }
	public abstract GenericArray<SsaOwnedArgumentReservation> reservations { get; }
}
public class SsaFunctionValueCall : SsaInstruction, SsaCallableInvocation {
	public SsaStructCallResults? struct_result { get; internal set; }
	public SsaCleanupContract? owned_cleanup { get; private set; }
	public SsaCleanupContract? result_cleanup() {
		return owned_cleanup;
	}
	public SsaValue? owned_result_value() {
		return result;
	}
	private GenericArray<SsaStructBoundaryMove> record_transfers = new GenericArray<SsaStructBoundaryMove> ();
	public GenericArray<SsaStructBoundaryMove> record_moves { get { return record_transfers; } }
	private GenericArray<SsaCallableOwnedArgument> argument_transfers = new GenericArray<SsaCallableOwnedArgument> ();
	public GenericArray<SsaCallableOwnedArgument> owned_arguments { get { return argument_transfers; } }
	private GenericArray<SsaOwnedArgumentReservation> argument_reservations = new GenericArray<SsaOwnedArgumentReservation> ();
	public GenericArray<SsaOwnedArgumentReservation> reservations { get { return argument_reservations; } }
	private GenericArray<SsaCallableBorrowArgument> argument_loans = new GenericArray<SsaCallableBorrowArgument> ();
	public GenericArray<SsaCallableBorrowArgument> borrowed_arguments { get { return argument_loans; } }
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public SsaValue callee { get; private set; }
	private GenericArray<SsaValue> call_arguments;
	public GenericArray<SsaValue> arguments { get { return call_arguments; } }
	internal SsaFunctionValueCall (SourceSpan span, FunctionValueType type, SsaValue callee, GenericArray<SsaValue> arguments, int ordinal, SsaCleanupContract? owned_cleanup = null) {
		base (span, type.result_type.kind == TypeKind.VOID || type.result_type.is_struct_storage () ? null : type.result_type, ordinal);
		this.callee = callee;
		this.call_arguments = arguments;
		this.owned_cleanup = owned_cleanup;
	}
}
}
