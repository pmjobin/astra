// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;

namespace Astra.CAbi {
public errordomain CAbiError {
	DUPLICATE_SYMBOL,
	INVALID_SSA,
	INVALID_NATIVE_ABI,
	INVALID_TYPE,
	INVALID_ABI,
	INCOMPATIBLE_CALL
}

// Versions Astra's supported C interop subset, not the host C ABI itself.
public enum CAbiProfile {
	SCALAR_V0,
	SCALAR_PTR_V1,
	SCALAR_FP_V2,
	TEXT_VIEW_V3,
	BUFFER_VIEW_V4,
	WIDE_INT_V5,
	POD_VALUE_V6,
	C_BOOL_V7;

	public string spelling() {
		switch (this) {
		case C_BOOL_V7:
			return "c-bool-v7";
		case SCALAR_V0:
			return "scalar-v0";
		case SCALAR_PTR_V1:
			return "scalar-ptr-v1";
		case SCALAR_FP_V2:
			return "scalar-fp-v2";
		case TEXT_VIEW_V3:
			return "text-view-v3";
		case BUFFER_VIEW_V4:
			return "buffer-view-v4";
		case WIDE_INT_V5:
			return "wide-int-v5";
		case POD_VALUE_V6:
			return "pod-value-v6";
		default:
			assert_not_reached ();
		}
	}
}

// Exact signed I32 plus explicitly admitted I64/U64 channels, qualified
// against C int32_t/int64_t/uint64_t. No implicit integer widening.
// CBOOL is a separate explicitly selected C99 copied boolean channel.
// Void is the absence of a result, never a scalar representation.
// PTR is the C void* channel, independent of NativeScalarType.PTR.
// F32/F64 are qualified C float/double, independent of native channels.
public enum CAbiScalarType {
	I32,
	PTR,
	F32,
	F64,
	I64,
	U64,
	CBOOL;

	public string spelling() {
		switch (this) {
		case I32:
			return "I32";
		case PTR:
			return "PTR";
		case F32:
			return "F32";
		case F64:
			return "F64";
		case I64:
			return "I64";
		case U64:
			return "U64";
		case CBOOL:
			return "CBOOL";
		default:
			assert_not_reached ();
		}
	}
}

public enum CAbiTextRole {
	IMPORT_PARAMETER
}
public enum CAbiTextComponentRole {
	DATA, BYTE_LENGTH
}
public enum CAbiBufferRole {
	IMPORT_PARAMETER
}
public enum CAbiBufferComponentRole {
	DATA, BYTE_LENGTH
}
public enum CAbiBufferAccess {
	READ_WRITE
}

// C-owned natural scalar record layout; copied names and physical extents,
// with no semantic graph or native-record-layout backlink.
public class CAbiRecordField : Object {
	private string identifier;
	private string scalar_identifier;
	public string name { get { return identifier; } }
	public string scalar_name { get { return scalar_identifier; } }
	public uint offset { get; private set; }
	public CAbiRecordField (string name, string scalar_name, uint offset) {
		this.identifier = name;
		this.scalar_identifier = scalar_name;
		this.offset = offset;
	}
	public uint bytes {
		get {
			switch (scalar_name) {
			case "i8":
			case "u8":
				return 1;
			case "i16":
			case "u16":
				return 2;
			case "int":
			case "u32":
			case "f32":
				return 4;
			case "i64":
			case "u64":
			case "isize":
			case "usize":
			case "f64":
				return 8;
			default:
				return 0;
			}
		}
	}
}

public class CAbiRecordPlan : Object {
	public Astra.Source.PodRepresentation? union_projection { get; internal set; }
	private string projection_origin;
	public string projection_identity { get { return projection_origin; } private set { projection_origin = value; } }
	internal bool projection_valid() {
		return union_projection == null ? projection_identity == "" : union_projection.is_union && union_projection.valid () && union_projection.identity == projection_identity;
	}
	public bool by_value { get; private set; }
	public bool memory { get { return by_value && size > 16; } }
	public int channel_count { get { return memory ? 1 : (int) fields.length; } }
	private string identifier;
	public string name { get { return identifier; } }
	public GenericArray<CAbiRecordField> fields { get; private set; }
	public uint size { get; private set; }
	public uint alignment { get; private set; }
	public CAbiRecordPlan (string name, GenericArray<CAbiRecordField> fields, uint size, uint alignment, bool by_value = false, Astra.Source.PodRepresentation? projection = null) {
		union_projection = projection == null ? null : projection.copy ();
		projection_identity = projection == null ? "" : projection.identity;
		this.by_value = by_value;
		this.identifier = name;
		this.fields = fields;
		this.size = size;
		this.alignment = alignment;
	}
}

public class CAbiCallbackPlan : Object {
	public int native_function_ordinal { get; private set; }
	private string target_identifier;
	public string target_name { get { return target_identifier; } }
	public CAbiCallbackPlan (int native_function_ordinal, string target_name) {
		this.native_function_ordinal = native_function_ordinal;
		this.target_identifier = target_name;
	}
}

public class CAbiBufferComponent : Object {
	public CAbiBufferComponentRole role { get; private set; }
	public CAbiScalarType scalar_type { get; private set; }
	public int physical_ordinal { get; private set; }
	public int logical_ordinal { get; private set; }
	public CAbiBufferComponent (CAbiBufferComponentRole role, CAbiScalarType scalar_type, int physical_ordinal, int logical_ordinal) {
		this.role = role;
		this.scalar_type = scalar_type;
		this.physical_ordinal = physical_ordinal;
		this.logical_ordinal = logical_ordinal;
	}
}

// Physical buffer authority is independent of native slice plans and holds
// no semantic graph. Only exact octets with alignment one are exposed.
public class CAbiBufferParameterPlan : Object {
	public CBufferAbi mode { get; private set; }
	public CAbiBufferRole role { get; private set; }
	public PointerParameterContract contract { get; private set; }
	public CAbiBufferAccess access { get; private set; }
	public uint element_bytes { get; private set; }
	public uint alignment { get; private set; }
	public GenericArray<CAbiBufferComponent> components { get; private set; }
	public CAbiBufferParameterPlan (CBufferAbi mode, CAbiBufferRole role, PointerParameterContract contract, GenericArray<CAbiBufferComponent> components, CAbiBufferAccess access = CAbiBufferAccess.READ_WRITE, uint element_bytes = 1, uint alignment = 1) {
		this.mode = mode;
		this.role = role;
		this.contract = contract;
		this.components = components;
		this.access = access;
		this.element_bytes = element_bytes;
		this.alignment = alignment;
	}
}

// A component is a channel of one logical text group, never a free-standing
// source argument. Positions allow independent verification of flattening.
public class CAbiTextComponent : Object {
	public CAbiTextComponentRole role { get; private set; }
	public CAbiScalarType scalar_type { get; private set; }
	public int physical_ordinal { get; private set; }
	public int logical_ordinal { get; private set; }
	public CAbiTextComponent (CAbiTextComponentRole role, CAbiScalarType scalar_type, int physical_ordinal, int logical_ordinal) {
		this.role = role;
		this.scalar_type = scalar_type;
		this.physical_ordinal = physical_ordinal;
		this.logical_ordinal = logical_ordinal;
	}
}

// Entirely CABI-owned. No NativeTextType, semantic type, callee or SSA graph.
public class CAbiTextParameterPlan : Object {
	public CTextAbi mode { get; private set; }
	public CAbiTextRole role { get; private set; }
	public PointerParameterContract contract { get; private set; }
	public GenericArray<CAbiTextComponent> components { get; private set; }
	public CAbiTextParameterPlan (CTextAbi mode, CAbiTextRole role, PointerParameterContract contract, GenericArray<CAbiTextComponent> components) {
		this.mode = mode;
		this.role = role;
		this.contract = contract;
		this.components = components;
	}
}

public class CAbiParameter : Object {
	public bool i32_pointer { get; internal set; }
	public CAbiRecordPlan? record { get; private set; }
	public CAbiBufferParameterPlan? buffer { get; private set; }
	public CAbiTextParameterPlan? text { get; private set; }
	public int physical_ordinal { get; private set; }
	public PointerParameterContract pointer_contract { get; private set; }
	public int ordinal { get; private set; }
	public CAbiScalarType scalar_type { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }

	internal CAbiParameter (SourceSpan span, SourceSpan name_span, string name, int ordinal, CAbiScalarType scalar_type, PointerParameterContract pointer_contract = PointerParameterContract.UNMANAGED, int physical_ordinal = -1) {
		this.physical_ordinal = physical_ordinal < 0 ? ordinal : physical_ordinal;
		this.pointer_contract = pointer_contract;
		this.span = span;
		this.name_span = name_span;
		this.identifier = name;
		this.ordinal = ordinal;
		this.scalar_type = scalar_type;
	}

	internal CAbiParameter.text_view (SourceSpan span, SourceSpan name_span, string name, int ordinal, int physical_ordinal, CAbiTextParameterPlan text, PointerParameterContract pointer_contract = PointerParameterContract.BORROWED_NOESCAPE) {
		this(span, name_span, name, ordinal, (CAbiScalarType) (-1), pointer_contract, physical_ordinal);
		this.text = text;
	}

	internal CAbiParameter.buffer_view (SourceSpan span, SourceSpan name_span, string name, int ordinal, int physical_ordinal, CAbiBufferParameterPlan buffer, PointerParameterContract pointer_contract = PointerParameterContract.BORROWED_NOESCAPE) {
		this(span, name_span, name, ordinal, (CAbiScalarType) (-1), pointer_contract, physical_ordinal);
		this.buffer = buffer;
	}

	internal CAbiParameter.record_value (SourceSpan span, SourceSpan name_span, string name, int ordinal, int physical_ordinal, CAbiRecordPlan record) {
		this(span, name_span, name, ordinal, (CAbiScalarType) (-1), PointerParameterContract.UNMANAGED, physical_ordinal);
		this.record = record;
	}

	internal CAbiParameter.record_view (SourceSpan span, SourceSpan name_span, string name, int ordinal, int physical_ordinal, CAbiRecordPlan record) {
		this(span, name_span, name, ordinal, CAbiScalarType.PTR, PointerParameterContract.BORROWED_NOESCAPE, physical_ordinal);
		this.record = record;
	}
	internal CAbiParameter.i32_view (SourceSpan span, SourceSpan name_span, string name, int ordinal, int physical_ordinal) {
		this(span, name_span, name, ordinal, CAbiScalarType.PTR, PointerParameterContract.BORROWED_NOESCAPE, physical_ordinal);
		i32_pointer = true;
	}
}

public class CAbiResult : Object {
	public CAbiRecordPlan? record { get; private set; }
	internal CAbiResult.record_value (CAbiRecordPlan record) {
		this.scalar_type = (CAbiScalarType) (-1);
		this.record = record;
	}
	public CAbiScalarType scalar_type { get; private set; }

	internal CAbiResult (CAbiScalarType scalar_type) {
		this.scalar_type = scalar_type;
	}
}

// Logical parameters retain their grouping. Scalar results remain direct;
// counted groups expand at their original position without hidden channels.
public class CAbiSignature : Object {
	public CBoolAbi bool_abi { get; private set; }
	public bool has_bool {
		get {
			if (result != null && result.record == null && result.scalar_type == CAbiScalarType.CBOOL) {
				return true;
			}
			foreach (var parameter in parameters) {
				if (parameter.text == null && parameter.buffer == null && parameter.record == null && parameter.scalar_type == CAbiScalarType.CBOOL) {
					return true;
				}
			}
			return false;
		}
	}
	public CAbiCallbackPlan? callback { get; private set; }
	public CAbiProfile profile { get; private set; }
	public GenericArray<CAbiParameter> parameters { get; private set; }
	public CAbiResult? result { get; private set; }
	public int physical_parameter_count {
		get {
			int count = (callback == null ? 0 : 1) + (result != null && result.record != null && result.record.memory ? 1 : 0);
			foreach (var p in parameters) {
				count += p.record != null && p.record.by_value ? p.record.channel_count : p.buffer != null ? (int) p.buffer.components.length : p.text == null ? 1 : (int) p.text.components.length;
			}
			return count;
		}
	}
	public bool has_text {
		get {
			foreach (var p in parameters) {
				if (p.text != null) {
					return true;
				}
			}
			return false;
		}
	}
	public bool has_buffer {
		get {
			foreach (var p in parameters) {
				if (p.buffer != null) {
					return true;
				}
			}
			return false;
		}
	}
	public bool has_record {
		get {
			if (result != null && result.record != null) {
				return true;
			}
			foreach (var p in parameters) {
				if (p.record != null) {
					return true;
				}
			}
			return false;
		}
	}
	public bool has_i32_pointer {
		get {
			foreach (var p in parameters) {
				if (p.i32_pointer) {
					return true;
				}
			}
			return false;
		}
	}
	public bool has_wide {
		get {
			if (result != null && (result.scalar_type == CAbiScalarType.I64 || result.scalar_type == CAbiScalarType.U64)) {
				return true;
			}
			foreach (var p in parameters) {
				if (p.text == null && p.buffer == null && (p.scalar_type == CAbiScalarType.I64 || p.scalar_type == CAbiScalarType.U64)) {
					return true;
				}
			}
			return false;
		}
	}

	internal CAbiSignature (CAbiProfile profile, GenericArray<CAbiParameter> parameters, CAbiResult? result, CAbiCallbackPlan? callback = null, CBoolAbi bool_abi = CBoolAbi.NONE) {
		this.bool_abi = bool_abi;
		this.callback = callback;
		this.profile = profile;
		this.parameters = parameters;
		this.result = result;
	}
}

// Imported physical identity with copied debug names and provenance.
// No body or call edges; only the program strongly owns its functions.
public class CAbiFunction : Object {
	public CAbiCleanupFunction? owned_cleanup { get; private set; }
	public int ordinal { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }
	public CAbiSignature signature { get; private set; }
	public CForeignMetadata metadata { get; private set; }
	public string external_symbol { get { return metadata.external_symbol; } }
	private WeakRef containing_program = WeakRef (null);
	public CAbiProgram? owner { owned get { return (CAbiProgram?) containing_program.get (); } }

	internal CAbiFunction (SourceSpan span, SourceSpan name_span, string name, int ordinal, CAbiSignature signature, CForeignMetadata metadata, CAbiCleanupFunction? owned_cleanup = null) {
		this.span = span;
		this.name_span = name_span;
		this.identifier = name;
		this.ordinal = ordinal;
		this.signature = signature;
		this.metadata = metadata.copy ();
		this.owned_cleanup = owned_cleanup;
	}

	internal void claim_owner(CAbiProgram program) throws CAbiError {
		if (owner != null) {
			throw new CAbiError.INVALID_ABI ("internal C ABI construction error: function #%d already belongs to a program", ordinal);
		}
		containing_program.set (program);
	}
}

// A wrapper contract, never an imported callable or an upstream function.
// The native ordinal is a within-compilation correspondence key only.
public class CAbiExport : Object {
	public int ordinal { get; private set; }
	public int native_function_ordinal { get; private set; }
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }
	public CAbiSignature signature { get; private set; }
	private string external_identifier;
	public string external_symbol { get { return external_identifier; } }
	private WeakRef containing_program = WeakRef (null);
	public CAbiProgram? owner { owned get { return (CAbiProgram?) containing_program.get (); } }

	internal CAbiExport (SourceSpan span, SourceSpan name_span, string external_symbol, int ordinal, CAbiSignature signature, int native_function_ordinal) {
		this.span = span;
		this.name_span = name_span;
		this.external_identifier = external_symbol;
		this.ordinal = ordinal;
		this.signature = signature;
		this.native_function_ordinal = native_function_ordinal;
	}

	internal void claim_owner(CAbiProgram program) throws CAbiError {
		if (owner != null) {
			throw new CAbiError.INVALID_ABI ("internal C ABI construction error: export #%d already belongs to a program", ordinal);
		}
		containing_program.set (program);
	}
}

// Compiler-generated physical C cleanup authority, never a source import.
public class CAbiCleanupFunction : Object {
	public int ordinal { get; private set; }
	private string identifier;
	public string external_symbol { get { return identifier; } }
	public SourceSpan symbol_span { get; private set; }
	public CAbiSignature signature { get; private set; }
	private WeakRef containing_program = WeakRef (null);
	public CAbiProgram? owner { owned get { return (CAbiProgram?) containing_program.get (); } }

	internal CAbiCleanupFunction (string external_symbol, SourceSpan symbol_span, int ordinal, CAbiSignature signature) {
		this.identifier = external_symbol;
		this.symbol_span = symbol_span;
		this.ordinal = ordinal;
		this.signature = signature;
	}

	internal void claim_owner(CAbiProgram program) throws CAbiError {
		if (owner != null) {
			throw new CAbiError.INVALID_ABI ("internal C ABI construction error: cleanup already belongs to a program");
		}
		containing_program.set (program);
	}
}

public class CAbiProgram : Object {
	public GenericArray<CAbiForeignSignal> foreign_signals { get; private set; default = new GenericArray<CAbiForeignSignal> (); }
	private GenericArray<CAbiForeignSignal> signal_origins = new GenericArray<CAbiForeignSignal> ();
	internal void bind_foreign_signal(CAbiForeignSignal signal) {
		foreign_signals.add (signal);
		signal_origins.add (signal);
	}
	internal bool foreign_signals_valid() {
		if (foreign_signals.length != signal_origins.length) {
			return false;
		}
		for (int p = 0; p < foreign_signals.length; p++) {
			if (foreign_signals[p] != signal_origins[p] || !foreign_signals[p].valid (this)) {
				return false;
			}
		}
		return true;
	}
	public GenericArray<Astra.NativeAbi.NativeCallbackViewPlan> callback_views { get; private set; default = new GenericArray<Astra.NativeAbi.NativeCallbackViewPlan> (); }
	private GenericArray<Astra.NativeAbi.NativeCallbackViewPlan> callback_view_origins = new GenericArray<Astra.NativeAbi.NativeCallbackViewPlan> ();
	internal void bind_callback_view(Astra.NativeAbi.NativeCallbackViewPlan plan) {
		callback_views.add (plan);
		callback_view_origins.add (plan);
	}
	internal bool callback_views_valid() {
		if (callback_views.length != callback_view_origins.length) {
			return false;
		}
		for (int p = 0; p < callback_views.length; p++) {
			if (callback_views[p] != callback_view_origins[p] || !callback_views[p].valid ()) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<CAbiClassAdapter> class_adapters { get; private set; }
	public GenericArray<Astra.Source.ForeignImportContract> class_import_roots { get; private set; default = new GenericArray<Astra.Source.ForeignImportContract> (); }
	public GenericArray<CAbiForeignImport> class_imports { get; private set; default = new GenericArray<CAbiForeignImport> (); }
	public GenericArray<CAbiRetainedPlan> retained_operations { get; private set; default = new GenericArray<CAbiRetainedPlan> (); }
	private GenericArray<CAbiRetainedPlan> retained_origins = new GenericArray<CAbiRetainedPlan> ();
	internal void bind_retained_operation(CAbiRetainedPlan plan) {
		retained_operations.add (plan);
		retained_origins.add (plan);
	}
	internal bool retained_operations_valid() {
		if (retained_operations.length != retained_origins.length) {
			return false;
		}
		for (int p = 0; p < retained_operations.length; p++) {
			if (retained_operations[p] != retained_origins[p] || !retained_operations[p].valid_signature ()) {
				return false;
			}
		}
		return true;
	}
	public GenericArray<CAbiCleanupFunction> cleanups { get; private set; }
	public SourceSpan span { get; private set; }
	public CAbiProfile profile { get; private set; }
	// Existing functions are imports; exports have a distinct physical type.
	public GenericArray<CAbiFunction> functions { get; private set; }
	public GenericArray<CAbiExport> exports { get; private set; }

	internal CAbiProgram (SourceSpan span, CAbiProfile profile, GenericArray<CAbiFunction> functions, GenericArray<CAbiExport>? exports = null, GenericArray<CAbiCleanupFunction>? cleanups = null, GenericArray<CAbiClassAdapter>? class_adapters = null) throws CAbiError {
		this.span = span;
		this.profile = profile;
		this.class_adapters = class_adapters ?? new GenericArray<CAbiClassAdapter> ();
		foreach (var adapter in this.class_adapters) {
			adapter.claim_owner (this);
		}
		this.cleanups = cleanups ?? new GenericArray<CAbiCleanupFunction> ();
		foreach (var cleanup in this.cleanups) {
			cleanup.claim_owner (this);
		}
		this.functions = functions;
		this.exports = exports ?? new GenericArray<CAbiExport> ();
		foreach (var exported in this.exports) {
			exported.claim_owner (this);
		}
		for (int i = 0; i < functions.length; i++) {
			functions[i].claim_owner (this);
		}
	}
}
}

namespace Astra.CAbi {
public class CAbiRetainedPlan : Object {
	public int caller { get; private set; } public int block { get; private set; } public int instruction { get; private set; } public int action { get; private set; }
	private string environment_name;
	public string environment { get { return environment_name; } }
	public CAbiScalarType callback_result { get; private set; }
	public bool callback_void { get; private set; }
	public GenericArray<CAbiScalarType> callback_parameters { get; private set; default = new GenericArray<CAbiScalarType> (); }
	public Astra.Source.ForeignValueType? signal_callback { get; private set; }
	private string signal_identity;
	internal CAbiRetainedPlan (int caller, int block, int instruction, int action, string environment, CAbiScalarType callback_result = CAbiScalarType.I32, Astra.Source.ForeignValueType? signal_callback = null) {
		this.caller = caller;
		this.block = block;
		this.instruction = instruction;
		this.action = action;
		this.environment_name = environment;
		this.signal_callback = signal_callback;
		signal_identity = signal_callback == null ? "" : signal_callback.identity ();
		this.callback_result = callback_result;
		callback_void = signal_callback != null;
		callback_parameters.add (CAbiScalarType.PTR);
		if (signal_callback == null) {
			callback_parameters.add (CAbiScalarType.I32);
		} else {
			for (uint p = 0; p < signal_callback.callback_parameter_count; p++) {
				callback_parameters.add (CAbiForeignImport.scalar (signal_callback.callback_parameter (p).kind));
			}
		}
	}
	public bool valid_signature() {
		if (action >= 7 && action <= 9) {
			if (signal_callback == null || !signal_callback.valid () || signal_callback.identity () != signal_identity || signal_callback.kind != Astra.Source.ForeignValueKind.CALLBACK || signal_callback.callback_result.kind != Astra.Source.ForeignValueKind.VOID || signal_callback.callback_parameter_count > 4 || !callback_void || callback_parameters.length != signal_callback.callback_parameter_count + 1 || callback_parameters[0] != CAbiScalarType.PTR) {
				return false;
			}
			for (uint p = 0; p < signal_callback.callback_parameter_count; p++) {
				var type = signal_callback.callback_parameter (p);
				if (!type.scalar () || callback_parameters[p + 1] != CAbiForeignImport.scalar (type.kind)) {
					return false;
				}
			}
			return true;
		}
		return !callback_void && signal_callback == null && signal_identity == "" && callback_result == CAbiScalarType.I32 && callback_parameters.length == 2 && callback_parameters[0] == CAbiScalarType.PTR && callback_parameters[1] == CAbiScalarType.I32;
	}
}
}
