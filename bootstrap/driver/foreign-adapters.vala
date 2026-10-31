// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.CAbi;

namespace Astra.Driver {
public errordomain ForeignAdapterError {
	INVALID
}
public class ForeignAdapters : Object {
	internal static string declared_type(ForeignValueType type, string prefix, HashTable<string, string>? roots = null) throws ForeignAdapterError {
		switch (type.kind) {
		case ForeignValueKind.VOID: return "void";
		case ForeignValueKind.I32:
			return "int32_t";
		case ForeignValueKind.U32:
			return "uint32_t";
		case ForeignValueKind.I64:
			return "int64_t";
		case ForeignValueKind.U64:
			return "uint64_t";
		case ForeignValueKind.F32:
			return "float";
		case ForeignValueKind.F64:
			return "double";
		case ForeignValueKind.BOOL:
			return "bool";
		case ForeignValueKind.NATIVE_OBJECT:
		case ForeignValueKind.GOBJECT:
		case ForeignValueKind.COM_OBJECT:
			if (type.kind == ForeignValueKind.COM_OBJECT && type.nominal_origin == "IUnknown") {
				return "void *";
			}
			if (roots != null) {
				var found = roots.lookup (type.nominal_origin);
				if (found == null) {
					throw new ForeignAdapterError.INVALID ("foreign handle header lost its exact nominal root declaration");
				}
				return found + "_handle *";
			}
			return prefix + "_handle *";
		case ForeignValueKind.RECORD:
			return CAbiClassAdapter.record_name (type);
		case ForeignValueKind.CALLBACK:
			return CAbiClassAdapter.callback_name (prefix, type);
		default:
			throw new ForeignAdapterError.INVALID ("declared foreign header requires a completed physical channel plan");
		}
	}
	private static void declared_header(StringBuilder text, ForeignApiContract api, HashTable<string, string> roots) throws ForeignAdapterError {
		bool internal_root = (api.active_personalities & ForeignClassPolicy.C) == 0;
		if (internal_root) {
			text.append ("#ifdef ASTRA_FOREIGN16_INTERNAL\n");
		}
		string p = api.prefix;
		var callbacks = new HashTable<string, bool> (str_hash, str_equal);
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			for (uint a = 0; a < member.parameter_count; a++) {
				var value = member.parameter (a).value_type;
				if (value.kind != ForeignValueKind.CALLBACK) {
					continue;
				}
				string name = CAbiClassAdapter.callback_name (p, value);
				if (callbacks.contains (name)) {
					continue;
				}
				callbacks.insert (name, true);
				text.append_printf ("/* Synchronous call-only callback; userdata remains caller-owned. */\ntypedef %s (*%s)(void *userdata", declared_type (value.callback_result, p, roots), name);
				for (uint c = 0; c < value.callback_parameter_count; c++) {
					text.append_printf (", %s argument%u", declared_type (value.callback_parameter (c), p, roots), c);
				}
				text.append (");\n");
			}
		}
		text.append ("\n#include <stdbool.h>\n#ifndef ASTRA_FOREIGN_ERROR_V1\n#define ASTRA_FOREIGN_ERROR_V1\ntypedef struct astra_foreign_error { int32_t domain; int32_t code; } astra_foreign_error;\nstatic inline __attribute__((unused)) void astra_foreign_error_clear(astra_foreign_error *error) { if (error) { error->domain = 0; error->code = 0; } }\n#endif\n");
		text.append_printf ("/* declarations-v1: %s owner; constructing-thread member calls; status/out publication. */\n", api.lifetime == ForeignLifetime.UNIQUE ? "unique" : "intrusive shared");
		if (api.lifetime == ForeignLifetime.UNIQUE) {
			text.append_printf ("int32_t %s_destroy(%s_handle **owner, astra_foreign_error *error);\n", p, p);
		} else if (api.declared_personalities == ForeignClassPolicy.COM || api.declared_personalities == ForeignClassPolicy.GOBJECT) {
			text.append_printf ("uint32_t %s_release(%s_handle *self);\n", p, p);
		} else {
			text.append_printf ("uint32_t %s_acquire(%s_handle *self);\nuint32_t %s_release(%s_handle *self);\ntypedef struct %s_weak_handle %s_weak_handle;\n", p, p, p, p, p, p);
			text.append_printf ("%s_weak_handle *%s_weak(%s_handle *self);\n%s_weak_handle *%s_weak_clone(%s_weak_handle *self);\n%s_handle *%s_weak_upgrade(%s_weak_handle *self);\nvoid %s_weak_release(%s_weak_handle *self);\n", p, p, p, p, p, p, p, p, p, p, p);
		}
		text.append_printf ("void *%s_root_identity(%s_handle *self);\n", p, p);
		for (uint m = 0; m < api.member_count; m++) {
			if (api.member (m).result.value_type.kind == ForeignValueKind.BYTES) {
				text.append_printf ("int32_t %s_bytes_release(uint8_t **data, int32_t *length, astra_foreign_error *error);\n", p);
				break;
			}
		}
		for (uint m = 0; m < api.member_count; m++) {
			if (api.member (m).result.value_type.kind == ForeignValueKind.TEXT) {
				text.append_printf ("int32_t %s_text_release(char **data, int32_t *length, astra_foreign_error *error);\n", p);
				break;
			}
		}
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			bool internal_member = (member.personalities & ForeignClassPolicy.C) == 0;
			if (internal_member) {
				text.append ("#ifdef ASTRA_FOREIGN16_INTERNAL\n");
			}
			if (member.error_map != null) {
				text.append_printf ("#define %s_%s_ERROR_DOMAIN INT32_C(%d)\n", p, member.name, member.error_map.domain);
				for (uint c = 0; c < member.error_map.case_count; c++) {
					var entry = member.error_map.at (c);
					text.append_printf ("#define %s_%s_ERROR_%s (INT32_C(%d))\n", p, member.name, entry.c_identifier (), entry.status);
				}
			}
			if (member.null_status != 0) {
				text.append_printf ("#define %s_%s_NULL_STATUS INT32_C(%d)\n", p, member.name, member.null_status);
			}
			declared_signature (text, api, member, false, roots);
			text.append (";\n");
			if (internal_member) {
				text.append ("#endif\n");
			}
		}
		if (internal_root) {
			text.append ("#endif\n");
		}
	}
	internal static void declared_signature(StringBuilder text, ForeignApiContract api, ForeignMemberContract member, bool canonical, HashTable<string, string> roots, bool importing = false) throws ForeignAdapterError {
		string p = api.prefix;
		text.append_printf ("int32_t %s(", importing ? "astra_foreign16_import_" + p + "_" + member.name : CAbiClassAdapter.member_symbol (api, member, canonical));
		bool comma = member.kind != ForeignMemberKind.CONSTRUCTOR;
		if (comma) {
			text.append_printf ("%s_handle *self", p);
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			if (comma) {
				text.append (", ");
			}
			var channel = member.parameter (a);
			if (channel.by_reference) {
				text.append_printf ("%s%s *argument%u", channel.direction == ForeignDirection.IN ? "const " : "", declared_type (channel.value_type, p, roots), a);
			} else if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("%s argument%u, void *argument%u_data", declared_type (channel.value_type, p, roots), a, a);
			} else if (CAbiClassAdapter.byte_sequence (channel.value_type.kind)) {
				text.append_printf ("%s%s *argument%u", channel.direction == ForeignDirection.IN ? "const " : "", channel.value_type.kind == ForeignValueKind.TEXT ? "char" : "uint8_t", a);
				if (channel.intrinsic_length) {
					text.append_printf (", int32_t argument%u_%s", a, channel.direction == ForeignDirection.IN ? "length" : "capacity");
				}
			} else if (canonical && channel.value_type.kind == ForeignValueKind.RECORD) {
				text.append_printf ("const %s *argument%u", declared_type (channel.value_type, p, roots), a);
			} else if (channel.value_type.object_handle () && channel.transfer == ForeignTransfer.OWN) {
				text.append_printf ("%s *argument%u", declared_type (channel.value_type, p, roots), a);
			} else {
				text.append_printf ("%s argument%u", declared_type (channel.value_type, p, roots), a);
			}
			comma = true;
		}
		if (member.result.value_type.kind != ForeignValueKind.VOID) {
			if (comma) {
				text.append (", ");
			}
			if (member.result.value_type.kind == ForeignValueKind.BYTES) {
				text.append ("uint8_t **result, int32_t *result_length");
			} else if (member.result.value_type.kind == ForeignValueKind.TEXT) {
				text.append ("char **result, int32_t *result_length");
			} else {
				text.append_printf ("%s *result", declared_type (member.result.value_type, p, roots));
			}
			comma = true;
		}
		if (comma) {
			text.append (", ");
		}
		text.append ("astra_foreign_error *error)");
	}
	private static void record_header(StringBuilder text, ForeignValueType type, HashTable<string, string> seen) throws ForeignAdapterError {
		if (type.kind != ForeignValueKind.RECORD) {
			return;
		}
		if (!type.valid ()) {
			throw new ForeignAdapterError.INVALID ("foreign POD header requires a valid scalar record declaration");
		}
		string name = CAbiClassAdapter.record_name (type), identity = type.identity ();
		if (seen.contains (name)) {
			if (seen.lookup (name) != identity) {
				throw new ForeignAdapterError.INVALID ("foreign record C identifier collision");
			}
			return;
		}
		seen.insert (name, identity);
		text.append_printf ("/* POD %s: target C natural scalar layout. */\ntypedef struct %s {\n", type.nominal_origin, name);
		for (uint f = 0; f < type.field_count; f++) {
			text.append_printf ("\t%s %s;\n", declared_type (new ForeignValueType (type.field (f).kind), ""), CAbiClassAdapter.record_field_name (type.field (f), f));
		}
		text.append_printf ("} %s;\n#ifdef __cplusplus\n", name);
		string cpp = "static_assert", c = "_Static_assert";
		foreach (string assertion in new string[] { cpp, c }) {
			text.append_printf ("%s(sizeof(%s) == %u, \"foreign POD size\");\n", assertion, name, CAbiClassAdapter.record_size (type));
			text.append_printf ("%s(%s(%s) == %u, \"foreign POD alignment\");\n", assertion, assertion == cpp ? "alignof" : "_Alignof", name, CAbiClassAdapter.record_alignment (type));
			for (uint f = 0; f < type.field_count; f++) {
				text.append_printf ("%s(offsetof(%s, %s) == %u, \"foreign POD offset\");\n", assertion, name, CAbiClassAdapter.record_field_name (type.field (f), f), CAbiClassAdapter.record_offset (type, f));
			}
			text.append (assertion == cpp ? "#else\n" : "#endif\n");
		}
	}
	internal static HashTable<string, string> root_prefixes(CheckedProgram program) {
		var roots = new HashTable<string, string> (str_hash, str_equal);
		foreach (var owner in program.classes) {
			var api = owner.foreign_export == null ? null : owner.foreign_export.declared_api;
			if (api != null) {
				roots.insert (api.native_origin, api.prefix);
			}
		}
		foreach (var handle in program.handles) {
			if (handle.c_import != null) {
				roots.insert (handle.c_import.api.native_origin, handle.c_import.api.prefix);
			}
		}
		return roots;
	}
	public static string source(CheckedProgram program) throws ForeignAdapterError {
		var roots = root_prefixes (program);
		var text = new StringBuilder ("#define ASTRA_FOREIGN16_INTERNAL\n" + header (program));
		text.append ("\n/* Mechanical target-C record forwarding. Native algorithms are linked Astra code. */\n#ifdef __cplusplus\nextern \"C\" {\n#endif\n");
		foreach (var owner in program.classes) {
			var api = owner.foreign_export == null ? null : owner.foreign_export.declared_api;
			if (api == null || api.active_personalities == 0) {
				continue;
			}
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!CAbiClassAdapter.record_forwarder (member)) {
					continue;
				}
				text.append ("extern ");
				declared_signature (text, api, member, true, roots);
				text.append (";\n");
				declared_signature (text, api, member, false, roots);
				text.append_printf (" {\n\treturn %s(", CAbiClassAdapter.member_symbol (api, member, true));
				bool comma = member.kind != ForeignMemberKind.CONSTRUCTOR;
				if (comma) {
					text.append ("self");
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					if (comma) {
						text.append (", ");
					}
					var channel = member.parameter (a);
					text.append_printf ("%sargument%u", channel.value_type.kind == ForeignValueKind.RECORD ? "&" : "", a);
					if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
						text.append_printf (", argument%u_data", a);
					}
					if (CAbiClassAdapter.byte_sequence (channel.value_type.kind) && channel.intrinsic_length) {
						text.append_printf (", argument%u_%s", a, channel.direction == ForeignDirection.IN ? "length" : "capacity");
					}
					comma = true;
				}
				if (member.result.value_type.kind != ForeignValueKind.VOID) {
					if (comma) {
						text.append (", ");
					}
					text.append ("result");
					if (CAbiClassAdapter.byte_sequence (member.result.value_type.kind)) {
						text.append (", result_length");
					}
					comma = true;
				}
				if (comma) {
					text.append (", ");
				}
				text.append ("error);\n}\n");
			}
		}
		foreach (var handle in program.handles) {
			if (handle.c_import == null || handle.c_import.api.active_personalities == 0) {
				continue;
			}
			var api = handle.c_import.api;
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!CAbiClassAdapter.record_forwarder (member)) {
					continue;
				}
				declared_signature (text, api, member, true, roots, true);
				text.append_printf (" {\n\treturn %s_%s(", api.prefix, member.name);
				bool comma = member.kind != ForeignMemberKind.CONSTRUCTOR;
				if (comma) {
					text.append ("self");
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					if (comma) {
						text.append (", ");
					}
					var channel = member.parameter (a);
					text.append_printf ("%sargument%u", channel.value_type.kind == ForeignValueKind.RECORD ? "*" : "", a);
					if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
						text.append_printf (", argument%u_data", a);
					}
					if (CAbiClassAdapter.byte_sequence (channel.value_type.kind) && channel.intrinsic_length) {
						text.append_printf (", argument%u_%s", a, channel.direction == ForeignDirection.IN ? "length" : "capacity");
					}
					comma = true;
				}
				if (member.result.value_type.kind != ForeignValueKind.VOID) {
					if (comma) {
						text.append (", ");
					}
					text.append ("result");
					if (CAbiClassAdapter.byte_sequence (member.result.value_type.kind)) {
						text.append (", result_length");
					}
					comma = true;
				}
				if (comma) {
					text.append (", ");
				}
				text.append ("error);\n}\n");
			}
		}
		text.append ("#ifdef __cplusplus\n}\n#endif\n");
		return text.str;
	}
	public static string header(CheckedProgram program) throws ForeignAdapterError {
		var identities = new StringBuilder ();
		foreach (var handle in program.handles) {
			if (handle.c_import != null) {
				identities.append (handle.c_import.api.identity ());
				identities.append_c ('\n');
			}
		}
		foreach (var owner in program.classes) {
			if (owner.foreign_export != null) {
				identities.append (owner.foreign_export.identity ());
				identities.append_c ('\n');
			}
		}
		string guard = "ASTRA_FOREIGN_CLASSES_V1_" + Checksum.compute_for_string (ChecksumType.SHA256, identities.str).up () + "_H";
		var text = new StringBuilder ("/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */\n/* Generated from checked Astra foreign Class policies; opaque C ABI version 1. */\n#ifndef " + guard + "\n#define " + guard + "\n#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n#ifdef __cplusplus\nextern \"C\" {\n#endif\n");
		var roots = root_prefixes (program);
		foreach (var owner in program.classes) {
			var api = owner.foreign_export == null ? null : owner.foreign_export.declared_api;
			if (api != null) {
				text.append_printf ("typedef struct %s_handle %s_handle;\n", api.prefix, api.prefix);
			}
		}
		foreach (var handle in program.handles) {
			if (handle.c_import != null) {
				var api = handle.c_import.api;
				text.append_printf ("typedef struct %s_handle %s_handle;\n", api.prefix, api.prefix);
			}
		}
		var seen_records = new HashTable<string, string> (str_hash, str_equal);
		foreach (var owner in program.classes) {
			var api = owner.foreign_export == null ? null : owner.foreign_export.declared_api;
			if (api == null || api.active_personalities == 0) {
				continue;
			}
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				for (uint a = 0; a < member.parameter_count; a++) {
					record_header (text, member.parameter (a).value_type, seen_records);
				}
				record_header (text, member.result.value_type, seen_records);
			}
		}
		int count = 0;
		foreach (var handle in program.handles) {
			if (handle.c_import == null || handle.c_import.api.active_personalities == 0) {
				continue;
			}
			var api = handle.c_import.api;
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				for (uint p = 0; p < member.parameter_count; p++) {
					record_header (text, member.parameter (p).value_type, seen_records);
				}
				record_header (text, member.result.value_type, seen_records);
			}
			declared_header (text, api, roots);
			count++;
		}
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy == null || policy.active_personalities == 0) {
				continue;
			}
			if (!ForeignClassPolicy.matches (policy, ((ClassType) owner.semantic_type).foreign_policy_identity, owner.name)) {
				throw new ForeignAdapterError.INVALID ("foreign Class header lost its admitted policy identity");
			}
			count++;
			if (policy.declared_api != null) {
				declared_header (text, policy.declared_api, roots);
				continue;
			}
			string p = policy.prefix;
			text.append_printf ("\n/* %s: native Shared root, explicit acquire/release, constructing-thread data calls. */\n", owner.name);
			text.append_printf ("typedef struct %s_handle %s_handle;\ntypedef struct %s_weak_handle %s_weak_handle;\n", p, p, p, p);
			text.append_printf ("%s_handle *%s_create(int32_t value);\nuint32_t %s_acquire(%s_handle *self);\nuint32_t %s_release(%s_handle *self);\n", p, p, p, p, p, p);
			text.append_printf ("int32_t %s_get(%s_handle *self, int32_t *out);\nint32_t %s_set(%s_handle *self, int32_t value);\nvoid *%s_root_identity(%s_handle *self);\n", p, p, p, p, p, p);
			text.append_printf ("%s_weak_handle *%s_weak(%s_handle *self);\n%s_weak_handle *%s_weak_clone(%s_weak_handle *self);\n%s_handle *%s_weak_upgrade(%s_weak_handle *self);\nvoid %s_weak_release(%s_weak_handle *self);\n", p, p, p, p, p, p, p, p, p, p, p);
			text.append ("#ifdef ASTRA_FOREIGN14_INTERNAL\n");
			text.append_printf ("int32_t astra_foreign14_%s_check_thread(%s_handle *self);\nvoid *astra_foreign14_%s_personality(%s_handle *self);\nint32_t astra_foreign14_%s_attach(%s_handle *self, void *personality, void (*destroy)(void *));\n", p, p, p, p, p, p);
			text.append ("#endif\n");
		}
		if (count == 0) {
			throw new ForeignAdapterError.INVALID ("no checked foreign Class exports were selected");
		}
		text.append ("\n#ifdef __cplusplus\n}\n#endif\n#endif\n");
		return text.str;
	}
}
}
