// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
namespace Astra.NativeAbi {
// A copied method type argument, with a frozen complete record layout when
// it has value storage. This is compile-time metadata, not a runtime box.
public class NativeCopyType : Object {
	private string identifier;
	public string name { get { return identifier; } }
	public NativeAbiType? abi_type { get; private set; }
	public NativeStructValuePlan? record { get; private set; }
	private GenericArray<NativeStructLeafChannel> leaves = new GenericArray<NativeStructLeafChannel> ();
	internal NativeCopyType (string name, NativeAbiType? type, NativeStructValuePlan? record = null) {
		identifier = name;
		abi_type = type;
		this.record = record;
		if (record != null) {
			foreach (var leaf in record.leaves) {
				leaves.add (leaf);
			}
		}
	}

	internal bool matches_layout() {
		if (record == null) {
			return leaves.length == 0;
		}
		if (record.mode != NativeStructValueMode.COPY_VALUE || record.ownership.length != 0 || record.leaves.length != leaves.length || record.struct_name != name) {
			return false;
		}
		for (int l = 0; l < leaves.length; l++) {
			var original = leaves[l];
			var actual = record.leaves[l];
			if (original.field_path != actual.field_path || original.storage_path != actual.storage_path || original.buffer_component != actual.buffer_component || !original.abi_type.same_type (actual.abi_type)) {
				return false;
			}
		}
		return true;
	}

	internal bool valid(NativeAbiProgram program) {
		if (name == "" || (record == null) == (abi_type == null) || !matches_layout ()) {
			return false;
		}
		if (record != null) {
			return program.struct_values.find (record);
		}
		try {
			NativeAbiVerifier.verify_type (abi_type, program.abi_version, "generic method argument");
		} catch (NativeAbiError error) {
			return false;
		}
		var scalar = abi_type as NativeScalarAbiType;
		if (scalar != null) {
			return abi_type.get_type () == typeof (NativeScalarAbiType) && (scalar.scalar_type != NativeScalarType.PTR || name == "void*");
		}
		if (abi_type is NativeVectorType) {
			return true;
		}
		var sum = abi_type as NativeSumType;
		if (sum != null && sum.identity.name == name && sum.role == NativeSumRole.SNAPSHOT_READONLY) {
			foreach (var plan in program.sum_values) {
				if (plan.identity == sum.identity) {
					return !plan.owning;
				}
			}
		}
		return false;
	}

	internal bool same_type(NativeCopyType other) {
		return name == other.name && record == other.record && matches_layout () && other.matches_layout () && (abi_type == null ? other.abi_type == null : other.abi_type != null && abi_type.same_type (other.abi_type));
	}

}
public class NativeGenericMethodInstance : Object {
	public ExactClassDefinitionIdentity definition { get; private set; }
	public int class_ordinal { get; private set; }
	public int member { get; private set; }
	public int target_ordinal { get; private set; }
	private NativeDeclaredType[] arguments;
	public int argument_count { get { return arguments.length; } }
	public unowned NativeDeclaredType argument_type(int index) {
		return arguments[index];
	}

	// Compatibility inspection for the original copied singleton profile.
	public NativeCopyType argument { get; private set; }
	public string name {
		owned get {
			var text = new StringBuilder (definition.generic_method_name (member) + "<");
			for (int a = 0; a < arguments.length; a++) {
				if (a != 0) {
					text.append (",");
				}
				text.append (arguments[a].nominal_name);
			}
			text.append (">");
			return text.str;
		}
	}
	internal NativeGenericMethodInstance (ExactClassDefinitionIdentity definition, int owner, int member, int target, NativeCopyType argument) {
		this.declared (definition, owner, member, target, new NativeDeclaredType[] { new NativeDeclaredType (argument.name, argument.abi_type, -1, argument.record) });
		this.argument = argument;
	}

	internal NativeGenericMethodInstance.declared (ExactClassDefinitionIdentity definition, int owner, int member, int target, NativeDeclaredType[] arguments) {
		this.definition = definition;
		class_ordinal = owner;
		this.member = member;
		target_ordinal = target;
		this.arguments = arguments.copy ();
		argument = arguments.length == 0 ? new NativeCopyType ("", null) : new NativeCopyType (arguments[0].name, arguments[0].storage, arguments[0].record);
	}
	internal bool matches_arguments(NativeDeclaredType[] other) {
		if (arguments.length != other.length) {
			return false;
		}
		for (int a = 0; a < arguments.length; a++) {
			if (!arguments[a].same_type (other[a])) {
				return false;
			}
		}
		return true;
	}

	internal bool same_arguments(NativeGenericMethodInstance other) {
		return matches_arguments (other.arguments);
	}

	internal bool valid_arguments(NativeAbiProgram program) {
		if (arguments.length == 0) {
			return false;
		}
		foreach (var type in arguments) {
			if (!type.valid (program)) {
				return false;
			}
		}
		return true;
	}

}
// Version 1: copied result only, synchronous first-success publication.
// Independent immutable ordinals/channels; no predecessor graph or runtime box.
public class NativeLazyCache : Object {
	public int factory_ordinal { get; internal set; default = -1; }
	public int owned_class_ordinal { get; internal set; default = -1; }
	private int original_factory = -1;
	private int original_owner = -1;
	internal void bind_owned_factory(int factory, int owner) throws NativeAbiError {
		if (original_factory >= 0 || factory < 0 || owner < 0) {
			throw new NativeAbiError.INVALID_ABI ("owned lazy factory declaration can only be bound once");
		}
		factory_ordinal = original_factory = factory;
		owned_class_ordinal = original_owner = owner;
	}

	internal bool matches_factory() {
		return factory_ordinal == original_factory && owned_class_ordinal == original_owner;
	}

	public bool is_owned { get { return original_factory >= 0; } }
	public SourceSpan span { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public int class_ordinal { get; private set; }
	public int property_ordinal { get; private set; }
	public int getter_ordinal { get; private set; }
	public int cache_ordinal { get; private set; }
	public int state_member { get; private set; }
	public int value_member { get { return state_member + 1; } }
	public NativeAbiType value_type { get; private set; }
	internal NativeLazyCache (SourceSpan span, string name, int class_ordinal, int property_ordinal, int getter_ordinal, int cache_ordinal, int state_member, NativeAbiType value_type) {
		this.span = span;
		this.identifier = name;
		this.class_ordinal = class_ordinal;
		this.property_ordinal = property_ordinal;
		this.getter_ordinal = getter_ordinal;
		this.cache_ordinal = cache_ordinal;
		this.state_member = state_member;
		this.value_type = value_type;
	}

}
// Copied declaration identity and layout channels; no semantic or SSA objects.
public class NativePrivateFieldAccess : Object {
	public int class_ordinal { get; private set; }
	public int field_ordinal { get; private set; }
	public int function_ordinal { get; private set; }
	internal NativePrivateFieldAccess (int owner, int field, int function) {
		class_ordinal = owner;
		field_ordinal = field;
		function_ordinal = function;
	}

}
public class NativeClassField : Object {
	public bool owns_record { get; private set; }
	public NativeScalarOwner? resource_owner { get; private set; }
	public bool owns_buffer { get; private set; }
	public NativeBufferValuePlan? buffer_value { get; private set; }
	public NativeStructValuePlan? record_value { get; private set; }
	public int owned_class_ordinal { get; private set; }
	public bool is_private { get; private set; }
	private string identifier;
	private string type_identifier;
	public string name { get { return identifier; } }
	public string type_name { get { return type_identifier; } }
	public SourceSpan span { get; private set; }
	public int ordinal { get; private set; }
	public NativeAbiType? storage_type { get; private set; }
	public int record_ordinal { get; private set; }
	public bool text_snapshot { get; private set; }
	internal NativeClassField (SourceSpan span, string name, string type_name, int ordinal, bool text_snapshot, NativeAbiType? storage_type, int record_ordinal, bool is_private = false, int owned_class_ordinal = -1, bool owns_buffer = false, NativeScalarOwner? resource_owner = null, bool owns_record = false, NativeBufferValuePlan? buffer_value = null, NativeStructValuePlan? record_value = null) {
		this.record_value = record_value;
		this.buffer_value = buffer_value;
		this.owns_record = owns_record;
		this.resource_owner = resource_owner;
		this.owns_buffer = owns_buffer;
		this.owned_class_ordinal = owned_class_ordinal;
		this.is_private = is_private;
		this.span = span;
		identifier = name;
		type_identifier = type_name;
		this.ordinal = ordinal;
		this.text_snapshot = text_snapshot;
		this.storage_type = storage_type;
		this.record_ordinal = record_ordinal;
	}

}
public class NativeConstructorUnwindPlan : Object {
	public int class_ordinal { get; private set; }
	private int[] fields;
	private int[] lazy_properties;
	public int field_count { get { return fields.length; } }
	public int lazy_count { get { return lazy_properties.length; } }
	public int field(int index) {
		return fields[index];
	}

	public int lazy_property(int index) {
		return lazy_properties[index];
	}

	internal NativeConstructorUnwindPlan (int class_ordinal, int[] fields, int[] lazy_properties) {
		this.class_ordinal = class_ordinal;
		this.fields = fields.copy ();
		this.lazy_properties = lazy_properties.copy ();
	}

	public static bool owns_field(NativeClassField field) {
		return field.text_snapshot || field.owns_record || field.owns_buffer || field.owned_class_ordinal >= 0 || field.resource_owner != null || field.storage_type is NativeOwnerSlotsType || field.storage_type is NativeSharedHandleType || field.storage_type is NativeClosureHandleType;
	}

	public static bool required(NativeAbiProgram program, NativeFunction function) {
		if (function.kind != NativeCallableKind.CONSTRUCTOR || !function.declaring_type_is_class || function.declaring_type_ordinal < 0 || function.declaring_type_ordinal >= program.classes.length || function.signature.exception_plan == null) {
			return false;
		}
		var root = program.classes[function.declaring_type_ordinal];
		if (root.allocation_policy != null && root.allocation_policy.checked_initialization ()) {
			return true;
		}
		var api = root.foreign_export == null ? null : root.foreign_export.declared_api;
		if (api == null) {
			return false;
		}
		for (uint m = 0; m < api.member_count; m++) {
			if (api.member (m).kind == ForeignMemberKind.CONSTRUCTOR && root.foreign_member (m) == function.ordinal && api.member (m).error_origin == function.signature.exception_plan.bound_name) {
				return true;
			}
		}
		return false;
	}

	public bool valid(NativeAbiProgram program, NativeFunction function) {
		if (!required (program, function) || class_ordinal != function.declaring_type_ordinal || fields.length > 4096) {
			return false;
		}
		var root = program.classes[class_ordinal];
		int cursor = 0;
		for (int f = root.fields.length - 1; f >= 0; f--) {
			if (!owns_field (root.fields[f])) {
				continue;
			}
			if (cursor >= fields.length || fields[cursor++] != f) {
				return false;
			}
		}
		if (cursor != fields.length) {
			return false;
		}
		cursor = 0;
		for (int p = root.lazy_caches.length - 1; p >= 0; p--) {
			var cache = root.lazy_caches[p];
			if (!cache.is_owned) {
				continue;
			}
			if (cursor >= lazy_properties.length || lazy_properties[cursor++] != cache.property_ordinal) {
				return false;
			}
		}
		return cursor == lazy_properties.length;
	}

}
public class NativeClassPlan : Object {
	public ForeignClassPolicy? foreign_export { get; internal set; }
	private string foreign_identity = "";
	private bool foreign_bound;
	public int foreign_constructor { get; internal set; default = -1; }
	public int foreign_getter { get; internal set; default = -1; }
	public int foreign_setter { get; internal set; default = -1; }
	private int original_foreign_constructor = -1;
	private int original_foreign_getter = -1;
	private int original_foreign_setter = -1;
	private int[] declared_foreign_targets;
	public int foreign_member(uint index) {
		return declared_foreign_targets[index];
	}

	public int[] foreign_targets() {
		return declared_foreign_targets.copy ();
	}

	public void bind_declared_foreign(ForeignClassPolicy policy, string identity, int[] targets) throws NativeAbiError {
		if (foreign_bound || policy.declared_api == null || !ForeignClassPolicy.matches (policy, identity, name) || targets.length != policy.declared_api.member_count) {
			throw new NativeAbiError.INVALID_ABI ("declared foreign API lost its native root/member identity");
		}
		foreach (var target in targets) {
			if (target < 0) {
				throw new NativeAbiError.INVALID_ABI ("declared foreign API requires exact native member targets");
			}
		}
		declared_foreign_targets = targets.copy ();
		foreign_export = policy.copy ();
		foreign_identity = identity;
		foreign_bound = true;
	}

	public void bind_foreign_export(ForeignClassPolicy? policy, string identity, int constructor = -1, int getter = -1, int setter = -1) throws NativeAbiError {
		if (foreign_bound || !ForeignClassPolicy.matches (policy, identity, name)) {
			throw new NativeAbiError.INVALID_ABI ("foreign Class policy lost its admitted native root identity");
		}
		if (policy == null ? constructor != -1 || getter != -1 || setter != -1 : constructor < 0 || getter < 0 || setter < 0) {
			throw new NativeAbiError.INVALID_ABI ("foreign Class policy requires exact constructor/property callable identities");
		}
		foreign_constructor = original_foreign_constructor = constructor;
		foreign_getter = original_foreign_getter = getter;
		foreign_setter = original_foreign_setter = setter;
		foreign_export = policy == null ? null : policy.copy ();
		foreign_identity = identity;
		foreign_bound = true;
	}

	public bool foreign_export_valid() {
		return ForeignClassPolicy.matches (foreign_export, foreign_identity, name) && foreign_constructor == original_foreign_constructor && foreign_getter == original_foreign_getter && foreign_setter == original_foreign_setter;
	}

	public ConcurrencyPolicy? concurrency_policy { get; internal set; }
	private uint concurrency_identity;
	private bool concurrency_bound;
	public void bind_concurrency_policy(ConcurrencyPolicy? policy, uint identity) throws NativeAbiError {
		if (concurrency_bound || !ConcurrencyPolicy.matches (policy, identity)) {
			throw new NativeAbiError.INVALID_ABI ("Class concurrency policy lost its admitted declaration");
		}
		concurrency_policy = policy == null ? null : policy.copy ();
		concurrency_identity = identity;
		concurrency_bound = true;
	}

	public bool concurrency_policy_valid() {
		return ConcurrencyPolicy.matches (concurrency_policy, concurrency_identity);
	}

	public AllocationPolicy? allocation_policy { get; internal set; }
	private string allocation_identity = "";
	private bool allocation_bound;
	public void bind_allocation_policy(AllocationPolicy? policy, string identity) throws NativeAbiError {
		if (allocation_bound || !AllocationPolicy.matches (policy, identity)) {
			throw new NativeAbiError.INVALID_ABI ("Class allocation policy lost its original admitted identity");
		}
		allocation_policy = policy == null ? null : policy.copy ();
		allocation_identity = identity;
		allocation_bound = true;
	}

	public bool allocation_policy_valid() {
		return AllocationPolicy.matches (allocation_policy, allocation_identity) && (allocation_policy == null || !polymorphic && parent_ordinal == -1 && !exception_root && !is_interface);
	}

	private GenericArray<NativeClassField> original_fields = new GenericArray<NativeClassField> ();
	internal bool matches_slot_declarations() {
		if (fields.length != original_fields.length) {
			return false;
		}
		for (int f = 0; f < fields.length; f++) {
			var declared = original_fields[f];
			var field = fields[f];
			if (declared.owns_buffer != field.owns_buffer || declared.name != field.name || declared.type_name != field.type_name || declared.ordinal != field.ordinal || declared.is_private != field.is_private || declared.record_ordinal != field.record_ordinal || declared.text_snapshot != field.text_snapshot || (declared.storage_type == null) != (field.storage_type == null) || declared.storage_type != null && !declared.storage_type.same_type (field.storage_type)) {
				return false;
			}
			if (declared.buffer_value == null ? field.buffer_value != null : field.buffer_value == null || declared.buffer_value.element_spelling () != field.buffer_value.element_spelling () || declared.buffer_value.base_type != field.buffer_value.base_type || declared.buffer_value.length_type != field.buffer_value.length_type || declared.buffer_value.transfers_ownership != field.buffer_value.transfers_ownership) {
				return false;
			}
			if (declared.record_value != field.record_value) {
				return false;
			}
			if (declared.owned_class_ordinal != field.owned_class_ordinal || (declared.owned_class_ordinal >= 0 && (declared.name != field.name || declared.type_name != field.type_name || declared.ordinal != field.ordinal || declared.storage_type == null || field.storage_type == null || !declared.storage_type.same_type (field.storage_type)))) {
				return false;
			}
			if (declared.resource_owner == null ? field.resource_owner != null : !declared.resource_owner.same_owner (field.resource_owner)) {
				return false;
			}
			if (declared.owns_record != field.owns_record) {
				return false;
			}
			var original = declared.storage_type as NativeOwnerSlotsType;
			var actual = field.storage_type as NativeOwnerSlotsType;
			if (original != null || actual != null) {
				if (original == null || actual == null || !original.same_type (actual)) {
					return false;
				}
			}
		}
		return true;
	}

	public bool is_interface { get; private set; }
	public NativeExactClassInstance? generic_instance { get; internal set; }
	public ExactClassDefinitionIdentity? generic_origin { get; private set; }
	private NativeDeclaredClass? generic_declared_origin;
	internal bool generic_arguments_match() {
		var current = generic_instance == null ? null : generic_instance.declared_structure;
		return generic_declared_origin == null ? current == null : current != null && generic_declared_origin.same_arguments (current);
	}

	internal void bind_generic(NativeExactClassInstance instance) throws NativeAbiError {
		if (generic_origin != null) {
			throw new NativeAbiError.INVALID_ABI ("generic Class origin is immutable once bound");
		}
		generic_origin = instance.definition;
		generic_instance = instance;
		generic_declared_origin = instance.declared_structure;
	}

	public GenericArray<NativeLazyCache> lazy_caches { get; private set; default = new GenericArray<NativeLazyCache> (); }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan span { get; private set; }
	public int ordinal { get; private set; }
	public int parent_ordinal { get; internal set; }
	public int destructor_ordinal { get; private set; }
	public bool polymorphic { get; private set; }
	public bool exception_root { get; private set; }
	public GenericArray<NativeClassField> fields { get; private set; }
	public GenericArray<int> virtual_targets { get; private set; }
	internal NativeClassPlan (SourceSpan span, string name, int ordinal, int parent_ordinal, int destructor_ordinal, bool polymorphic, bool exception_root, GenericArray<NativeClassField> fields, GenericArray<int> virtual_targets, bool is_interface = false) {
		this.is_interface = is_interface;
		this.span = span;
		identifier = name;
		this.ordinal = ordinal;
		this.parent_ordinal = parent_ordinal;
		this.destructor_ordinal = destructor_ordinal;
		this.polymorphic = polymorphic;
		this.exception_root = exception_root;
		this.fields = fields;
		this.virtual_targets = virtual_targets;
		foreach (var field in fields) {
			original_fields.add (field);
		}
	}

}
internal class NativeClassVerifier : Object {
	private static void generic_owner(int ordinal, ExactClassDefinitionIdentity? definition, bool heap, NativeObjectOriginPlan? actual, NativeAbiProgram program) throws NativeAbiError {
		if (definition == null) {
			if (ordinal != -1) {
				throw new NativeAbiError.INVALID_ABI ("generic Class owner lost its original declaration");
			}
			return;
		}
		if (!definition.general_bodies || ordinal < 0 || ordinal >= program.classes.length || program.classes[ordinal].generic_origin != definition || actual == null || actual.heap != heap || actual.class_ordinal != ordinal || actual.class_name != program.classes[ordinal].name) {
			throw new NativeAbiError.INVALID_ABI ("generic Class owner changed its exact original instance or storage origin");
		}
	}

	private static bool generic_role(GenericClassValueRole role, NativeAbiType? type) {
		if (role == GenericClassValueRole.VOID) {
			return type == null;
		}
		var scalar = type as NativeScalarAbiType;
		return scalar != null && scalar.scalar_type == (role == GenericClassValueRole.ARGUMENT ? NativeScalarType.PTR : role == GenericClassValueRole.BOOL ? NativeScalarType.B1 : NativeScalarType.I32);
	}

	private static void generic_body_signature(NativeFunction function, NativeClassPlan plan, NativeClassPlan? argument, NativeExactClassInstance key, int member, NativeGenericMethodInstance? method = null) throws NativeAbiError {
		var source = method == null ? key.definition.signature(member) : key.definition.generic_method_signature (member);
		var signature = function.signature;
		string name = method == null ? key.definition.member_name(member) : method.name;
		bool constructor = method == null && key.definition.operation (member) == ExactClassOperation.INITIALIZE;
		if (source == null || function.name != name || function.declaring_type_ordinal != plan.ordinal || !function.declaring_type_is_class || function.kind != (constructor ? NativeCallableKind.CONSTRUCTOR : NativeCallableKind.METHOD) || signature.receiver == null || signature.receiver.scalar_type != NativeScalarType.PTR || signature.object_result != null || signature.exception_plan != null || signature.buffer_result != null || signature.buffer_parameters.length != 0) {
			throw new NativeAbiError.INVALID_ABI ("generic Class body member lost its concrete declaration signature");
		}
		var result_record = source.result == GenericClassValueRole.ARGUMENT ? key.record_argument : source.result == GenericClassValueRole.METHOD_ARGUMENT && method != null ? method.argument.record : null;
		var result_sum = source.result == GenericClassValueRole.METHOD_ARGUMENT && method != null ? method.argument.abi_type as NativeSumType : null;
		if (result_record != null) {
			if (signature.struct_result != result_record || signature.result != null || signature.sum_result != null) {
				throw new NativeAbiError.INVALID_ABI ("generic Class record result lost its complete exact copied group");
			}
		} else if (result_sum != null) {
			if (signature.struct_result != null || signature.result != null || signature.sum_result == null || signature.sum_result.identity != result_sum.identity || signature.sum_result.role != NativeSumRole.RESULT_CALLER_STORAGE || signature.sum_result.channel != NativeScalarType.PTR) {
				throw new NativeAbiError.INVALID_ABI ("generic method result lost its copied Enum identity");
			}
		} else {
			bool correct = source.result == GenericClassValueRole.METHOD_ARGUMENT ? method != null && method.argument.abi_type != null && signature.result != null && method.argument.abi_type.same_type (signature.result.abi_type) : generic_role (source.result, signature.result == null ? null : signature.result.abi_type);
			if (signature.struct_result != null || signature.sum_result != null || !correct) {
				throw new NativeAbiError.INVALID_ABI ("generic Class body result lost its concrete type");
			}
		}
		var returned = signature.heap_result;
		var resource = key.resource_argument;
		if (source.result == GenericClassValueRole.ARGUMENT && key.record_argument == null) {
			if (resource != null) {
				if (returned != null || (source.owned_result ? (!resource.same_owner (signature.resource_result)) : signature.resource_result != null)) {
					throw new NativeAbiError.INVALID_ABI ("generic Class body Resource result lost its exact owned destructor");
				}
			} else if (signature.resource_result != null || (source.owned_result ? returned == null || !returned.heap || argument == null || returned.class_ordinal != argument.ordinal || returned.class_name != argument.name : returned != null)) {
				throw new NativeAbiError.INVALID_ABI ("generic Class body result lost its exact ownership");
			}
		} else if (returned != null || signature.resource_result != null) {
			throw new NativeAbiError.INVALID_ABI ("copied generic result cannot acquire scalar ownership");
		}
		int physical = 0;
		int groups = 0;
		for (int p = 0; p < source.parameter_count; p++) {
			var role = source.parameter (p);
			var record = role == GenericClassValueRole.ARGUMENT ? key.record_argument : role == GenericClassValueRole.METHOD_ARGUMENT && method != null ? method.argument.record : null;
			if (record != null) {
				NativeStructParameterPlan? group = null;
				foreach (var candidate in signature.struct_parameters) {
					if (candidate.source_ordinal == p) {
						group = candidate;
					}
				}
				if (group == null || group.value_plan != record || group.first_leaf != physical) {
					throw new NativeAbiError.INVALID_ABI ("generic Class record parameter lost complete exact copied grouping");
				}
				physical += record.leaves.length;
				groups++;
				continue;
			}
			if (physical >= signature.parameters.length) {
				throw new NativeAbiError.INVALID_ABI ("generic Class body parameter arity mismatch");
			}
			var parameter = signature.parameters[physical++];
			var origin = parameter.object_origin;
			bool correct = role == GenericClassValueRole.METHOD_ARGUMENT ? method != null && method.argument.abi_type != null && method.argument.abi_type.same_type (parameter.abi_type) : generic_role (role, parameter.abi_type);
			if (!correct) {
				throw new NativeAbiError.INVALID_ABI ("generic Class body parameter lost its concrete type");
			}
			if (role != GenericClassValueRole.ARGUMENT) {
				if (origin != null || parameter.resource != null || parameter.owns_resource || parameter.borrowed_class_ordinal != -1 || parameter.generic_borrow_class != -1) {
					throw new NativeAbiError.INVALID_ABI ("copied generic parameter cannot acquire scalar ownership");
				}
			} else if (resource != null) {
				if (origin != null || !resource.same_owner (parameter.resource) || parameter.owns_resource != source.owns_parameter (p) || parameter.borrowed_class_ordinal != -1) {
					throw new NativeAbiError.INVALID_ABI ("generic Class body Resource parameter lost exact nominal ownership");
				}
			} else if (argument == null || parameter.resource != null || (source.owns_parameter (p) ? origin == null || !origin.heap || origin.class_ordinal != argument.ordinal || origin.class_name != argument.name : origin != null) || (!source.owns_parameter (p) && parameter.borrowed_class_ordinal != argument.ordinal)) {
				throw new NativeAbiError.INVALID_ABI ("generic Class body parameter lost its exact type or ownership");
			}
		}
		if (physical != signature.parameters.length || groups != signature.struct_parameters.length) {
			throw new NativeAbiError.INVALID_ABI ("generic Class member has an unrelated parameter channel or group");
		}
	}

	private static void generic_class(NativeClassPlan plan, NativeAbiProgram program) throws NativeAbiError {
		var key = plan.generic_instance;
		if ((key != null) != (plan.generic_origin != null) || (key != null && key.definition != plan.generic_origin)) {
			throw new NativeAbiError.INVALID_ABI ("generic Class native origin/key mismatch");
		}
		if (key == null) {
			return;
		}
		if (key.declared_structure != null) {
			if (key.definition.structure == null) {
				throw new NativeAbiError.INVALID_ABI ("unexpected declared generic native structure binding");
			}
			if (key.declared_structure.definition != key.definition) {
				throw new NativeAbiError.INVALID_ABI ("declared generic Class definition/key mismatch");
			}
			key.declared_structure.verify (plan, program);
			if (!plan.generic_arguments_match ()) {
				throw new NativeAbiError.INVALID_ABI ("declared generic Class changed its original ordered argument binding");
			}
			return;
		}
		if (key.definition.structure != null || !key.definition.valid () || plan.fields.length != 1 || plan.parent_ordinal != -1 || plan.polymorphic || plan.exception_root || key.member_count != key.definition.member_count || !plan.matches_slot_declarations ()) {
			throw new NativeAbiError.INVALID_ABI ("generic Class native specialization lost definition/argument/field authority");
		}
		if (key.property_count != key.definition.property_count) {
			throw new NativeAbiError.INVALID_ABI ("generic property lost its declared target inventory");
		}
		for (int p = 0; p < key.property_count; p++) {
			int ordinal = key.property_target (p);
			if (ordinal < 0 || ordinal >= program.functions.length) {
				throw new NativeAbiError.INVALID_ABI ("generic property target is missing");
			}
			var getter = program.functions[ordinal];
			var signature = getter.signature;
			var scalar = signature.result == null ? null : signature.result.abi_type as NativeScalarAbiType;
			var expected = key.definition.property_result (p) == GenericClassValueRole.BOOL ? NativeScalarType.B1 : NativeScalarType.I32;
			if (getter.ordinal != ordinal || getter.name != "get" || getter.kind != NativeCallableKind.PROPERTY_GETTER || !getter.declaring_type_is_class || getter.declaring_type_ordinal != plan.ordinal || getter.property_ordinal != p || getter.receiver_borrow || getter.lazy_cache != null || getter.virtual_slot != -1 || signature.receiver == null || signature.receiver.scalar_type != NativeScalarType.PTR || signature.parameters.length != 0 || signature.exception_plan != null || scalar == null || scalar.scalar_type != expected || signature.heap_result != null || signature.object_result != null || signature.struct_result != null || signature.sum_result != null || signature.buffer_result != null) {
				throw new NativeAbiError.INVALID_ABI ("generic property target lost its exact nominal copied getter contract");
			}
		}
		foreach (var function in program.functions) {
			if (!function.declaring_type_is_class || function.declaring_type_ordinal != plan.ordinal || (function.kind != NativeCallableKind.PROPERTY_GETTER && function.kind != NativeCallableKind.PROPERTY_SETTER)) {
				continue;
			}
			int property = function.property_ordinal;
			if (function.kind != NativeCallableKind.PROPERTY_GETTER || property < 0 || property >= key.property_count || key.property_target (property) != function.ordinal) {
				throw new NativeAbiError.INVALID_ABI ("generic property has an undeclared or substituted accessor");
			}
		}
		var slots = plan.fields[0].storage_type as NativeOwnerSlotsType;
		NativeClassPlan? argument = null;
		if (slots == null || slots.element_ordinal != key.argument_ordinal || plan.fields[0].name != key.definition.field_name) {
			throw new NativeAbiError.INVALID_ABI ("generic Class native slot identity mismatch");
		}
		string argument_name;
		if (key.record_argument != null) {
			var record = key.record_argument;
			if (!key.definition.general_bodies || key.argument_ordinal != -1 || key.resource_argument != null || slots.resource != null || slots.record_value != record || !slots.matches_record_layout () || !program.struct_values.find (record)) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native record lost its exact copied value plan");
			}
			argument_name = record.struct_name;
		} else if (key.resource_argument != null) {
			var resource = key.resource_argument;
			if (!key.definition.general_bodies || key.argument_ordinal != -1 || resource.class_ordinal != -1 || resource.cleanup_symbol == "" || resource.type_name == "" || !resource.same_owner (slots.resource)) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native Resource lost exact nominal destructor authority");
			}
			argument_name = resource.type_name;
		} else {
			if (key.argument_ordinal < 0 || key.argument_ordinal >= program.classes.length || slots.resource != null || slots.record_value != null) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native argument rank mismatch");
			}
			argument = program.classes[key.argument_ordinal];
			argument_name = argument.name;
			if (argument.generic_instance != null && !(key.definition.general_bodies && argument.generic_instance.definition.general_bodies) || argument.polymorphic || argument.parent_ordinal != -1) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native field/argument identity mismatch");
			}
		}
		if (plan.name != key.definition.name + "<" + argument_name + ">") {
			throw new NativeAbiError.INVALID_ABI ("generic Class native nominal application mismatch");
		}
		foreach (var other in program.classes) {
			if (other == plan || other.generic_instance == null || other.generic_instance.definition != key.definition || other.generic_instance.argument_ordinal != key.argument_ordinal) {
				continue;
			}
			var prior = other.generic_instance.resource_argument;
			if (key.record_argument != null ? key.record_argument == other.generic_instance.record_argument : other.generic_instance.record_argument == null && (key.resource_argument == null ? prior == null : key.resource_argument.same_owner (prior))) {
				throw new NativeAbiError.INVALID_ABI ("duplicate native generic Class specialization");
			}
		}
		foreach (var method in key.generic_methods) {
			if (!key.definition.general_bodies || method.definition != key.definition || method.class_ordinal != plan.ordinal || method.member < 0 || method.member >= key.definition.generic_method_count || method.target_ordinal < 0 || method.target_ordinal >= program.functions.length || !method.argument.valid (program)) {
				throw new NativeAbiError.INVALID_ABI ("generic method lost its closed declaration and copied argument");
			}
			var target = program.functions[method.target_ordinal];
			if (target.generic_method_instance != method) {
				throw new NativeAbiError.INVALID_ABI ("generic method target lost its original binding");
			}
			foreach (var other in key.generic_methods) {
				if (other != method && (other.target_ordinal == method.target_ordinal || other.member == method.member && other.argument.same_type (method.argument))) {
					throw new NativeAbiError.INVALID_ABI ("duplicate native generic method specialization");
				}
			}
			generic_body_signature (target, plan, argument, key, method.member, method);
		}
		for (int i = 0; i < key.member_count; i++) {
			int target = key.member_target (i);
			if (target < 0 || target >= program.functions.length) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native member target missing");
			}
			if (key.definition.general_bodies) {
				generic_body_signature (program.functions[target], plan, argument, key, i);
				continue;
			}
			var function = program.functions[target];
			var signature = function.signature;
			var operation = key.definition.operation (i);
			if (function.name != key.definition.member_name (i) || function.declaring_type_ordinal != plan.ordinal || !function.declaring_type_is_class || function.kind != (operation == ExactClassOperation.INITIALIZE ? NativeCallableKind.CONSTRUCTOR : NativeCallableKind.METHOD) || signature.receiver == null || signature.receiver.scalar_type != NativeScalarType.PTR || signature.object_result != null || (operation == ExactClassOperation.TAKE ? signature.heap_result == null || !signature.heap_result.heap || signature.heap_result.class_ordinal != key.argument_ordinal || signature.heap_result.class_name != argument.name : signature.heap_result != null) || signature.exception_plan != null) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native direct member/receiver identity mismatch");
			}
			int arity = operation == ExactClassOperation.REPLACE ? 2 : operation == ExactClassOperation.RESERVE || operation == ExactClassOperation.APPEND || operation == ExactClassOperation.TAKE ? 1 : 0;
			if (signature.parameters.length != arity) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native member arity mismatch");
			}
			bool returns_void = operation == ExactClassOperation.INITIALIZE || operation == ExactClassOperation.APPEND || operation == ExactClassOperation.REPLACE;
			var result = signature.result == null ? null : signature.result.abi_type as NativeScalarAbiType;
			if ((signature.result == null) != returns_void || (!returns_void && (result == null || result.scalar_type != (operation == ExactClassOperation.RESERVE ? NativeScalarType.B1 : operation == ExactClassOperation.TAKE ? NativeScalarType.PTR : NativeScalarType.I32)))) {
				throw new NativeAbiError.INVALID_ABI ("generic Class native member result mismatch");
			}
			for (int p = 0; p < arity; p++) {
				var parameter = signature.parameters[p];
				var type = parameter.abi_type as NativeScalarAbiType;
				bool owned_element = operation == ExactClassOperation.APPEND || operation == ExactClassOperation.REPLACE && p == 1;
				var origin = parameter.object_origin;
				if (type == null || type.scalar_type != (owned_element ? NativeScalarType.PTR : NativeScalarType.I32) || (owned_element ? origin == null || !origin.heap || origin.class_ordinal != key.argument_ordinal || origin.class_name != argument.name : origin != null)) {
					throw new NativeAbiError.INVALID_ABI ("generic Class native member lost exact heap element parameter");
				}
			}

		}
	}

	private static void verify_slot_ownership(int ordinal, NativeAbiProgram program, HashTable<int, int> states) throws NativeAbiError {
		if (ordinal < 0 || ordinal >= program.classes.length) {
			throw new NativeAbiError.INVALID_ABI ("owned slot dependency lost its exact Class rank");
		}
		if (states.contains (ordinal)) {
			if (states.lookup (ordinal) != 2) {
				throw new NativeAbiError.INVALID_ABI ("cyclic native slot/record ownership dependency");
			}
			return;
		}
		states.insert (ordinal, 1);
		var plan = program.classes[ordinal];
		foreach (var field in plan.fields) {
			if (field.owned_class_ordinal >= 0) {
				verify_slot_ownership (field.owned_class_ordinal, program, states);
			}
			var slots = field.storage_type as NativeOwnerSlotsType;
			if (slots == null || slots.resource != null) {
				continue;
			}
			if (slots.record_value == null) {
				verify_slot_ownership (slots.element_ordinal, program, states);
			} else {
				foreach (var owner in slots.record_value.ownership) {
					if (owner.cleanup_class_ordinal >= 0) {
						verify_slot_ownership (owner.cleanup_class_ordinal, program, states);
					}
				}
			}
		}
		foreach (var cache in plan.lazy_caches) {
			if (cache.is_owned) {
				verify_slot_ownership (cache.owned_class_ordinal, program, states);
			}
		}
		states.insert (ordinal, 2);
	}

	internal static void verify(NativeAbiProgram program) throws NativeAbiError {
		var allocation_domains = new AllocationDomains ();
		foreach (var owner in program.classes) {
			if (!owner.foreign_export_valid () || (owner.parent_ordinal >= 0 && owner.parent_ordinal < program.classes.length && program.classes[owner.parent_ordinal].foreign_export != null)) {
				throw new NativeAbiError.INVALID_ABI ("foreign Class policy lost its exact admitted native root identity");
			}
			var policy = owner.foreign_export;
			if (policy == null) {
				continue;
			}
			if (policy.declared_api != null) {
				if (!NativeForeignApi.valid (program, owner)) {
					throw new NativeAbiError.INVALID_ABI ("declared foreign API lost exact native binding, physical channel or ownership authority");
				}
				continue;
			}
			if (owner.parent_ordinal != -1 || owner.polymorphic || owner.exception_root || owner.is_interface || owner.generic_instance != null || owner.allocation_policy != null || owner.concurrency_policy == null || (owner.concurrency_policy.identity != 1 && owner.concurrency_policy.identity != 3) || owner.lazy_caches.length != 0) {
				throw new NativeAbiError.INVALID_ABI ("foreign Class policy requires its selected independent Shared heap root");
			}
			foreach (var field in owner.fields) {
				var scalar = field.storage_type as NativeScalarAbiType;
				if (scalar == null || scalar.scalar_type != NativeScalarType.I32 || field.owned_class_ordinal >= 0 || field.owns_buffer || field.text_snapshot || field.record_ordinal >= 0) {
					throw new NativeAbiError.INVALID_ABI ("foreign Class policy requires exact copied I32 payload fields");
				}
			}
			for (int role = 0; role < 3; role++) {
				int ordinal = role == 0 ? owner.foreign_constructor : role == 1 ? owner.foreign_getter : owner.foreign_setter;
				if (ordinal < 0 || ordinal >= program.functions.length) {
					throw new NativeAbiError.INVALID_ABI ("foreign Class policy lost a nominated native callable");
				}
				var function = program.functions[ordinal];
				var signature = function.signature;
				var kind = role == 0 ? NativeCallableKind.CONSTRUCTOR : role == 1 ? NativeCallableKind.PROPERTY_GETTER : NativeCallableKind.PROPERTY_SETTER;
				if (function.kind != kind || !function.declaring_type_is_class || function.declaring_type_ordinal != owner.ordinal || (role != 0 && function.property_ordinal != policy.property_ordinal) || signature.receiver == null || signature.exception_plan != null || signature.heap_result != null || signature.struct_result != null || signature.buffer_result != null || signature.sum_result != null || signature.parameters.length != (role == 1 ? 0 : 1)) {
					throw new NativeAbiError.INVALID_ABI ("foreign Class policy lost its exact constructor/property role signature");
				}
				if (role != 1) {
					var input = signature.parameters[0].abi_type as NativeScalarAbiType;
					if (signature.result != null || input == null || input.scalar_type != NativeScalarType.I32) {
						throw new NativeAbiError.INVALID_ABI ("foreign Class construction/setter requires an exact native void(I32) role");
					}
				} else {
					var result = signature.result == null ? null : signature.result.abi_type as NativeScalarAbiType;
					if (result == null || result.scalar_type != NativeScalarType.I32) {
						throw new NativeAbiError.INVALID_ABI ("foreign Class getter requires an exact native I32 result");
					}
				}
			}
		}
		foreach (var owner in program.classes) {
			if (owner.exception_root && owner.concurrency_policy != null) {
				throw new NativeAbiError.INVALID_ABI ("native exception roots require their unique lifetime policy");
			}
		}
		foreach (var owner in program.classes) {
			if (!owner.concurrency_policy_valid () || !owner.allocation_policy_valid () || !allocation_domains.admit (owner.allocation_policy)) {
				throw new NativeAbiError.INVALID_ABI ("Class allocation policy differs from its exact admitted storage/release identity");
			}
		}
		foreach (var owner in program.classes) {
			var policy = owner.concurrency_policy;
			if (policy == null || !policy.singleton) {
				continue;
			}
			if (policy.identity != 7 || owner.parent_ordinal != -1 || owner.polymorphic || owner.is_interface || owner.allocation_policy != null) {
				throw new NativeAbiError.INVALID_ABI ("Singleton requires one exact hosted Shared Monitor root");
			}
			foreach (var field in owner.fields) {
				var scalar = field.storage_type as NativeScalarAbiType;
				if (!field.is_private || scalar == null || scalar.scalar_type == NativeScalarType.PTR || field.owned_class_ordinal >= 0 || field.record_ordinal >= 0) {
					throw new NativeAbiError.INVALID_ABI ("Singleton initialization requires private copied numeric state");
				}
			}
			bool constructor = false;
			foreach (var function in program.functions) {
				if (function.kind != NativeCallableKind.CONSTRUCTOR || !function.declaring_type_is_class || function.declaring_type_ordinal != owner.ordinal) {
					continue;
				}
				if (constructor) {
					throw new NativeAbiError.INVALID_ABI ("Singleton requires one exact constructor");
				}
				constructor = true;
				foreach (var parameter in function.signature.parameters) {
					var scalar = parameter.abi_type as NativeScalarAbiType;
					if (scalar == null || scalar.scalar_type == NativeScalarType.PTR || parameter.object_origin != null || parameter.resource != null) {
						throw new NativeAbiError.INVALID_ABI ("Singleton constructor requires copied numeric inputs");
					}
				}
			}
			if (!constructor) {
				throw new NativeAbiError.INVALID_ABI ("Singleton lost its explicit initializer");
			}
		}
		uint interface_count = 0;
		foreach (var owner in program.classes) {
			if (owner.is_interface) {
				interface_count++;
				if (!owner.polymorphic || owner.parent_ordinal != -1 || owner.fields.length != 0 || owner.destructor_ordinal != -1 || owner.virtual_targets.length == 0 || owner.exception_root || owner.generic_instance != null) {
					throw new NativeAbiError.INVALID_ABI ("interface plan requires exact fieldless abstract root and typed operation slots");
				}
			}
		}
		if (interface_count != program.interface_count) {
			throw new NativeAbiError.INVALID_ABI ("interface plan inventory lost its complete nominal contract binding");
		}
		if (program.private_accesses.length != program.private_access_count) {
			throw new NativeAbiError.INVALID_ABI ("private field access inventory lost its complete binding");
		}
		var accesses = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var access in program.private_accesses) {
			if (access.class_ordinal < 0 || access.class_ordinal >= program.classes.length || access.function_ordinal < 0 || access.function_ordinal >= program.functions.length) {
				throw new NativeAbiError.INVALID_ABI ("private field access lost exact class/caller ranks");
			}
			var owner = program.classes[access.class_ordinal];
			var caller = program.functions[access.function_ordinal];
			string key = "%d/%d/%d".printf (access.class_ordinal, access.field_ordinal, access.function_ordinal);
			if (owner.generic_instance != null && owner.generic_instance.declared_structure == null || access.field_ordinal < 0 || access.field_ordinal >= owner.fields.length || !owner.fields[access.field_ordinal].is_private || !caller.declaring_type_is_class || caller.declaring_type_ordinal != owner.ordinal || caller.signature.receiver == null || caller.kind == NativeCallableKind.FUNCTION || accesses.contains (key)) {
				throw new NativeAbiError.INVALID_ABI ("private field access requires its exact lexical declaring Class");
			}
			accesses.insert (key, true);
		}
		foreach (var function in program.functions) {
			var method = function.generic_method_instance;
			if (!function.generic_method_matches () || (method != null) != (function.generic_method_origin != null) || (method == null && function.generic_method_member_origin != -1)) {
				throw new NativeAbiError.INVALID_ABI ("generic method native origin/key mismatch");
			}
			if (method != null) {
				if (!method.valid_arguments (program) || method.definition != function.generic_method_origin || method.member != function.generic_method_member_origin || method.target_ordinal != function.ordinal || method.class_ordinal < 0 || method.class_ordinal >= program.classes.length || function.declaring_type_ordinal != method.class_ordinal || !function.declaring_type_is_class || function.kind != NativeCallableKind.METHOD) {
					throw new NativeAbiError.INVALID_ABI ("generic method lost immutable owner/member/target identity");
				}
				var owner = program.classes[method.class_ordinal].generic_instance;
				if (owner == null || !owner.generic_methods.find (method)) {
					throw new NativeAbiError.INVALID_ABI ("generic method missing from its owning Class specialization");
				}
			}
			foreach (var parameter in function.signature.parameters) {
				int c = parameter.generic_borrow_class;
				if (!parameter.generic_borrow_matches () || (c >= 0) != (parameter.generic_borrow_origin != null) || c < -1 || c >= program.classes.length || (c >= 0 && (program.classes[c].generic_origin != parameter.generic_borrow_origin || parameter.object_origin != null || !(parameter.abi_type is NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR))) {
					throw new NativeAbiError.INVALID_ABI ("borrowed generic Class lost exact native instance/pointer contract");
				}
				if (c >= 0 && !parameter.generic_borrow_origin.general_bodies) {
					var signature = function.signature;
					var scalar = signature.result == null ? null : signature.result.abi_type as NativeScalarAbiType;
					if (signature.exception_plan != null || signature.object_result != null || signature.heap_result != null || signature.struct_result != null || signature.sum_result != null || signature.buffer_result != null || (signature.result != null && (scalar == null || scalar.scalar_type == NativeScalarType.PTR))) {
						throw new NativeAbiError.INVALID_ABI ("generic bag helper requires a nonthrowing copied scalar/void native result");
					}
				}
				var origin = parameter.object_origin;
				generic_owner (parameter.generic_owner_class, parameter.generic_owner_origin, parameter.generic_owner_heap, origin, program);
				if (parameter.generic_owner_origin != null && (c != -1 || parameter.borrowed_class_ordinal != -1 || parameter.resource != null || !(parameter.abi_type is NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR)) {
					throw new NativeAbiError.INVALID_ABI ("generic Class owned channel cannot also borrow or own a Resource");
				}
				if (origin != null && origin.class_ordinal >= 0 && origin.class_ordinal < program.classes.length) {
					var definition = program.classes[origin.class_ordinal].generic_origin;
					if (definition != null && (!definition.general_bodies || parameter.generic_owner_class != origin.class_ordinal)) {
						throw new NativeAbiError.INVALID_ABI ("generic Class owned parameter requires its exact general instance binding");
					}
				}
			}
			var signature = function.signature;
			var result = signature.heap_result ?? (signature.object_result == null ? null : signature.object_result.object_origin);
			generic_owner (signature.generic_owner_result_class, signature.generic_owner_result_origin, signature.generic_owner_result_heap, result, program);
			if (result != null && result.class_ordinal >= 0 && result.class_ordinal < program.classes.length) {
				var owner = program.classes[result.class_ordinal];
				if (owner.is_interface || owner.generic_origin != null && (!owner.generic_origin.general_bodies || signature.generic_owner_result_class != result.class_ordinal)) {
					throw new NativeAbiError.INVALID_ABI ("generic Class result requires its exact general instance binding");
				}
			}
		}
		int root = -1;
		for (int c = 0; c < program.classes.length; c++) {
			var plan = program.classes[c];
			generic_class (plan, program);
			if (plan.ordinal != c || plan.name == "" || plan.parent_ordinal < -1 || plan.parent_ordinal >= program.classes.length) {
				throw new NativeAbiError.INVALID_ABI ("class plan requires exact declaration rank and bounded parent");
			}
			var seen = new HashTable<int, bool> (direct_hash, direct_equal);
			int depth = 0;
			for (int current = c; current >= 0; current = program.classes[current].parent_ordinal) {
				if (current >= program.classes.length || seen.contains (current) || ++depth > 256) {
					throw new NativeAbiError.INVALID_ABI ("class plan requires bounded acyclic parent ancestry");
				}
				seen.insert (current, true);
			}
			bool interface_dispatch = false;
			foreach (var ancestor in seen.get_keys ()) {
				if (program.classes[ancestor].is_interface) {
					interface_dispatch = true;
				}
			}
			if (plan.exception_root) {
				if (root >= 0 || plan.parent_ordinal != -1 || !plan.polymorphic) {
					throw new NativeAbiError.INVALID_ABI ("exception class plan requires one nominated polymorphic root");
				}
				root = c;
			}
			if (plan.destructor_ordinal >= 0 && (plan.destructor_ordinal >= program.functions.length || program.functions[plan.destructor_ordinal].kind != NativeCallableKind.DESTRUCTOR || program.functions[plan.destructor_ordinal].declaring_type_ordinal != c || !program.functions[plan.destructor_ordinal].declaring_type_is_class)) {
				throw new NativeAbiError.INVALID_ABI ("class plan destructor requires exact declaring class function");
			}
			if (!plan.polymorphic && (plan.parent_ordinal != -1 || plan.virtual_targets.length != 0)) {
				throw new NativeAbiError.INVALID_ABI ("class plan header requires participating hierarchy");
			}
			if (plan.parent_ordinal >= 0 && (!program.classes[plan.parent_ordinal].polymorphic || plan.virtual_targets.length < program.classes[plan.parent_ordinal].virtual_targets.length)) {
				throw new NativeAbiError.INVALID_ABI ("class plan must preserve complete inherited virtual table");
			}
			var names = new HashTable<string, bool> (str_hash, str_equal);
			for (int f = 0; f < plan.fields.length; f++) {
				var field = plan.fields[f];
				if (field.is_private && plan.generic_instance != null && plan.generic_instance.declared_structure == null) {
					throw new NativeAbiError.INVALID_ABI ("private fields require a nongeneric native Class");
				}
				if (field.ordinal != f || (field.storage_type == null) != (field.record_ordinal >= 0) || field.name == "" || field.type_name == "" || names.contains (field.name) || (field.text_snapshot && field.type_name != "string")) {
					throw new NativeAbiError.INVALID_ABI ("class field plan requires exact unique declared storage channel");
				}
				names.insert (field.name, true);
			}
			if (!plan.matches_slot_declarations ()) {
				throw new NativeAbiError.INVALID_ABI ("owner slots require their original element declaration, exact field storage and PTR/I32/I32 channels");
			}
			foreach (var field in plan.fields) {
				if (field.owns_record) {
					NativeStructValuePlan? record = null;
					foreach (var value in program.struct_values) {
						if (value.struct_ordinal == field.record_ordinal && value.struct_name == field.type_name) {
							record = value;
						}
					}
					if (field.record_value != null && field.record_value != record || record == null || record.mode != NativeStructValueMode.MOVE_VALUE || plan.destructor_ordinal < 0 || field.storage_type != null || field.owned_class_ordinal >= 0 || field.owns_buffer || field.resource_owner != null) {
						throw new NativeAbiError.INVALID_ABI ("owning record field lost complete inline layout and retirement plan");
					}
				}

				if (field.owned_class_ordinal < -1 || field.owned_class_ordinal >= program.classes.length) {
					throw new NativeAbiError.INVALID_ABI ("owned child field lost exact Class rank");
				}
				if (field.owned_class_ordinal >= 0) {
					var child = program.classes[field.owned_class_ordinal];
					if (child.polymorphic || child.is_interface || child.name != field.type_name || !(field.storage_type is NativeScalarAbiType) || !field.storage_type.same_type (new NativeScalarAbiType (NativeScalarType.PTR)) || field.record_ordinal != -1 || field.text_snapshot || plan.destructor_ordinal < 0) {
						throw new NativeAbiError.INVALID_ABI ("owned child field requires exact unique heap Class storage and retirement");
					}
					if (child.generic_origin != null && !child.generic_origin.general_bodies) {
						throw new NativeAbiError.INVALID_ABI ("legacy generic Bag cannot become an owned child field");
					}
				}
				var slots = field.storage_type as NativeOwnerSlotsType;
				if (slots == null) {
					continue;
				}
				if (program.abi_version != NativeAbiVersion.OWNER_SLOTS_V15 || plan.polymorphic || plan.parent_ordinal != -1 || field.record_ordinal != -1 || field.text_snapshot || slots.base_type != NativeScalarType.PTR || slots.length_type != NativeScalarType.I32 || slots.capacity_type != NativeScalarType.I32 || plan.destructor_ordinal < 0) {
					throw new NativeAbiError.INVALID_ABI ("owner slots require v15, exact unique field identities and ordered PTR/I32/I32 storage");
				}
				if (slots.record_value != null) {
					if (slots.resource != null || slots.element_ordinal != -1 || slots.destructor_ordinal != -1 || slots.element_name != slots.record_value.struct_name || !slots.matches_record_layout () || !program.struct_values.find (slots.record_value)) {
						throw new NativeAbiError.INVALID_ABI ("record slots lost their original complete copy layout");
					}
					continue;
				}
				if (slots.resource != null) {
					if (slots.element_ordinal != -1 || slots.destructor_ordinal != -1 || slots.resource.class_ordinal != -1 || slots.element_name != slots.resource.type_name || slots.resource.type_name == "" || slots.resource.cleanup_symbol == "") {
						throw new NativeAbiError.INVALID_ABI ("owner slots lost exact Resource cleanup");
					}
					continue;
				}
				if (slots.element_ordinal < 0 || slots.element_ordinal >= program.classes.length || slots.element_ordinal == c) {
					throw new NativeAbiError.INVALID_ABI ("owner slots lost exact Class rank");
				}
				var element = program.classes[slots.element_ordinal];
				if (element.name != slots.element_name || element.polymorphic || element.parent_ordinal != -1 || slots.destructor_ordinal != element.destructor_ordinal) {
					throw new NativeAbiError.INVALID_ABI ("owner slots lost exact element and automatic destructor identity");
				}
			}
			int previous_property = -1;
			for (int z = 0; z < plan.lazy_caches.length; z++) {
				var cache = plan.lazy_caches[z];
				int prefix = plan.parent_ordinal >= 0 ? 1 : plan.concurrency_policy != null ? 6 : plan.polymorphic ? 2 : 0;
				if (!cache.matches_factory () || cache.class_ordinal != c || cache.cache_ordinal != z || cache.property_ordinal <= previous_property || cache.getter_ordinal < 0 || cache.getter_ordinal >= program.functions.length || cache.state_member != prefix + plan.fields.length + z * 2 || cache.name == "" || names.contains (cache.name) || (!(cache.value_type is NativeScalarAbiType) && !(cache.value_type is NativeVectorType))) {
					throw new NativeAbiError.INVALID_ABI ("lazy cache requires exact declaring class/property, distinct copied channel and complete layout slots");
				}
				var getter = program.functions[cache.getter_ordinal];
				if (cache.is_owned) {
					if (cache.factory_ordinal >= program.functions.length || cache.owned_class_ordinal < 0 || cache.owned_class_ordinal >= program.classes.length || plan.destructor_ordinal < 0 || !getter.receiver_borrow) {
						throw new NativeAbiError.INVALID_ABI ("owned lazy cache lost distinct factory, borrowed getter or destruction owner");
					}
					var factory = program.functions[cache.factory_ordinal];
					var produced = factory.signature.heap_result;
					if (factory.kind != NativeCallableKind.METHOD || !factory.declaring_type_is_class || factory.declaring_type_ordinal != c || factory.signature.receiver == null || factory.signature.parameters.length != 0 || produced == null || !produced.heap || produced.class_ordinal != cache.owned_class_ordinal || program.classes[produced.class_ordinal].polymorphic || factory.signature.result == null || !factory.signature.result.abi_type.same_type (cache.value_type) || ((factory.signature.exception_plan == null) != (getter.signature.exception_plan == null)) || (factory.signature.exception_plan != null && (factory.signature.exception_plan.bound_ordinal != getter.signature.exception_plan.bound_ordinal || factory.signature.exception_plan.root_ordinal != getter.signature.exception_plan.root_ordinal))) {
						throw new NativeAbiError.INVALID_ABI ("owned lazy factory and borrowed observation disagree on exact private ABI channels");
					}
				} else if (cache.owned_class_ordinal != -1 || getter.receiver_borrow) {
					throw new NativeAbiError.INVALID_ABI ("copied lazy cache cannot own or borrow a Class result");
				}
				if (getter.lazy_cache != cache || getter.kind != NativeCallableKind.PROPERTY_GETTER || !getter.declaring_type_is_class || getter.declaring_type_ordinal != c || getter.property_ordinal != cache.property_ordinal || getter.signature.result == null || getter.signature.heap_result != null || !getter.signature.result.abi_type.same_type (cache.value_type)) {
					throw new NativeAbiError.INVALID_ABI ("lazy cache requires its exact get-only initializer and copied result channel");
				}
				foreach (var candidate in program.functions) {
					if (candidate.kind == NativeCallableKind.PROPERTY_SETTER && candidate.declaring_type_is_class && candidate.declaring_type_ordinal == c && candidate.property_ordinal == cache.property_ordinal) {
						throw new NativeAbiError.INVALID_ABI ("lazy cache cannot have a setter");
					}
				}
				for (int v = 0; v < plan.virtual_targets.length; v++) {
					if (plan.virtual_targets[v] == cache.getter_ordinal) {
						throw new NativeAbiError.INVALID_ABI ("lazy cache cannot be a virtual target");
					}
				}
				names.insert (cache.name, true);
				previous_property = cache.property_ordinal;
			}
			for (int v = 0; v < plan.virtual_targets.length; v++) {
				int target = plan.virtual_targets[v];
				if (target < 0 || target >= program.functions.length) {
					throw new NativeAbiError.INVALID_ABI ("class virtual target lies outside native program");
				}
				var function = program.functions[target];
				if ((interface_dispatch && function.virtual_slot != v) || !function.declaring_type_is_class || function.signature.receiver == null || !seen.contains (function.declaring_type_ordinal) || (!plan.is_interface && program.classes[function.declaring_type_ordinal].is_interface) || (function.kind != NativeCallableKind.METHOD && function.kind != NativeCallableKind.PROPERTY_GETTER)) {
					throw new NativeAbiError.INVALID_ABI ("class virtual target requires exact ancestor receiver and callable kind");
				}
				if (plan.is_interface) {
					var signature = function.signature;
					if (signature.result == null || !signature.result.abi_type.same_type (new NativeScalarAbiType (NativeScalarType.I32)) || signature.exception_plan != null || signature.heap_result != null || signature.object_result != null || signature.struct_result != null || signature.buffer_result != null || signature.sum_result != null) {
						throw new NativeAbiError.INVALID_ABI ("interface operation lost its copied nonthrowing int result channel");
					}
					foreach (var parameter in signature.parameters) {
						if (!parameter.abi_type.same_type (new NativeScalarAbiType (NativeScalarType.I32)) || parameter.object_origin != null) {
							throw new NativeAbiError.INVALID_ABI ("interface operation lost copied int parameter channels");
						}
					}
				}
			}
		}
		var owned_slots = new HashTable<int, int> (direct_hash, direct_equal);
		for (int c = 0; c < program.classes.length; c++) {
			verify_slot_ownership (c, program, owned_slots);
		}
		foreach (var function in program.functions) {
			var cache = function.lazy_cache;
			if (cache != null && (cache.class_ordinal < 0 || cache.class_ordinal >= program.classes.length || cache.cache_ordinal < 0 || cache.cache_ordinal >= program.classes[cache.class_ordinal].lazy_caches.length || program.classes[cache.class_ordinal].lazy_caches[cache.cache_ordinal] != cache || cache.getter_ordinal != function.ordinal)) {
				throw new NativeAbiError.INVALID_ABI ("initializer cache must belong to its exact independent class plan");
			}
		}
		foreach (var function in program.functions) {
			if (function.signature.exception_plan == null || (function.kind != NativeCallableKind.PROPERTY_GETTER && function.kind != NativeCallableKind.PROPERTY_SETTER)) {
				continue;
			}
			if (function.kind != NativeCallableKind.PROPERTY_GETTER || !function.declaring_type_is_class || function.declaring_type_ordinal < 0 || function.declaring_type_ordinal >= program.classes.length || function.signature.result == null || function.signature.heap_result != null || (!(function.signature.result.abi_type is NativeScalarAbiType) && !(function.signature.result.abi_type is NativeVectorType))) {
				throw new NativeAbiError.INVALID_ABI ("checked property effect requires a copied get-only class getter");
			}
			foreach (var candidate in program.functions) {
				if (candidate.kind == NativeCallableKind.PROPERTY_SETTER && candidate.declaring_type_is_class && candidate.declaring_type_ordinal == function.declaring_type_ordinal && candidate.property_ordinal == function.property_ordinal) {
					throw new NativeAbiError.INVALID_ABI ("checked property effect cannot have a setter");
				}
			}
			var owner = program.classes[function.declaring_type_ordinal];
			for (int v = 0; v < owner.virtual_targets.length; v++) {
				if (owner.virtual_targets[v] == function.ordinal) {
					throw new NativeAbiError.INVALID_ABI ("checked property effect cannot be virtual");
				}
			}
		}
		foreach (var function in program.functions) {
			var plan = function.signature.exception_plan;
			if (plan == null) {
				continue;
			}
			if (plan.root_ordinal != root || plan.bound_ordinal >= program.classes.length || plan.bound_name != program.classes[plan.bound_ordinal].name || plan.root_name != program.classes[root].name) {
				throw new NativeAbiError.INVALID_ABI ("exception bound requires exact native class plan identity");
			}
			bool compatible = false;
			for (int current = plan.bound_ordinal; current >= 0; current = program.classes[current].parent_ordinal) {
				if (current == root) {
					compatible = true;
				}
			}
			if (!compatible) {
				throw new NativeAbiError.INVALID_ABI ("exception bound must descend from nominated native root");
			}
		}
	}

}

public class NativeExactClassInstance : Object {
	public NativeDeclaredClass? declared_structure { get; private set; }
	public GenericArray<NativeGenericMethodInstance> generic_methods { get; private set; default = new GenericArray<NativeGenericMethodInstance> (); }
	public NativeStructValuePlan? record_argument { get; private set; }
	public NativeScalarOwner? resource_argument { get; private set; }
	public ExactClassDefinitionIdentity definition { get; private set; }
	public int argument_ordinal { get; private set; }
	private int[] targets;
	private int[]? properties;
	public int property_count { get { return properties == null ? 0 : properties.length; } }
	public int property_target(int index) {
		return properties[index];
	}

	public int member_count { get { return targets.length; } }
	public int member_target(int index) {
		return targets[index];
	}

	internal NativeExactClassInstance (ExactClassDefinitionIdentity definition, int argument_ordinal, int[] targets, NativeScalarOwner? resource = null, NativeStructValuePlan? record = null, GenericArray<NativeGenericMethodInstance>? methods = null, int[]? properties = null) {
		this.definition = definition;
		this.argument_ordinal = argument_ordinal;
		this.targets = targets.copy ();
		if (properties != null) {
			this.properties = properties.copy ();
		}
		this.resource_argument = resource;
		this.record_argument = record;
		if (methods != null) {
			foreach (var method in methods) {
				generic_methods.add (method);
			}
		}
	}

	internal NativeExactClassInstance.declared (ExactClassDefinitionIdentity definition, NativeDeclaredClass structure, int[] targets, int[] properties) {
		this.definition = definition;
		declared_structure = structure;
		argument_ordinal = -1;
		// Preserve one-argument inspection APIs; the complete immutable vector
		// remains the declaration-driven specialization and validation authority.
		if (structure.argument_count == 1) {
			var argument = structure.argument (0);
			argument_ordinal = argument.class_ordinal;
			resource_argument = argument.resource;
			record_argument = argument.record;
		}
		this.targets = targets.copy ();
		this.properties = properties.copy ();
	}
}
}

namespace Astra.NativeAbi {
// Field-only unique owner group. Pointer-sized carriers do not erase the
// exact nominal element/destructor identity into a copied Slice ABI.
public class NativeOwnerSlotsType : NativeAbiType {
	public NativeStructValuePlan? record_value { get; private set; }
	private NativeStructValueMode original_record_mode;
	private GenericArray<NativeRecordResource> original_record_owners = new GenericArray<NativeRecordResource> ();
	private GenericArray<NativeStructLeafChannel> original_record_leaves = new GenericArray<NativeStructLeafChannel> ();
	internal bool matches_record_layout() {
		if (record_value == null) {
			return original_record_leaves.length == 0;
		}
		if (record_value.mode != original_record_mode || record_value.leaves.length != original_record_leaves.length || record_value.ownership.length != original_record_owners.length) {
			return false;
		}
		for (int l = 0; l < original_record_leaves.length; l++) {
			var original = original_record_leaves[l];
			var actual = record_value.leaves[l];
			if (original.field_path != actual.field_path || original.storage_path != actual.storage_path || original.buffer_component != actual.buffer_component || !original.abi_type.same_type (actual.abi_type)) {
				return false;
			}
		}
		for (int o = 0; o < original_record_owners.length; o++) {
			if (original_record_owners[o] != record_value.ownership[o]) {
				return false;
			}
		}
		return true;
	}

	public NativeScalarOwner? resource { get; private set; }
	public int element_ordinal { get; private set; }
	private string element_identifier;
	public string element_name { get { return element_identifier; } }
	public int destructor_ordinal { get; private set; }
	public NativeScalarType base_type { get; private set; }
	public NativeScalarType length_type { get; private set; }
	public NativeScalarType capacity_type { get; private set; }
	internal NativeOwnerSlotsType (int element, string name, int destructor, NativeScalarType base_type = NativeScalarType.PTR, NativeScalarType length_type = NativeScalarType.I32, NativeScalarType capacity_type = NativeScalarType.I32, NativeScalarOwner? resource = null, NativeStructValuePlan? record = null) {
		this.resource = resource;
		this.record_value = record;
		if (record != null) {
			original_record_mode = record.mode;
			foreach (var owner in record.ownership) {
				original_record_owners.add (owner);
			}
			foreach (var leaf in record.leaves) {
				original_record_leaves.add (leaf);
			}
		}
		element_ordinal = element;
		element_identifier = name;
		destructor_ordinal = destructor;
		this.base_type = base_type;
		this.length_type = length_type;
		this.capacity_type = capacity_type;
	}

	public override string spelling() {
		if (record_value != null) {
			return "OWNER_SLOTS(record#%d:%s,leaves#%u,%s,%s,%s)".printf (record_value.struct_ordinal, record_value.struct_name, record_value.leaf_count, base_type.spelling (), length_type.spelling (), capacity_type.spelling ());
		}
		if (resource != null) {
			return "OWNER_SLOTS(resource:%s,destroy:%s,%s,%s,%s)".printf (resource.type_name, resource.cleanup_symbol, base_type.spelling (), length_type.spelling (), capacity_type.spelling ());
		}
		return "OWNER_SLOTS(class#%d:%s,dtor#%d,%s,%s,%s)".printf (element_ordinal, element_name, destructor_ordinal, base_type.spelling (), length_type.spelling (), capacity_type.spelling ());
	}

	public override bool same_type(NativeAbiType other) {
		var slots = other as NativeOwnerSlotsType;
		return slots != null && matches_record_layout () && slots.matches_record_layout () && slots.record_value == record_value && (resource == null ? slots.resource == null : resource.same_owner (slots.resource)) && slots.element_ordinal == element_ordinal && slots.element_name == element_name && slots.destructor_ordinal == destructor_ordinal && slots.base_type == base_type && slots.length_type == length_type && slots.capacity_type == capacity_type;
	}

}
}
