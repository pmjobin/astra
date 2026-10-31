// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.NativeAbi {
// Copied nominal/physical type facts. This model contains no semantic types,
// declaration symbols, executable source, or predecessor-stage objects.
// Copied declared application facts remain independent of semantic types.
public class NativeRecordApplicationPlan : Object {
	public NativeOwnedRecordDeclaration? owned_declaration { get; private set; }
	private string identifier;
	public string definition_name { get { return identifier; } }
	private NativeDeclaredType[] arguments;
	public int argument_count { get { return arguments.length; } }
	public string nominal_name { owned get { return spelling (definition_name, arguments); } }
	public unowned NativeDeclaredType argument(int ordinal) {
		return arguments[ordinal];
	}
	public NativeStructValuePlan record { get; private set; }
	internal NativeRecordApplicationPlan (string name, NativeDeclaredType[] arguments, NativeStructValuePlan record, NativeOwnedRecordDeclaration? owned_declaration = null) {
		identifier = name;
		this.arguments = arguments.copy ();
		this.record = record;
		this.owned_declaration = owned_declaration;
	}
	internal static string spelling(string name, NativeDeclaredType[] arguments) {
		string result = name + "<";
		for (int a = 0; a < arguments.length; a++) {
			result += (a == 0 ? "" : ",") + arguments[a].nominal_name;
		}
		return result + ">";
	}
	internal bool matches(string name, NativeDeclaredType[] actual) {
		if (name != definition_name || actual.length != arguments.length) {
			return false;
		}
		for (int a = 0; a < arguments.length; a++) {
			if (!arguments[a].same_type (actual[a])) {
				return false;
			}
		}
		return true;
	}
	internal bool declared_argument(GenericTypePattern pattern, NativeDeclaredType actual, NativeAbiProgram program) {
		return NativeDeclaredClass.match_arguments (pattern, actual, arguments, program);
	}
}
public class NativeOwnedRecordDeclaration : Object {
	private GenericFieldPattern[] declaration;
	private bool[] owner_parameters;
	private bool[] owned_fields;
	private bool[] private_fields;
	private NativeDeclaredType[] fields;
	internal NativeOwnedRecordDeclaration (GenericFieldPattern[] declaration, bool[] owner_parameters, NativeDeclaredType[] fields, bool[] owned_fields, bool[] private_fields) {
		this.declaration = declaration.copy ();
		this.owner_parameters = owner_parameters.copy ();
		this.fields = fields.copy ();
		this.owned_fields = owned_fields.copy ();
		this.private_fields = private_fields.copy ();
	}
	private static bool resource(NativeRecordResource owner, NativeDeclaredType type) {
		if (owner.type_name != type.name) {
			return false;
		}
		if (type.class_ordinal >= 0) {
			return owner.cleanup_class_ordinal == type.class_ordinal && owner.cleanup_symbol == "" && owner.buffer_cleanup == null;
		}
		if (type.resource != null) {
			return owner.cleanup_class_ordinal == -1 && owner.cleanup_symbol == type.resource.cleanup_symbol && owner.buffer_cleanup == null;
		}
		var element = type.slice_element ();
		if (element == null || owner.buffer_cleanup == null || owner.cleanup_class_ordinal != -1 || owner.cleanup_symbol != "") {
			return false;
		}
		var buffer = owner.buffer_cleanup;
		var context = type.storage as NativeContextSliceType;
		if ((context != null) != (buffer.context_origin != null) || context != null && !context.same_type (buffer.context_origin)) {
			return false;
		}
		return element.record != null ? buffer.record_element != null && buffer.record_element.struct_name == element.record.struct_name : buffer.element_type != null && element.storage != null && buffer.element_type.same_type (element.storage);
	}
	private static bool channel(NativeStructValuePlan record, ref int position, string path, string storage, int component, NativeAbiType type) {
		if (position >= record.leaves.length) {
			return false;
		}
		var actual = record.leaves[position++];
		return actual.field_path == path && actual.storage_path == storage && actual.buffer_component == component && actual.abi_type.get_type () == type.get_type () && actual.abi_type.same_type (type);
	}
	internal bool valid(NativeRecordApplicationPlan application, NativeAbiProgram program, out string reason) {
		reason = "declared argument arity, field inventory or nominal record name";
		if (application.argument_count != owner_parameters.length || application.nominal_name != application.record.struct_name || fields.length != declaration.length || fields.length != owned_fields.length || fields.length != private_fields.length) {
			return false;
		}
		for (int a = 0; a < owner_parameters.length; a++) {
			var argument = application.argument (a);
			reason = "type argument #%d capability".printf (a);
			if (!argument.valid (program)) {
				return false;
			}
			if (owner_parameters[a]) {
				if (!argument.satisfies (GenericCapabilityIdentity.OWNABLE, program)) {
					return false;
				}
			} else if (!argument.plain_record_argument (program)) {
				return false;
			}
		}
		var actual = application.record.declaration;
		int owners = 0;
		int physical = 0;
		for (int f = 0; f < fields.length; f++) {
			var field = fields[f];
			var declared = declaration[f];
			reason = "field #%d declared type, ownership or visibility".printf (f);
			if (!field.valid (program) || declared.owned_field != owned_fields[f] || declared.private_field != private_fields[f] || declared.readonly_field || !application.declared_argument (declared.value_type, field, program)) {
				return false;
			}
			reason = "field #%d exact physical channels".printf (f);
			string prefix = f.to_string ();
			if (field.record != null) {
				foreach (var leaf in field.record.leaves) {
					if (!channel (application.record, ref physical, prefix + "." + leaf.field_path, prefix + "." + leaf.storage_path, leaf.buffer_component, leaf.abi_type)) {
						return false;
					}
				}
			} else if (field.is_slice ()) {
				if (!channel (application.record, ref physical, prefix + "@base", prefix, 0, new NativeScalarAbiType (NativeScalarType.PTR)) || !channel (application.record, ref physical, prefix + "@length", prefix, 1, new NativeScalarAbiType (NativeScalarType.I32))) {
					return false;
				}
			} else if (field.storage == null || !channel (application.record, ref physical, prefix, prefix, -1, field.storage)) {
				return false;
			}
			if (field.record != null && field.record.mode == NativeStructValueMode.MOVE_VALUE) {
				reason = "field #%d recursive record cleanup".printf (f);
				if (actual == null || field.record.declaration == null) {
					return false;
				}
				foreach (var child in field.record.declaration.fields) {
					int matches = 0;
					foreach (var owner in actual.fields) {
						if (owner.depth != child.depth + 1 || owner.path_ordinal (0) != f || owner.type_name != child.type_name || !owner.same_cleanup (child)) {
							continue;
						}
						bool path = true;
						for (int p = 0; p < child.depth; p++) {
							path &= owner.path_ordinal (p + 1) == child.path_ordinal (p);
						}
						if (path) {
							matches++;
						}
					}
					if (matches != 1) {
						return false;
					}
					owners++;
				}
			} else if (owned_fields[f]) {
				reason = "field #%d exact owner release".printf (f);
				if (actual == null) {
					return false;
				}
				int matches = 0;
				foreach (var owner in actual.fields) {
					if (owner.depth == 1 && owner.path_ordinal (0) == f && resource (owner, field)) {
						matches++;
					}
				}
				if (matches != 1) {
					return false;
				}
				owners++;
			}
		}
		reason = "complete recursive owner conservation";
		return physical == application.record.leaves.length && (actual == null ? owners == 0 : owners == actual.field_count && actual.fields.length == actual.field_count);
	}
}
public class NativeDeclaredType : Object {
	private string identifier;
	private string nominal_identifier;
	public string nominal_name { get { return nominal_identifier; } }
	public string name { get { return identifier; } }
	public NativeAbiType? storage { get; private set; }
	public int class_ordinal { get; private set; }
	public NativeStructValuePlan? record { get; private set; }
	public NativeScalarOwner? resource { get; private set; }
	private string? constructor_name;
	private NativeDeclaredType[] application_arguments;

	internal NativeDeclaredType (string name, NativeAbiType? storage, int class_ordinal = -1,
	                             NativeStructValuePlan? record = null, NativeScalarOwner? resource = null,
	                             string? constructor_name = null, NativeDeclaredType[]? application_arguments = null, string? nominal_name = null) {
		identifier = name;
		nominal_identifier = nominal_name ?? name;
		this.storage = storage;
		this.class_ordinal = class_ordinal;
		this.record = record;
		this.resource = resource;
		this.constructor_name = constructor_name;
		this.application_arguments = application_arguments == null ? new NativeDeclaredType[0] : application_arguments.copy ();
	}

	internal bool same_type(NativeDeclaredType other) {
		if (nominal_name != other.nominal_name || constructor_name != other.constructor_name || application_arguments.length != other.application_arguments.length) {
			return false;
		}
		for (int a = 0; a < application_arguments.length; a++) {
			if (!application_arguments[a].same_type (other.application_arguments[a])) {
				return false;
			}
		}
		return class_ordinal == other.class_ordinal && record == other.record &&
			   (resource == null ? other.resource == null : resource.same_owner (other.resource)) &&
			   (storage == null ? other.storage == null : other.storage != null && storage.same_type (other.storage)) && name == other.name;
	}

	internal bool satisfies(GenericCapabilityIdentity capability, NativeAbiProgram program) {
		var domain = GenericCapabilityDomain.NONE;
		if (class_ordinal >= 0) {
			if (class_ordinal < program.classes.length) {
				domain = GenericCapabilityDomain.OWNER;
			}
		} else if (resource != null) {
			domain = GenericCapabilityDomain.OWNER;
		} else {
			var scalar = storage as NativeScalarAbiType;
			if (scalar != null) {
				switch (scalar.scalar_type) {
				case NativeScalarType.I8: case NativeScalarType.U8: case NativeScalarType.I16: case NativeScalarType.U16:
				case NativeScalarType.I32: case NativeScalarType.U32: case NativeScalarType.I64: case NativeScalarType.U64:
					domain = GenericCapabilityDomain.INTEGER;
					break;
				case NativeScalarType.F32:
				case NativeScalarType.F64:
					domain = GenericCapabilityDomain.FLOATING;
					break;
				case NativeScalarType.B1:
					domain = GenericCapabilityDomain.BOOLEAN;
					break;
				case NativeScalarType.PTR:
					if (name == "void*") {
						domain = GenericCapabilityDomain.RAW_POINTER;
					}
					break;
				}
			}
		}
		return capability.valid () && (domain.capabilities () & capability.bit ()) != 0;
	}

	internal bool valid(NativeAbiProgram program) {
		if (name == "") {
			return false;
		}
		if (constructor_name != null && !(constructor_name == "ContextBytes" ? valid_context_bytes (program) : constructor_name == "@slice" ? valid_slice_application (program) : record != null ? valid_record_application (program) : valid_function_application (program))) {
			return false;
		}
		if (constructor_name == null && nominal_name != name) {
			return false;
		}
		if (class_ordinal >= 0) {
			return class_ordinal < program.classes.length && program.classes[class_ordinal].name == name && record == null && resource == null && storage is NativeScalarAbiType && ((NativeScalarAbiType) storage).scalar_type == NativeScalarType.PTR;
		}
		if (record != null) {
			return storage == null && resource == null && record.struct_name == name && program.struct_values.find (record);
		}
		if (resource != null) {
			if (storage == null || resource.type_name != name || resource.class_ordinal != -1 || resource.cleanup_symbol == "") {
				return false;
			}
			var context = storage as NativeContextHandleType;
			if (context != null && (!context.valid () || context.name != name || context.cleanup != resource.cleanup_symbol)) {
				return false;
			}
			try {
				NativeAbiVerifier.verify_type (storage, program.abi_version, "declared generic Resource");
			} catch (NativeAbiError error) {
				return false;
			}
			return true;
		}
		if (storage == null) {
			return name == "void";
		}
		if (storage is NativeOwnerSlotsType) {
			var slots = (NativeOwnerSlotsType) storage;
			return program.abi_version == NativeAbiVersion.OWNER_SLOTS_V15 && slots.base_type == NativeScalarType.PTR && slots.length_type == NativeScalarType.I32 && slots.capacity_type == NativeScalarType.I32 && slots.matches_record_layout ();
		}
		try {
			NativeAbiVerifier.verify_type (storage, program.abi_version, "declared generic type");
		} catch (NativeAbiError error) {
			return false;
		}
		return true;
	}

	private bool valid_slice_application(NativeAbiProgram program) {
		if (constructor_name != "@slice" || application_arguments.length != 1 || class_ordinal >= 0 || record != null || resource != null || storage == null || storage.get_type () != typeof (NativeSliceType)) {
			return false;
		}
		var element = application_arguments[0];
		return element.valid (program) && name == element.name + "[]" && nominal_name == element.nominal_name + "[]";
	}
	private bool valid_context_bytes(NativeAbiProgram program) {
		var bytes = storage as NativeContextSliceType;
		if (bytes == null || !bytes.valid () || application_arguments.length != 1 || class_ordinal >= 0 || record != null || resource != null || name != bytes.name || nominal_name != bytes.name) {
			return false;
		}
		var allocator = application_arguments[0];
		return allocator.valid (program) && allocator.name == bytes.allocator.name && allocator.storage != null && allocator.storage.same_type (bytes.allocator);
	}

	internal bool matches_slice(GenericTypePattern pattern, NativeDeclaredType[] arguments, NativeAbiProgram program, NativeDeclaredType[]? method_arguments) {
		return pattern.kind == GenericTypePatternKind.SLICE && pattern.argument_count == 1 && valid_slice_application (program)
		       && NativeDeclaredClass.match_arguments (pattern.argument (0), application_arguments[0], arguments, program, method_arguments);
	}

	internal bool is_slice() {
		return constructor_name == "@slice" || constructor_name == "ContextBytes";
	}
	internal NativeDeclaredType? slice_element() {
		if (constructor_name == "ContextBytes") {
			return new NativeDeclaredType ("u8", new NativeScalarAbiType (NativeScalarType.U8));
		}
		return constructor_name == "@slice" && application_arguments.length == 1 ? application_arguments[0] : null;
	}
	internal bool plain_record_argument(NativeAbiProgram program) {
		if (!valid (program) || class_ordinal >= 0 || resource != null || is_slice ()) {
			return false;
		}
		if (record != null) {
			return record.mode == NativeStructValueMode.COPY_VALUE;
		}
		if (storage is NativeScalarAbiType && ((NativeScalarAbiType) storage).scalar_type == NativeScalarType.PTR) {
			return name == "void*";
		}
		return storage != null;
	}

	private bool valid_record_application(NativeAbiProgram program) {
		int matches = 0;
		foreach (var application in program.record_applications) {
			if (application.record == record && application.matches (constructor_name, application_arguments)) {
				matches++;
			}
		}
		if (matches != 1 || nominal_name != NativeRecordApplicationPlan.spelling (constructor_name, application_arguments)) {
			return false;
		}
		foreach (var argument in application_arguments) {
			if (!argument.valid (program)) {
				return false;
			}
		}
		return true;
	}

	private bool valid_function_application(NativeAbiProgram program) {
		var signature = storage as NativeFunctionPointerType;
		if ((constructor_name == "Callback" ? !(signature is NativeCallbackType) : constructor_name != "Fn" || signature is NativeCallbackType) || signature == null || class_ordinal >= 0 || record != null || resource != null || application_arguments.length < 1 || application_arguments.length > ((signature is NativeCallbackType) ? 257 : 5)) {
			return false;
		}
		foreach (var argument in application_arguments) {
			if (!argument.valid (program)) {
				return false;
			}
		}
		var result = application_arguments[0].storage as NativeScalarAbiType;
		var record_result = application_arguments[0].record;
		if (signature.void_result) {
			if (signature.result_scalar () != null || signature.record_result != null || result != null || record_result != null || application_arguments[0].name != "void") {
				return false;
			}
		} else if (signature.record_result != null) {
			if (signature.result_scalar () != null || record_result == null || !signature.record_result.matches (record_result.struct_name, record_result.mode, record_result.leaves)) {
				return false;
			}
		} else {
			if (record_result != null || result == null || result.get_type () != typeof (NativeScalarAbiType) || result.scalar_type != signature.result_scalar ()) {
				return false;
			}
		}
		int physical = 0;
		int group = 0;
		int borrowed = 0;
		int owned_count = 0;
		if (signature.owned_result != null && (signature.owned_result.type_name != application_arguments[0].name || signature.owned_result.is_class != (application_arguments[0].class_ordinal >= 0))) {
			return false;
		}
		string expected_name = ((signature is NativeCallbackType) ? "Callback<" : "Fn<") + (signature.owned_result == null ? "" : "owned ") + application_arguments[0].name;
		string expected_nominal = ((signature is NativeCallbackType) ? "Callback<" : "Fn<") + (signature.owned_result == null ? "" : "owned ") + application_arguments[0].nominal_name;
		for (int p = 1; p < application_arguments.length; p++) {
			var argument = application_arguments[p];
			var channel = borrowed < signature.borrowed_parameters.length ? signature.borrowed_parameters[borrowed] : null;
			bool scalar_borrow = channel != null && channel.ordinal == physical;
			var transfer = owned_count < signature.owned_parameters.length ? signature.owned_parameters[owned_count] : null;
			bool scalar_owned = transfer != null && transfer.ordinal == physical;
			if (scalar_owned) {
				if (scalar_borrow || transfer.type_name != argument.name || transfer.is_class != (argument.class_ordinal >= 0) || (!transfer.is_class && argument.resource == null) || argument.record != null) {
					return false;
				}
				owned_count++;
			}
			bool record_borrow = argument.record != null && group < signature.record_parameters.length && signature.record_parameters[group].mode == NativeStructValueMode.BORROW_VALUE;
			bool observes = scalar_borrow || record_borrow;
			if (scalar_borrow) {
				if (channel.type_name != argument.name || channel.is_class != (argument.class_ordinal >= 0) || (!channel.is_class && argument.resource == null) || argument.record != null) {
					return false;
				}
				borrowed++;
			}
			expected_name += "," + (scalar_owned ? "owned " : observes ? "borrowed " : "") + argument.name;
			expected_nominal += "," + (scalar_owned ? "owned " : observes ? "borrowed " : "") + argument.nominal_name;
			if (argument.record != null) {
				if (group >= signature.record_parameters.length) {
					return false;
				}
				var declared = signature.record_parameters[group++];
				if (declared.source_ordinal != p - 1 || declared.first_leaf != physical || declared.record_name != argument.record.struct_name || declared.leaves.length != argument.record.leaves.length || !declared.mode.matches_storage (argument.record)) {
					return false;
				}
				foreach (var leaf in argument.record.leaves) {
					if (physical >= signature.parameter_types.length || !leaf.abi_type.same_type (signature.parameter_types[physical++])) {
						return false;
					}
				}
			} else {
				if (argument.storage == null || physical >= signature.parameter_types.length || !argument.storage.same_type (signature.parameter_types[physical++])) {
					return false;
				}
			}
		}
		return nominal_name == expected_nominal + ">" && name == expected_name + ">" && physical == signature.parameter_types.length && group == signature.record_parameters.length && borrowed == signature.borrowed_parameters.length && owned_count == signature.owned_parameters.length;
	}

	internal bool matches_application(GenericTypePattern pattern, NativeDeclaredType[] arguments, NativeAbiProgram program, NativeDeclaredType[]? method_arguments) {
		if (constructor_name != pattern.name || application_arguments.length != pattern.argument_count || !valid (program)) {
			return false;
		}
		var signature = storage as NativeFunctionPointerType;
		if (signature != null) {
			if ((pattern.argument (0).value_mode == GenericValueMode.OWNED) != (signature.owned_result != null)) {
				return false;
			}
			int physical = 0;
			for (int p = 1; p < application_arguments.length; p++) {
				var argument = application_arguments[p];
				bool borrows = false, consumes = false;
				foreach (var channel in signature.borrowed_parameters) {
					if (channel.ordinal == physical) {
						borrows = true;
					}
				}
				foreach (var channel in signature.owned_parameters) {
					if (channel.ordinal == physical) {
						consumes = true;
					}
				}
				foreach (var group in signature.record_parameters) {
					if (group.source_ordinal == p - 1 && group.mode == NativeStructValueMode.BORROW_VALUE) {
						borrows = true;
					}
				}
				var mode = pattern.argument (p).value_mode;
				bool owner = argument.class_ordinal >= 0 || argument.resource != null || argument.record != null && argument.record.mode == NativeStructValueMode.MOVE_VALUE;
				if (consumes != (mode == GenericValueMode.OWNED) || borrows != (mode == GenericValueMode.BORROWED && owner)) {
					return false;
				}
				physical += argument.record == null ? 1 : argument.record.leaves.length;
			}
		}
		for (int a = 0; a < application_arguments.length; a++) {
			if (!NativeDeclaredClass.match_arguments (pattern.argument (a), application_arguments[a], arguments, program, method_arguments)) {
				return false;
			}
		}
		return true;
	}
}

public class NativeDeclaredMember : Object {
	public GenericMemberPattern declaration { get; private set; }
	public int target { get; private set; }
	public NativeDeclaredType result { get; private set; }
	private NativeDeclaredType[] parameters;
	private NativeDeclaredType[] method_arguments;
	private bool[] heap_parameters;
	private bool heap_result;

	internal NativeDeclaredMember (GenericMemberPattern declaration, int target, NativeDeclaredType result,
	                               NativeDeclaredType[] parameters, bool[] heap_parameters, bool heap_result,
	                               NativeDeclaredType[]? method_arguments = null) {
		this.declaration = declaration;
		this.target = target;
		this.result = result;
		this.parameters = parameters.copy ();
		this.heap_parameters = heap_parameters.copy ();
		this.heap_result = heap_result;
		this.method_arguments = method_arguments == null ? new NativeDeclaredType[0] : method_arguments.copy ();
	}

	internal void verify(NativeDeclaredClass key, NativeClassPlan owner, NativeAbiProgram program) throws NativeAbiError {
		if (target < 0 || target >= program.functions.length || parameters.length != declaration.parameter_count || heap_parameters.length != parameters.length) {
			NativeDeclaredClass.reject ("member target/arity");
		}
		var function = program.functions[target];
		var signature = function.signature;
		if (!function.declaring_type_is_class || function.declaring_type_ordinal != owner.ordinal || signature.receiver == null) {
			NativeDeclaredClass.reject ("member receiver");
		}
		NativeCallableKind kind;
		switch (declaration.kind) {
		case GenericMemberPatternKind.CONSTRUCTOR: kind = NativeCallableKind.CONSTRUCTOR;
			break;
		case GenericMemberPatternKind.DESTRUCTOR: kind = NativeCallableKind.DESTRUCTOR;
			break;
		case GenericMemberPatternKind.GETTER: kind = NativeCallableKind.PROPERTY_GETTER;
			break;
		case GenericMemberPatternKind.SETTER:
			kind = NativeCallableKind.PROPERTY_SETTER;
			break;
		default:
			kind = NativeCallableKind.METHOD;
			break;
		}
		if (function.kind != kind || method_arguments.length != declaration.type_parameter_count) {
			NativeDeclaredClass.reject ("member kind/type-argument arity");
		}
		var binding = function.generic_method_instance;
		if (method_arguments.length == 0 ? binding != null : binding == null || !binding.valid_arguments (program) || !binding.matches_arguments (method_arguments)) {
			NativeDeclaredClass.reject ("member ordered type-argument binding");
		}
		for (int c = 0; c < declaration.constraint_count; c++) {
			if (!key.constraint (declaration.constraint (c), program, method_arguments)) {
				NativeDeclaredClass.reject ("member substituted capability constraint");
			}
		}
		string name = declaration.name;
		if (method_arguments.length != 0) {
			name += "<";
			for (int a = 0; a < method_arguments.length; a++) {
				if (!method_arguments[a].valid (program)) {
					NativeDeclaredClass.reject ("method type argument");
				}
				name += (a == 0 ? "" : ",") + method_arguments[a].nominal_name;
			}
			name += ">";
		}
		if (function.name != name || (declaration.dispatch == 0 ? function.virtual_slot != -1 : function.virtual_slot < 0)) {
			NativeDeclaredClass.reject ("member name/dispatch");
		}
		bool async_member = false;
		foreach (var frame in program.async_frames) {
			if (frame.function_ordinal == target) {
				async_member = true;
			}
		}
		if (async_member != declaration.async_member) {
			NativeDeclaredClass.reject ("async member identity");
		}
		if (!key.matches (declaration.result, result, program, method_arguments) || !result.valid (program)) {
			NativeDeclaredClass.reject ("member result substitution");
		}
		bool borrowed_result = declaration.result_mode == GenericValueMode.BORROWED && (result.class_ordinal >= 0 || result.resource != null || result.record != null && result.record.mode == NativeStructValueMode.MOVE_VALUE);
		if (function.receiver_borrow != borrowed_result) {
			NativeDeclaredClass.reject ("receiver-borrow result provenance");
		}
		if ((declaration.error == null) != (signature.exception_plan == null)) {
			NativeDeclaredClass.reject ("checked member effect");
		}
		if (signature.exception_plan != null) {
			var error = signature.exception_plan;
			var type = new NativeDeclaredType (error.bound_name, new NativeScalarAbiType (NativeScalarType.PTR), error.bound_ordinal);
			if (!key.matches (declaration.error, type, program, method_arguments)) {
				NativeDeclaredClass.reject ("checked member error identity");
			}
		}
		bool owns_class_result = result.class_ordinal >= 0 && declaration.result_mode == GenericValueMode.OWNED;
		if (owns_class_result && !heap_result) {
			if (signature.result == null || result.storage == null || !result.storage.same_type (signature.result.abi_type) || signature.object_result == null || signature.heap_result != null) {
				NativeDeclaredClass.reject ("caller-backed result provenance");
			}
		} else if (result.storage is NativeSumType) {
			if (signature.sum_result == null || signature.sum_result.identity != ((NativeSumType) result.storage).identity || signature.result != null) {
				NativeDeclaredClass.reject ("enum result grouping");
			}
		} else if (result.record != null) {
			if (signature.struct_result != result.record || signature.result != null || signature.struct_result_mode != (borrowed_result ? NativeStructValueMode.BORROW_VALUE : result.record.mode)) {
				NativeDeclaredClass.reject ("record result grouping");
			}
		} else if (result.storage == null ? signature.result != null : signature.result == null || !result.storage.same_type (signature.result.abi_type)) {
			NativeDeclaredClass.reject ("result physical channel");
		}
		if (owns_class_result && heap_result && (signature.heap_result == null || !signature.heap_result.heap || signature.heap_result.class_ordinal != result.class_ordinal)) {
			NativeDeclaredClass.reject ("owned result provenance");
		}
		if (!owns_class_result) {
			if (signature.heap_result != null || signature.object_result != null) {
				NativeDeclaredClass.reject ("unrelated object result ownership");
			}
		}
		if (result.resource != null && declaration.result_mode == GenericValueMode.OWNED) {
			if (!result.resource.same_owner (signature.resource_result)) {
				NativeDeclaredClass.reject ("Resource result cleanup");
			}
		} else if (signature.resource_result != null) {
			NativeDeclaredClass.reject ("unrelated Resource result ownership");
		}
		int physical = 0;
		int groups = 0;
		for (int p = 0; p < parameters.length; p++) {
			var type = parameters[p];
			if (!type.valid (program) || !key.matches (declaration.parameter_type (p), type, program, method_arguments)) {
				NativeDeclaredClass.reject ("member parameter substitution");
			}
			if (type.record != null) {
				NativeStructParameterPlan? group = null;
				foreach (var candidate in signature.struct_parameters) {
					if (candidate.source_ordinal == p) {
						group = candidate;
					}
				}
				var mode = declaration.parameter_mode (p) == GenericValueMode.BORROWED && type.record.mode == NativeStructValueMode.MOVE_VALUE ? NativeStructValueMode.BORROW_VALUE : type.record.mode;
				if (group == null || group.first_leaf != physical || group.value_plan != type.record || group.mode != mode) {
					NativeDeclaredClass.reject ("record parameter grouping or declared copy, move or borrowed operation");
				}
				physical += type.record.leaves.length;
				groups++;
				continue;
			}
			if (physical >= signature.parameters.length) {
				NativeDeclaredClass.reject ("parameter physical arity");
			}
			var actual = signature.parameters[physical++];
			if (type.storage == null || !type.storage.same_type (actual.abi_type)) {
				NativeDeclaredClass.reject ("parameter physical type");
			}
			if (type.class_ordinal >= 0) {
				if (declaration.parameter_mode (p) == GenericValueMode.OWNED) {
					if (actual.object_origin == null || actual.object_origin.heap != heap_parameters[p] || actual.object_origin.class_ordinal != type.class_ordinal) {
						NativeDeclaredClass.reject ("parameter owner provenance");
					}
				} else if (actual.object_origin != null || actual.borrowed_class_ordinal != type.class_ordinal) {
					NativeDeclaredClass.reject ("parameter borrow provenance");
				}
			} else if (type.resource != null && (!type.resource.same_owner (actual.resource) || actual.owns_resource != (declaration.parameter_mode (p) == GenericValueMode.OWNED))) {
				NativeDeclaredClass.reject ("Resource parameter cleanup");
			}
		}
		if (physical != signature.parameters.length || groups != signature.struct_parameters.length) {
			NativeDeclaredClass.reject ("unrelated parameter channel");
		}
	}
}

public class NativeDeclaredClass : Object {
	public ExactClassDefinitionIdentity definition { get; private set; }
	private NativeDeclaredType[] arguments;
	private NativeDeclaredType[] fields;
	private NativeDeclaredMember[] members;
	public int argument_count { get { return arguments.length; } }
	public unowned NativeDeclaredType argument(int ordinal) {
		return arguments[ordinal];
	}
	public int field_count { get { return fields.length; } }
	public unowned NativeDeclaredType field_type(int ordinal) {
		return fields[ordinal];
	}
	public int member_count { get { return members.length; } }
	public unowned NativeDeclaredMember member(int ordinal) {
		return members[ordinal];
	}

	internal NativeDeclaredClass (ExactClassDefinitionIdentity definition, NativeDeclaredType[] arguments,
	                              NativeDeclaredType[] fields, NativeDeclaredMember[] members) {
		this.definition = definition;
		this.arguments = arguments.copy ();
		this.fields = fields.copy ();
		this.members = members.copy ();
	}

	internal static void reject(string fact) throws NativeAbiError {
		throw new NativeAbiError.INVALID_ABI ("declared generic native Class lost %s", fact);
	}

	internal bool constraint(GenericTypeConstraint constraint, NativeAbiProgram program, NativeDeclaredType[]? method_arguments = null) {
		var types = constraint.method_parameter ? method_arguments : arguments;
		if (types == null || constraint.parameter < 0 || constraint.parameter >= types.length) {
			return false;
		}
		if (constraint.exact_heap_class) {
			int ordinal = types[constraint.parameter].class_ordinal;
			if (ordinal < 0 || ordinal >= program.classes.length) {
				return false;
			}
			var owner = program.classes[ordinal];
			return owner.generic_instance == null && !owner.polymorphic && owner.parent_ordinal < 0 && !owner.is_interface;
		}
		for (int c = 0; c < constraint.capabilities.length; c++) {
			if (!types[constraint.parameter].satisfies (constraint.capabilities.at (c), program)) {
				return false;
			}
		}
		return true;
	}

	internal bool matches(GenericTypePattern pattern, NativeDeclaredType actual, NativeAbiProgram program, NativeDeclaredType[]? method_arguments = null) {
		return match_arguments (pattern, actual, arguments, program, method_arguments);
	}
	internal static bool match_arguments(GenericTypePattern pattern, NativeDeclaredType actual, NativeDeclaredType[] arguments, NativeAbiProgram program, NativeDeclaredType[]? method_arguments = null) {
		if (pattern.kind == GenericTypePatternKind.PARAMETER) {
			return pattern.parameter >= 0 && pattern.parameter < arguments.length && arguments[pattern.parameter].same_type (actual);
		}
		if (pattern.kind == GenericTypePatternKind.METHOD_PARAMETER) {
			return method_arguments != null && pattern.parameter >= 0 && pattern.parameter < method_arguments.length && method_arguments[pattern.parameter].same_type (actual);
		}
		if (pattern.kind == GenericTypePatternKind.NONNULL) {
			return match_arguments (pattern.argument (0), actual, arguments, program, method_arguments);
		}
		if (pattern.kind == GenericTypePatternKind.NAMED) {
			return (pattern.name == "i32" && actual.name == "int") || pattern.name == actual.name;
		}
		if (pattern.kind == GenericTypePatternKind.APPLICATION && (actual.storage is NativeFunctionPointerType || actual.storage is NativeContextSliceType || actual.record != null)) {
			return actual.matches_application (pattern, arguments, program, method_arguments);
		}
		if (pattern.kind == GenericTypePatternKind.APPLICATION && actual.class_ordinal >= 0 && actual.class_ordinal < program.classes.length) {
			var instance = program.classes[actual.class_ordinal].generic_instance;
			var nested = instance == null ? null : instance.declared_structure;
			if (nested == null || nested.definition.name != pattern.name || nested.arguments.length != pattern.argument_count) {
				return false;
			}
			for (int a = 0; a < pattern.argument_count; a++) {
				if (!match_arguments (pattern.argument (a), nested.arguments[a], arguments, program, method_arguments)) {
					return false;
				}
			}
			return true;
		}
		if (pattern.kind == GenericTypePatternKind.SLICE) {
			return actual.matches_slice (pattern, arguments, program, method_arguments);
		}
		if (pattern.kind == GenericTypePatternKind.OWNER_SLOTS && actual.storage is NativeOwnerSlotsType) {
			var slots = (NativeOwnerSlotsType) actual.storage;
			string name = slots.record_value != null ? slots.record_value.struct_name : slots.resource != null ? slots.resource.type_name : slots.element_ordinal >= 0 && slots.element_ordinal < program.classes.length ? program.classes[slots.element_ordinal].name : "";
			var element = new NativeDeclaredType (name, slots.record_value == null ? new NativeScalarAbiType (NativeScalarType.PTR) : null, slots.element_ordinal, slots.record_value, slots.resource);
			return match_arguments (pattern.argument (0), element, arguments, program, method_arguments);
		}
		return false;
	}

	internal bool same_arguments(NativeDeclaredClass other) {
		if (definition != other.definition || arguments.length != other.arguments.length) {
			return false;
		}
		for (int a = 0; a < arguments.length; a++) {
			if (!arguments[a].same_type (other.arguments[a])) {
				return false;
			}
		}
		return true;
	}

	internal void verify(NativeClassPlan owner, NativeAbiProgram program) throws NativeAbiError {
		var structure = definition.structure;
		if (structure == null || !definition.valid () || arguments.length != structure.parameter_count || fields.length != structure.field_count || owner.fields.length != fields.length || !owner.matches_slot_declarations ()) {
			reject ("definition/argument/field inventory");
		}
		foreach (var argument in arguments) {
			if (!argument.valid (program)) {
				reject ("type argument identity");
			}
		}
		for (int c = 0; c < structure.constraint_count; c++) {
			if (!constraint (structure.constraint (c), program)) {
				reject ("Class substituted capability constraint");
			}
		}
		for (int f = 0; f < fields.length; f++) {
			var declared = structure.field (f);
			var actual = owner.fields[f];
			var type = fields[f];
			if (!type.valid (program) || !matches (declared.value_type, type, program) || declared.name != actual.name || actual.is_private != declared.private_field || actual.text_snapshot != declared.readonly_field) {
				reject ("field type/visibility substitution");
			}
			if (actual.type_name != type.name || (type.record == null ? actual.record_ordinal != -1 || actual.storage_type == null || type.storage == null || !type.storage.same_type (actual.storage_type) : actual.record_ordinal != type.record.struct_ordinal || actual.storage_type != null)) {
				reject ("field physical layout");
			}
			if (actual.owns_record != (type.record != null && type.record.mode == NativeStructValueMode.MOVE_VALUE)) {
				reject ("field aggregate responsibility");
			}
			if (actual.owns_buffer != (type.is_slice () && declared.owned_field)) {
				reject ("field buffer responsibility");
			}
			if (type.class_ordinal >= 0 && declared.owned_field && actual.owned_class_ordinal != type.class_ordinal) {
				reject ("field cleanup origin");
			}
			if (type.resource != null && declared.owned_field) {
				if (!type.resource.same_owner (actual.resource_owner)) {
					reject ("field Resource cleanup");
				}
			} else if (actual.resource_owner != null) {
				reject ("unrelated field Resource ownership");
			}
		}
		var targets = new HashTable<int, bool> (direct_hash, direct_equal);
		foreach (var member in members) {
			if (targets.contains (member.target)) {
				reject ("duplicate member target");
			}
			targets.insert (member.target, true);
			bool declared = false;
			for (int m = 0; m < structure.member_count; m++) {
				if (structure.member (m) == member.declaration) {
					declared = true;
				}
			}
			for (int p = 0; p < structure.property_count; p++) {
				var property = structure.property (p);
				if (property.getter != member.declaration && property.setter != member.declaration) {
					continue;
				}
				declared = true;
				if (member.target < 0 || member.target >= program.functions.length || program.functions[member.target].property_ordinal != p) {
					reject ("property member identity");
				}
			}
			if (!declared) {
				reject ("unrelated member declaration");
			}
			member.verify (this, owner, program);
		}
		// The compatibility inspection tables must agree with the same exact
		// declaration identities as the complete structural member inventory.
		var member_map = owner.generic_instance;
		if (member_map == null || member_map.declared_structure != this) {
			reject ("member target map owner identity");
		}
		int member_rank = 0;
		for (int m = 0; m < structure.member_count; m++) {
			var declaration = structure.member (m);
			if (declaration.kind == GenericMemberPatternKind.DESTRUCTOR || declaration.type_parameter_count != 0) {
				continue;
			}
			bool matched = false;
			foreach (var member in members) {
				if (member.declaration == declaration && member_rank < member_map.member_count && member.target == member_map.member_target (member_rank)) {
					matched = true;
				}
			}
			if (!matched) {
				reject ("member target map correspondence");
			}
			member_rank++;
		}
		if (member_rank != member_map.member_count || member_map.property_count != structure.property_count) {
			reject ("member/property target map inventory");
		}
		for (int p = 0; p < structure.property_count; p++) {
			bool matched = false;
			foreach (var member in members) {
				if (member.declaration == structure.property (p).getter && member.target == member_map.property_target (p)) {
					matched = true;
				}
			}
			if (!matched) {
				reject ("property target map correspondence");
			}
		}
		foreach (var function in program.functions) {
			if (!function.declaring_type_is_class || function.declaring_type_ordinal != owner.ordinal || function.kind == NativeCallableKind.DESTRUCTOR) {
				continue;
			}
			if (!targets.contains (function.ordinal)) {
				reject ("incomplete member inventory");
			}
		}
		for (int m = 0; m < structure.member_count; m++) {
			var declared = structure.member (m);
			if (declared.type_parameter_count != 0) {
				continue;
			}
			int count = 0;
			foreach (var member in members) {
				if (member.declaration == declared) {
					count++;
				}
			}
			if (count != 1) {
				reject ("missing declared member");
			}
		}
		foreach (var other in program.classes) {
			var instance = other.generic_instance;
			if (other != owner && instance != null && instance.declared_structure != null && same_arguments (instance.declared_structure)) {
				reject ("duplicate specialization identity");
			}
		}
	}
}
}
