// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.CAbi;
namespace Astra.Driver {
// Only representation, context, ownership and status conversion. Every
// application operation dispatches through the declared COM virtual method.
internal class ComDeclared : Object {
	private static string physical(ForeignValueType type, string prefix) throws ForeignAdapterError {
		switch (type.kind) {
		case ForeignValueKind.VOID:
			return "void";
		case ForeignValueKind.I32:
			return "LONG";
		case ForeignValueKind.U32:
			return "ULONG";
		case ForeignValueKind.I64:
			return "LONGLONG";
		case ForeignValueKind.U64:
			return "ULONGLONG";
		case ForeignValueKind.F32:
			return "FLOAT";
		case ForeignValueKind.F64:
			return "DOUBLE";
		case ForeignValueKind.BOOL:
			return "BOOL";
		case ForeignValueKind.RECORD:
			return record_name (type);
		case ForeignValueKind.BYTES:
			return "BYTE";
		case ForeignValueKind.TEXT:
			return "char";
		case ForeignValueKind.COM_OBJECT:
			return interface_alias (type.nominal_origin) + " *";
		case ForeignValueKind.CALLBACK:
			return callback_name (prefix, type);
		default:
			throw new ForeignAdapterError.INVALID ("typed COM channel bridge is not implemented for this declared value kind");
		}
	}

	private static string callback_name(string prefix, ForeignValueType type) {
		return prefix + "_com_callback_" + Checksum.compute_for_string (ChecksumType.SHA256, type.identity ());
	}

	private static string record_name(ForeignValueType type) {
		return "astra_com_record_" + Checksum.compute_for_string (ChecksumType.SHA256, new ForeignComRecordLayout (type).identity ());
	}

	private static string interface_alias(string name) {
		return "astra_com_interface_" + Checksum.compute_for_string (ChecksumType.SHA256, name);
	}

	private static string native_root_key(ForeignClassPolicy policy) {
		return Checksum.compute_for_string (ChecksumType.SHA256, "astra-native-COM-root-v1;" + policy.identity ());
	}

	private static string native_root_iid(ForeignClassPolicy policy) {
		string key = native_root_key (policy);
		return key.substring (0, 8) + "-" + key.substring (8, 4) + "-" + key.substring (12, 4) + "-" + key.substring (16, 4) + "-" + key.substring (20, 12);
	}

	private static ForeignClassPolicy native_root_policy(CheckedProgram program, ForeignChannel channel) throws ForeignAdapterError {
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy != null && policy.declared_api != null && policy.native_name == channel.value_type.nominal_origin && policy.declared_api.lifetime == ForeignLifetime.SHARED && policy.com_count != 0 && policy.valid ()) {
				return policy;
			}
		}
		throw new ForeignAdapterError.INVALID ("COM native Class channel lost its exact Shared root and interface projection");
	}

	private static string converted(ForeignValueType type, string expression, bool to_com) throws ForeignAdapterError {
		if (type.kind == ForeignValueKind.RECORD) {
			return record_name (type) + (to_com ? "_from_c(" : "_to_c(") + expression + ")";
		}
		return type.kind == ForeignValueKind.BOOL ? (to_com ? "(" + expression + " ? TRUE : FALSE)" : "(" + expression + " != FALSE)") : "static_cast<" + (to_com ? physical (type, "") : ForeignAdapters.declared_type (type, "")) + ">(" + expression + ")";
	}

	private static void record(StringBuilder text, ForeignValueType type, HashTable<string, bool> seen, bool implementation) throws ForeignAdapterError {
		if (type.kind != ForeignValueKind.RECORD) {
			return;
		}
		string name = record_name (type);
		if (seen.contains (name)) {
			return;
		}
		seen.insert (name, true);
		var layout = new ForeignComRecordLayout (type);
		if (!layout.valid ()) {
			throw new ForeignAdapterError.INVALID ("typed COM POD lost its exact scalar layout");
		}
		text.append_printf ("struct %s {\n", name);
		for (uint f = 0; f < type.field_count; f++) {
			text.append_printf ("%s %s;\n", physical (new ForeignValueType (type.field (f).kind), ""), CAbiClassAdapter.record_field_name (type.field (f), f));
		}
		text.append_printf ("};\nstatic_assert(sizeof(%s) == %u && alignof(%s) == %u, \"COM POD storage\");\n", name, layout.size, name, layout.alignment);
		for (uint f = 0; f < type.field_count; f++) {
			text.append_printf ("static_assert(offsetof(%s, %s) == %u, \"COM POD field\");\n", name, CAbiClassAdapter.record_field_name (type.field (f), f), layout.offset (f));
		}
		if (!implementation) {
			return;
		}
		foreach (bool to_com in new bool[] { true, false }) {
			text.append_printf ("static inline %s %s_%s(%s value) noexcept { %s result{};\n", to_com ? name : ForeignAdapters.declared_type (type, ""), name, to_com ? "from_c" : "to_c", to_com ? ForeignAdapters.declared_type (type, "") : name, to_com ? name : ForeignAdapters.declared_type (type, ""));
			for (uint f = 0; f < type.field_count; f++) {
				string field = CAbiClassAdapter.record_field_name (type.field (f), f);
				text.append_printf ("result.%s = %s;\n", field, converted (new ForeignValueType (type.field (f).kind), "value." + field, to_com));
			}
			text.append ("return result; }\n");
		}
	}

	private static string failure_domain(ForeignMemberContract member) {
		string result = "0";
		if (member.error_map == null) {
			return result;
		}
		for (uint index = 0; index < member.error_map.case_count; index++) {
			result = "(status == static_cast<HRESULT>(INT32_C(%d)) ? INT32_C(%d) : %s)".printf (member.error_map.at (index).status, member.error_map.domain, result);
		}
		return result;
	}

	private static void fail_return(StringBuilder text, ForeignImportContract root, ForeignMemberContract member, string expression) {
		text.append_printf ("{ HRESULT failure_code = %s; return %s_com_report(failure_code, error, %s); }\n", expression, root.api.prefix, failure_domain (member).replace ("status", "failure_code"));
	}

	private static void signature(StringBuilder text, ForeignComInterface protocol, ForeignMemberContract member, bool definition = false) throws ForeignAdapterError {
		text.append_printf ("virtual HRESULT STDMETHODCALLTYPE %s(", member.name);
		bool comma = false;
		for (uint index = 0; index < member.parameter_count; index++) {
			if (comma) {
				text.append (", ");
			}
			var channel = member.parameter (index);
			bool bytes = CAbiClassAdapter.byte_sequence (channel.value_type.kind);
			text.append_printf ("%s%s argument%u", (channel.by_reference || bytes) && channel.direction == ForeignDirection.IN ? "const " : "", physical (channel.value_type, protocol.prefix) + (channel.by_reference || bytes || channel.value_type.kind == ForeignValueKind.COM_OBJECT && channel.transfer == ForeignTransfer.OWN ? " *" : ""), index);
			if (bytes && channel.intrinsic_length) {
				text.append_printf (", LONG argument%u_%s", index, channel.direction == ForeignDirection.IN ? "length" : "capacity");
			}
			if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf (", void *argument%u_data", index);
			}
			comma = true;
		}
		if (member.result.value_type.kind != ForeignValueKind.VOID) {
			bool bytes = CAbiClassAdapter.byte_sequence (member.result.value_type.kind);
			text.append_printf ("%s%s %sresult%s", comma ? ", " : "", physical (member.result.value_type, protocol.prefix), bytes ? "**" : "*", bytes ? ", LONG *result_length" : "");
		}
		text.append (definition ? ") noexcept override {\n" : ") = 0;\n");
	}

	private static void callbacks(StringBuilder text, ForeignImportContract root, bool implementation) throws ForeignAdapterError {
		string prefix = root.api.prefix;
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (uint index = 0; index < root.api.member_count; index++) {
			var member = root.api.member (index);
			for (uint p = 0; p < member.parameter_count; p++) {
				var type = member.parameter (p).value_type;
				if (type.kind != ForeignValueKind.CALLBACK) {
					continue;
				}
				string name = callback_name (prefix, type);
				if (seen.contains (name)) {
					continue;
				}
				seen.insert (name, true);
				text.append_printf ("using %s = %s (STDMETHODCALLTYPE *)(void *userdata", name, physical (type.callback_result, prefix));
				for (uint a = 0; a < type.callback_parameter_count; a++) {
					text.append_printf (", %s argument%u", physical (type.callback_parameter (a), prefix), a);
				}
				text.append (");\n");
				if (!implementation) {
					continue;
				}
				text.append_printf ("struct %s_context { %s code; void *data; };\nstatic %s STDMETHODCALLTYPE %s_thunk(void *opaque", name, CAbiClassAdapter.callback_name (prefix, type), physical (type.callback_result, prefix), name);
				for (uint a = 0; a < type.callback_parameter_count; a++) {
					text.append_printf (", %s argument%u", physical (type.callback_parameter (a), prefix), a);
				}
				text.append_printf (") noexcept { auto context = static_cast<%s_context *>(opaque);\n", name);
				string invocation = "context->code(context->data";
				for (uint a = 0; a < type.callback_parameter_count; a++) {
					invocation += ", " + converted (type.callback_parameter (a), "argument%u".printf (a), false);
				}
				invocation += ")";
				text.append (type.callback_result.kind == ForeignValueKind.VOID ? invocation + ";\n}\n" : "return " + converted (type.callback_result, invocation, true) + ";\n}\n");
			}
		}
	}

	private static void acquire(StringBuilder text, ForeignImportContract root, ForeignMemberContract member, HashTable<string, string> roots) throws ForeignAdapterError {
		string p = root.api.prefix;
		text.append ("extern \"C\" ");
		ForeignAdapters.declared_signature (text, root.api, member, false, roots);
		text.append (" {\n\tif (!result) ");
		fail_return (text, root, member, "E_POINTER");
		text.append ("\t*result = nullptr; if (error) astra_foreign_error_clear(error); if (!argument0) ");
		fail_return (text, root, member, "E_POINTER");
		text.append ("\tAPTTYPE apartment; APTTYPEQUALIFIER qualifier; HRESULT status = CoGetApartmentType(&apartment, &qualifier); if (FAILED(status)) ");
		fail_return (text, root, member, "status");
		text.append_printf ("\tvoid *raw = nullptr; status = static_cast<IUnknown *>(argument0)->QueryInterface(IID_%s_Interface, &raw);\n\tif (status != S_OK || !raw) { if (raw) static_cast<%s_Interface *>(raw)->Release(); ", p, p);
		fail_return (text, root, member, "FAILED(status) ? status : E_UNEXPECTED");
		text.append ("\t}\n");
		text.append_printf ("\tauto owner = new(std::nothrow) %s_handle{static_cast<%s_Interface *>(raw), astra_foreign14_thread_identity(), apartment, qualifier};\n\tif (!owner) { static_cast<%s_Interface *>(raw)->Release(); ", p, p, p);
		fail_return (text, root, member, "E_OUTOFMEMORY");
		text.append ("\t}\n\t*result = owner; return 0;\n}\n");
	}

	private static void import_method(StringBuilder text, ForeignImportContract root, ForeignMemberContract member, HashTable<string, string> roots) throws ForeignAdapterError {
		string p = root.api.prefix;
		text.append ("extern \"C\" ");
		ForeignAdapters.declared_signature (text, root.api, member, false, roots);
		text.append (" {\n\tif (error) astra_foreign_error_clear(error);\n");
		bool result = member.result.value_type.kind != ForeignValueKind.VOID;
		bool sequence_result = CAbiClassAdapter.byte_sequence (member.result.value_type.kind);
		if (result) {
			text.append ("\tif (!result) ");
			fail_return (text, root, member, "E_POINTER");
		}
		// Snapshot every input before clearing any aliased caller output.
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference) {
				text.append_printf ("\t%s reference%u = %s;\n", physical (channel.value_type, p), a, channel.direction == ForeignDirection.OUT ? "{}" : "argument%u ? %s : %s{}".printf (a, converted (channel.value_type, "*argument%u".printf (a), true), physical (channel.value_type, p)));
			}
		}
		if (result) {
			text.append ("\t*result = {};\n");
		}
		if (sequence_result) {
			text.append ("\tif (!result_length) ");
			fail_return (text, root, member, "E_POINTER");
			text.append ("\t*result_length = 0;\n");
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			if (member.parameter (a).by_reference && member.parameter (a).direction == ForeignDirection.OUT) {
				text.append_printf ("\tif (argument%u) *argument%u = {};\n", a, a);
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference || channel.value_type.kind == ForeignValueKind.CALLBACK && !channel.nullable) {
				text.append_printf ("\tif (!argument%u) ", a);
				fail_return (text, root, member, "E_POINTER");
			}
		}
		text.append_printf ("\tHRESULT status = %s_com_context(self); if (FAILED(status)) ", p);
		fail_return (text, root, member, "status");
		text.append_printf ("\tstatus = astra_foreign16_%s_borrow_acquire(self); if (FAILED(status)) ", p);
		fail_return (text, root, member, "status");
		text.append_printf ("\tastra_com16_owner_pin<%s_handle> pin{self, astra_foreign16_%s_borrow_release};\n", p, p);
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind != ForeignValueKind.COM_OBJECT) {
				continue;
			}
			string other = roots.lookup (channel.value_type.nominal_origin);
			if (other == null) {
				throw new ForeignAdapterError.INVALID ("COM input lost its exact nominal owner");
			}
			if (channel.transfer == ForeignTransfer.OWN) {
				text.append_printf ("\tif (!argument%u) ", a);
				fail_return (text, root, member, "E_POINTER");
			}
			string value = channel.transfer == ForeignTransfer.OWN ? "*argument%u".printf (a) : "argument%u".printf (a);
			text.append_printf ("\tif (%s) { status = %s_com_context(%s); if (FAILED(status)) ", value, other, value);
			fail_return (text, root, member, "status");
			text.append ("\t}\n");
			if (!channel.nullable) {
				text.append_printf ("\tif (!%s) ", value);
				fail_return (text, root, member, "E_POINTER");
			}
		}

		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind != ForeignValueKind.COM_OBJECT || channel.transfer != ForeignTransfer.BORROW) {
				continue;
			}
			string other = roots.lookup (channel.value_type.nominal_origin);
			text.append_printf ("\tstatus = astra_foreign16_%s_borrow_acquire(argument%u); if (FAILED(status)) ", other, a);
			fail_return (text, root, member, "status");
			text.append_printf ("\tastra_com16_owner_pin<%s_handle> input_pin%u{argument%u, astra_foreign16_%s_borrow_release};\n", other, a, a, other);
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind != ForeignValueKind.COM_OBJECT || channel.transfer != ForeignTransfer.OWN) {
				continue;
			}
			text.append_printf ("\t%s owned%u = *argument%u ? (*argument%u)->view : nullptr; if (*argument%u) { auto carrier = *argument%u; if (carrier->retired) { std::abort(); } carrier->retired = true; if (!carrier->borrows) delete carrier; } *argument%u = nullptr;\n", physical (channel.value_type, p), a, a, a, a, a, a);
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var type = member.parameter (a).value_type;
			if (type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("\t%s_context callback%u{argument%u, argument%u_data};\n", callback_name (p, type), a, a, a);
			}
		}
		if (result) {
			text.append_printf ("\t%s%s value{};\n", physical (member.result.value_type, p), sequence_result ? " *" : "");
			if (sequence_result) {
				text.append ("\tLONG value_length = 0;\n");
			}
		}
		text.append_printf ("\tstatus = self->view->%s(", member.name);
		bool comma = false;
		for (uint a = 0; a < member.parameter_count; a++) {
			if (comma) {
				text.append (", ");
			}
			var channel = member.parameter (a);
			if (channel.by_reference) {
				text.append_printf ("&reference%u", a);
			} else if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("argument%u ? %s_thunk : nullptr, argument%u ? &callback%u : nullptr", a, callback_name (p, channel.value_type), a, a);
			} else if (CAbiClassAdapter.byte_sequence (channel.value_type.kind)) {
				text.append_printf ("argument%u", a);
				if (channel.intrinsic_length) {
					text.append_printf (", static_cast<LONG>(argument%u_%s)", a, channel.direction == ForeignDirection.IN ? "length" : "capacity");
				}
			} else if (channel.value_type.kind == ForeignValueKind.COM_OBJECT) {
				text.append (channel.transfer == ForeignTransfer.OWN ? "&owned%u".printf (a) : "argument%u ? argument%u->view : nullptr".printf (a, a));
			} else {
				text.append (converted (channel.value_type, "argument%u".printf (a), true));
			} comma = true;
		}
		if (result) {
			text.append_printf ("%s&value%s", comma ? ", " : "", sequence_result ? ", &value_length" : "");
		}
		text.append (");\n");
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind == ForeignValueKind.COM_OBJECT && channel.transfer == ForeignTransfer.OWN) {
				text.append_printf ("\tif (owned%u) owned%u->Release();\n", a, a);
			}
		}
		if (sequence_result) {
			text.append ("\tif (FAILED(status)) { CoTaskMemFree(value); ");
			fail_return (text, root, member, "status");
			text.append ("\t}\n");
		} else if (member.result.value_type.kind == ForeignValueKind.COM_OBJECT) {
			text.append ("\tif (FAILED(status)) { if (value) value->Release(); ");
			fail_return (text, root, member, "status");
			text.append ("\t}\n");
		} else {
			text.append ("\tif (FAILED(status)) ");
			fail_return (text, root, member, "status");
		}
		if (member.result.value_type.kind == ForeignValueKind.COM_OBJECT) {
			string other = roots.lookup (member.result.value_type.nominal_origin);
			if (other == null) {
				throw new ForeignAdapterError.INVALID ("COM result lost its declared interface owner");
			}
			text.append_printf ("\t%s_handle *published_owner = nullptr; if (value) { published_owner = new(std::nothrow) %s_handle{value, self->thread, self->apartment, self->qualifier}; if (!published_owner) { value->Release(); ", other, other);
			fail_return (text, root, member, "E_OUTOFMEMORY");
			text.append ("\t} }\n");
			if (!member.result.nullable) {
				text.append ("\tif (!value) ");
				fail_return (text, root, member, "E_UNEXPECTED");
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference && channel.direction != ForeignDirection.IN) {
				text.append_printf ("\t*argument%u = %s;\n", a, converted (channel.value_type, "reference%u".printf (a), false));
			}
		}
		if (sequence_result) {
			text.append ("\t*result = value; *result_length = static_cast<int32_t>(value_length);\n");
		} else if (member.result.value_type.kind == ForeignValueKind.COM_OBJECT) {
			text.append ("\t*result = published_owner;\n");
		} else if (result) {
			text.append_printf ("\t*result = %s;\n", converted (member.result.value_type, "value", false));
		}
		if (member.null_status != 0) {
			text.append_printf ("\tif (!value) return INT32_C(%d);\n", member.null_status);
		}
		text.append ("\treturn 0;\n}\n");
	}

	private static void export_callbacks(StringBuilder text, ForeignComInterface protocol) throws ForeignAdapterError {
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (uint m = 0; m < protocol.requirement_count; m++) {
			var member = protocol.requirement (m);
			for (uint p = 0; p < member.parameter_count; p++) {
				var type = member.parameter (p).value_type;
				if (type.kind != ForeignValueKind.CALLBACK) {
					continue;
				}
				string name = callback_name (protocol.prefix, type) + "_export";
				if (seen.contains (name)) {
					continue;
				}
				seen.insert (name, true);
				text.append_printf ("struct %s_context { %s code; void *data; };\nstatic inline %s %s_thunk(void *opaque", name, callback_name (protocol.prefix, type), ForeignAdapters.declared_type (type.callback_result, ""), name);
				for (uint a = 0; a < type.callback_parameter_count; a++) {
					text.append_printf (", %s argument%u", ForeignAdapters.declared_type (type.callback_parameter (a), ""), a);
				}
				text.append_printf (") noexcept { auto context = static_cast<%s_context *>(opaque);\n", name);
				string invocation = "context->code(context->data";
				for (uint a = 0; a < type.callback_parameter_count; a++) {
					invocation += ", " + converted (type.callback_parameter (a), "argument%u".printf (a), true);
				}
				invocation += ")";
				text.append (type.callback_result.kind == ForeignValueKind.VOID ? invocation + ";\n}\n" : "return " + converted (type.callback_result, invocation, false) + ";\n}\n");
			}
		}
	}

	private static void export_method(StringBuilder text, CheckedProgram program, ForeignClassPolicy policy, ForeignComExportBinding binding, uint requirement, HashTable<string, string> roots) throws ForeignAdapterError {
		var member = binding.protocol.requirement (requirement);
		var target = policy.declared_api.member (binding.target (requirement));
		string p = policy.prefix;
		signature (text, binding.protocol, member, true);
		bool result = member.result.value_type.kind != ForeignValueKind.VOID;
		bool sequence = CAbiClassAdapter.byte_sequence (member.result.value_type.kind);
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (!channel.value_type.object_handle () || channel.transfer != ForeignTransfer.OWN) {
				continue;
			}
			text.append_printf ("if (!argument%u) return E_POINTER;\n", a);
			if (result) {
				text.append_printf ("if (static_cast<void *>(argument%u) == static_cast<void *>(result)) return E_INVALIDARG;\n", a);
			}
			for (uint q = 0; q < a; q++) {
				var previous = member.parameter (q);
				if (previous.value_type.object_handle () && previous.transfer == ForeignTransfer.OWN) {
					text.append_printf ("if (static_cast<void *>(argument%u) == static_cast<void *>(argument%u)) return E_INVALIDARG;\n", a, q);
				}
			}
		}
		// Preserve scalar input aliases before zeroing any foreign outputs.
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference) {
				text.append_printf ("%s reference%u = %s;\n", ForeignAdapters.declared_type (channel.value_type, p, roots), a, channel.direction == ForeignDirection.OUT ? "{}" : "argument%u ? %s : %s{}".printf (a, converted (channel.value_type, "*argument%u".printf (a), false), ForeignAdapters.declared_type (channel.value_type, p, roots)));
			}
		}
		if (result) {
			text.append ("if (!result) { return E_POINTER; } *result = {};\n");
			if (sequence) {
				text.append ("if (!result_length) { return E_POINTER; } *result_length = 0;\n");
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference && channel.direction == ForeignDirection.OUT) {
				text.append_printf ("if (argument%u) *argument%u = {};\n", a, a);
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference || channel.value_type.kind == ForeignValueKind.CALLBACK && !channel.nullable) {
				text.append_printf ("if (!argument%u) return E_POINTER;\n", a);
			}
		}
		text.append ("HRESULT status = context(); if (FAILED(status)) return status; astra_com16_import_pin pin(canonical());\n");
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (!CAbiClassAdapter.byte_sequence (channel.value_type.kind) || channel.direction == ForeignDirection.IN) {
				continue;
			}
			string capacity = channel.intrinsic_length ? "argument%u_capacity".printf (a) : "argument%d".printf (channel.capacity_index);
			text.append_printf ("if (%s < 0 || (%s && !argument%u)) return E_INVALIDARG;\nstd::unique_ptr<BYTE[]> output%u(%s ? new(std::nothrow) BYTE[static_cast<size_t>(%s)] : nullptr); if (%s && !output%u) return E_OUTOFMEMORY;\n", capacity, capacity, a, a, capacity, capacity, capacity, a);
			if (channel.direction == ForeignDirection.INOUT) {
				text.append_printf ("if (%s) std::memcpy(output%u.get(), argument%u, static_cast<size_t>(%s));\n", capacity, a, a, capacity);
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind != ForeignValueKind.COM_OBJECT) {
				continue;
			}
			string other = roots.lookup (channel.value_type.nominal_origin);
			if (other == null) {
				throw new ForeignAdapterError.INVALID ("COM export input lost its exact imported owner");
			}
			string value = channel.transfer == ForeignTransfer.OWN ? "*argument%u".printf (a) : "argument%u".printf (a);
			if (ForeignComExportBinding.native_view (target.parameter (a), channel)) {
				var native_root = native_root_policy (program, target.parameter (a));
				string n = native_root.prefix;
				if (!channel.nullable) {
					text.append_printf ("if (!%s) return E_POINTER;\n", value);
				}
				text.append_printf ("std::unique_ptr<%s_handle, decltype(&%s_release)> projected%u(nullptr, %s_release);\nif (%s) { void *raw = nullptr; status = (%s)->QueryInterface(IID_%s_NativeRoot, &raw); auto bridge = static_cast<%s_NativeRoot *>(raw); if (status != S_OK || !bridge) { if (bridge) bridge->Release(); return FAILED(status) ? status : E_UNEXPECTED; } %s_handle *native_root = nullptr; status = bridge->astra_native_root_%s(&native_root); bridge->Release(); projected%u.reset(native_root); if (FAILED(status)) return status; if (!native_root) return E_UNEXPECTED; }\nauto object%u = projected%u.get();\n", n, n, a, n, value, value, n, n, n, native_root_key (native_root), a, a, a);
				continue;
			}
			if (channel.transfer == ForeignTransfer.OWN) {
				text.append_printf ("if (!argument%u) return E_POINTER;\nstd::unique_ptr<%s_handle> pending%u(%s ? new(std::nothrow) %s_handle{%s, astra_foreign14_thread_identity(), apartment, qualifier} : nullptr); auto object%u = pending%u.get(); if (%s && !object%u) return E_OUTOFMEMORY;\n", a, other, a, value, other, value, a, a, value, a);
			} else {
				text.append_printf ("%s_handle object%u{%s, astra_foreign14_thread_identity(), apartment, qualifier}; astra_com16_import_pin object_pin%u(%s);\n", other, a, value, a, value);
			}
			if (!channel.nullable) {
				text.append_printf ("if (!%s) return E_POINTER;\n", value);
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind == ForeignValueKind.COM_OBJECT && channel.transfer == ForeignTransfer.OWN) {
				if (ForeignComExportBinding.native_view (target.parameter (a), channel)) {
					text.append_printf ("if (*argument%u) { (*argument%u)->Release(); } *argument%u = nullptr; projected%u.release();\n", a, a, a, a);
				} else {
					text.append_printf ("*argument%u = nullptr; pending%u.release();\n", a, a);
				}
			}
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var type = member.parameter (a).value_type;
			if (type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("%s_export_context callback%u{argument%u, argument%u_data};\n", callback_name (binding.protocol.prefix, type), a, a, a);
			}
		}
		if (result) {
			text.append_printf ("%s%s value{};\n", sequence ? physical (member.result.value_type, p) : ForeignAdapters.declared_type (target.result.value_type, p, roots), sequence ? " *" : "");
			if (sequence) {
				text.append ("int32_t value_length = 0;\n");
			}
		}
		text.append_printf ("astra_foreign_error error{}; status = static_cast<HRESULT>(%s(root", CAbiClassAdapter.member_symbol (policy.declared_api, target));
		for (uint a = 0; a < member.parameter_count; a++) {
			text.append (", ");
			var channel = member.parameter (a);
			if (channel.by_reference) {
				text.append_printf ("&reference%u", a);
			} else if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				text.append_printf ("argument%u ? %s_export_thunk : nullptr, argument%u ? &callback%u : nullptr", a, callback_name (binding.protocol.prefix, channel.value_type), a, a);
			} else if (CAbiClassAdapter.byte_sequence (channel.value_type.kind)) {
				text.append (channel.direction == ForeignDirection.IN ? "argument%u".printf (a) : "output%u.get()".printf (a));
				if (channel.intrinsic_length) {
					text.append_printf (", static_cast<int32_t>(argument%u_%s)", a, channel.direction == ForeignDirection.IN ? "length" : "capacity");
				}
			} else if (channel.value_type.kind == ForeignValueKind.COM_OBJECT) {
				text.append (channel.transfer == ForeignTransfer.OWN ? "&object%u".printf (a) : ForeignComExportBinding.native_view (target.parameter (a), channel) ? "object%u".printf (a) : "argument%u ? &object%u : nullptr".printf (a, a));
			} else {
				text.append (converted (channel.value_type, "argument%u".printf (a), false));
			}
		}
		if (result) {
			text.append (", &value");
			if (sequence) {
				text.append (", &value_length");
			}
		}
		text.append (", &error));\n");
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.value_type.kind == ForeignValueKind.COM_OBJECT && channel.transfer == ForeignTransfer.OWN) {
				string other = roots.lookup (target.parameter (a).value_type.nominal_origin);
				text.append_printf ("if (object%u) %s_release(object%u);\n", a, other, a);
			}
		}
		if (member.result.value_type.kind == ForeignValueKind.COM_OBJECT) {
			string other = roots.lookup (target.result.value_type.nominal_origin);
			text.append_printf ("if (FAILED(status)) { if (value) %s_release(value); return status; }\n", other);
		} else {
			text.append ("if (FAILED(status)) return status;\n");
		}
		if (sequence) {
			string release = target.result.release_symbol;
			text.append_printf ("%s *copy = nullptr;\nif (value_length < 0 || (value_length && !value)) { %s(&value, &value_length, nullptr); return E_UNEXPECTED; }\n", physical (member.result.value_type, p), release);
			text.append_printf ("if (value_length) { copy = static_cast<%s *>(CoTaskMemAlloc(static_cast<size_t>(value_length)%s)); if (!copy) { %s(&value, &value_length, nullptr); return E_OUTOFMEMORY; } std::memcpy(copy, value, static_cast<size_t>(value_length)); %s }\n", physical (member.result.value_type, p), member.result.encoding == ForeignTextEncoding.UTF8_NUL ? " + 1" : "", release, member.result.encoding == ForeignTextEncoding.UTF8_NUL ? "copy[value_length] = 0;" : "");
			text.append_printf ("int32_t published_length = value_length; %s(&value, &value_length, nullptr); *result = copy; *result_length = static_cast<LONG>(published_length);\n", release);
		} else if (ForeignComExportBinding.native_view (target.result, member.result)) {
			var native_root = native_root_policy (program, target.result);
			var imported = interface_alias (member.result.value_type.nominal_origin);
			string interface_prefix = roots.lookup (member.result.value_type.nominal_origin);
			text.append_printf ("if (value) { IUnknown *unknown = nullptr; HRESULT conversion = %s_as_com(value, &unknown); %s_release(value); if (FAILED(conversion)) return conversion; if (!unknown) return E_UNEXPECTED; void *raw = nullptr; conversion = unknown->QueryInterface(IID_%s_Interface, &raw); unknown->Release(); auto view = static_cast<%s *>(raw); if (conversion != S_OK || !view) { if (view) view->Release(); return FAILED(conversion) ? conversion : E_UNEXPECTED; } *result = view; }\n", native_root.prefix, native_root.prefix, interface_prefix, imported);
		} else if (member.result.value_type.kind == ForeignValueKind.COM_OBJECT) {
			text.append ("if (value) { *result = value->view; if (value->retired) { std::abort(); } value->retired = true; if (!value->borrows) delete value; }\n");
		} else if (result) {
			text.append_printf ("*result = %s;\n", converted (member.result.value_type, "value", true));
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (!CAbiClassAdapter.byte_sequence (channel.value_type.kind) || channel.direction == ForeignDirection.IN) {
				continue;
			}
			string produced = channel.produced_by_result ? "value" : "reference%d".printf (channel.produced_index);
			text.append_printf ("if (%s) std::memcpy(argument%u, output%u.get(), static_cast<size_t>(%s));\n", produced, a, a, produced);
		}
		for (uint a = 0; a < member.parameter_count; a++) {
			var channel = member.parameter (a);
			if (channel.by_reference && channel.direction != ForeignDirection.IN) {
				text.append_printf ("*argument%u = %s;\n", a, converted (channel.value_type, "reference%u".printf (a), true));
			}
		}
		text.append ("return status;\n}\n");
	}

	internal static string generate_exports(CheckedProgram program, bool implementation) throws ForeignAdapterError {
		var text = new StringBuilder ();
		var roots = ForeignAdapters.root_prefixes (program);
		// A compiler-pinned private COM interface proves the native root brand.
		// Inputs are queried through IUnknown, never recovered by pointer casts.
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy == null || policy.com_count == 0 || !policy.active (ForeignClassPolicy.COM)) {
				continue;
			}
			string p = policy.prefix;
			text.append_printf ("inline constexpr IID IID_%s_NativeRoot = %s;\nstruct %s_NativeRoot : IUnknown { virtual HRESULT STDMETHODCALLTYPE astra_native_root_%s(%s_handle **out) = 0; };\nextern \"C\" HRESULT %s_as_com(%s_handle *, IUnknown **) noexcept;\n", p, ComAdapters.guid_initializer (native_root_iid (policy)), p, native_root_key (policy), p, p, p);
		}
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy == null || policy.declared_api == null || policy.com_count == 0 || !policy.active (ForeignClassPolicy.COM)) {
				continue;
			}
			if (!policy.valid ()) {
				throw new ForeignAdapterError.INVALID ("typed COM export lost its exact native requirement bindings");
			}
			string p = policy.prefix;
			if (!implementation) {
				text.append_printf ("extern \"C\" HRESULT %s_as_com(%s_handle *self, IUnknown **out) noexcept;\n", p, p);
				continue;
			}
			text.append ("#include <cstring>\n#include <memory>\n");
			text.append_printf ("extern \"C\" int32_t astra_foreign14_%s_check_thread(%s_handle *);\nextern \"C\" void *astra_foreign14_%s_personality(%s_handle *);\nextern \"C\" int32_t astra_foreign14_%s_attach(%s_handle *, void *, void (*)(void *));\n", p, p, p, p, p, p);
			for (uint b = 0; b < policy.com_count; b++) {
				export_callbacks (text, policy.com_binding (b).protocol);
			}
			text.append_printf ("class %s_Com final : ", p);
			var leaves = new GenericArray<ForeignComInterface> ();
			for (uint b = 0; b < policy.com_count; b++) {
				var protocol = policy.com_binding (b).protocol;
				bool ancestor = false;
				for (uint other = 0; other < policy.com_count; other++) {
					for (var parent = policy.com_binding (other).protocol.parent; parent != null; parent = parent.parent) {
						ancestor |= parent.iid == protocol.iid;
					}
				}
				if (!ancestor) {
					leaves.add (protocol);
				}
			}
			for (uint l = 0; l < leaves.length; l++) {
				text.append_printf ("%spublic %s_Interface", l == 0 ? "" : ", ", leaves[l].prefix);
			}
			text.append_printf (", public %s_NativeRoot", p);
			text.append_printf (" {\n%s_handle *root; APTTYPE apartment; APTTYPEQUALIFIER qualifier;\n~%s_Com() = default;\npublic:\n%s_Com(%s_handle *value, APTTYPE apartment, APTTYPEQUALIFIER qualifier) noexcept : root(value), apartment(apartment), qualifier(qualifier) {}\nstatic void retire(void *value) noexcept { delete static_cast<%s_Com *>(value); }\nIUnknown *canonical() noexcept { return static_cast<%s_Interface *>(this); }\n", p, p, p, p, p, leaves[0].prefix);
			text.append ("HRESULT context() noexcept { HRESULT status = static_cast<HRESULT>(astra_foreign14_@P@_check_thread(root)); if (FAILED(status)) return status; APTTYPE current; APTTYPEQUALIFIER detail; status = CoGetApartmentType(&current, &detail); if (FAILED(status)) return status; return current == apartment && detail == qualifier ? S_OK : RPC_E_WRONG_THREAD; }\nULONG STDMETHODCALLTYPE AddRef() noexcept override { return @P@_acquire(root); }\nULONG STDMETHODCALLTYPE Release() noexcept override { return @P@_release(root); }\nHRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) noexcept override { if (!out) return E_POINTER; *out = nullptr; HRESULT status = context(); if (FAILED(status)) return status; if (IsEqualIID(iid, IID_IUnknown)) *out = canonical();\n".replace ("@P@", p));
			var seen = new HashTable<string, bool> (str_hash, str_equal);
			foreach (var leaf in leaves) {
				for (var protocol = leaf; protocol != null; protocol = protocol.parent) {
					if (seen.contains (protocol.iid)) {
						continue;
					}
					seen.insert (protocol.iid, true);
					text.append_printf ("else if (IsEqualIID(iid, IID_%s_Interface)) *out = static_cast<%s_Interface *>(static_cast<%s_Interface *>(this));\n", protocol.prefix, protocol.prefix, leaf.prefix);
				}
			}
			text.append_printf ("else if (IsEqualIID(iid, IID_%s_NativeRoot)) *out = static_cast<%s_NativeRoot *>(this);\n", p, p);
			text.append ("else { return E_NOINTERFACE; } AddRef(); return S_OK; }\n");
			text.append_printf ("HRESULT STDMETHODCALLTYPE astra_native_root_%s(%s_handle **out) noexcept override { if (!out) return E_POINTER; *out = nullptr; HRESULT status = context(); if (FAILED(status)) return status; if (!%s_acquire(root)) return E_UNEXPECTED; *out = root; return S_OK; }\n", native_root_key (policy), p, p);
			seen.remove_all ();
			for (uint b = 0; b < policy.com_count; b++) {
				var binding = policy.com_binding (b);
				for (uint r = 0; r < binding.protocol.requirement_count; r++) {
					string name = binding.protocol.requirement (r).name;
					if (seen.contains (name)) {
						continue;
					}
					seen.insert (name, true);
					export_method (text, program, policy, binding, r, roots);
				}
			}
			text.append ("};\nextern \"C\" HRESULT @P@_as_com(@P@_handle *self, IUnknown **out) noexcept { if (!out) return E_POINTER; *out = nullptr; HRESULT status = static_cast<HRESULT>(astra_foreign14_@P@_check_thread(self)); if (FAILED(status)) return status; APTTYPE apartment; APTTYPEQUALIFIER qualifier; status = CoGetApartmentType(&apartment, &qualifier); if (FAILED(status)) return status; auto view = static_cast<@P@_Com *>(astra_foreign14_@P@_personality(self)); if (!view) { view = new(std::nothrow) @P@_Com(self, apartment, qualifier); if (!view) return E_OUTOFMEMORY; status = static_cast<HRESULT>(astra_foreign14_@P@_attach(self, view, @P@_Com::retire)); if (FAILED(status)) { @P@_Com::retire(view); return status; } } status = view->context(); if (FAILED(status)) return status; view->AddRef(); *out = view->canonical(); return S_OK; }\n".replace ("@P@", p));
		}
		return text.str;
	}

	internal static string generate_imports(CheckedProgram program, bool implementation) throws ForeignAdapterError {
		var protocols = new GenericArray<ForeignImportContract> ();
		var identities = new StringBuilder ();
		foreach (var handle in program.handles) {
			var root = handle.c_import;
			if (root == null || root.com == null || root.api.active_personalities == 0) {
				continue;
			}
			if (!ForeignImportContract.matches (root, handle.semantic_type.foreign_policy_identity, handle.name, handle.cleanup.external_symbol)) {
				throw new ForeignAdapterError.INVALID ("typed COM import lost exact interface and cleanup identity");
			}
			protocols.add (root);
			identities.append (root.com.identity ());
		}
		if (protocols.length == 0) {
			return "";
		}
		// Refuse an unimplemented conversion before producing a partial SDK.
		foreach (var root in protocols) {
			for (uint m = 0; m < root.api.member_count; m++) {
				var member = root.api.member (m);
				if (member.kind == ForeignMemberKind.CONSTRUCTOR) {
					continue;
				}
				physical (member.result.value_type, root.api.prefix);
				for (uint a = 0; a < member.parameter_count; a++) {
					physical (member.parameter (a).value_type, root.api.prefix);
				}
			}
		}
		string guard = "ASTRA_TYPED_COM_IMPORT_" + Checksum.compute_for_string (ChecksumType.SHA256, identities.str).up ();
		var text = new StringBuilder ("\n#ifndef " + guard + "\n#define " + guard + "\n");
		text.append ((implementation ? "#define ASTRA_FOREIGN16_INTERNAL\n" : "") + ForeignAdapters.header (program));
		text.append ("\n#include <windows.h>\n#include <unknwn.h>\n#include <objbase.h>\nstatic_assert(sizeof(void*) == 8 && sizeof(LONG) == 4 && sizeof(BOOL) == 4 && sizeof(HRESULT) == 4 && sizeof(GUID) == 16, \"typed COM Windows x64 ABI\");\n");
		if (implementation) {
			text.append ("#include <new>\n#include <cstdlib>\nextern \"C\" uint64_t astra_foreign14_thread_identity(void);\ntemplate<class T> struct astra_com16_owner_pin { T *owner; uint32_t (*release)(T *); ~astra_com16_owner_pin() { release(owner); } };\nstruct astra_com16_import_pin { IUnknown *view; explicit astra_com16_import_pin(IUnknown *value) noexcept : view(value) { if (view) view->AddRef(); } ~astra_com16_import_pin() { if (view) view->Release(); } };\n");
		}
		var roots = ForeignAdapters.root_prefixes (program);
		foreach (var root in protocols) {
			text.append_printf ("struct %s_Interface; using %s = %s_Interface;\n", root.api.prefix, interface_alias (root.api.native_origin), root.api.prefix);
		}
		if (implementation) {
			foreach (var root in protocols) {
				string p = root.api.prefix;
				text.append_printf ("struct %s_handle { %s_Interface *view; uint64_t thread; APTTYPE apartment; APTTYPEQUALIFIER qualifier; uint32_t borrows = 0; bool retired = false; };\nstatic HRESULT %s_com_context(%s_handle *) noexcept;\nextern \"C\" int32_t astra_foreign16_%s_borrow_acquire(%s_handle *);\nextern \"C\" uint32_t astra_foreign16_%s_borrow_release(%s_handle *);\n", p, p, p, p, p, p, p, p);
			}
		}
		var records = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var root in protocols) {
			for (uint m = 0; m < root.api.member_count; m++) {
				var member = root.api.member (m);
				record (text, member.result.value_type, records, implementation);
				for (uint a = 0; a < member.parameter_count; a++) {
					record (text, member.parameter (a).value_type, records, implementation);
				}
			}
		}
		foreach (var root in protocols) {
			string p = root.api.prefix;
			var protocol = root.com;
			callbacks (text, root, implementation);
			text.append_printf ("inline constexpr IID IID_%s_Interface = %s;\nstruct %s_Interface : %s {\n", p, ComAdapters.guid_initializer (protocol.iid), p, protocol.parent == null ? "IUnknown" : protocol.parent.prefix + "_Interface");
			for (uint m = protocol.inherited_count; m < protocol.requirement_count; m++) {
				signature (text, protocol, protocol.requirement (m));
			}
			text.append ("};\n");
		}
		if (implementation) {
			foreach (var root in protocols) {
				string p = root.api.prefix;
				foreach (var kind in new ForeignValueKind[] { ForeignValueKind.BYTES, ForeignValueKind.TEXT }) {
					bool used = false;
					for (uint m = 0; m < root.api.member_count; m++) {
						if (root.api.member (m).result.value_type.kind == kind) {
							used = true;
						}
					}
					if (!used) {
						continue;
					}
					text.append_printf ("extern \"C\" int32_t %s_%s_release(%s **data, int32_t *length, astra_foreign_error *error) { if (error) astra_foreign_error_clear(error); if (!data || !length) return static_cast<int32_t>(E_POINTER); auto value = *data; *data = nullptr; *length = 0; CoTaskMemFree(value); return 0; }\n", p, kind == ForeignValueKind.TEXT ? "text" : "bytes", kind == ForeignValueKind.TEXT ? "char" : "uint8_t");
				}
				text.append ("""
static HRESULT @P@_com_context(@P@_handle *self) noexcept {
	if (!self) return E_POINTER;
	if (self->thread != astra_foreign14_thread_identity()) return RPC_E_WRONG_THREAD;
	APTTYPE apartment; APTTYPEQUALIFIER qualifier;
	HRESULT status = CoGetApartmentType(&apartment, &qualifier);
	if (FAILED(status)) return status;
	return apartment == self->apartment && qualifier == self->qualifier ? S_OK : RPC_E_WRONG_THREAD;
}
static int32_t @P@_com_report(HRESULT status, astra_foreign_error *error, int32_t domain) noexcept {
	if (error) { error->domain = domain; error->code = static_cast<int32_t>(status); }
	return static_cast<int32_t>(status);
}
extern "C" uint32_t @P@_release(@P@_handle *self) {
	if (!self) return 0;
	if (FAILED(@P@_com_context(self))) std::abort();
	if (self->retired) { std::abort(); } self->retired = true;
	ULONG remaining = self->view->Release(); if (!self->borrows) delete self; return static_cast<uint32_t>(remaining);
}
extern "C" int32_t astra_foreign16_@P@_borrow_acquire(@P@_handle *self) {
	if (!self) return 0;
	HRESULT status = @P@_com_context(self); if (FAILED(status)) return static_cast<int32_t>(status);
	if (self->borrows == UINT32_MAX) return static_cast<int32_t>(E_UNEXPECTED);
	++self->borrows; self->view->AddRef(); return 0;
}
extern "C" uint32_t astra_foreign16_@P@_borrow_release(@P@_handle *self) {
	if (!self) return 0;
	if (FAILED(@P@_com_context(self))) std::abort();
	if (!self->borrows) { std::abort(); } --self->borrows;
	ULONG remaining = self->view->Release(); if (!self->borrows && self->retired) delete self; return static_cast<uint32_t>(remaining);
}
extern "C" void *@P@_root_identity(@P@_handle *self) {
	if (FAILED(@P@_com_context(self))) return nullptr;
	void *raw = nullptr; HRESULT status = self->view->QueryInterface(IID_IUnknown, &raw); auto identity = static_cast<IUnknown *>(raw);
	if (status != S_OK || !identity) { if (identity) identity->Release(); return nullptr; }
	identity->Release(); return identity;
}
""".replace ("@P@", p));
				for (uint m = 0; m < root.api.member_count; m++) {
					var member = root.api.member (m);
					if (member.kind == ForeignMemberKind.CONSTRUCTOR) {
						acquire (text, root, member, roots);
					} else {
						import_method (text, root, member, roots);
					}
				}
			}
		}
		text.append ("\n#endif\n");
		return text.str;
	}

}
}
