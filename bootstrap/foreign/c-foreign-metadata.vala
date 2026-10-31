// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Foreign {
public enum CBoolAbi {
	NONE, C99, INVALID;
	public static CBoolAbi parse(string mode) {
		return mode == "c99" ? C99 : INVALID;
	}
	public bool valid() {
		return this == NONE || this == C99;
	}
}
public enum CPointerAbi {
	NONE, I32_NOESCAPE, INVALID;
	public static CPointerAbi parse(string mode) {
		return mode == "i32-noescape" ? I32_NOESCAPE : INVALID;
	}
	public bool is_valid() {
		return this == NONE || this == I32_NOESCAPE;
	}
	public string dump_suffix() {
		return this == NONE ? "" : " (pointer-abi i32-noescape read-write)";
	}
}
// Finite target primitives. No address, pointer, foreign lifetime promise,
// or arbitrary assembly can be supplied by a source declaration.
public enum PcDeviceOperation {
	INVALID, UART_TX8, EDU_READ32, EDU_WRITE32, BREAKPOINT,
	ATOMIC_LOAD_RELAXED, ATOMIC_LOAD_ACQUIRE, ATOMIC_LOAD_SEQ_CST,
	ATOMIC_STORE_RELAXED, ATOMIC_STORE_RELEASE, ATOMIC_STORE_SEQ_CST,
	ATOMIC_ADD_RELAXED, ATOMIC_ADD_ACQ_REL, ATOMIC_ADD_SEQ_CST;

	public static PcDeviceOperation parse(string name) {
		switch (name) {
		case "pc-uart-tx8":
			return UART_TX8;
		case "pc-edu-read32":
			return EDU_READ32;
		case "pc-edu-write32":
			return EDU_WRITE32;
		case "pc-breakpoint":
			return BREAKPOINT;
		case "pc-atomic-load-relaxed":
			return ATOMIC_LOAD_RELAXED;
		case "pc-atomic-load-acquire":
			return ATOMIC_LOAD_ACQUIRE;
		case "pc-atomic-load-seq-cst":
			return ATOMIC_LOAD_SEQ_CST;
		case "pc-atomic-store-relaxed":
			return ATOMIC_STORE_RELAXED;
		case "pc-atomic-store-release":
			return ATOMIC_STORE_RELEASE;
		case "pc-atomic-store-seq-cst":
			return ATOMIC_STORE_SEQ_CST;
		case "pc-atomic-add-relaxed":
			return ATOMIC_ADD_RELAXED;
		case "pc-atomic-add-acq-rel":
			return ATOMIC_ADD_ACQ_REL;
		case "pc-atomic-add-seq-cst":
			return ATOMIC_ADD_SEQ_CST;
		default:
			return INVALID;
		}
	}
	public bool atomic_load() {
		return this >= ATOMIC_LOAD_RELAXED && this <= ATOMIC_LOAD_SEQ_CST;
	}
	public bool atomic_store() {
		return this >= ATOMIC_STORE_RELAXED && this <= ATOMIC_STORE_SEQ_CST;
	}
	public bool atomic_add() {
		return this >= ATOMIC_ADD_RELAXED && this <= ATOMIC_ADD_SEQ_CST;
	}
	public int argument_count() {
		return this == EDU_READ32 || atomic_load () ? 0 : 1;
	}
	public int ordering() {
		if (this == ATOMIC_LOAD_ACQUIRE) {
			return 4;
		}
		if (this == ATOMIC_STORE_RELEASE) {
			return 5;
		}
		if (this == ATOMIC_ADD_ACQ_REL) {
			return 6;
		}
		if (this == ATOMIC_LOAD_SEQ_CST || this == ATOMIC_STORE_SEQ_CST || this == ATOMIC_ADD_SEQ_CST) {
			return 7;
		}
		return atomic_load () || atomic_store () || atomic_add () ? 2 : 0;
	}
}

public class PcDeviceContract : Object {
	private PcDeviceOperation admitted_operation;
	public PcDeviceOperation operation { get; internal set; }
	public PcDeviceContract (PcDeviceOperation operation) {
		this.operation = operation;
		admitted_operation = operation;
	}
	public bool valid() {
		return operation == admitted_operation && operation > PcDeviceOperation.INVALID && operation <= PcDeviceOperation.ATOMIC_ADD_SEQ_CST;
	}
	public PcDeviceContract copy() {
		var result = new PcDeviceContract (admitted_operation);
		result.operation = operation;
		return result;
	}
}

public enum CCallbackAbi {
	NONE, I32_CONTEXT_I32_SYNC, INVALID;
	public static CCallbackAbi parse(string mode) {
		return mode == "i32-context-i32-sync" ? I32_CONTEXT_I32_SYNC : INVALID;
	}
	public bool is_valid() {
		return this == NONE || this == I32_CONTEXT_I32_SYNC;
	}
}
public enum CRecordAbi {
	NONE, NATURAL_LP64, VALUE_LP64, INVALID;
	public static CRecordAbi parse(string mode) {
		return mode == "natural-lp64" ? NATURAL_LP64 : mode == "value-lp64" ? VALUE_LP64 : INVALID;
	}
	public bool is_valid() {
		return this == NONE || this == NATURAL_LP64 || this == VALUE_LP64;
	}
	public string dump_suffix() {
		return this == NONE ? "" : this == VALUE_LP64 ? " (record-abi value-lp64 sysv-eightbytes)" : " (record-abi natural-lp64 borrowed-noescape)";
	}
}
// Trusted synchronous foreign obligation. Payloads are arbitrary octets;
// unlike CTextAbi this conveys no UTF-8 or terminated-string promise.
public enum CBufferAbi {
	NONE,
	U8_I32,
	INVALID;

	public static CBufferAbi parse(string mode) {
		return mode == "u8-i32" ? U8_I32 : INVALID;
	}
	public bool is_valid() {
		return this == NONE || this == U8_I32;
	}
	public string dump_suffix() {
		return this == NONE ? "" : " (buffer-abi u8-i32)";
	}
}
// Explicit outbound transport authority, independent of native text ABI.
public enum CTextAbi {
	NONE,
	UTF8_I32,
	INVALID;

	public static CTextAbi parse(string mode) {
		return mode == "utf8-i32" ? UTF8_I32 : INVALID;
	}
	public bool is_valid() {
		return this == NONE || this == UTF8_I32;
	}
	public string dump_suffix() {
		return this == NONE ? "" : " (text-abi utf8-i32)";
	}
}

// Immutable normalized foreign resource contracts. The signature is fixed
// at one void* argument and no result; this is not a source callable.
public class CForeignCleanupContract : Object {
	private string identifier;
	public string external_symbol { get { return identifier; } }
	public SourceSpan? symbol_span { get; private set; }

	public CForeignCleanupContract (string external_symbol, SourceSpan? symbol_span = null) {
		this.identifier = external_symbol;
		this.symbol_span = symbol_span;
	}
}

public class CForeignOwnedResultContract : Object {
	public CForeignCleanupContract cleanup { get; private set; }

	public CForeignOwnedResultContract (CForeignCleanupContract cleanup) {
		this.cleanup = cleanup;
	}
}

// Descriptive integration metadata, never a file to open or a link input.
public class CForeignHeader : Object {
	private string filename;
	public string name { get { return filename; } }
	public SourceSpan? span { get; private set; }

	public CForeignHeader (string name, SourceSpan? span = null) {
		this.filename = name;
		this.span = span;
	}
}

// Immutable, origin-independent C declaration metadata. No syntax or types.
// Copy the collection; callers cannot mutate the retained ordered entries.
public class CForeignMetadata : Object {
	public CBoolAbi bool_abi { get; internal set; }
	private CBoolAbi admitted_bool_abi;
	public bool bool_policy_valid() {
		return bool_abi == admitted_bool_abi && bool_abi.valid ();
	}
	public bool bool_signature_valid(bool has_bool) {
		return bool_policy_valid () && (has_bool == (bool_abi == CBoolAbi.C99)) && (bool_abi == CBoolAbi.NONE || import_policy == DeclarationPolicyId.C_IMPORT && com_import == null && device == null && callback == null && owned_result == null && record_abi == CRecordAbi.NONE && pointer_abi == CPointerAbi.NONE && text_abi == CTextAbi.NONE && buffer_abi == CBufferAbi.NONE);
	}
	public DeclarationPolicyId import_policy { get; internal set; }
	private DeclarationPolicyId admitted_import_policy;
	private string carrier_identifier;
	public string gobject_carrier { get { return carrier_identifier; } internal set { carrier_identifier = value; } }
	private string admitted_gobject_carrier;
	public bool import_policy_valid() {
		return gobject_carrier == admitted_gobject_carrier && (gobject_carrier == "" || import_policy == DeclarationPolicyId.GOBJECT_IMPORT && Astra.Source.ForeignClassPolicy.identifier (gobject_carrier) && com_import == null && device == null && callback == null && pointer_abi == CPointerAbi.NONE && record_abi == CRecordAbi.NONE && text_abi == CTextAbi.NONE && buffer_abi == CBufferAbi.NONE && bool_abi == CBoolAbi.NONE) && import_policy == admitted_import_policy && (import_policy == DeclarationPolicyId.C_IMPORT || import_policy == DeclarationPolicyId.GOBJECT_IMPORT && com_import == null && device == null && header_count > 0);
	}
	public string policy_identity() {
		var text = new StringBuilder ("%u;%d:%s;".printf ((uint) import_policy, external_symbol.length, external_symbol));
		if (gobject_carrier != "") {
			text.append_printf ("carrier=%d:%s;", gobject_carrier.length, gobject_carrier);
		}
		if (bool_abi != CBoolAbi.NONE) {
			text.append ("bool=%u;".printf ((uint) bool_abi));
		}
		foreach (var header in headers) {
			text.append ("%d:%s;".printf (header.name.length, header.name));
		}
		return Checksum.compute_for_string (ChecksumType.SHA256, text.str);
	}
	public ComImportContract? com_import { get; private set; }
	public ComImportRole com_role { get; private set; }
	private string com_identity;
	public bool com_owner_result { get { return com_import != null && (com_role == ComImportRole.ACQUIRE || com_role == ComImportRole.CLONE); } }
	public bool valid_com() {
		return com_import == null ? com_role == ComImportRole.NONE : com_import.valid () && com_import.identity () == com_identity && com_import.admits (com_role) && external_symbol == com_import.prefix + "_" + ComImportContract.suffix (com_role) && callback == null && device == null && header_count == 0 && record_abi == CRecordAbi.NONE && text_abi == CTextAbi.NONE && buffer_abi == CBufferAbi.NONE && pointer_abi == (com_role == ComImportRole.SET ? CPointerAbi.NONE : CPointerAbi.I32_NOESCAPE);
	}
	public static bool portable_symbol(string name) {
		if (name.length == 0) {
			return false;
		}
		for (int i = 0; i < name.length; i++) {
			char c = name[i];
			if (c != '_' && !(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(i != 0 && c >= '0' && c <= '9')) {
				return false;
			}
		}
		return true;
	}
	public PcDeviceContract? device { get; private set; }
	public bool device_signature(bool result_word, int parameter_count, bool parameters_word) {
		return device == null || (device.valid () && result_word && parameters_word && parameter_count == device.operation.argument_count () && header_count == 0 && owned_result == null && callback == null && callback_abi == CCallbackAbi.NONE && record_abi == CRecordAbi.NONE && text_abi == CTextAbi.NONE && buffer_abi == CBufferAbi.NONE && pointer_abi == CPointerAbi.NONE);
	}
	private string? callback_identifier;
	public string? callback { get { return callback_identifier; } }
	public CCallbackAbi callback_abi { get; private set; }
	public string callback_dump_suffix() {
		return callback == null ? "" : " (callback \"%s\" i32-context-i32-sync nonretaining)".printf (callback.escape ());
	}
	public CRecordAbi record_abi { get; private set; }
	public CPointerAbi pointer_abi { get; private set; }
	public SourceSpan? record_abi_span { get; private set; }
	public CBufferAbi buffer_abi { get; private set; }
	public SourceSpan? buffer_abi_span { get; private set; }
	public CTextAbi text_abi { get; private set; }
	public SourceSpan? text_abi_span { get; private set; }
	public CForeignOwnedResultContract? owned_result { get; private set; }
	private string external_identifier;
	public string external_symbol { get { return external_identifier; } }
	public SourceSpan? external_symbol_span { get; private set; }
	private GenericArray<CForeignHeader> headers = new GenericArray<CForeignHeader> ();
	public int header_count { get { return headers.length; } }

	public CForeignMetadata (string external_symbol, SourceSpan? external_symbol_span = null, CForeignHeader[]? headers = null, CForeignOwnedResultContract? owned_result = null, CTextAbi text_abi = CTextAbi.NONE, SourceSpan? text_abi_span = null, CBufferAbi buffer_abi = CBufferAbi.NONE, SourceSpan? buffer_abi_span = null, CRecordAbi record_abi = CRecordAbi.NONE, SourceSpan? record_abi_span = null, string? callback = null, CCallbackAbi callback_abi = CCallbackAbi.NONE, PcDeviceContract? device = null, CPointerAbi pointer_abi = CPointerAbi.NONE, ComImportContract? com_import = null, ComImportRole com_role = ComImportRole.NONE, DeclarationPolicyId import_policy = DeclarationPolicyId.C_IMPORT, CBoolAbi bool_abi = CBoolAbi.NONE, string gobject_carrier = "") {
		this.gobject_carrier = admitted_gobject_carrier = gobject_carrier;
		this.bool_abi = admitted_bool_abi = bool_abi;
		this.import_policy = admitted_import_policy = import_policy;
		this.com_import = com_import == null ? null : com_import.copy ();
		this.com_role = com_role;
		com_identity = com_import == null ? "" : com_import.identity ();
		this.pointer_abi = pointer_abi;
		this.device = device == null ? null : device.copy ();
		this.callback_identifier = callback;
		this.callback_abi = callback_abi;
		this.record_abi = record_abi;
		this.record_abi_span = record_abi_span;
		this.buffer_abi = buffer_abi;
		this.buffer_abi_span = buffer_abi_span;
		this.text_abi = text_abi;
		this.text_abi_span = text_abi_span;
		this.owned_result = owned_result;
		this.external_identifier = external_symbol;
		this.external_symbol_span = external_symbol_span;
		if (headers != null) {
			foreach (var header in headers) {
				this.headers.add (header);
			}
		}
	}

	// Downstream stages supply their own cleanup identities and do not retain
	// the semantic ownership contract through descriptive metadata.
	public CForeignMetadata copy() {
		return copy_with_owned_result (owned_result);
	}
	public CForeignMetadata copy_with_owned_result(CForeignOwnedResultContract? owned_result = null) {
		CForeignHeader[] copies = {};
		foreach (var header in headers) {
			copies += new CForeignHeader (header.name, header.span);
		}
		var result = new CForeignMetadata (external_symbol, external_symbol_span, copies, owned_result, text_abi, text_abi_span, buffer_abi, buffer_abi_span, record_abi, record_abi_span, callback, callback_abi, device, pointer_abi, com_import, com_role, import_policy, bool_abi, gobject_carrier);
		result.admitted_bool_abi = admitted_bool_abi;
		result.admitted_import_policy = admitted_import_policy;
		result.admitted_gobject_carrier = admitted_gobject_carrier;
		return result;
	}

	public CForeignHeader header_at(int ordinal) {
		return headers[ordinal];
	}
}
}
