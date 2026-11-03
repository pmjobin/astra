// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.CAbi;
namespace Astra.Driver {
// Declaration-derived GLib transport; application operations stay in native code.
internal class GObjectDeclared : Object {
	private static bool selected(ForeignMemberContract member) {
		return (member.personalities & ForeignClassPolicy.GOBJECT) != 0;
	}

	private static string callback_name(ForeignClassPolicy policy, ForeignValueType type) {
		return policy.gobject.type_name + "Callback" + Checksum.compute_for_string (ChecksumType.SHA256, type.identity ()).up ();
	}

	private static string signal_type(ForeignClassPolicy policy, ForeignChannel channel, CheckedProgram program) throws ForeignAdapterError {
		if (channel.value_type.kind == ForeignValueKind.RECORD) {
			return record_prefix (policy, channel.value_type) + "_get_type()";
		}
		if (channel.value_type.kind == ForeignValueKind.NATIVE_OBJECT) {
			return object_policy (program, channel.value_type).gobject.symbol_prefix () + "_get_type()";
		}
		if (channel.value_type.kind == ForeignValueKind.GOBJECT) {
			return imported_object (program, channel.value_type).gobject.symbol_prefix + "_get_type()";
		}
		if (sequence (channel)) {
			return channel.encoding == ForeignTextEncoding.UTF8_NUL ? "G_TYPE_STRING" : "G_TYPE_BYTES";
		}
		switch (channel.value_type.kind) {
		case ForeignValueKind.I32:
			return "G_TYPE_INT";
		case ForeignValueKind.U32:
			return "G_TYPE_UINT";
		case ForeignValueKind.I64:
			return "G_TYPE_INT64";
		case ForeignValueKind.U64:
			return "G_TYPE_UINT64";
		case ForeignValueKind.F32:
			return "G_TYPE_FLOAT";
		case ForeignValueKind.F64:
			return "G_TYPE_DOUBLE";
		case ForeignValueKind.BOOL:
			return "G_TYPE_BOOLEAN";
		default:
			throw new ForeignAdapterError.INVALID ("native signal argument lacks a completed GValue mapping");
		}
	}

	private static void signal_bridge(StringBuilder text, ForeignClassPolicy policy, ForeignMemberContract member, uint index, CheckedProgram program) throws ForeignAdapterError {
		string p = policy.gobject.symbol_prefix (), n = policy.prefix, t = policy.gobject.type_name;
		var binding = new ForeignSignalBinding (policy, index);
		text.append_printf ("void %s(%s_handle *root", binding.symbol (), n);
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			var type = channel.value_type;
			if (type.kind == ForeignValueKind.RECORD) {
				for (uint f = 0; f < type.field_count; f++) {
					text.append_printf (", %s argument%u_field%u", ForeignAdapters.declared_type (new ForeignValueType (type.field (f).kind), n), a, f);
				}
			} else if (type.object_handle ()) {
				text.append_printf (", void *argument%u", a);
			} else if (sequence (channel)) {
				text.append_printf (", const %s *argument%u, int32_t argument%u_length", type.kind == ForeignValueKind.TEXT ? "char" : "uint8_t", a, a);
			} else {
				text.append_printf (", %s%s argument%u", ForeignAdapters.declared_type (type, n), channel.by_reference ? " *" : "", a);
			}
		}
		text.append_printf (") { if (!root) return; if (astra_foreign14_%s_check_thread(root)) g_error(\"native signal requires its constructing thread\"); if (!%s_acquire(root)) return; %s_Cache *cache = astra_foreign14_%s_personality(root); %s *self = cache ? g_weak_ref_get(&cache->wrapper) : NULL; if (!self) { %s_release(root); return; }\n", n, n, p, n, t, n);
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			var type = channel.value_type;
			if (channel.by_reference || type.object_handle () && !channel.nullable) {
				text.append_printf ("if (!argument%u) g_error(\"native signal requires its nonnull argument view\");\n", a);
			}
			if (sequence (channel)) {
				text.append_printf ("if (argument%u_length < 0 || (!argument%u && argument%u_length)) g_error(\"invalid native signal view\");\n", a, a, a);
				if (channel.encoding == ForeignTextEncoding.UTF8_NUL) {
					text.append_printf ("if (argument%u_length && memchr(argument%u, 0, argument%u_length)) g_error(\"native signal cannot truncate counted text\"); g_autofree gchar *value%u = g_strndup(argument%u ? argument%u : \"\", argument%u_length);\n", a, a, a, a, a, a, a);
				} else {
					text.append_printf ("g_autoptr(GBytes) value%u = g_bytes_new(argument%u, argument%u_length);\n", a, a, a);
				}
			} else if (type.kind == ForeignValueKind.RECORD) {
				string native = ForeignAdapters.declared_type (type, n), prefix = record_prefix (policy, type), boxed = record_name (policy, type);
				text.append_printf ("%s native%u = {0};\n", native, a);
				for (uint f = 0; f < type.field_count; f++) {
					text.append_printf ("native%u.%s = argument%u_field%u;\n", a, CAbiClassAdapter.record_field_name (type.field (f), f), a, f);
				}
				text.append_printf ("%s *value%u = %s_from_native(native%u);\n", boxed, a, prefix, a);
			} else if (type.kind == ForeignValueKind.NATIVE_OBJECT) {
				var other = object_policy (program, type);
				string project = CAbiClassAdapter.native_projection_symbol (other);
				text.append_printf ("extern int32_t %s(void *, %s_handle **, astra_foreign_error *); %s_handle *carrier%u = NULL; astra_foreign_error failure%u = {0, 0}; if (%s(argument%u, &carrier%u, &failure%u)) g_error(\"native signal lost its exact argument projection\"); %s *value%u = carrier%u ? %s_as_gobject(carrier%u, NULL) : NULL; if (carrier%u && !value%u) g_error(\"native signal lost its argument root\");\n", project, other.prefix, other.prefix, a, a, project, a, a, a, other.gobject.type_name, a, a, other.gobject.symbol_prefix (), a, a, a);
			} else if (type.kind == ForeignValueKind.GOBJECT) {
				var other = imported_object (program, type);
				text.append_printf ("%s_handle *carrier%u = argument%u; if (carrier%u && astra_foreign16_%s_borrow_acquire(carrier%u)) g_error(\"native signal lost its foreign argument\"); GObject *value%u = carrier%u ? carrier%u->view : NULL;\n", other.api.prefix, a, a, a, other.api.prefix, a, a, a, a);
			}
		}
		text.append_printf ("if (!self->disposed && g_atomic_int_get(&cache->state) == 1) { g_signal_emit(self, %s_signals[%u], 0", p, index);
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			text.append (", " + (channel.value_type.scalar () ? converted (channel.value_type, (channel.by_reference ? "*" : "") + "argument%u".printf (a), false) : "value%u".printf (a)));
		}
		text.append ("); }\n");
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			var type = channel.value_type;
			if (type.kind == ForeignValueKind.RECORD) {
				text.append_printf ("%s_free(value%u);\n", record_prefix (policy, type), a);
			} else if (type.kind == ForeignValueKind.NATIVE_OBJECT) {
				text.append_printf ("if (value%u) { g_object_unref(value%u); } if (carrier%u) { %s_release(carrier%u); }\n", a, a, a, object_policy (program, type).prefix, a);
			} else if (type.kind == ForeignValueKind.GOBJECT) {
				text.append_printf ("if (carrier%u) astra_foreign16_%s_borrow_release(carrier%u);\n", a, imported_object (program, type).api.prefix, a);
			}
		}
		text.append_printf ("g_object_unref(self); %s_release(root); }\n", n);
	}

	private static void callbacks(StringBuilder text, ForeignClassPolicy policy, bool implementation) throws ForeignAdapterError {
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		var api = policy.declared_api;
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			if (!selected (member)) {
				continue;
			}
			for (uint p = 0; p < member.parameter_count; p++) {
				var type = member.parameter (p).value_type;
				if (type.kind != ForeignValueKind.CALLBACK) {
					continue;
				}
				string name = callback_name (policy, type);
				if (seen.contains (name)) {
					continue;
				}
				seen.insert (name, true);
				if (!implementation) {
					text.append_printf ("/**\n * %s:\n * @userdata: (closure): caller data\n", name);
					for (uint a = 0; a < type.callback_parameter_count; a++) {
						text.append_printf (" * @argument%u: copied value\n", a);
					}
					if (type.callback_result.kind != ForeignValueKind.VOID) {
						text.append (" * Returns: the copied callback result\n");
					}
					text.append_printf (" */\ntypedef %s (*%s)(gpointer userdata", type.callback_result.kind == ForeignValueKind.VOID ? "void" : scalar_type (type.callback_result), name);
					for (uint a = 0; a < type.callback_parameter_count; a++) {
						text.append_printf (", %s argument%u", scalar_type (type.callback_parameter (a)), a);
					}
					text.append (");\n");
					continue;
				}
				text.append_printf ("typedef struct { %s code; gpointer data; } %s_Context;\nstatic inline __attribute__((unused)) %s %s_native(void *opaque", name, name, ForeignAdapters.declared_type (type.callback_result, policy.prefix), name);
				for (uint a = 0; a < type.callback_parameter_count; a++) {
					text.append_printf (", %s argument%u", ForeignAdapters.declared_type (type.callback_parameter (a), policy.prefix), a);
				}
				text.append_printf (") { %s_Context *context = opaque;\n", name);
				string invocation = "context->code(context->data";
				for (uint a = 0; a < type.callback_parameter_count; a++) {
					invocation += ", " + converted (type.callback_parameter (a), "argument%u".printf (a), false);
				}
				invocation += ")";
				text.append (type.callback_result.kind == ForeignValueKind.VOID ? invocation + ";\n}\n" : "return " + converted (type.callback_result, invocation, true) + ";\n}\n");
			}
		}
	}

	private static string scalar_type(ForeignValueType type) throws ForeignAdapterError {
		switch (type.kind) {
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
			throw new ForeignAdapterError.INVALID ("declared GObject value requires its completed physical channel plan");
		}
	}

	private static string record_name(ForeignClassPolicy policy, ForeignValueType type) {
		return policy.gobject.namespace_name + "Record" + Checksum.compute_for_string (ChecksumType.SHA256, new ForeignGObjectRecordLayout (type).identity ()).up ();
	}

	private static string record_prefix(ForeignClassPolicy policy, ForeignValueType type) {
		return policy.gobject.namespace_name.ascii_down () + "_record_" + Checksum.compute_for_string (ChecksumType.SHA256, new ForeignGObjectRecordLayout (type).identity ());
	}

	private static void records(StringBuilder text, ForeignClassPolicy policy, bool implementation, HashTable<string, bool> seen) throws ForeignAdapterError {
		var api = policy.declared_api;
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			if (!selected (member)) {
				continue;
			}
			for (uint v = 0; v <= member.parameter_count; v++) {
				var type = v == member.parameter_count ? member.result.value_type : member.parameter (v).value_type;
				if (type.kind != ForeignValueKind.RECORD) {
					continue;
				}
				string name = record_name (policy, type), prefix = record_prefix (policy, type);
				if (seen.contains (name)) {
					continue;
				}
				seen.insert (name, true);
				var layout = new ForeignGObjectRecordLayout (type);
				if (!layout.valid ()) {
					throw new ForeignAdapterError.INVALID ("GObject boxed record lost its scalar layout");
				}
				if (!implementation) {
					text.append_printf ("/**\n * %s: (attributes astra.native-type=%s)\n */\ntypedef struct _%s {\n", name, type.nominal_origin, name);
					for (uint f = 0; f < type.field_count; f++) {
						text.append_printf ("%s %s;\n", scalar_type (new ForeignValueType (type.field (f).kind)), CAbiClassAdapter.record_field_name (type.field (f), f));
					}
					text.append_printf ("} %s;\nGType %s_get_type(void);\n/**\n * %s_new:\n * Returns: (transfer full): a zero initialized copied record\n */\n%s *%s_new(void);\n/**\n * %s_copy:\n * @self: the record\n * Returns: (transfer full): an independent copy\n */\n%s *%s_copy(const %s *self);\n/**\n * %s_free:\n * @self: (transfer full): the record\n */\nvoid %s_free(%s *self);\n", name, prefix, prefix, name, prefix, prefix, name, prefix, name, prefix, prefix, name);
					continue;
				}
				text.append_printf ("_Static_assert(sizeof(%s) == %u && _Alignof(%s) == %u, \"GObject boxed POD storage\");\n", name, layout.size, name, layout.alignment);
				for (uint f = 0; f < type.field_count; f++) {
					text.append_printf ("_Static_assert(offsetof(%s, %s) == %u, \"GObject POD field\");\n", name, CAbiClassAdapter.record_field_name (type.field (f), f), layout.offset (f));
				}
				text.append_printf ("%s *%s_new(void) { return g_new0(%s, 1); }\n%s *%s_copy(const %s *self) { return self ? g_memdup2(self, sizeof *self) : NULL; }\nvoid %s_free(%s *self) { g_free(self); }\nG_DEFINE_BOXED_TYPE(%s, %s, %s_copy, %s_free)\n", name, prefix, name, name, prefix, name, prefix, name, name, prefix, prefix, prefix);
				text.append_printf ("static inline __attribute__((unused)) %s %s_to_native(const %s *input) { %s result = {0};\n", ForeignAdapters.declared_type (type, ""), prefix, name, ForeignAdapters.declared_type (type, ""));
				for (uint f = 0; f < type.field_count; f++) {
					string field = CAbiClassAdapter.record_field_name (type.field (f), f);
					text.append_printf ("result.%s = %s;\n", field, converted (new ForeignValueType (type.field (f).kind), "input->" + field, true));
				}
				text.append ("return result; }\n");
				text.append_printf ("static inline __attribute__((unused)) %s *%s_from_native(%s input) { %s *result = %s_new();\n", name, prefix, ForeignAdapters.declared_type (type, ""), name, prefix);
				for (uint f = 0; f < type.field_count; f++) {
					string field = CAbiClassAdapter.record_field_name (type.field (f), f);
					text.append_printf ("result->%s = %s;\n", field, converted (new ForeignValueType (type.field (f).kind), "input." + field, false));
				}
				text.append ("return result; }\n");
			}
		}
	}

	private static ForeignImportContract imported_object(CheckedProgram program, ForeignValueType type) throws ForeignAdapterError {
		foreach (var handle in program.handles) {
			if (handle.c_import != null && handle.c_import.gobject != null && handle.c_import.api.native_origin == type.nominal_origin && handle.c_import.valid ()) {
				return handle.c_import;
			}
		}
		throw new ForeignAdapterError.INVALID ("GObject export channel lost its exact imported GType and reference contract");
	}

	private static ForeignClassPolicy object_policy(CheckedProgram program, ForeignValueType type) throws ForeignAdapterError {
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy != null && policy.declared_api != null && policy.native_name == type.nominal_origin && policy.declared_api.lifetime == ForeignLifetime.SHARED && policy.gobject != null && policy.gobject.declarations && policy.valid ()) {
				return policy;
			}
		}
		throw new ForeignAdapterError.INVALID ("GObject native Class projection requires its exact Shared root and declared GType");
	}

	private static void object_inputs(StringBuilder text, CheckedProgram program, ForeignMemberContract member, string prefix, bool factory) throws ForeignAdapterError {
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind == ForeignValueKind.GOBJECT) {
				var other = imported_object (program, channel.value_type);
				text.append_printf ("g_autoptr(%s_handle) object%u = NULL;\n", other.api.prefix, a);
				if (!channel.nullable) {
					text.append_printf ("if (!argument%u) { %s_error(error, (int32_t)UINT32_C(0x80004003)); return %s; }\n", a, prefix, factory ? "NULL" : "FALSE");
				}
				text.append_printf ("if (argument%u) { int32_t status = %s_adopt(%s, &object%u); if (status) { %s_error(error, status); return %s; } }\n", a, other.api.prefix, channel.transfer == ForeignTransfer.OWN ? "g_steal_pointer(&consumed%u)".printf (a) : "g_object_ref(G_OBJECT(argument%u))".printf (a), a, prefix, factory ? "NULL" : "FALSE");
				continue;
			}
			if (channel.value_type.kind != ForeignValueKind.NATIVE_OBJECT) {
				continue;
			}
			var root = object_policy (program, channel.value_type);
			text.append_printf ("g_autoptr(%s_handle) object%u = NULL;\n", root.prefix, a);
			if (!channel.nullable) {
				text.append_printf ("if (!argument%u) { %s_error(error, (int32_t)UINT32_C(0x80004003)); return %s; }\n", a, prefix, factory ? "NULL" : "FALSE");
			}
			text.append_printf ("if (argument%u) { object%u = %s_native_acquire(argument%u, error); if (!object%u) return %s; }\n", a, a, root.gobject.symbol_prefix (), a, a, factory ? "NULL" : "FALSE");
		}
	}

	private static bool sequence(ForeignChannel channel) {
		return channel.value_type.kind == ForeignValueKind.BYTES || channel.value_type.kind == ForeignValueKind.TEXT;
	}

	private static string channel_type(ForeignChannel channel, ForeignClassPolicy policy, CheckedProgram program) throws ForeignAdapterError {
		if (channel.value_type.kind == ForeignValueKind.GOBJECT) {
			return imported_object (program, channel.value_type).gobject.type_name + " *";
		}
		if (channel.value_type.kind == ForeignValueKind.NATIVE_OBJECT) {
			return object_policy (program, channel.value_type).gobject.type_name + " *";
		}
		if (channel.value_type.kind == ForeignValueKind.RECORD) {
			return record_name (policy, channel.value_type) + " *";
		}
		if (sequence (channel)) {
			if (channel.direction != ForeignDirection.IN && channel.transfer == ForeignTransfer.BORROW) {
				return "guint8 **";
			}
			return channel.encoding == ForeignTextEncoding.UTF8_NUL ? "gchar *" : "GBytes *";
		}
		return scalar_type (channel.value_type);
	}

	private static string native_type(ForeignChannel channel, string prefix) throws ForeignAdapterError {
		return sequence (channel) ? channel.value_type.kind == ForeignValueKind.TEXT ? "char *" : "uint8_t *" : ForeignAdapters.declared_type (channel.value_type, prefix);
	}

	private static string channel_attributes(ForeignChannel channel) {
		string kind = channel.value_type.kind == ForeignValueKind.TEXT ? "text" : channel.value_type.kind == ForeignValueKind.BYTES ? "bytes" : "";
		if (kind == "") {
			return "";
		}
		string encoding = channel.encoding == ForeignTextEncoding.UTF8_NUL ? "utf8-nul" : channel.encoding == ForeignTextEncoding.UTF8_COUNTED ? "utf8-counted" : "bytes";
		string attributes = " (attributes astra.kind=" + kind + " astra.encoding=" + encoding + " astra.direction=" + (channel.direction == ForeignDirection.IN ? "in" : channel.direction == ForeignDirection.OUT ? "out" : "inout");
		if (channel.produced_by_result) {
			attributes += " astra.produced=result";
		}
		return attributes + ")";
	}

	private static string member_attributes(ForeignMemberContract member) {
		string attributes = " (attributes astra.profile=declarations-v1";
		if (member.kind == ForeignMemberKind.SIGNAL) {
			attributes += " astra.signal-scope=synchronous astra.signal-closure=gclosure astra.signal-destroy=finalized";
		}
		if (member.error_map != null) {
			string codes = "";
			for (uint c = 0; c < member.error_map.case_count; c++) {
				codes += (c == 0 ? "" : ",") + member.error_map.at (c).status.to_string ();
			}
			attributes += " astra.error-domain=" + member.error_map.domain.to_string () + " astra.error-codes=" + codes;
		}
		return attributes + ")";
	}

	private static bool is_capacity(ForeignMemberContract member,uint parameter) {
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (sequence (channel) && channel.direction != ForeignDirection.IN && !channel.intrinsic_length && channel.capacity_index == parameter) {
				return true;
			}
		}
		return false;
	}

	private static string capacity(ForeignChannel channel,uint ordinal) {
		return channel.intrinsic_length ? "argument%u_capacity".printf (ordinal) : "argument%d".printf (channel.capacity_index);
	}

	private static void sequence_inputs(StringBuilder text,ForeignMemberContract member,string prefix,bool factory) {
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (!sequence (channel) || channel.direction != ForeignDirection.IN || channel.encoding == ForeignTextEncoding.UTF8_NUL) {
				continue;
			}
			text.append_printf ("gsize length%u = 0; const void *bytes%u = argument%u ? g_bytes_get_data(argument%u, &length%u) : NULL;\n",a,a,a,a,a);
			text.append_printf ("if (length%u > G_MAXINT32%s) { %s_error(error, (int32_t)UINT32_C(0x80070057)); return %s; }\n",a,channel.nullable ? "" : " || !argument%u".printf (a),prefix,factory ? "NULL" : "FALSE");
			text.append_printf ("const %s *input%u = bytes%u ? bytes%u : argument%u ? (const void *)\"\" : NULL;\n",channel.value_type.kind == ForeignValueKind.TEXT ? "char" : "uint8_t",a,a,a,a);
			if (!channel.intrinsic_length) {
				text.append_printf ("if (argument%d < 0 || (gsize)argument%d != length%u) { %s_error(error, (int32_t)UINT32_C(0x80070057)); return %s; }\n",channel.length_index,channel.length_index,a,prefix,factory ? "NULL" : "FALSE");
			}
		}
	}

	private static void sequence_result(StringBuilder text,ForeignChannel channel,string prefix) {
		text.append_printf ("if (ok && (value_length < 0 || (value_length && !value))) ok = %s_error(error, (int32_t)UINT32_C(0x8000ffff));\n",prefix);
		if (channel.encoding == ForeignTextEncoding.UTF8_NUL) {
			text.append ("if (ok) *result = g_strndup(value ? value : \"\", (gsize)value_length);\n");
		} else {
			text.append ("if (ok) *result = g_bytes_new(value, (gsize)value_length);\n");
		}
		text.append_printf ("%s(&value, &value_length, NULL);\n",channel.release_symbol);
	}

	private static string value_suffix(ForeignValueType type) throws ForeignAdapterError {
		switch (type.kind) {
		case ForeignValueKind.I32:
			return "int";
		case ForeignValueKind.U32:
			return "uint";
		case ForeignValueKind.I64:
			return "int64";
		case ForeignValueKind.U64:
			return "uint64";
		case ForeignValueKind.F32:
			return "float";
		case ForeignValueKind.F64:
			return "double";
		case ForeignValueKind.BOOL:
			return "boolean";
		default:
			throw new ForeignAdapterError.INVALID ("declared GObject property requires a typed GValue plan");
		}
	}

	private static string converted(ForeignValueType type,string value,bool native) throws ForeignAdapterError {
		return type.kind == ForeignValueKind.BOOL ? "(" + value + (native ? " != FALSE)" : " ? TRUE : FALSE)") : "(" + (native ? ForeignAdapters.declared_type (type,"") : scalar_type (type)) + ")(" + value + ")";
	}

	private static int property_id(ForeignApiContract api,ForeignMemberContract member) {
		for (uint m = 0; m < api.member_count; m++) {
			if (api.member (m).kind == ForeignMemberKind.GETTER && api.member (m).native_member_ordinal == member.native_member_ordinal) {
				return (int) m + 1;
			}
		}
		return 0;
	}

	private static string property_name(ForeignMemberContract member) {
		return member.name.substring (4).replace ("_","-");
	}

	private static ForeignMemberContract? setter(ForeignApiContract api,ForeignMemberContract getter) {
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			if (!selected (member)) {
				continue;
			}
			if (member.kind == ForeignMemberKind.SETTER && member.native_member_ordinal == getter.native_member_ordinal) {
				return member;
			}
		}
		return null;
	}

	private static void signature(StringBuilder text,ForeignClassPolicy policy,ForeignMemberContract member,CheckedProgram program) throws ForeignAdapterError {
		string p = policy.gobject.symbol_prefix (),t = policy.gobject.type_name;
		bool factory = member.kind == ForeignMemberKind.CONSTRUCTOR;
		text.append_printf ("%s %s_%s(",factory ? t + " *" : "gboolean",p,factory ? "new" : "try_" + member.name);
		bool comma = !factory;
		if (!factory) {
			text.append_printf ("%s *self",t);
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			if (comma) {
				text.append (", ");
			}
			var channel = member.parameter (a);
			if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("%s argument%u, gpointer argument%u_data",callback_name (policy,channel.value_type),a,a);
			} else {
				text.append_printf ("%s%s%s argument%u","",channel_type (channel,policy,program),GObjectExportContract.indirect_reference (channel) || is_capacity (member,a) ? " *" : "",a);
			} if (sequence (channel) && channel.direction != ForeignDirection.IN && channel.intrinsic_length) {
				text.append_printf (", gint *argument%u_capacity",a);
			}
			comma = true;
		}
		if (!factory && member.result.value_type.kind != ForeignValueKind.VOID) {
			text.append_printf ("%s%s *result",comma ? ", " : "",channel_type (member.result,policy,program));
			comma = true;
		}
		text.append_printf ("%sGError **error)", comma ? ", " : "");
	}

	private static string property_suffix(ForeignChannel channel) throws ForeignAdapterError {
		if (channel.value_type.kind == ForeignValueKind.NATIVE_OBJECT) {
			return "object";
		}
		if (sequence (channel)) {
			return channel.encoding == ForeignTextEncoding.UTF8_NUL ? "string" : "boxed";
		}
		if (channel.value_type.kind == ForeignValueKind.RECORD) {
			return "boxed";
		}
		return value_suffix (channel.value_type);
	}

	private static string property_spec(ForeignChannel channel, ForeignClassPolicy policy, CheckedProgram program) throws ForeignAdapterError {
		if (channel.value_type.kind == ForeignValueKind.NATIVE_OBJECT) {
			return "object(@ARGS@, " + object_policy (program, channel.value_type).gobject.symbol_prefix () + "_get_type(), @FLAGS@)";
		}
		if (sequence (channel)) {
			return channel.encoding == ForeignTextEncoding.UTF8_NUL ? "string(@ARGS@, NULL, @FLAGS@)" : "boxed(@ARGS@, G_TYPE_BYTES, @FLAGS@)";
		}
		if (channel.value_type.kind == ForeignValueKind.RECORD) {
			return "boxed(@ARGS@, " + record_prefix (policy, channel.value_type) + "_get_type(), @FLAGS@)";
		}
		return param_spec (channel.value_type);
	}

	private static string param_spec(ForeignValueType type) throws ForeignAdapterError {
		switch (type.kind) {
		case ForeignValueKind.I32: return "int(@ARGS@, G_MININT, G_MAXINT, 0, @FLAGS@)";
		case ForeignValueKind.U32:
			return "uint(@ARGS@, 0, G_MAXUINT, 0, @FLAGS@)";
		case ForeignValueKind.I64:
			return "int64(@ARGS@, G_MININT64, G_MAXINT64, 0, @FLAGS@)";
		case ForeignValueKind.U64:
			return "uint64(@ARGS@, 0, G_MAXUINT64, 0, @FLAGS@)";
		case ForeignValueKind.F32:
			return "float(@ARGS@, -G_MAXFLOAT, G_MAXFLOAT, 0, @FLAGS@)";
		case ForeignValueKind.F64:
			return "double(@ARGS@, -G_MAXDOUBLE, G_MAXDOUBLE, 0, @FLAGS@)";
		case ForeignValueKind.BOOL:
			return "boolean(@ARGS@, FALSE, @FLAGS@)";
		default:
			throw new ForeignAdapterError.INVALID ("declared property has no admitted GParamSpec");
		}
	}

	internal static string generate(CheckedProgram program, bool implementation) throws ForeignAdapterError {
		var identities = new StringBuilder ();
		var policies = new GenericArray<ForeignClassPolicy> ();
		var symbols = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy == null || policy.declared_api == null || policy.gobject == null || !policy.active (ForeignClassPolicy.GOBJECT)) {
				continue;
			}
			if (!ForeignClassPolicy.matches (policy, ((ClassType) owner.semantic_type).foreign_policy_identity, owner.name)) {
				throw new ForeignAdapterError.INVALID ("declared GObject root lost its exact policy");
			}
			policies.add (policy);
			identities.append (policy.identity ());
		}
		if (policies.length == 0) {
			return "";
		}
		// Validate every selected channel before producing any SDK text.
		foreach (var owner in program.classes) {
			var api = owner.foreign_export == null ? null : owner.foreign_export.declared_api;
			if (api == null) {
				continue;
			}
			for (uint m = 0; m < api.member_count; m++) {
				symbols.insert (api.prefix + "_" + api.member (m).name, true);
			}
		}
		foreach (var policy in policies) {
			string p = policy.gobject.symbol_prefix ();
			var api = policy.declared_api;
			foreach (string suffix in new string[] { "get_type", "as_gobject", "error_quark" }) {
				string symbol = p + "_" + suffix;
				if (symbols.contains (symbol)) {
					throw new ForeignAdapterError.INVALID ("C/GObject SDK symbol collision: " + symbol);
				}
				symbols.insert (symbol, true);
			}
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!selected (member)) {
					continue;
				}
				if (member.kind != ForeignMemberKind.CONSTRUCTOR && member.result.value_type.kind != ForeignValueKind.VOID) {
					channel_type (member.result, policy, program);
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					var channel = member.parameter (a);
					if (channel.value_type.kind == ForeignValueKind.CALLBACK || channel.value_type.kind == ForeignValueKind.NATIVE_OBJECT || channel.value_type.kind == ForeignValueKind.GOBJECT || sequence (channel)) {
						continue;
					}
					if (!channel.by_reference && channel.transfer != ForeignTransfer.COPY) {
						throw new ForeignAdapterError.INVALID ("declared GObject channel requires completed ownership conversion");
					}
					channel_type (channel, policy, program);
				}
				string symbol = p + (member.kind == ForeignMemberKind.CONSTRUCTOR ? "_new" : "_try_" + member.name);
				if (symbols.contains (symbol)) {
					throw new ForeignAdapterError.INVALID ("C/GObject SDK symbol collision: " + symbol);
				}
				symbols.insert (symbol, true);
			}
		}
		string guard = "ASTRA_GOBJECT_DECLARED_" + Checksum.compute_for_string (ChecksumType.SHA256, identities.str).up ();
		var text = new StringBuilder ("/* Generated declaration-driven GObject projection. */\n#ifndef " + guard + "\n#define " + guard + "\n#include <glib-object.h>\nG_BEGIN_DECLS\n");
		foreach (var policy in policies) {
			text.append_printf ("typedef struct _%s %s;\n", policy.gobject.type_name, policy.gobject.type_name);
		}
		var header_records = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var policy in policies) {
			records (text, policy, false, header_records);
			callbacks (text, policy, false);
			var contract = policy.gobject;
			string p = contract.symbol_prefix (), t = contract.type_name;
			text.append_printf ("G_DECLARE_FINAL_TYPE(%s, %s, %s, %s, GObject)\n/**\n * %sNativeHandle: (skip)\n */\ntypedef struct %s_handle %sNativeHandle;\n/**\n * %s_as_gobject: (skip)\n * @root: the native C owner\n * @error: return location for an error\n * Returns: (transfer full) (nullable): the live wrapper\n */\n%s *%s_as_gobject(%sNativeHandle *root, GError **error);\nGQuark %s_error_quark(void);\n", t, p, contract.namespace_name.up (), t.substring (contract.namespace_name.length).up (), t, policy.prefix, t, p, t, p, t, p);
			for (uint m = 0; m < policy.declared_api.member_count; m++) {
				var member = policy.declared_api.member (m);
				if (!selected (member)) {
					continue;
				}
				if (member.kind == ForeignMemberKind.SIGNAL) {
					text.append_printf ("/**\n * %s::%s:%s\n * @self: the emitting native-backed object\n",t,member.name.replace ("_","-"),member_attributes (member));
					for (uint a = 0; a < member.parameter_count; a++) {
						var channel = member.parameter (a);
						text.append_printf (" * @argument%u: (in)%s%s%s: synchronous argument\n", a, channel.value_type.scalar () ? "" : " (transfer none)", channel.nullable ? " (nullable)" : "", channel_attributes (channel));
					}
					text.append (" */\n");
					continue;
				}
				bool factory = member.kind == ForeignMemberKind.CONSTRUCTOR;
				text.append_printf ("/**\n * %s_%s:%s\n", p, factory ? "new" : "try_" + member.name, member_attributes (member));
				if (!factory) {
					text.append (" * @self: the native-backed object\n");
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					var channel = member.parameter (a);
					if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
						text.append_printf (" * @argument%u: (scope call) (closure argument%u_data)%s: synchronous callback\n * @argument%u_data: caller data\n", a, a, channel.nullable ? " (nullable)" : "", a);
					} else if (channel.value_type.object_handle ()) {
						text.append_printf (" * @argument%u: (transfer %s)%s: exact typed native root view\n", a, channel.transfer == ForeignTransfer.OWN ? "full" : "none", channel.nullable ? " (nullable)" : "");
					} else if (sequence (channel)) {
						if (channel.direction == ForeignDirection.IN) {
							text.append_printf (" * @argument%u: (transfer none)%s%s: exact input\n", a, channel.nullable ? " (nullable)" : "", channel_attributes (channel));
						} else {
							string count = capacity (channel, a);
							text.append_printf (" * @argument%u: (inout) (array length=%s) (element-type guint8) (transfer none)%s%s: bounded caller storage\n", a, count, channel.nullable ? " (nullable)" : "", channel_attributes (channel));
							if (channel.intrinsic_length) {
								text.append_printf (" * @argument%u_capacity: (inout): caller capacity (unchanged)\n", a);
							}
						}
					} else {
						text.append_printf (" * @argument%u:%s copied value\n", a, GObjectExportContract.indirect_reference (channel) || is_capacity (member, a) ? channel.direction == ForeignDirection.OUT ? " (out):" : " (inout):" : " (in):");
					}
				}
				if (!factory && member.result.value_type.kind != ForeignValueKind.VOID) {
					text.append ((sequence (member.result) || member.result.value_type.object_handle () || member.result.value_type.kind == ForeignValueKind.RECORD) ? " * @result: (out) (transfer full)" + (member.result.nullable ? " (nullable)" : "") + channel_attributes (member.result) + ": independent owned result\n" : " * @result: (out): copied result\n");
				}
				text.append (" * @error: return location for an error\n");
				text.append (factory ? " * Returns: (transfer full) (nullable): a native-backed object\n */\n" : " * Returns: whether the operation succeeded\n */\n");
				signature (text, policy, member, program);
				text.append (";\n");
			}
		}
		text.append ("G_END_DECLS\n#endif\n");
		if (!implementation) {
			return text.str;
		}
		text.append ("\n#include <stddef.h>\n#include <string.h>\n_Static_assert(sizeof(gboolean) == 4 && sizeof(gint) == 4 && sizeof(gint64) == 8 && sizeof(gfloat) == 4 && sizeof(gdouble) == 8 && sizeof(void*) == 8, \"GObject LP64 transport\");\n");
		foreach (var handle in program.handles) {
			var root = handle.c_import;
			if (root != null && root.gobject != null) {
				text.append_printf ("G_DEFINE_AUTOPTR_CLEANUP_FUNC(%s_handle, %s_release)\n", root.api.prefix, root.api.prefix);
			}
		}
		foreach (var policy in policies) {
			text.append_printf ("G_DEFINE_AUTOPTR_CLEANUP_FUNC(%s_handle, %s_release)\nstatic %s_handle *%s_native_acquire(%s *view, GError **error);\n", policy.prefix, policy.prefix, policy.prefix, policy.gobject.symbol_prefix (), policy.gobject.type_name);
		}
		var implementation_records = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var policy in policies) {
			records (text, policy, true, implementation_records);
			callbacks (text, policy, true);
			string p = policy.gobject.symbol_prefix (), n = policy.prefix, t = policy.gobject.type_name;
			var api = policy.declared_api;
			text.append_printf ("extern int32_t astra_foreign14_%s_check_thread(%s_handle *);\nextern void *astra_foreign14_%s_personality(%s_handle *);\nextern int32_t astra_foreign14_%s_attach(%s_handle *, void *, void (*)(void *));\n", n, n, n, n, n, n);
			text.append ("""
typedef struct { GWeakRef wrapper; gint state; } @P@_Cache;
struct _@T@ { GObject parent_instance; GRecMutex gate; @N@_handle *root; @P@_Cache *cache; gboolean disposed; };
G_DEFINE_FINAL_TYPE(@T@, @P@, G_TYPE_OBJECT)
static GParamSpec *@P@_properties[@COUNT@];
static guint @P@_signals[@SIGNAL_COUNT@];
GQuark @P@_error_quark(void) { return g_quark_from_static_string("@P@-error"); }
static gboolean @P@_error(GError **error, int32_t code) { g_set_error_literal(error, @P@_error_quark(), code, "native GObject boundary failure"); return FALSE; }
static inline __attribute__((unused)) gboolean @P@_status(int32_t status, const astra_foreign_error *native, GError **error) {
	if (status >= 0 && (!native || (!native->domain && !native->code))) return TRUE;
	GQuark domain = @P@_error_quark();
	if (native && native->domain) { char name[64]; g_snprintf(name, sizeof name, "astra-foreign-domain-%d", native->domain); domain = g_quark_from_string(name); }
	g_set_error_literal(error, domain, status < 0 ? status : (int32_t)UINT32_C(0x8000ffff), "native checked operation failed"); return FALSE;
}
static inline __attribute__((unused)) gboolean @P@_enter(@T@ *self, GError **error) {
	if (!self || G_TYPE_FROM_INSTANCE(self) != @P@_get_type()) return @P@_error(error, (int32_t)UINT32_C(0x80004003));
	g_object_ref(self); g_rec_mutex_lock(&self->gate);
	int32_t status = self->disposed || !self->root ? (int32_t)UINT32_C(0x80004003) : astra_foreign14_@N@_check_thread(self->root);
	if (status) { g_rec_mutex_unlock(&self->gate); g_object_unref(self); return @P@_error(error, status); } return TRUE;
}
static inline __attribute__((unused)) void @P@_leave(@T@ *self) { g_rec_mutex_unlock(&self->gate); g_object_unref(self); }
static void @P@_cache_retire(void *opaque) { @P@_Cache *cache = opaque; g_weak_ref_clear(&cache->wrapper); g_free(cache); }
static void @P@_dispose(GObject *object) { @T@ *self = (@T@ *)object; g_rec_mutex_lock(&self->gate); self->disposed = TRUE; if (self->cache) g_atomic_int_set(&self->cache->state, 2); G_OBJECT_CLASS(@P@_parent_class)->dispose(object); g_rec_mutex_unlock(&self->gate); }
static void @P@_finalize(GObject *object) { @T@ *self = (@T@ *)object; @N@_handle *root = self->root; self->root = NULL; if (self->cache) g_atomic_int_set(&self->cache->state, 0); self->cache = NULL; if (root) { if (astra_foreign14_@N@_check_thread(root)) g_error("native GObject finalization requires its constructing thread"); @N@_release(root); } g_rec_mutex_clear(&self->gate); G_OBJECT_CLASS(@P@_parent_class)->finalize(object); }
static void @P@_init(@T@ *self) { g_rec_mutex_init(&self->gate); }
@T@ *@P@_as_gobject(@T@NativeHandle *root, GError **error) {
	int32_t status = astra_foreign14_@N@_check_thread(root); if (status) { @P@_error(error, status); return NULL; }
	@P@_Cache *cache = astra_foreign14_@N@_personality(root);
	if (!cache) { cache = g_try_new0(@P@_Cache, 1); if (!cache) { @P@_error(error, (int32_t)UINT32_C(0x8007000e)); return NULL; } g_weak_ref_init(&cache->wrapper, NULL); status = astra_foreign14_@N@_attach(root, cache, @P@_cache_retire); if (status) { @P@_cache_retire(cache); @P@_error(error, status); return NULL; } }
	@T@ *view = g_weak_ref_get(&cache->wrapper); if (view) { if (g_atomic_int_get(&cache->state) == 1) return view; g_object_unref(view); @P@_error(error, (int32_t)UINT32_C(0x80004003)); return NULL; }
	if (g_atomic_int_get(&cache->state)) { @P@_error(error, (int32_t)UINT32_C(0x80004003)); return NULL; }
	if (!@N@_acquire(root)) { @P@_error(error, (int32_t)UINT32_C(0x8000ffff)); return NULL; }
	view = g_object_new(@P@_get_type(), NULL); view->root = root; view->cache = cache; g_weak_ref_set(&cache->wrapper, view); g_atomic_int_set(&cache->state, 1); return view;
}
""".replace ("@P@", p).replace ("@N@", n).replace ("@T@", t).replace ("@COUNT@", (api.member_count + 1).to_string ()).replace ("@SIGNAL_COUNT@", (api.member_count + 1).to_string ()));
			text.append_printf ("static inline __attribute__((unused)) %s_handle *%s_native_acquire(%s *view, GError **error) { if (!%s_enter(view, error)) return NULL; %s_handle *root = view->root; if (!%s_acquire(root)) { %s_error(error, (int32_t)UINT32_C(0x8000ffff)); root = NULL; } %s_leave(view); return root; }\n", n, p, t, p, n, n, p, p);
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (selected (member) && member.kind == ForeignMemberKind.SIGNAL) {
					signal_bridge (text,policy,member,m,program);
				}
			}

			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!selected (member) || member.kind == ForeignMemberKind.SIGNAL) {
					continue;
				}
				bool factory = member.kind == ForeignMemberKind.CONSTRUCTOR,result = !factory && member.result.value_type.kind != ForeignValueKind.VOID;
				signature (text,policy,member,program);
				text.append (" {\n");
				for (uint a = 0; a < member.parameter_count; a++) {
					var channel = member.parameter (a);
					if (channel.value_type.kind == ForeignValueKind.GOBJECT && channel.transfer == ForeignTransfer.OWN) {
						text.append_printf ("g_autoptr(GObject) consumed%u = (GObject *)argument%u;\n",a,a);
					}
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					var channel = member.parameter (a);
					if (channel.by_reference) {
						text.append_printf ("%s reference%u = %s;\n",ForeignAdapters.declared_type (channel.value_type,n),a,channel.direction == ForeignDirection.OUT ? "0" : channel.direction == ForeignDirection.IN ? converted (channel.value_type,"argument%u".printf (a),true) : "argument%u ? %s : 0".printf (a,converted (channel.value_type,"*argument%u".printf (a),true)));
					}
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					var channel = member.parameter (a);
					if (channel.by_reference && channel.direction == ForeignDirection.OUT) {
						text.append_printf ("if (argument%u) *argument%u = 0;\n",a,a);
					}
				}
				if (result) {
					text.append_printf ("if (!result) return %s_error(error, (int32_t)UINT32_C(0x80004003));\n*result = 0;\n",p);
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					var channel = member.parameter (a);
					if (GObjectExportContract.indirect_reference (channel) || channel.value_type.kind == ForeignValueKind.RECORD || channel.value_type.kind == ForeignValueKind.CALLBACK && !channel.nullable) {
						text.append_printf ("if (!argument%u) { %s_error(error, (int32_t)UINT32_C(0x80004003)); return %s; }\n",a,p,factory ? "NULL" : "FALSE");
					}
					if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
						text.append_printf ("%s_Context callback%u = {argument%u, argument%u_data};\n",callback_name (policy,channel.value_type),a,a,a);
					}
				}
				sequence_inputs (text,member,p,factory);
				object_inputs (text,program,member,p,factory);
				if (!factory) {
					text.append_printf ("if (!%s_enter(self, error)) return FALSE;\n",p);
				}
				ForeignMemberContract? property_getter = null;
				if (member.kind == ForeignMemberKind.SETTER) {
					for (uint g = 0; g < api.member_count; g++) {
						var candidate = api.member (g);
						if (candidate.kind == ForeignMemberKind.GETTER && candidate.native_member_ordinal == member.native_member_ordinal) {
							property_getter = candidate;
							break;
						}
					}
					if (property_getter == null) {
						throw new ForeignAdapterError.INVALID ("GObject setter lost its actual getter");
					}
					text.append_printf ("%s previous = 0; astra_foreign_error before = {0, 0}; int32_t read_status = %s_%s(self->root, &previous, &before); if (!%s_status(read_status, &before, error)) { %s_leave(self); return FALSE; }\n",ForeignAdapters.declared_type (property_getter.result.value_type,n),n,property_getter.name,p,p);
				}

				if (factory) {
					text.append_printf ("%s_handle *value = NULL;\n",n);
				} else if (result) {
					text.append_printf ("%s value = {0};\n",native_type (member.result,member.result.value_type.kind == ForeignValueKind.GOBJECT ? imported_object (program,member.result.value_type).api.prefix : member.result.value_type.kind == ForeignValueKind.NATIVE_OBJECT && !factory ? object_policy (program,member.result.value_type).prefix : n));
					if (sequence (member.result)) {
						text.append ("int32_t value_length = 0;\n");
					}
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					var channel = member.parameter (a);
					if (channel.value_type.kind == ForeignValueKind.NATIVE_OBJECT && channel.transfer == ForeignTransfer.OWN) {
						text.append_printf ("if (argument%u) g_object_unref(argument%u);\n",a,a);
					}
				}
				text.append_printf ("astra_foreign_error native = {0, 0}; int32_t status = %s_%s(",n,member.name);
				bool comma = !factory;
				if (!factory) {
					text.append ("self->root");
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					if (comma) {
						text.append (", ");
					}
					var channel = member.parameter (a);
					if (channel.by_reference) {
						text.append_printf ("&reference%u",a);
					} else if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
						text.append_printf ("argument%u ? %s_native : NULL, argument%u ? &callback%u : NULL",a,callback_name (policy,channel.value_type),a,a);
					} else if (channel.value_type.object_handle ()) {
						text.append_printf ("%sobject%u",channel.transfer == ForeignTransfer.OWN ? "&" : "",a);
					} else if (channel.value_type.kind == ForeignValueKind.RECORD) {
						text.append_printf ("%s_to_native(argument%u)",record_prefix (policy,channel.value_type),a);
					} else if (sequence (channel)) {
						text.append (channel.direction == ForeignDirection.IN && channel.encoding != ForeignTextEncoding.UTF8_NUL ? "input%u".printf (a) : channel.direction == ForeignDirection.IN ? "argument%u".printf (a) : "(argument%u ? *argument%u : NULL)".printf (a,a));
						if (channel.intrinsic_length) {
							text.append (", " + (channel.direction == ForeignDirection.IN ? "(int32_t)length%u".printf (a) : "(argument%u_capacity ? *argument%u_capacity : -1)".printf (a,a)));
						}
					} else {
						text.append (converted (channel.value_type,is_capacity (member,a) ? "(argument%u ? *argument%u : -1)".printf (a,a) : "argument%u".printf (a),true));
					} comma = true;
				}
				if (factory || result) {
					text.append_printf ("%s&value",comma ? ", " : "");
					if (sequence (member.result)) {
						text.append (", &value_length");
					}
					comma = true;
				}
				text.append_printf ("%s&native);\n",comma ? ", " : "");
				if (factory) {
					text.append_printf ("if (!%s_status(status, &native, error)) { if (value) %s_release(value); return NULL; }\n%s *view = %s_as_gobject(value, error); %s_release(value);\n",p,n,t,p,n);
					for (uint a = 0; a < member.parameter_count; a++) {
						var channel = member.parameter (a);
						if (GObjectExportContract.indirect_reference (channel)) {
							text.append_printf ("if (view) *argument%u = %s;\n",a,converted (channel.value_type,"reference%u".printf (a),false));
						}
					}
					text.append ("return view;\n}\n");
				} else {
					text.append_printf ("gboolean ok = %s_status(status, &native, error);\n",p);
					for (uint a = 0; a < member.parameter_count; a++) {
						var channel = member.parameter (a);
						if (GObjectExportContract.indirect_reference (channel)) {
							text.append_printf ("if (ok) *argument%u = %s;\n",a,converted (channel.value_type,"reference%u".printf (a),false));
						}
					}
					if (result && member.result.value_type.kind == ForeignValueKind.GOBJECT) {
						string other = imported_object (program,member.result.value_type).api.prefix;
						text.append_printf ("if (ok && value) { *result = (%s)%s_extract(&value); } if (value) %s_release(value);\n",channel_type (member.result,policy,program),other,other);
					} else if (result && member.result.value_type.kind == ForeignValueKind.NATIVE_OBJECT) {
						var root = object_policy (program,member.result.value_type);
						text.append_printf ("if (ok && value) { *result = %s_as_gobject(value, error); if (!*result) ok = FALSE; } if (value) %s_release(value);\n",root.gobject.symbol_prefix (),root.prefix);
					} else if (result && member.result.value_type.kind == ForeignValueKind.RECORD) {
						text.append_printf ("if (ok) *result = %s_from_native(value);\n",record_prefix (policy,member.result.value_type));
					} else if (result && sequence (member.result)) {
						sequence_result (text,member.result,p);
					} else if (result) {
						text.append_printf ("if (ok) *result = %s;\n",converted (member.result.value_type,"value",false));
					}
					if (member.kind == ForeignMemberKind.SETTER) {
						text.append_printf ("if (ok && !self->disposed) { %s current = 0; astra_foreign_error after = {0, 0}; int32_t read_status = %s_%s(self->root, &current, &after); ok = %s_status(read_status, &after, error); if (ok && !self->disposed && current != previous) g_object_notify_by_pspec(G_OBJECT(self), %s_properties[%d]); }\n",ForeignAdapters.declared_type (property_getter.result.value_type,n),n,property_getter.name,p,p,property_id (api,member));
					}
					text.append_printf ("%s_leave(self); return ok;\n}\n",p);
				}
			}
			text.append_printf ("static void %s_get_property(GObject *object, guint id, GValue *value, GParamSpec *spec) { %s *self = (%s *)object; (void)self; (void)value; switch (id) {\n",p,t,t);
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!selected (member)) {
					continue;
				}
				if (member.kind != ForeignMemberKind.GETTER) {
					continue;
				}
				text.append_printf ("case %d: { %s result = 0; %s_try_%s(self, &result, NULL); g_value_%s_%s(value, result); break; }\n",property_id (api,member),channel_type (member.result,policy,program),p,member.name,member.result.value_type.scalar () ? "set" : "take",property_suffix (member.result));
			}
			text.append ("default: G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, spec); break; } }\n");
			text.append_printf ("static void %s_set_property(GObject *object, guint id, const GValue *value, GParamSpec *spec) { %s *self = (%s *)object; (void)self; (void)value; switch (id) {\n",p,t,t);
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!selected (member)) {
					continue;
				}
				if (member.kind != ForeignMemberKind.GETTER) {
					continue;
				}
				var set = setter (api,member);
				if (set == null) {
					continue;
				}
				text.append_printf ("case %d: %s_try_%s(self, g_value_get_%s(value), NULL); break;\n",property_id (api,member),p,set.name,value_suffix (member.result.value_type));
			}
			text.append ("default: G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, spec); break; } }\n");
			text.append_printf ("static void %s_class_init(%sClass *klass) { GObjectClass *base = G_OBJECT_CLASS(klass); base->get_property = %s_get_property; base->set_property = %s_set_property; base->dispose = %s_dispose; base->finalize = %s_finalize; (void)%s_properties; (void)%s_signals;\n",p,t,p,p,p,p,p,p);
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!selected (member) || member.kind != ForeignMemberKind.SIGNAL) {
					continue;
				}
				text.append_printf ("%s_signals[%u] = g_signal_new(\"%s\", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, %u",p,m,member.name.replace ("_","-"),member.parameter_count);
				for (uint a = 0; a < member.parameter_count; a++) {
					text.append (", " + signal_type (policy,member.parameter (a),program));
				}
				text.append (");\n");
			}
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				if (!selected (member)) {
					continue;
				}
				if (member.kind != ForeignMemberKind.GETTER) {
					continue;
				}
				string name = property_name (member);
				string arguments = "\"" + name + "\", \"" + name + "\", \"native " + name + "\"";
				string flags = "G_PARAM_READABLE | G_PARAM_EXPLICIT_NOTIFY | G_PARAM_STATIC_STRINGS" + (setter (api,member) == null ? "" : " | G_PARAM_WRITABLE");
				string spec = "g_param_spec_" + property_spec (member.result,policy,program).replace ("@ARGS@",arguments).replace ("@FLAGS@",flags);
				text.append_printf ("%s_properties[%d] = %s; g_object_class_install_property(base, %d, %s_properties[%d]);\n",p,property_id (api,member),spec,property_id (api,member),p,property_id (api,member));
			}
			text.append ("}\n");
		}
		return text.str;
	}

}
}
