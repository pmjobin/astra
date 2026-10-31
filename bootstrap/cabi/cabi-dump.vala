// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.CAbi {
// Verified internal inspection format, not a serialization/linker contract.
public class CAbiDump : Object {
	private StringBuilder output = new StringBuilder ();

	public static string format(CAbiProgram program) throws CAbiError {
		CAbiVerifier.verify (program);
		string header = "(c-abi " + program.profile.spelling ();
		if (program.functions.length == 0 && program.exports.length == 0 && program.cleanups.length == 0 && program.retained_operations.length == 0 && program.class_adapters.length == 0 && program.class_imports.length == 0) {
			return header + ")\n";
		}
		var dump = new CAbiDump ();
		dump.line (0, header);
		foreach (var imported in program.class_imports) {
			dump.line (1, "(CImport declarations-v1 native-function=%d status-out %s)".printf (imported.native_function, imported.binding.identity ()));
		}
		foreach (var adapter in program.class_adapters) {
			dump.line (1, adapter.policy.dump ());
			dump.line (1, "(opaque-class #%d native-class=%d name=%s constructor=%d getter=%d setter=%d".printf (adapter.ordinal, adapter.native_class, adapter.policy.native_name, adapter.constructor, adapter.getter, adapter.setter));
			if (adapter.policy.declared_api != null) {
				var api = adapter.policy.declared_api;
				for (uint m = 0; m < api.member_count; m++) {
					dump.line (2, "(declared-member %s native-function=%d contract=%s)".printf (api.member (m).name, adapter.member_target (m), api.member (m).identity ()));
				}
			} else {
				foreach (var role in CAbiClassAdapter.roles ()) {
					dump.line (2, "(role %s symbol=%s lifetime=\"%s\")".printf (CAbiClassAdapter.suffix (role), adapter.symbol (role), CAbiClassAdapter.lifetime (role)));
				}
			}
			dump.line (1, ")");
		}
		foreach (var plan in program.retained_operations) {
			dump.line (1, plan.signal_callback == null ? "(retained-callback action=%d caller=%d block=%d instruction=%d environment=%s C-i32(opaque-context,i32))".printf (plan.action, plan.caller, plan.block, plan.instruction, plan.environment) : "(retained-signal action=%d caller=%d block=%d instruction=%d environment=%s callback=%s quiescence=GClosure-finalized)".printf (plan.action, plan.caller, plan.block, plan.instruction, plan.environment, plan.signal_callback.identity ()));
		}
		foreach (var cleanup in program.cleanups) {
			dump.line (1, "(cleanup #%d".printf (cleanup.ordinal));
			dump.line (2, "(symbol \"%s\")".printf (cleanup.external_symbol.escape ()));
			dump.write_signature (cleanup.signature);
			dump.line (1, ")");
		}
		for (int i = 0; i < program.functions.length; i++) {
			dump.write_function (program.functions[i]);
		}
		foreach (var exported in program.exports) {
			dump.line (1, "(export #%d".printf (exported.ordinal));
			dump.line (2, "(symbol \"%s\")".printf (exported.external_symbol.escape ()));
			dump.line (2, "(native-function #%d)".printf (exported.native_function_ordinal));
			dump.write_signature (exported.signature);
			dump.line (1, ")");
		}
		dump.line (0, ")");
		return dump.output.str;
	}

	private void line(int indentation, string text) {
		for (int i = 0; i < indentation; i++) {
			output.append_c ('\t');
		}
		output.append (text);
		output.append_c ('\n');
	}

	private void write_function(CAbiFunction function) {
		line (1, "(import #%d".printf (function.ordinal));
		line (2, "(name \"%s\")".printf (function.name.escape ()));
		line (2, "(symbol \"%s\")".printf (function.external_symbol.escape ()));
		if (function.owned_cleanup != null) {
			line (2, "(owned-result (cleanup #%d))".printf (function.owned_cleanup.ordinal));
		}
		if (function.metadata.text_abi != Astra.Foreign.CTextAbi.NONE) {
			line (2, function.metadata.text_abi.dump_suffix ().strip ());
		}
		if (function.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE) {
			line (2, function.metadata.buffer_abi.dump_suffix ().strip ());
		}
		if (function.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE) {
			line (2, function.metadata.record_abi.dump_suffix ().strip ());
		}
		if (function.metadata.com_import != null) {
			line (2, "(" + function.metadata.com_import.identity () + " role=" + Astra.Source.ComImportContract.suffix (function.metadata.com_role) + ")");
		}
		if (function.metadata.pointer_abi != Astra.Foreign.CPointerAbi.NONE) {
			line (2, function.metadata.pointer_abi.dump_suffix ().strip ());
		}
		if (function.metadata.import_policy == Astra.Source.DeclarationPolicyId.GOBJECT_IMPORT) {
			line (2, "(policy GObjectImport typed-C-bridge explicit-header)");
		}
		if (function.metadata.header_count > 0) {
			line (2, "(headers");
			for (int h = 0; h < function.metadata.header_count; h++) {
				line (3, "\"%s\"".printf (function.metadata.header_at (h).name.escape ()));
			}
			line (2, ")");
		}
		write_signature (function.signature);
		line (1, ")");
	}

	private static string channel_detail(CAbiScalarType type) {
		if (type == CAbiScalarType.F32) {
			return " (semantic f32) (c-type float)";
		}
		if (type == CAbiScalarType.F64) {
			return " (semantic f64) (c-type double)";
		}
		if (type == CAbiScalarType.I64) {
			return " (semantic i64) (c-type int64_t)";
		}
		if (type == CAbiScalarType.U64) {
			return " (semantic u64) (c-type uint64_t)";
		}
		return "";
	}

	private void write_signature(CAbiSignature signature) {
		line (2, "(signature");
		if (signature.bool_abi == Astra.Foreign.CBoolAbi.C99) {
			line (3, "(C99-bool i1 zeroext copied no-bool-storage)");
		}
		if (signature.result != null && signature.result.record != null && signature.result.record.union_projection != null) {
			line (3, signature.result.record.union_projection.dump ());
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.record != null && parameter.record.union_projection != null) {
				line (3, parameter.record.union_projection.dump ());
			}
		}
		if (signature.callback != null) {
			line (3, "(callback #0 PTR (native-function #%d \"%s\") (c-signature I32 PTR I32) synchronous-nonretaining)".printf (signature.callback.native_function_ordinal, signature.callback.target_name.escape ()));
		}
		if (signature.parameters.length == 0) {
			line (3, "(parameters)");
		} else {
			line (3, "(parameters");
			for (int i = 0; i < signature.parameters.length; i++) {
				var parameter = signature.parameters[i];
				if (parameter.record != null && parameter.record.by_value) {
					var record = parameter.record;
					line (4, "(parameter #%d (record-value \"%s\" size=%u align=%u %s))".printf (parameter.ordinal, record.name, record.size, record.alignment, record.memory ? "byval-stack" : "eightbyte-registers"));
					continue;
				}
				if (parameter.record != null) {
					var record = parameter.record;
					line (4, "(parameter #%d PTR (record \"%s\" size=%u align=%u borrowed-noescape)".printf (parameter.ordinal, record.name.escape (), record.size, record.alignment));
					foreach (var field in record.fields) {
						line (5, "(field \"%s\" %s offset=%u bytes=%u)".printf (field.name.escape (), field.scalar_name, field.offset, field.bytes));
					}
					line (4, ")");
					continue;
				}
				if (parameter.text != null) {
					line (4, "(parameter #%d (text-view utf8-i32) (contract borrowed-noescape)".printf (parameter.ordinal));
					foreach (var component in parameter.text.components) {
						line (5, "(component #%d %s %s)".printf (component.physical_ordinal, component.role == CAbiTextComponentRole.DATA ? "data" : "byte-length", component.scalar_type.spelling ()));
					}
					line (4, ")");
					continue;
				}
				if (parameter.buffer != null) {
					line (4, "(parameter #%d (buffer-view u8-i32 alignment=1 read-write) (contract borrowed-noescape)".printf (parameter.ordinal));
					foreach (var component in parameter.buffer.components) {
						line (5, "(component #%d %s %s)".printf (component.physical_ordinal, component.role == CAbiBufferComponentRole.DATA ? "data" : "byte-length", component.scalar_type.spelling ()));
					}
					line (4, ")");
					continue;
				}
				line (4, "(parameter #%d %s%s)".printf (parameter.ordinal, parameter.scalar_type.spelling (), parameter.pointer_contract.dump_suffix () + channel_detail (parameter.scalar_type)));
			}
			line (3, ")");
		}
		if (signature.result != null && signature.result.record != null) {
			var record = signature.result.record;
			line (3, "(result (record-value \"%s\" size=%u align=%u %s))".printf (record.name, record.size, record.alignment, record.memory ? "sret" : "registers"));
		} else {
			line (3, "(result %s)".printf (signature.result == null ? "void" : signature.result.scalar_type.spelling () + channel_detail (signature.result.scalar_type)));
		}
		line (2, ")");
	}
}
}
