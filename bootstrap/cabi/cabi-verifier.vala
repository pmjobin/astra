// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.CAbi {
// Structural verification needs only physical types and shared contracts.
public class CAbiVerifier : Object {
	internal static void verify_record(CAbiRecordPlan plan) throws CAbiError {
		if (!plan.projection_valid ()) {
			fail ("C union", "lost admitted active-member representation identity");
		}
		if (plan.union_projection != null) {
			var projection = plan.union_projection;
			if (!plan.by_value || projection.name != plan.name || projection.field_names.length != plan.fields.length || projection.size () != plan.size || projection.alignment () != plan.alignment) {
				fail ("C union", "active projection differs from its exact by-value C carrier");
			}
			for (uint i = 0; i < plan.fields.length; i++) {
				if (projection.field_names[i] != plan.fields[i].name || projection.field_types[i] != plan.fields[i].scalar_name || projection.offset (i) != plan.fields[i].offset) {
					fail ("C union", "incompatible active member or tag channel");
				}
			}
		}
		if (plan.name == "" || plan.fields.length == 0 || plan.fields.length > 32) {
			fail ("record", "record requires exact nominal identity and 1..32 fields");
		}
		uint offset = 0;
		uint alignment = 1;
		var names = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var field in plan.fields) {
			uint bytes = field.bytes;
			if (bytes == 0 || field.name == "" || names.contains (field.name)) {
				fail ("record", "record fields require unique names and exact numeric scalar identity");
			}
			names.insert (field.name, true);
			offset = (offset + bytes - 1) / bytes * bytes;
			if (field.offset != offset) {
				fail ("record", "record field offset differs from natural LP64 scalar layout");
			}
			offset += bytes;
			alignment = uint.max (alignment, bytes);
		}
		if (plan.by_value) {
			if (plan.fields.length > 3 || plan.size > 24) {
				fail ("record", "C value record exceeds finite field/extent profile");
			}
			for (int i = 0; i < plan.fields.length; i++) {
				var field = plan.fields[i];
				if (field.bytes == 8) {
					continue;
				}
				if (field.scalar_name == "f32" && (plan.fields.length == 1 || (i == 0 && plan.fields.length == 2 && plan.fields[1].scalar_name == "f64"))) {
					continue;
				}
				fail ("record", "C value record field has unsupported eightbyte classification");
			}
		}
		if (plan.alignment != alignment || plan.size != (offset + alignment - 1) / alignment * alignment) {
			fail ("record", "record extent/alignment differs from natural LP64 scalar layout");
		}
	}

	private static void fail(string path, string message) throws CAbiError {
		throw new CAbiError.INVALID_ABI ("internal C ABI verification error at %s: %s", path, message);
	}

	private static void verify_scalar(CAbiScalarType scalar_type, CAbiProfile profile, string path) throws CAbiError {
		if (scalar_type != CAbiScalarType.I32 && scalar_type != CAbiScalarType.PTR && scalar_type != CAbiScalarType.F64 && scalar_type != CAbiScalarType.F32 && scalar_type != CAbiScalarType.I64 && scalar_type != CAbiScalarType.U64 && scalar_type != CAbiScalarType.CBOOL) {
			fail (path, "unsupported C ABI scalar type");
		}
		if (scalar_type == CAbiScalarType.CBOOL && profile < CAbiProfile.C_BOOL_V7) {
			fail (path, "CBOOL requires explicit c-bool-v7");
		}
		if (scalar_type == CAbiScalarType.PTR && profile < CAbiProfile.SCALAR_PTR_V1) {
			fail (path, "PTR requires scalar-ptr-v1");
		}
		if (scalar_type == CAbiScalarType.F32 && profile < CAbiProfile.SCALAR_FP_V2) {
			fail (path, "F32 requires scalar-fp-v2");
		}
		if (scalar_type == CAbiScalarType.F64 && profile < CAbiProfile.SCALAR_FP_V2) {
			fail (path, "F64 requires scalar-fp-v2");
		}
		if ((scalar_type == CAbiScalarType.I64 || scalar_type == CAbiScalarType.U64) && profile < CAbiProfile.WIDE_INT_V5) {
			fail (path, "64-bit integer channel requires wide-int-v5");
		}
	}

	private static void claim_symbol(HashTable<string, string> symbols, string symbol, Astra.Source.SourceSpan span, string path) throws CAbiError {
		if (symbol == "") {
			fail (path, "external symbols must be nonempty and unique");
		}
		if (symbols.contains (symbol)) {
			var diagnostic = new Astra.Source.Diagnostic (span, "C external symbol '%s' is declared more than once".printf (symbol.escape ()));
			throw new CAbiError.DUPLICATE_SYMBOL ("%s", diagnostic.format ());
		}
		symbols.insert (symbol, symbol);
	}

	public static void verify(CAbiProgram program) throws CAbiError {
		if (!program.callback_views_valid ()) {
			fail ("captured callback", "lost exact borrowed Closure projection/signature inventory");
		}
		if (!program.foreign_signals_valid ()) {
			fail ("native signal", "lost exact shared-root signal/member/physical target inventory");
		}
		if (program.profile < CAbiProfile.SCALAR_V0 || program.profile > CAbiProfile.C_BOOL_V7) {
			fail ("program", "unsupported C ABI profile");
		}
		if (program.retained_operations.length != 0 && program.profile < CAbiProfile.SCALAR_PTR_V1) {
			fail ("retained C callback", "opaque context and registration require scalar-ptr-v1 or later");
		}
		if (!program.retained_operations_valid ()) {
			fail ("retained C callback", "lost exact original callback signature and retirement inventory");
		}
		var retained_sites = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var plan in program.retained_operations) {
			string site = "%d/%d/%d".printf (plan.caller, plan.block, plan.instruction);
			if (plan.caller < 0 || plan.block < 0 || plan.instruction < 0 || plan.action < 0 || plan.action > 9 || plan.environment == "" || retained_sites.contains (site) || !plan.valid_signature ()) {
				fail ("retained C callback", "requires unique finite adapter action and C i32(opaque-context,i32) signature");
			}
			retained_sites.insert (site, true);
		}
		bool has_text = false;
		bool has_buffer = false;
		bool has_wide = false;
		bool has_bool = false;
		foreach (var function in program.functions) {
			has_bool |= function.signature.has_bool;
		}
		foreach (var exported in program.exports) {
			has_bool |= exported.signature.has_bool;
		}
		if (program.profile == CAbiProfile.C_BOOL_V7 && !has_bool) {
			fail ("program", "c-bool-v7 requires explicit copied bool channels");
		}
		foreach (var function in program.functions) {
			has_text |= function.signature.has_text;
			has_buffer |= function.signature.has_buffer;
			has_wide |= function.signature.has_wide;
		}
		foreach (var exported in program.exports) {
			has_wide |= exported.signature.has_wide;
		}
		if (program.profile == CAbiProfile.TEXT_VIEW_V3 && !has_text) {
			fail ("program", "text-view-v3 requires imported text groups");
		}
		if (program.profile == CAbiProfile.BUFFER_VIEW_V4 && !has_buffer) {
			fail ("program", "buffer-view-v4 requires imported buffer groups");
		}
		if (program.profile == CAbiProfile.WIDE_INT_V5 && !has_wide) {
			fail ("program", "wide-int-v5 requires exact 64-bit integer channels");
		}
		var symbols = new HashTable<string, string> (str_hash, str_equal);
		var cleanups = new HashTable<CAbiCleanupFunction, CAbiCleanupFunction> (direct_hash, direct_equal);
		for (int c = 0; c < program.cleanups.length; c++) {
			var cleanup = program.cleanups[c];
			string path = "cleanup #%d".printf (c);
			if (cleanup.ordinal != c || cleanup.owner != program || cleanups.contains (cleanup)) {
				fail (path, "cleanup requires exact program owner and unique declaration ordinal");
			}
			cleanups.insert (cleanup, cleanup);
			claim_symbol (symbols, cleanup.external_symbol, cleanup.symbol_span, path);
			verify_signature (cleanup.signature, program.profile, path);
			if (cleanup.signature.parameters.length != 1 || cleanup.signature.parameters[0].scalar_type != CAbiScalarType.PTR || cleanup.signature.result != null || cleanup.signature.parameters[0].pointer_contract != PointerParameterContract.UNMANAGED) {
				fail (path, "cleanup signature must be exactly (PTR) -> void");
			}
		}
		var functions = new HashTable<CAbiFunction, CAbiFunction> (direct_hash, direct_equal);
		for (int f = 0; f < program.functions.length; f++) {
			var function = program.functions[f];
			if (!function.metadata.bool_signature_valid (function.signature.has_bool) || function.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && function.owned_cleanup != null) {
				fail ("C99 bool", "lost admitted copied boolean policy");
			}
			if (!function.metadata.import_policy_valid ()) {
				fail ("foreign import", "lost admitted policy or GObject header identity");
			}
			if (!function.metadata.valid_com ()) {
				fail ("COMImport", "lost admitted IID/vtable/context/symbol identity");
			}
			if (function.metadata.gobject_carrier != "") {
				int roots = 0;
				foreach (var root in program.class_import_roots) {
					if (root.api.native_origin == function.metadata.gobject_carrier && root.gobject != null && root.valid ()) {
						roots++;
					}
				}
				if (roots != 1 || function.signature.parameters.length != 1 || function.signature.parameters[0].scalar_type != CAbiScalarType.PTR || function.signature.parameters[0].pointer_contract != Astra.Semantic.PointerParameterContract.BORROWED_NOESCAPE || function.owned_cleanup == null || function.signature.result == null || function.signature.result.scalar_type != CAbiScalarType.PTR) {
					fail ("GObject carrier bridge", "requires its exact nominal imported root, one borrowed carrier and independent owned Resource result");
				}
			}

			string path = "function #%d".printf (f);
			if (functions.contains (function) || function.ordinal != f) {
				fail (path, "function identity/ordinal must be unique and in source order");
			}
			functions.insert (function, function);
			if (function.owner != program) {
				fail (path, "function is not owned by the containing program");
			}
			claim_symbol (symbols, function.external_symbol, function.metadata.external_symbol_span ?? function.name_span, path);
			for (int h = 0; h < function.metadata.header_count; h++) {
				if (function.metadata.header_at (h).name == "") {
					fail (path, "C header metadata must be nonempty");
				}
			}
			verify_signature (function.signature, program.profile, path, function.metadata.text_abi, function.metadata.buffer_abi, function.metadata.record_abi, function.metadata.pointer_abi, function.metadata.com_owner_result, function.metadata.bool_abi);
			if (function.metadata.com_import != null) {
				var role = function.metadata.com_role;
				var sig = function.signature;
				if (sig.parameters.length != (role == Astra.Source.ComImportRole.SCALE ? 3 : 2) || sig.result == null || sig.result.scalar_type != (function.metadata.com_owner_result ? CAbiScalarType.PTR : CAbiScalarType.I32) || (function.owned_cleanup != null) != function.metadata.com_owner_result || function.owned_cleanup != null && function.owned_cleanup.external_symbol != function.metadata.com_import.prefix + "_release" || sig.parameters[0].scalar_type != CAbiScalarType.PTR || sig.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || sig.parameters[0].i32_pointer) {
					fail ("COMImport", "wrong physical interface/result/ownership role");
				}
				if (role != Astra.Source.ComImportRole.SET && !sig.parameters[sig.parameters.length - 1].i32_pointer) {
					fail ("COMImport", "missing exact int out role");
				}
				if ((role == Astra.Source.ComImportRole.SET || role == Astra.Source.ComImportRole.SCALE) && (sig.parameters[1].scalar_type != CAbiScalarType.I32 || sig.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED)) {
					fail ("COMImport", "wrong method value role");
				}
			}
			bool device_parameters = true;
			foreach (var parameter in function.signature.parameters) {
				device_parameters &= parameter.scalar_type == CAbiScalarType.I32;
			}
			if (!function.metadata.device_signature (function.signature.result != null && function.signature.result.scalar_type == CAbiScalarType.I32, function.signature.parameters.length, device_parameters)) {
				fail (path, "PC device policy lost its admitted operation or exact physical i32 ABI");
			}
			if (!function.metadata.callback_abi.is_valid () || (function.metadata.callback != null) != (function.metadata.callback_abi == Astra.Foreign.CCallbackAbi.I32_CONTEXT_I32_SYNC) || (function.signature.callback != null) != (function.metadata.callback != null) || (function.signature.callback != null && function.signature.callback.target_name != function.metadata.callback)) {
				fail (path, "C callback plan requires exact synchronous nonretaining metadata and target");
			}
			if (function.signature.has_buffer && function.signature.result != null && function.signature.result.scalar_type == CAbiScalarType.PTR) {
				fail (path, "C byte buffer imports cannot return pointer-like values");
			}
			if (function.signature.has_record && function.signature.result != null && function.signature.result.scalar_type == CAbiScalarType.PTR) {
				fail (path, "C record imports cannot return pointer-like values or derived owners");
			}
			if (function.metadata.owned_result != null || (function.owned_cleanup != null && (!cleanups.contains (function.owned_cleanup) || function.signature.result == null || function.signature.result.scalar_type != CAbiScalarType.PTR))) {
				fail (path, "owned-result requires an exact C ABI cleanup and PTR result");
			}
		}
		for (int e = 0; e < program.exports.length; e++) {
			var exported = program.exports[e];
			string path = "export #%d".printf (e);
			if (exported.ordinal != e) {
				fail (path, "export identity/ordinal must be unique and in source order");
			}
			if (exported.owner != program) {
				fail (path, "export is not owned by the containing program");
			}
			if (exported.native_function_ordinal < 0) {
				fail (path, "native target ordinal must be nonnegative");
			}
			claim_symbol (symbols, exported.external_symbol, exported.name_span, path);
			verify_signature (exported.signature, program.profile, path, Astra.Foreign.CTextAbi.NONE, Astra.Foreign.CBufferAbi.NONE, exported.signature.has_record ? Astra.Foreign.CRecordAbi.VALUE_LP64 : Astra.Foreign.CRecordAbi.NONE, Astra.Foreign.CPointerAbi.NONE, false, exported.signature.bool_abi);
			if (exported.signature.callback != null) {
				fail (path, "C exports cannot retain callback transport authority");
			}
			foreach (var parameter in exported.signature.parameters) {
				if (parameter.text != null || parameter.buffer != null || (parameter.record != null && !parameter.record.by_value) || parameter.pointer_contract != PointerParameterContract.UNMANAGED) {
					fail (path, "C export borrowed parameters are unsupported");
				}
			}
		}
		if (!Astra.Source.ForeignImportContract.distinct (program.class_import_roots)) {
			fail ("foreign imports", "requires distinct nominal roots, prefixes and COM IIDs with exact declared parents");
		}
		foreach (var root in program.class_import_roots) {
			if (!root.valid ()) {
				fail ("CImport", "invalid declared physical import root");
			}
			for (uint m = 0; m < root.api.member_count; m++) {
				int matches = 0;
				foreach (var imported in program.class_imports) {
					if (imported.binding.root.equal (root) && imported.binding.member_index == m) {
						matches++;
					}
				}
				if (matches != 1) {
					fail ("CImport", "physical import lost a declared member");
				}
			}
		}
		foreach (var imported in program.class_imports) {
			bool root = false;
			foreach (var declared in program.class_import_roots) {
				root |= imported.binding.root.equal (declared);
			}
			if (!root || !imported.valid ()) {
				fail ("CImport", "physical import lost typed status/out channels");
			}
			claim_symbol (symbols, imported.symbol (), program.span, "CImport member");
		}
		var com_roots = new GenericArray<Astra.Source.ForeignClassPolicy> ();
		var com_protocols = new GenericArray<Astra.Source.ForeignComInterface> ();
		foreach (var adapter in program.class_adapters) {
			com_roots.add (adapter.policy);
		}
		foreach (var root in program.class_import_roots) {
			if (root.com != null) {
				com_protocols.add (root.com);
			}
		}
		foreach (var policy in com_roots) {
			if (!Astra.Source.ForeignClassPolicy.com_roots_valid (policy, com_roots, com_protocols)) {
				fail ("COM object projection", "requires the exact native Shared root and admitted interface declaration");
			}
		}
		for (int a = 0; a < program.class_adapters.length; a++) {
			var adapter = program.class_adapters[a];
			if (adapter.owner != program || adapter.ordinal != a || !adapter.valid () || program.profile < CAbiProfile.SCALAR_PTR_V1) {
				fail ("opaque Class adapter", "requires its exact program owner, ordinal, native roles and pointer ABI");
			}
			if (adapter.policy.declared_api != null) {
				foreach (var symbol in adapter.declared_symbols ()) {
					claim_symbol (symbols, symbol, adapter.span, "declared Class adapter");
				}
			} else {
				foreach (var role in CAbiClassAdapter.roles ()) {
					claim_symbol (symbols, adapter.symbol (role), adapter.span, "opaque Class adapter");
				}
			}
			if (adapter.policy.com != null) {
				claim_symbol (symbols, adapter.policy.prefix + "_as_com", adapter.span, "COM Class adapter");
				claim_symbol (symbols, adapter.policy.prefix + "_com_create", adapter.span, "COM Class factory");
			}
			if (adapter.policy.gobject != null) {
				foreach (string suffix in new string[] { "get_type", "new", "as_gobject", "try_get_value", "try_set_value", "error_quark" }) {
					claim_symbol (symbols, adapter.policy.prefix + "_" + suffix, adapter.span, "GObject Class adapter");
				}
			}
		}
	}

	private static void verify_signature(CAbiSignature? signature, CAbiProfile profile, string path, Astra.Foreign.CTextAbi mode = Astra.Foreign.CTextAbi.NONE, Astra.Foreign.CBufferAbi buffer_mode = Astra.Foreign.CBufferAbi.NONE, Astra.Foreign.CRecordAbi record_mode = Astra.Foreign.CRecordAbi.NONE, Astra.Foreign.CPointerAbi pointer_mode = Astra.Foreign.CPointerAbi.NONE, bool com_owner_result = false, Astra.Foreign.CBoolAbi bool_mode = Astra.Foreign.CBoolAbi.NONE) throws CAbiError {
		if (signature == null) {
			fail (path + "/signature", "missing C ABI signature");
			return;
		}
		if (signature.profile < CAbiProfile.SCALAR_V0 || signature.profile > profile || (profile < CAbiProfile.TEXT_VIEW_V3 && signature.profile != profile) || (signature.profile == CAbiProfile.TEXT_VIEW_V3 && !signature.has_text) || (signature.profile == CAbiProfile.BUFFER_VIEW_V4 && !signature.has_buffer)) {
			fail (path + "/signature", "signature C ABI profile must match the program");
		}
		if (!mode.is_valid () || signature.has_text != (mode == Astra.Foreign.CTextAbi.UTF8_I32)) {
			fail (path, "text group requires explicit import text ABI mode");
		}
		if (!buffer_mode.is_valid () || signature.has_buffer != (buffer_mode == Astra.Foreign.CBufferAbi.U8_I32)) {
			fail (path, "buffer group requires explicit import buffer ABI mode");
		}
		if (!pointer_mode.is_valid () || signature.has_i32_pointer != (pointer_mode == Astra.Foreign.CPointerAbi.I32_NOESCAPE) || signature.has_i32_pointer && (signature.has_record || signature.has_text || signature.has_buffer || signature.callback != null || !com_owner_result && signature.result != null && signature.result.scalar_type == CAbiScalarType.PTR)) {
			fail (path, "int pointer requires exclusive i32-noescape transport and no pointer result");
		}
		if (!record_mode.is_valid () || signature.has_record != (record_mode != Astra.Foreign.CRecordAbi.NONE)) {
			fail (path, "record pointer requires explicit import natural-lp64 record ABI mode");
		}
		if (!signature.bool_abi.valid () || signature.bool_abi != bool_mode || signature.has_bool != (bool_mode == Astra.Foreign.CBoolAbi.C99) || bool_mode == Astra.Foreign.CBoolAbi.C99 && (signature.profile < CAbiProfile.C_BOOL_V7 || signature.has_record || signature.has_text || signature.has_buffer || signature.has_i32_pointer || signature.callback != null)) {
			fail (path, "C99 bool profile lost exact copied boolean channels or gained alternate transport");
		}
		if (signature.callback != null) {
			if (signature.callback.native_function_ordinal < 0 || signature.callback.target_name == "" || signature.parameters.length != 2 || signature.parameters[0].record == null || signature.parameters[1].record != null || signature.parameters[1].text != null || signature.parameters[1].buffer != null || signature.parameters[1].scalar_type != CAbiScalarType.I32 || signature.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED || signature.result == null || signature.result.scalar_type != CAbiScalarType.I32) {
				fail (path, "C callback requires one exact function channel and I32(POD*, I32) transport");
			}
		}
		int physical_ordinal = (signature.callback == null ? 0 : 1) + (signature.result != null && signature.result.record != null && signature.result.record.memory ? 1 : 0);
		if (record_mode == Astra.Foreign.CRecordAbi.VALUE_LP64 && (signature.profile < CAbiProfile.POD_VALUE_V6 || signature.parameters.length > 2 || signature.callback != null || signature.has_buffer || signature.has_text)) {
			fail (path, "C value records require finite SysV LP64 profile and signature budget");
		}
		for (int p = 0; p < signature.parameters.length; p++) {
			var parameter = signature.parameters[p];
			string parameter_path = path + "/parameter #%d".printf (p);
			if (parameter.ordinal != p || parameter.physical_ordinal != physical_ordinal) {
				fail (parameter_path, "parameter ordinals must be unique and in source order");
			}
			if (parameter.i32_pointer) {
				if (parameter.scalar_type != CAbiScalarType.PTR || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || parameter.record != null || parameter.text != null || parameter.buffer != null || signature.profile < CAbiProfile.SCALAR_PTR_V1) {
					fail (parameter_path, "int pointer lost exact borrowed PTR authority");
				}
				physical_ordinal++;
				continue;
			}
			if (parameter.record != null && parameter.record.by_value) {
				if (record_mode != Astra.Foreign.CRecordAbi.VALUE_LP64 || parameter.scalar_type != (CAbiScalarType) (-1) || parameter.pointer_contract != PointerParameterContract.UNMANAGED || parameter.text != null || parameter.buffer != null) {
					fail (parameter_path, "C value record lost explicit copied transport classification");
				}
				verify_record (parameter.record);
				physical_ordinal += parameter.record.channel_count;
				continue;
			}
			if (parameter.record != null) {
				if (record_mode != Astra.Foreign.CRecordAbi.NATURAL_LP64) {
					fail (parameter_path, "borrowed record cannot masquerade as by-value record");
				}
				if (parameter.text != null || parameter.buffer != null || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || parameter.scalar_type != CAbiScalarType.PTR || signature.profile < CAbiProfile.SCALAR_PTR_V1) {
					fail (parameter_path, "record pointer requires exact borrowed PTR without alternate group");
				}
				verify_record (parameter.record);
				physical_ordinal++;
				continue;
			}
			if (parameter.text != null) {
				var text = parameter.text;
				if (signature.profile < CAbiProfile.TEXT_VIEW_V3 || parameter.buffer != null || text.mode != mode || text.role != CAbiTextRole.IMPORT_PARAMETER || text.contract != PointerParameterContract.BORROWED_NOESCAPE || parameter.pointer_contract != text.contract || parameter.scalar_type != (CAbiScalarType) (-1) || text.components.length != 2) {
					fail (parameter_path, "invalid imported borrowed text group role, mode, contract or arity");
				}
				for (int c = 0; c < text.components.length; c++) {
					var component = text.components[c];
					if (component.logical_ordinal != p || component.physical_ordinal != physical_ordinal + c || component.role != (c == 0 ? CAbiTextComponentRole.DATA : CAbiTextComponentRole.BYTE_LENGTH) || component.scalar_type != (c == 0 ? CAbiScalarType.PTR : CAbiScalarType.I32)) {
						fail (parameter_path, "text channels must be adjacent PTR/I32 in logical parameter order");
					}
				}
				physical_ordinal += 2;
				continue;
			}
			if (parameter.buffer != null) {
				var buffer = parameter.buffer;
				if (signature.profile < CAbiProfile.BUFFER_VIEW_V4 || buffer.mode != buffer_mode || buffer.role != CAbiBufferRole.IMPORT_PARAMETER || buffer.contract != PointerParameterContract.BORROWED_NOESCAPE || parameter.pointer_contract != buffer.contract || parameter.scalar_type != (CAbiScalarType) (-1) || buffer.components.length != 2 || buffer.access != CAbiBufferAccess.READ_WRITE || buffer.element_bytes != 1 || buffer.alignment != 1) {
					fail (parameter_path, "invalid imported borrowed octet buffer role, mode, lifetime, layout or arity");
				}
				for (int c = 0; c < buffer.components.length; c++) {
					var component = buffer.components[c];
					if (component.logical_ordinal != p || component.physical_ordinal != physical_ordinal + c || component.role != (c == 0 ? CAbiBufferComponentRole.DATA : CAbiBufferComponentRole.BYTE_LENGTH) || component.scalar_type != (c == 0 ? CAbiScalarType.PTR : CAbiScalarType.I32)) {
						fail (parameter_path, "buffer channels must be adjacent PTR/I32 in logical parameter order");
					}
				}
				physical_ordinal += 2;
				continue;
			}
			physical_ordinal++;
			verify_scalar (parameter.scalar_type, signature.profile, parameter_path);
			if (!parameter.pointer_contract.is_valid () || parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && parameter.scalar_type != CAbiScalarType.PTR)) {
				fail (parameter_path, "borrowed parameter requires PTR channel and a valid behavioral contract");
			}
		}
		if (signature.result != null) {
			if (signature.result.record != null) {
				if (record_mode != Astra.Foreign.CRecordAbi.VALUE_LP64 || !signature.result.record.by_value || signature.result.scalar_type != (CAbiScalarType) (-1)) {
					fail (path, "C record result lost exact copied value classification");
				}
				verify_record (signature.result.record);
			} else {
				verify_scalar (signature.result.scalar_type, signature.profile, path + "/result");
			}
		}
	}

}
}
