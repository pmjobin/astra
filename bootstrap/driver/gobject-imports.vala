// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.CAbi;
namespace Astra.Driver {
// Checked GLib calls and reference retirement; no provider algorithms live here.
internal class GObjectImports : Object {
	private static string scalar(ForeignValueType type) throws ForeignAdapterError {
		switch (type.kind) {
		case ForeignValueKind.VOID:
			return "void";
		case ForeignValueKind.I32:
			return "gint";
		case ForeignValueKind.U32:
			return "guint";
		case ForeignValueKind.I64:
			return "gint64";
		case ForeignValueKind.U64:
			return "guint64";
		case ForeignValueKind.F32:
			return "gfloat";
		case ForeignValueKind.F64:
			return "gdouble";
		case ForeignValueKind.BOOL:
			return "gboolean";
		default:
			throw new ForeignAdapterError.INVALID ("GObject import channel requires its completed physical conversion plan");
		}
	}

	private static string convert(ForeignValueType type, string value, bool to_glib) throws ForeignAdapterError {
		return type.kind == ForeignValueKind.BOOL ? "(" + value + (to_glib ? " ? TRUE : FALSE)" : " != FALSE)") : "(" + (to_glib ? scalar (type) : ForeignAdapters.declared_type (type, "")) + ")(" + value + ")";
	}

	private static ForeignImportContract object_root(CheckedProgram program, ForeignValueType type) throws ForeignAdapterError {
		foreach (var handle in program.handles) {
			var root = handle.c_import;
			if (root != null && root.gobject != null && root.api.native_origin == type.nominal_origin && root.valid ()) {
				return root;
			}
		}
		throw new ForeignAdapterError.INVALID ("GObject channel requires its exact imported GType and foreign reference authority");
	}

	private static void object_inputs(StringBuilder text, CheckedProgram program, ForeignImportContract root, ForeignMemberContract member) throws ForeignAdapterError {
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind != ForeignValueKind.GOBJECT) {
				continue;
			}
			string p = object_root (program, channel.value_type).api.prefix;
			string value = channel.transfer == ForeignTransfer.OWN ? "*argument%u".printf (a) : "argument%u".printf (a);
			if (channel.transfer == ForeignTransfer.OWN) {
				text.append_printf ("if (!argument%u) ", a);
				report (text, root, member, "(int32_t)UINT32_C(0x80004003)");
			}
			if (!channel.nullable) {
				text.append_printf ("if (!%s) ", value);
				report (text, root, member, "(int32_t)UINT32_C(0x80004003)");
			}
			text.append_printf ("if (%s) { int32_t status = %s_context(%s); if (status%s) ", value, p, value, channel.transfer == ForeignTransfer.OWN ? " || (" + value + ")->retired" : "");
			report (text, root, member, "status ? status : (int32_t)UINT32_C(0x80070057)");
			text.append ("}\n");
			if (channel.transfer == ForeignTransfer.BORROW) {
				text.append_printf ("int32_t object_status%u = astra_foreign16_%s_borrow_acquire(argument%u); if (object_status%u) ", a, p, a, a);
				report (text, root, member, "object_status%u".printf (a));
				text.append_printf ("__attribute__((cleanup(%s_unpin))) %s_handle *input_pin%u = argument%u;\n", p, p, a, a);
			}
		}
	}

	private static bool sequence(ForeignChannel channel) {
		return channel.value_type.kind == ForeignValueKind.BYTES || channel.value_type.kind == ForeignValueKind.TEXT;
	}

	private static string physical_result(ForeignChannel channel, CheckedProgram program) throws ForeignAdapterError {
		return channel.value_type.kind == ForeignValueKind.GOBJECT ? object_root (program, channel.value_type).gobject.type_name + " *" : sequence (channel) ? channel.encoding == ForeignTextEncoding.UTF8_NUL ? "gchar *" : "GBytes *" : scalar (channel.value_type);
	}

	private static ForeignGObjectRecordBinding record(ForeignImportContract root, ForeignValueType type) throws ForeignAdapterError {
		var binding = root.gobject.record (type);
		if (binding == null || !binding.valid ()) {
			throw new ForeignAdapterError.INVALID ("GObject POD import requires its exact boxed SDK binding");
		}
		return binding;
	}

	private static string record_helper(ForeignImportContract root, ForeignValueType type) {
		return root.api.prefix + "_record_" + Checksum.compute_for_string (ChecksumType.SHA256, type.identity ());
	}

	private static void records(StringBuilder text, ForeignImportContract root) throws ForeignAdapterError {
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (uint m = 0; m < root.api.member_count; m++) {
			var member = root.api.member (m);
			for (uint v = 0; v <= member.parameter_count; v++) {
				var type = v == member.parameter_count ? member.result.value_type : member.parameter (v).value_type;
				if (type.kind != ForeignValueKind.RECORD) {
					continue;
				}
				string helper = record_helper (root, type);
				if (seen.contains (helper)) {
					continue;
				}
				seen.insert (helper, true);
				var binding = record (root, type);
				var layout = new ForeignGObjectRecordLayout (type);
				string native = ForeignAdapters.declared_type (type, "");
				text.append_printf ("_Static_assert(sizeof(%s) == %u && _Alignof(%s) == %u, \"imported boxed POD storage\");\n", binding.type_name, layout.size, binding.type_name, layout.alignment);
				for (uint f = 0; f < type.field_count; f++) {
					string field = CAbiClassAdapter.record_field_name (type.field (f), f);
					text.append_printf ("_Static_assert(offsetof(%s, %s) == %u && _Generic(((%s *)0)->%s, %s: 1, default: 0), \"imported boxed POD field\");\n", binding.type_name, field, layout.offset (f), binding.type_name, field, scalar (new ForeignValueType (type.field (f).kind)));
				}
				text.append_printf ("static inline void %s_free(%s **value) { if (*value) %s_free(*value); }\nstatic inline gboolean %s_valid(void) { return G_TYPE_FUNDAMENTAL(%s_get_type()) == G_TYPE_BOXED; }\n", helper, binding.type_name, binding.symbol_prefix, helper, binding.symbol_prefix);
				text.append_printf ("static inline %s %s_from_native(%s input) { %s value = {0};\n", binding.type_name, helper, native, binding.type_name);
				for (uint f = 0; f < type.field_count; f++) {
					string field = CAbiClassAdapter.record_field_name (type.field (f), f);
					text.append_printf ("value.%s = %s;\n", field, convert (new ForeignValueType (type.field (f).kind), "input." + field, true));
				}
				text.append ("return value; }\n");
				text.append_printf ("static inline %s %s_to_native(const %s *input) { %s value = {0};\n", native, helper, binding.type_name, native);
				for (uint f = 0; f < type.field_count; f++) {
					string field = CAbiClassAdapter.record_field_name (type.field (f), f);
					text.append_printf ("value.%s = %s;\n", field, convert (new ForeignValueType (type.field (f).kind), "input->" + field, false));
				}
				text.append ("return value; }\n");
			}
		}
	}

	private static string? capacity_slot(ForeignMemberContract member, uint parameter) {
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (sequence (channel) && channel.direction != ForeignDirection.IN && !channel.intrinsic_length && channel.capacity_index == parameter) {
				return "capacity%u".printf (a);
			}
		}
		return null;
	}

	private static string input_count(ForeignChannel channel, uint a) {
		return channel.intrinsic_length ? "argument%u_%s".printf (a, channel.direction == ForeignDirection.IN ? "length" : "capacity") : "argument%d".printf (channel.direction == ForeignDirection.IN ? channel.length_index : channel.capacity_index);
	}

	private static void sequences(StringBuilder text, ForeignImportContract root, ForeignMemberContract member) {
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (!sequence (channel) || channel.encoding == ForeignTextEncoding.UTF8_NUL) {
				continue;
			}
			string count = input_count (channel, a);
			text.append_printf ("if (%s < 0 || (%s && !argument%u)%s) ", count, count, a, channel.nullable ? "" : " || !argument%u".printf (a));
			report (text, root, member, "(int32_t)UINT32_C(0x80070057)");
			if (channel.direction == ForeignDirection.IN) {
				text.append_printf ("g_autoptr(GBytes) sequence%u = argument%u ? g_bytes_new_static(argument%u, (gsize)%s) : NULL;\n", a, a, a, count);
			} else {
				text.append_printf ("guint8 *output%u = argument%u; gint capacity%u = %s;\n", a, a, a, count);
			}
		}
	}

	private static string callback_name(ForeignImportContract root, ForeignValueType type) {
		return root.api.prefix + "_glib_callback_" + Checksum.compute_for_string (ChecksumType.SHA256, type.identity ());
	}

	private static void callbacks(StringBuilder text, ForeignImportContract root) throws ForeignAdapterError {
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (uint m = 0; m < root.api.member_count; m++) {
			var member = root.api.member (m);
			for (uint a = 0; a < member.parameter_count; a++) {
				var type = member.parameter (a).value_type;
				if (type.kind != ForeignValueKind.CALLBACK) {
					continue;
				}
				string name = callback_name (root, type);
				if (seen.contains (name)) {
					continue;
				}
				seen.insert (name, true);
				text.append_printf ("typedef struct { %s code; void *data; } %s_Context;\nstatic inline %s %s_thunk(gpointer opaque", ForeignAdapters.declared_type (type, root.api.prefix), name, scalar (type.callback_result), name);
				for (uint p = 0; p < type.callback_parameter_count; p++) {
					text.append_printf (", %s argument%u", scalar (type.callback_parameter (p)), p);
				}
				text.append_printf (") { %s_Context *context = opaque;\n", name);
				string call = "context->code(context->data";
				for (uint p = 0; p < type.callback_parameter_count; p++) {
					call += ", " + convert (type.callback_parameter (p), "argument%u".printf (p), false);
				}
				call += ")";
				text.append (type.callback_result.kind == ForeignValueKind.VOID ? call + ";\n}\n" : "return " + convert (type.callback_result, call, true) + ";\n}\n");
			}
		}
	}

	private static void report(StringBuilder text, ForeignImportContract root, ForeignMemberContract member, string status, string glib_error = "NULL") {
		string mapped = "0";
		if (member.error_map != null) {
			for (uint c = 0; c < member.error_map.case_count; c++) {
				mapped += " || failure == INT32_C(%d)".printf (member.error_map.at (c).status);
			}
		}
		text.append_printf ("{ int32_t failure = %s; GError *reported = %s; if (error) { error->domain = reported && reported->domain == g_quark_from_static_string(\"astra-foreign-domain-%d\") && (%s) ? %d : 0; error->code = failure; } if (reported) g_error_free(reported); return failure; }\n", status, glib_error, member.error_map == null ? 0 : member.error_map.domain, mapped, member.error_map == null ? 0 : member.error_map.domain);
	}

	private static void method(StringBuilder text, ForeignImportContract root, ForeignMemberContract member, HashTable<string, string> roots, CheckedProgram program) throws ForeignAdapterError {
		string p = root.api.prefix, target = root.gobject.symbol_prefix;
		bool factory = member.kind == ForeignMemberKind.CONSTRUCTOR, result = !factory && member.result.value_type.kind != ForeignValueKind.VOID;
		ForeignAdapters.declared_signature (text, root.api, member, false, roots);
		text.append (" {\nif (error) astra_foreign_error_clear(error);\n");
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind != ForeignValueKind.GOBJECT || channel.transfer != ForeignTransfer.OWN) {
				continue;
			}
			if (factory || result) {
				text.append_printf ("if ((void *)argument%u == (void *)result) ", a);
				report (text, root, member, "(int32_t)UINT32_C(0x80070057)");
			}
			for (uint b = 0; b < a; b++) {
				var previous = member.parameter (b);
				if (previous.value_type.kind != ForeignValueKind.GOBJECT || previous.transfer != ForeignTransfer.OWN) {
					continue;
				}
				text.append_printf ("if ((void *)argument%u == (void *)argument%u || (argument%u && argument%u && *argument%u && (void *)*argument%u == (void *)*argument%u)) ", a, b, a, b, a, a, b);
				report (text, root, member, "(int32_t)UINT32_C(0x80070057)");
			}
		}

		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference) {
				text.append_printf ("%s reference%u = %s;\n", scalar (channel.value_type), a, channel.direction == ForeignDirection.OUT ? "0" : "argument%u ? %s : 0".printf (a, convert (channel.value_type, "*argument%u".printf (a), true)));
			}
		}
		if (factory || result) {
			text.append ("if (!result) ");
			report (text, root, member, "(int32_t)UINT32_C(0x80004003)");
			text.append ("*result = NULL;\n".replace ("NULL", factory || sequence (member.result) || member.result.value_type.kind == ForeignValueKind.GOBJECT ? "NULL" : member.result.value_type.kind == ForeignValueKind.RECORD ? "(" + ForeignAdapters.declared_type (member.result.value_type, "") + "){0}" : "0"));
			if (!factory && sequence (member.result)) {
				text.append ("if (!result_length) ");
				report (text, root, member, "(int32_t)UINT32_C(0x80004003)");
				text.append ("*result_length = 0;\n");
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference && channel.direction == ForeignDirection.OUT) {
				text.append_printf ("if (argument%u) *argument%u = 0;\n", a, a);
			}
			if (channel.by_reference || channel.value_type.kind == ForeignValueKind.CALLBACK && !channel.nullable) {
				text.append_printf ("if (!argument%u) ", a);
				report (text, root, member, "(int32_t)UINT32_C(0x80004003)");
			}
		}
		sequences (text, root, member);
		if (!factory) {
			text.append_printf ("int32_t context = astra_foreign16_%s_borrow_acquire(self); if (context) ", p);
			report (text, root, member, "context");
			text.append_printf ("__attribute__((cleanup(%s_unpin))) %s_handle *pin = self;\n", p, p);
		}
		object_inputs (text, program, root, member);
		for (uint a = 0; a < member.parameter_count; a++) {
			var type = member.parameter (a).value_type;
			if (type.kind != ForeignValueKind.RECORD) {
				continue;
			}
			var binding = record (root, type);
			string helper = record_helper (root, type);
			text.append_printf ("if (!%s_valid()) ", helper);
			report (text, root, member, "(int32_t)UINT32_C(0x80004002)");
			text.append_printf ("%s record%u = %s_from_native(argument%u);\n", binding.type_name, a, helper, a);
		}

		for (uint a = 0; a < member.parameter_count; a++) {
			var type = member.parameter (a).value_type;
			if (type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("%s_Context callback%u = {argument%u, argument%u_data};\n", callback_name (root, type), a, a, a);
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind != ForeignValueKind.GOBJECT) {
				continue;
			}
			var other = object_root (program, channel.value_type);
			text.append_printf ("%s *object%u = (%s *)%s;\n", other.gobject.type_name, a, other.gobject.type_name, channel.transfer == ForeignTransfer.OWN ? other.api.prefix + "_extract(argument%u)".printf (a) : "(argument%u ? argument%u->view : NULL)".printf (a, a));
		}
		text.append ("GError *foreign = NULL;\n");
		if (factory) {
			text.append ("g_autoptr(GObject) value = (GObject *)");
		} else {
			if (result && member.result.value_type.kind == ForeignValueKind.RECORD) {
				var binding = record (root, member.result.value_type);
				string helper = record_helper (root, member.result.value_type);
				text.append_printf ("if (!%s_valid()) ", helper);
				report (text, root, member, "(int32_t)UINT32_C(0x80004002)");
				text.append_printf ("__attribute__((cleanup(%s_free))) %s *value = NULL;\n", helper, binding.type_name);
			} else if (result && member.result.value_type.kind == ForeignValueKind.GOBJECT) {
				text.append_printf ("__attribute__((cleanup(%s_foreign_unref))) %s value = NULL;\n", object_root (program, member.result.value_type).api.prefix, physical_result (member.result, program));
			} else if (result) {
				text.append_printf ("%s%s value = 0;\n", sequence (member.result) ? member.result.encoding == ForeignTextEncoding.UTF8_NUL ? "g_autofree " : "g_autoptr(GBytes) " : "", sequence (member.result) && member.result.encoding != ForeignTextEncoding.UTF8_NUL ? "" : physical_result (member.result, program));
			}
			text.append ("gboolean ok = ");
		}
		text.append (target + (factory ? "_new(" : "_try_" + member.name + "("));
		bool comma = !factory;
		if (!factory) {
			text.append_printf ("(%s *)self->view", root.gobject.type_name);
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			if (comma) {
				text.append (", ");
			}
			var channel = member.parameter (a);
			if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("argument%u ? %s_thunk : NULL, argument%u ? &callback%u : NULL", a, callback_name (root, channel.value_type), a, a);
			} else if (channel.value_type.kind == ForeignValueKind.RECORD) {
				text.append_printf ("&record%u", a);
			} else if (channel.value_type.kind == ForeignValueKind.GOBJECT) {
				text.append_printf ("object%u", a);
			} else if (sequence (channel)) {
				text.append (channel.encoding == ForeignTextEncoding.UTF8_NUL ? "(gchar *)argument%u".printf (a) : channel.direction == ForeignDirection.IN ? "sequence%u".printf (a) : channel.intrinsic_length ? "&output%u, &capacity%u".printf (a, a) : "&output%u".printf (a));
			} else if (capacity_slot (member, a) != null) {
				text.append ("&" + capacity_slot (member, a));
			} else {
				text.append (channel.by_reference ? (channel.direction == ForeignDirection.IN ? "reference%u".printf (a) : "&reference%u".printf (a)) : convert (channel.value_type, "argument%u".printf (a), true));
			} comma = true;
		}
		if (result) {
			text.append_printf ("%s&value", comma ? ", " : "");
			comma = true;
		}
		text.append_printf ("%s&foreign);\n", comma ? ", " : "");
		text.append (factory ? "if (!value || foreign) {\n" : "if (!ok || foreign) {\n");
		report (text, root, member, "foreign && foreign->code < 0 ? foreign->code : (int32_t)UINT32_C(0x8000ffff)", "foreign");
		text.append ("}\n");
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (sequence (channel) && channel.direction != ForeignDirection.IN) {
				text.append_printf ("if (output%u != argument%u || capacity%u != %s) ", a, a, a, input_count (channel, a));
				report (text, root, member, "(int32_t)UINT32_C(0x8000ffff)");
			}
		}
		if (factory) {
			text.append_printf ("int32_t adopted = %s_adopt(g_steal_pointer(&value), result); if (adopted) ", p);
			report (text, root, member, "adopted");
		} else if (result && member.result.value_type.kind == ForeignValueKind.GOBJECT) {
			if (!member.result.nullable) {
				text.append ("if (!value) ");
				report (text, root, member, "(int32_t)UINT32_C(0x8000ffff)");
			}
			text.append_printf ("if (value) { int32_t adopted = %s_adopt((GObject *)g_steal_pointer(&value), result); if (adopted) ", object_root (program, member.result.value_type).api.prefix);
			report (text, root, member, "adopted");
			text.append ("}\n");
		} else if (result && sequence (member.result)) {
			text.append ("if (!value) ");
			report (text, root, member, "(int32_t)UINT32_C(0x8000ffff)");
			text.append (member.result.encoding == ForeignTextEncoding.UTF8_NUL ? "gsize count = strlen(value); const void *data = value;\n" : "gsize count = 0; const void *data = g_bytes_get_data(value, &count);\n");
			text.append ("if (count > G_MAXINT32 || (count && !data)) ");
			report (text, root, member, "(int32_t)UINT32_C(0x8000ffff)");
			text.append (member.result.encoding == ForeignTextEncoding.UTF8_NUL ? "void *copy = g_try_malloc(count + 1); if (!copy) " : "void *copy = count ? g_try_malloc(count) : NULL; if (count && !copy) ");
			report (text, root, member, "(int32_t)UINT32_C(0x8007000e)");
			text.append ("if (count) { memcpy(copy, data, count); }\n");
			if (member.result.encoding == ForeignTextEncoding.UTF8_NUL) {
				text.append ("((char *)copy)[count] = 0;\n");
			}
			text.append ("*result = copy; *result_length = (int32_t)count;\n");
		} else if (result && member.result.value_type.kind == ForeignValueKind.RECORD) {
			text.append ("if (!value) ");
			report (text, root, member, "(int32_t)UINT32_C(0x8000ffff)");
			text.append_printf ("*result = %s_to_native(value);\n", record_helper (root, member.result.value_type));
		} else if (result) {
			text.append_printf ("*result = %s;\n", convert (member.result.value_type, "value", false));
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference && channel.direction != ForeignDirection.IN) {
				text.append_printf ("*argument%u = %s;\n", a, convert (channel.value_type, "reference%u".printf (a), false));
			}
		}
		text.append ("return 0;\n}\n");
	}

	internal static string generate(CheckedProgram program, bool implementation) throws ForeignAdapterError {
		var imports = new GenericArray<ForeignImportContract> ();
		foreach (var handle in program.handles) {
			var root = handle.c_import;
			if (root == null || root.gobject == null || root.api.active_personalities == 0) {
				continue;
			}
			if (!ForeignImportContract.matches (root, handle.semantic_type.foreign_policy_identity, handle.name, handle.cleanup.external_symbol)) {
				throw new ForeignAdapterError.INVALID ("GObject import lost exact GType, reference and checked member authority");
			}
			imports.add (root);
		}
		if (imports.length == 0) {
			return "";
		}
		foreach (var root in imports) {
			for (uint m = 0; m < root.api.member_count; m++) {
				var member = root.api.member (m);
				if (member.kind != ForeignMemberKind.CONSTRUCTOR) {
					if (member.result.value_type.kind == ForeignValueKind.RECORD) {
						record (root, member.result.value_type);
					} else {
						physical_result (member.result, program);
					}
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					if (member.parameter (a).value_type.kind != ForeignValueKind.CALLBACK && !sequence (member.parameter (a)) && member.parameter (a).value_type.kind != ForeignValueKind.GOBJECT && member.parameter (a).value_type.kind != ForeignValueKind.RECORD) {
						scalar (member.parameter (a).value_type);
					}
				}
			}
		}
		var text = new StringBuilder ((implementation ? "#define ASTRA_FOREIGN16_INTERNAL\n" : "") + ForeignAdapters.header (program));
		if (!implementation) {
			var included = new HashTable<string, bool> (str_hash, str_equal);
			foreach (var root in imports) {
				if (!included.contains (root.gobject.header)) {
					text.append_printf ("\n#include \"%s\"\n", root.gobject.header);
					included.insert (root.gobject.header, true);
				}
			}
			return text.str;
		}
		text.append ("\n#include <glib-object.h>\n#include <stdint.h>\n#include <string.h>\nextern uint64_t astra_foreign14_thread_identity(void);\n_Static_assert(sizeof(gboolean) == 4 && sizeof(void*) == 8, \"GObject import LP64 transport\");\n");
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var root in imports) {
			if (!seen.contains (root.gobject.header)) {
				text.append_printf ("#include \"%s\"\n", root.gobject.header);
				seen.insert (root.gobject.header, true);
			}
		}
		foreach (var root in imports) {
			string p = root.api.prefix;
			text.append_printf ("struct %s_handle { GObject *view; uint64_t thread; uint32_t active; gboolean retired; };\nstatic int32_t %s_context(%s_handle *);\nstatic int32_t %s_adopt(GObject *, %s_handle **);\nstatic inline void %s_unpin(%s_handle **);\nint32_t astra_foreign16_%s_borrow_acquire(%s_handle *);\nuint32_t astra_foreign16_%s_borrow_release(%s_handle *);\nstatic GObject *%s_extract(%s_handle **);\nstatic inline void %s_foreign_unref(%s **view) { if (*view) g_object_unref(*view); }\n", p, p, p, p, p, p, p, p, p, p, p, p, p, p, root.gobject.type_name);
		}
		foreach (var root in imports) {
			records (text, root);
			callbacks (text, root);
			string p = root.api.prefix;
			foreach (var kind in new ForeignValueKind[] { ForeignValueKind.BYTES, ForeignValueKind.TEXT }) {
				bool used = false;
				for (uint m = 0; m < root.api.member_count; m++) {
					used |= root.api.member (m).result.value_type.kind == kind;
				}
				if (!used) {
					continue;
				}
				text.append_printf ("int32_t %s_%s_release(%s **data, int32_t *length, astra_foreign_error *error) { if (error) astra_foreign_error_clear(error); if (!data || !length) { if (error) error->code = (int32_t)UINT32_C(0x80004003); return (int32_t)UINT32_C(0x80004003); } void *value = *data; *data = NULL; *length = 0; g_free(value); return 0; }\n", p, kind == ForeignValueKind.TEXT ? "text" : "bytes", kind == ForeignValueKind.TEXT ? "char" : "uint8_t");
			}
			text.append ("""
static int32_t @P@_context(@P@_handle *self) { if (!self) return (int32_t)UINT32_C(0x80004003); if (self->thread != astra_foreign14_thread_identity()) return (int32_t)UINT32_C(0x8001010e); if (self->retired && !self->active) return (int32_t)UINT32_C(0x80004003); if (!G_TYPE_CHECK_INSTANCE_TYPE(self->view, @TYPE@_get_type())) return (int32_t)UINT32_C(0x80004002); return 0; }
int32_t astra_foreign16_@P@_borrow_acquire(@P@_handle *self) { if (!self) return 0; int32_t status = @P@_context(self); if (status) return status; if (self->active == UINT32_MAX) return (int32_t)UINT32_C(0x8007000e); g_object_ref(self->view); ++self->active; return 0; }
uint32_t astra_foreign16_@P@_borrow_release(@P@_handle *self) { if (!self) return 0; if (!self->active || @P@_context(self)) g_error("invalid imported GObject borrow retirement"); GObject *view = self->view; --self->active; if (!self->active && self->retired) g_free(self); g_object_unref(view); return 0; }
static inline void @P@_unpin(@P@_handle **self) { astra_foreign16_@P@_borrow_release(*self); }
uint32_t @P@_release(@P@_handle *self) { if (!self) return 0; if (@P@_context(self) || self->retired) g_error("invalid imported GObject owner retirement"); GObject *view = self->view; self->retired = TRUE; if (!self->active) g_free(self); g_object_unref(view); return 0; }
static inline GObject *@P@_extract(@P@_handle **slot) { @P@_handle *self = *slot; *slot = NULL; if (!self) return NULL; GObject *view = self->view; self->retired = TRUE; if (!self->active) g_free(self); return view; }
void *@P@_root_identity(@P@_handle *self) { return @P@_context(self) ? NULL : self->view; }
static int32_t @P@_adopt(GObject *view, @P@_handle **result) { if (!view || !G_TYPE_CHECK_INSTANCE_TYPE(view, @TYPE@_get_type()) || g_object_is_floating(view)) { if (view) g_object_unref(view); return (int32_t)UINT32_C(0x80004002); } @P@_handle *owner = g_try_new0(@P@_handle, 1); if (!owner) { g_object_unref(view); return (int32_t)UINT32_C(0x8007000e); } owner->view = view; owner->thread = astra_foreign14_thread_identity(); *result = owner; return 0; }
""".replace ("@P@", p).replace ("@TYPE@", root.gobject.symbol_prefix));
			for (uint m = 0; m < root.api.member_count; m++) {
				method (text, root, root.api.member (m), ForeignAdapters.root_prefixes (program), program);
			}
		}
		return text.str;
	}

}
}
