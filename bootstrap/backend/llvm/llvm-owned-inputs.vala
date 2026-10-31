// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.NativeAbi;
using Astra.Source;

namespace Astra.Backend.LLVM {
// The record tuple has one physical role map. Context, ownership and loan
// contracts consume it independently and retain only their own LLVM authority.
internal class LlvmScopedRecordInputs : Object {
	internal static bool bind(NativeSignature signature, GenericArray<NativeClassPlan> classes, HashTable<int, NativeObjectOriginPlan> origins) throws LlvmError {
		var occupied = new HashTable<int, bool> (direct_hash, direct_equal);
		foreach (var group in signature.struct_parameters) {
			var record = group.value_plan;
			bool borrowed = group.mode == NativeStructValueMode.BORROW_VALUE;
			if (group.first_leaf < 0 || group.first_leaf > signature.parameters.length || record.leaves.length > signature.parameters.length - group.first_leaf) {
				return false;
			}
			var seen = new HashTable<NativeRecordResource, bool> (direct_hash, direct_equal);
			for (int f = 0; f < record.leaves.length; f++) {
				int position = group.first_leaf + f;
				var leaf = record.leaves[f];
				var parameter = signature.parameters[position];
				var scalar = leaf.abi_type as NativeScalarAbiType;
				if (occupied.contains (position) || leaf.buffer_component != -1 || scalar == null || leaf.abi_type.get_type () != typeof (NativeScalarAbiType) || !parameter.abi_type.same_type (leaf.abi_type) || parameter.resource != null || parameter.owns_resource) {
					return false;
				}
				occupied.insert (position, true);
				NativeRecordResource? owner = null;
				foreach (var candidate in record.ownership) {
					if (candidate.field_path == leaf.storage_path) {
						if (owner != null) {
							throw new LlvmError.INVALID_INPUT ("record Class input repeats a physical ownership path");
						}
						owner = candidate;
					}
				}
				if (owner == null) {
					if (scalar.scalar_type == NativeScalarType.PTR || parameter.borrowed_class_ordinal >= 0 || parameter.object_origin != null) {
						return false;
					}
					continue;
				}
				if ((!borrowed && group.mode != NativeStructValueMode.MOVE_VALUE) || scalar.scalar_type != NativeScalarType.PTR || owner.buffer_cleanup != null || owner.cleanup_symbol != "" || owner.cleanup_class_ordinal < 0 || owner.cleanup_class_ordinal >= classes.length || seen.contains (owner)) {
					return false;
				}
				var object_class = classes[owner.cleanup_class_ordinal];
				if (object_class.name != owner.type_name || !object_class.allocation_policy_valid ()) {
					throw new LlvmError.INVALID_INPUT ("record Class input lost its exact native heap origin");
				}
				var original = parameter.object_origin;
				if (borrowed) {
					if (original != null || parameter.borrowed_class_ordinal != object_class.ordinal) {
						return false;
					}
					var policy = object_class.allocation_policy;
					if (!(policy != null && policy.kind == AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") && !LlvmScopedClassGraph.scope_free (object_class, classes)) {
						return false;
					}
				} else {
					if (parameter.borrowed_class_ordinal >= 0 || object_class.polymorphic) {
						return false;
					}
					if (original != null && (!original.heap || original.class_ordinal != object_class.ordinal || original.class_name != object_class.name)) {
						throw new LlvmError.INVALID_INPUT ("record Class input conflicts with its physical parameter origin");
					}
					origins.insert (position, new NativeObjectOriginPlan (object_class.ordinal, object_class.name, true));
				} seen.insert (owner, true);
			}
			if (seen.size () != record.ownership.length) {
				return false;
			}
		}
		return true;
	}
}

// Presence discovery follows copied native owning declarations only. It never
// grants a loan or transfer; every discovered scoped graph needs its own proof.
private class LlvmScopedGraphInventory : Object {
	private NativeAbiProgram program;
	private GenericArray<NativeClassPlan> classes = new GenericArray<NativeClassPlan> ();
	private GenericArray<NativeStructValuePlan> records = new GenericArray<NativeStructValuePlan> ();
	internal LlvmScopedGraphInventory (NativeAbiProgram program) {
		this.program = program;
	}
	internal void add_class(int ordinal) throws LlvmError {
		if (ordinal < 0 || ordinal >= program.classes.length) {
			throw new LlvmError.INVALID_INPUT ("scoped graph lost its exact native Class origin");
		}
		classes.add (program.classes[ordinal]);
	}
	private void add_fields(NativeClassPlan owner) throws LlvmError {
		foreach (var field in owner.fields) {
			if (field.owned_class_ordinal >= 0) {
				add_class (field.owned_class_ordinal);
			}
			if (field.owns_record) {
				add_record_ordinal (field.record_ordinal);
			}
			add_type (field.storage_type);
		}
		foreach (var cache in owner.lazy_caches) {
			if (cache.is_owned) {
				add_class (cache.owned_class_ordinal);
			}
		}
	}
	internal void add_value_class(int ordinal) throws LlvmError {
		// Caller-provided Class storage does not use the Class heap allocator.
		// Its owned fields still retain their actual heap/context authority.
		var pending = new GenericArray<int> ();
		var seen = new HashTable<int, bool> (direct_hash, direct_equal);
		pending.add (ordinal);
		for (int i = 0; i < pending.length; i++) {
			int next = pending[i];
			if (next < 0 || next >= program.classes.length) {
				throw new LlvmError.INVALID_INPUT ("scoped graph lost its exact native value Class origin");
			}
			if (seen.contains (next)) {
				continue;
			}
			seen.insert (next, true);
			var owner = program.classes[next];
			if (!owner.allocation_policy_valid ()) {
				throw new LlvmError.INVALID_INPUT ("scoped value Class graph lost its exact allocator policy");
			}
			add_fields (owner);
			if (owner.parent_ordinal >= 0) {
				pending.add (owner.parent_ordinal);
			}
			if (owner.polymorphic) {
				foreach (var derived in program.classes) {
					if (derived.parent_ordinal == owner.ordinal) {
						pending.add (derived.ordinal);
					}
				}
			}
		}
	}
	private void add_name(string name) throws LlvmError {
		foreach (var owner in program.classes) {
			if (owner.name == name) {
				add_class (owner.ordinal);
				return;
			}
		}
		throw new LlvmError.INVALID_INPUT ("scoped graph lost its exact retained Class declaration");
	}
	internal void add_record(NativeStructValuePlan record) {
		records.add (record);
	}
	private void add_record_ordinal(int ordinal) throws LlvmError {
		bool found = false;
		foreach (var record in program.struct_values) {
			if (record.struct_ordinal == ordinal) {
				add_record (record);
				found = true;
			}
		}
		if (!found) {
			throw new LlvmError.INVALID_INPUT ("scoped graph lost its exact owning record declaration");
		}
	}
	internal void add_buffer(NativeBufferValuePlan buffer) throws LlvmError {
		if (buffer.record_element != null) {
			if (!buffer.record_element.trivial_destruction) {
				add_record_ordinal (buffer.record_element.struct_ordinal);
			}
		} else {
			add_type (buffer.element_type);
		}
	}
	internal void add_type(NativeAbiType? type) throws LlvmError {
		var slots = type as NativeOwnerSlotsType;
		if (slots != null) {
			if (slots.record_value != null) {
				add_record (slots.record_value);
			} else if (slots.resource == null) {
				add_class (slots.element_ordinal);
			}
			return;
		}
		var shared = type as NativeSharedHandleType;
		if (shared != null) {
			if (shared.actor_sender != null) {
				add_type (shared.actor_sender);
			} else {
				add_name (shared.payload);
			} return;
		}
		var closure = type as NativeClosureHandleType;
		if (closure != null) {
			add_name (closure.environment);
			if (closure.actor_message != null) {
				add_name (closure.actor_message);
			}
		}
	}
	internal bool contains_scope() throws LlvmError {
		var seen_classes = new HashTable<NativeClassPlan, bool> (direct_hash, direct_equal);
		var seen_records = new HashTable<NativeStructValuePlan, bool> (direct_hash, direct_equal);
		int at = 0;
		int record_at = 0;
		while (at < classes.length || record_at < records.length) {
			while (at < classes.length) {
				var owner = classes[at++];
				if (seen_classes.contains (owner)) {
					continue;
				}
				seen_classes.insert (owner, true);
				if (!owner.allocation_policy_valid ()) {
					throw new LlvmError.INVALID_INPUT ("scoped Class graph lost its exact allocator policy");
				}
				var policy = owner.allocation_policy;
				if (policy != null && policy.kind == AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") {
					return true;
				}
				if (owner.parent_ordinal >= 0) {
					add_class (owner.parent_ordinal);
				}
				if (owner.polymorphic) {
					foreach (var derived in program.classes) {
						if (derived.parent_ordinal == owner.ordinal) {
							add_class (derived.ordinal);
						}
					}
				}
				add_fields (owner);
			}
			while (record_at < records.length) {
				var record = records[record_at++];
				if (seen_records.contains (record)) {
					continue;
				}
				seen_records.insert (record, true);
				foreach (var owner in record.ownership) {
					if (owner.cleanup_class_ordinal >= 0) {
						add_class (owner.cleanup_class_ordinal);
					}
					if (owner.buffer_cleanup != null) {
						add_buffer (owner.buffer_cleanup);
					}
				}
				foreach (var leaf in record.leaves) {
					add_type (leaf.abi_type);
				}
			}
		}
		return false;
	}
}
// An ordinary Class parameter may accompany a scoped input only when its
// complete native owning graph proves that no scoped authority is hidden in it.
internal class LlvmScopedClassGraph : Object {
	internal static bool contains_scope(NativeClassPlan root, NativeAbiProgram program) throws LlvmError {
		var inventory = new LlvmScopedGraphInventory (program);
		inventory.add_class (root.ordinal);
		return inventory.contains_scope ();
	}
	internal static bool scope_free(NativeClassPlan root, GenericArray<NativeClassPlan> classes) {
		var pending = new GenericArray<NativeClassPlan> ();
		var seen = new HashTable<NativeClassPlan, bool> (direct_hash, direct_equal);
		pending.add (root);
		for (int at = 0; at < pending.length; at++) {
			var owner = pending[at];
			if (seen.contains (owner)) {
				continue;
			}
			seen.insert (owner, true);
			if (!owner.allocation_policy_valid () || owner.polymorphic || owner.foreign_export != null || owner.lazy_caches.length != 0 || owner.allocation_policy != null && owner.allocation_policy.kind == AllocationKind.CONTEXT && owner.allocation_policy.context_mode == "scoped-affine") {
				return false;
			}
			if (owner.parent_ordinal >= 0) {
				if (owner.parent_ordinal >= classes.length) {
					return false;
				}
				pending.add (classes[owner.parent_ordinal]);
			}
			foreach (var field in owner.fields) {
				if (field.owns_record) {
					var children = LlvmScopedPlainRecords.children (field, classes);
					if (children == null) {
						return false;
					}
					foreach (var child in children) {
						pending.add (child);
					}
					continue;
				}
				if (LlvmScopedPlainBuffers.field (field)) {
					continue;
				}
				if (field.storage_type == null || field.storage_type.get_type () != typeof (NativeScalarAbiType) || field.text_snapshot || field.owns_buffer || field.owns_record || field.resource_owner != null) {
					return false;
				}
				var scalar = (NativeScalarAbiType) field.storage_type;
				if (scalar.scalar_type != NativeScalarType.PTR) {
					if (field.owned_class_ordinal >= 0) {
						return false;
					}
					continue;
				}
				if (field.owned_class_ordinal < 0 || field.owned_class_ordinal >= classes.length) {
					return false;
				}
				pending.add (classes[field.owned_class_ordinal]);
			}
		}
		return true;
	}
	internal static bool value_scope_free(NativeClassPlan owner, GenericArray<NativeClassPlan> classes) {
		// Caller-provided value storage ignores only the outer heap allocator.
		// Unknown layouts and owning descendants still require their own proof.
		if (!owner.allocation_policy_valid () || owner.parent_ordinal >= 0 || owner.polymorphic || owner.foreign_export != null || owner.concurrency_policy != null || owner.lazy_caches.length != 0) {
			return false;
		}
		foreach (var field in owner.fields) {
			if (LlvmScopedPlainRecords.scope_free (field, classes) || LlvmScopedPlainBuffers.field (field)) {
				continue;
			}
			var scalar = field.storage_type as NativeScalarAbiType;
			if (scalar == null || field.storage_type.get_type () != typeof (NativeScalarAbiType) || field.text_snapshot || field.owns_buffer || field.owns_record || field.resource_owner != null) {
				return false;
			}
			if (scalar.scalar_type != NativeScalarType.PTR) {
				if (field.owned_class_ordinal >= 0) {
					return false;
				}
				continue;
			}
			if (field.owned_class_ordinal < 0 || field.owned_class_ordinal >= classes.length || !scope_free (classes[field.owned_class_ordinal], classes)) {
				return false;
			}
		}
		return true;
	}
}
// Inline owned records carry exact copied leaf/cleanup plans. Only ordinary
// Class owners and numeric/vector copied data participate in this descriptor.
internal class LlvmScopedPlainRecords : Object {
	internal static GenericArray<NativeClassPlan>? children(NativeClassField field, GenericArray<NativeClassPlan> classes) {
		var plan = field.record_value;
		if (!field.owns_record || plan == null || plan.mode != NativeStructValueMode.MOVE_VALUE || plan.ownership.length == 0 || plan.struct_ordinal != field.record_ordinal || plan.struct_name != field.type_name || field.storage_type != null || field.owns_buffer || field.owned_class_ordinal >= 0 || field.resource_owner != null || field.text_snapshot) {
			return null;
		}
		var result = new GenericArray<NativeClassPlan> ();
		var found = new HashTable<NativeRecordResource, bool> (direct_hash, direct_equal);
		foreach (var leaf in plan.leaves) {
			var scalar = leaf.abi_type as NativeScalarAbiType;
			if (leaf.buffer_component != -1 || scalar == null && !(leaf.abi_type is NativeVectorType) || scalar != null && leaf.abi_type.get_type () != typeof (NativeScalarAbiType)) {
				return null;
			}
			if (scalar == null || scalar.scalar_type != NativeScalarType.PTR) {
				continue;
			}
			NativeRecordResource? owner = null;
			foreach (var candidate in plan.ownership) {
				if (candidate.field_path == leaf.storage_path) {
					if (owner != null) {
						return null;
					}
					owner = candidate;
				}
			}
			if (owner == null || found.contains (owner) || owner.buffer_cleanup != null || owner.cleanup_symbol != "" || owner.cleanup_class_ordinal < 0 || owner.cleanup_class_ordinal >= classes.length || owner.type_name != classes[owner.cleanup_class_ordinal].name) {
				return null;
			}
			var child = classes[owner.cleanup_class_ordinal];
			if (!child.allocation_policy_valid () || child.polymorphic || child.is_interface) {
				return null;
			}
			result.add (child);
			found.insert (owner, true);
		}
		return found.size () == plan.ownership.length ? result : null;
	}
	internal static bool scope_free(NativeClassField field, GenericArray<NativeClassPlan> classes) {
		var children = children (field, classes);
		if (children == null) {
			return false;
		}
		foreach (var child in children) {
			if (!LlvmScopedClassGraph.scope_free (child, classes)) {
				return false;
			}
		}
		return true;
	}
	internal static GenericArray<int>? inputs(RuntimeLifetimeSummary summary, int field, NativeStructValuePlan plan, NativeSignature signature) throws RuntimeLifetimeError {
		GenericArray<int>? found = null;
		foreach (var group in signature.struct_parameters) {
			if (group.value_plan != plan || group.mode != NativeStructValueMode.MOVE_VALUE) {
				continue;
			}
			var positions = new GenericArray<int> ();
			bool exact = true;
			foreach (var owner in plan.ownership) {
				int leaf = -1;
				for (int i = 0; i < plan.leaves.length; i++) {
					if (plan.leaves[i].storage_path == owner.field_path) {
						leaf = i;
					}
				}
				if (leaf < 0) {
					exact = false;
					break;
				}
				var path = new StringBuilder ("f%d".printf (field));
				for (int d = 0; d < owner.depth; d++) {
					path.append_printf (".f%d", owner.path_ordinal (d));
				}
				var roots = summary.equations.requirements (summary.update (-1), path.str);
				int position = group.first_leaf + leaf;
				if (position < 0 || position >= signature.parameters.length || roots.length != 1 || roots[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || roots[0].ordinal != position || roots[0].path != "" || !roots[0].descendants || roots[0].exclusion_count != 0) {
					exact = false;
					break;
				}
				positions.add (position);
			}
			if (exact) {
				if (found != null) {
					return null;
				}
				found = positions;
			}
		}
		return found;
	}
}
// Ordinary numeric/vector buffer contents carry no scoped owners. The full
// owned PTR/I32 role and element descriptor remain mandatory at admission.
internal class LlvmScopedPlainBuffers : Object {
	internal static bool scope_free(NativeBufferValuePlan? plan) {
		if (plan == null || plan.context_origin != null || plan.record_element != null || !plan.transfers_ownership || plan.base_type != NativeScalarType.PTR || plan.length_type != NativeScalarType.I32) {
			return false;
		}
		var scalar = plan.element_type as NativeScalarAbiType;
		return scalar != null && plan.element_type.get_type () == typeof (NativeScalarAbiType) && scalar.scalar_type != NativeScalarType.PTR || plan.element_type is NativeVectorType;
	}
	internal static bool field(NativeClassField field) {
		return field.owns_buffer && field.owned_class_ordinal < 0 && field.resource_owner == null && !field.text_snapshot && !field.owns_record && field.storage_type != null && field.storage_type.get_type () == typeof (NativeSliceType) && scope_free (field.buffer_value);
	}
	internal static NativeBufferValuePlan? parameter(NativeSignature signature, int position) {
		foreach (var group in signature.buffer_parameters) {
			if (group.first_leaf == position && scope_free (group.value_plan)) {
				return group.value_plan;
			}
		}
		return null;
	}
	internal static bool groups(NativeSignature signature) {
		var occupied = new HashTable<int, bool> (direct_hash, direct_equal);
		foreach (var group in signature.buffer_parameters) {
			int p = group.first_leaf;
			if (!scope_free (group.value_plan) || p < 0 || p + 1 >= signature.parameters.length || occupied.contains (p) || occupied.contains (p + 1)) {
				return false;
			}
			var pointer = signature.parameters[p];
			var length = signature.parameters[p + 1];
			if (pointer.abi_type.get_type () != typeof (NativeScalarAbiType) || length.abi_type.get_type () != typeof (NativeScalarAbiType) || pointer.scalar_type != NativeScalarType.PTR || length.scalar_type != NativeScalarType.I32 || pointer.object_origin != null || pointer.borrowed_class_ordinal >= 0 || pointer.resource != null || pointer.owns_resource || length.object_origin != null || length.resource != null || length.owns_resource) {
				return false;
			}
			occupied.insert (p, true);
			occupied.insert (p + 1, true);
		}
		return true;
	}
	internal static bool component(NativeSignature signature, int position) {
		foreach (var group in signature.buffer_parameters) {
			if (position == group.first_leaf || position == group.first_leaf + 1) {
				return true;
			}
		}
		return false;
	}
}
// A copied physical projection. Every GEP retains its exact containing type,
// bounded constant index and original receiver; no source place survives.
internal class LlvmScopedMemberPath : Object {
	private int[] steps;
	internal LlvmScopedMemberPath (int field) {
		steps = {
			field
		};
	}
	internal LlvmScopedMemberPath.record (int field, NativeRecordResource owner) throws LlvmError {
		if (owner.depth < 1 || owner.depth > 255) {
			throw new LlvmError.INVALID_INPUT ("scoped record field requires a bounded complete physical path");
		}
		steps = new int[owner.depth + 1];
		steps[0] = field;
		for (int i = 0; i < owner.depth; i++) {
			steps[i + 1] = owner.path_ordinal (i);
		}
	}
	internal string key {
		owned get {
			var text = new StringBuilder ();
			foreach (int step in steps) {
				text.append_printf ("/%d", step);
			}
			return text.str;
		}
	}
	private bool matches_depth(CApi.ValueRef value, CApi.ValueRef receiver, CApi.TypeRef layout, int depth) {
		if (depth == 0) {
			return (void*) value == (void*) receiver;
		}
		var containing = layout;
		for (int i = 0; i < depth - 1; i++) {
			if (CApi.type_kind (containing) != CApi.TypeKind.STRUCT || steps[i] < 0 || steps[i] >= CApi.count_struct_element_types (containing)) {
				return false;
			}
			containing = CApi.struct_get_type_at_index (containing, (uint) steps[i]);
		}
		if (CApi.type_kind (containing) != CApi.TypeKind.STRUCT || steps[depth - 1] < 0 || steps[depth - 1] >= CApi.count_struct_element_types (containing) || (void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.GEP || CApi.operand_count (value) != 3 || (void*) CApi.gep_source_type (value) != (void*) containing || (void*) CApi.is_constant_int (CApi.operand (value, 1)) == null || CApi.const_int_zext (CApi.operand (value, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (value, 2)) == null || CApi.const_int_zext (CApi.operand (value, 2)) != steps[depth - 1]) {
			return false;
		}
		return matches_depth (CApi.operand (value, 0), receiver, layout, depth - 1);
	}
	internal bool matches(CApi.ValueRef value, CApi.ValueRef receiver, CApi.TypeRef layout) {
		return steps.length > 0 && steps.length <= 256 && matches_depth (value, receiver, layout, steps.length);
	}
}
// Copied field effects of an exact native Class constructor/destructor. These
// establish callee proofs; caller field transport needs its own loan tracking.
internal class LlvmScopedFieldContract : Object {
	internal bool plain_buffers { get; private set; }
	internal bool plain_records { get; private set; }
	private GenericArray<int> buffer_members = new GenericArray<int> ();
	internal CApi.ValueRef receiver;
	internal CApi.TypeRef layout;
	internal bool constructor;
	internal bool mutation;
	internal bool publishes { get { return constructor || mutation; } }
	internal bool scoped_receiver { get; private set; }
	internal CApi.ValueRef receiver_tag;
	internal CApi.ValueRef receiver_size;
	internal CApi.ValueRef receiver_alignment;
	internal bool default_backing { get; private set; }
	internal int backing_mode { get; private set; default = -1; }
	internal CApi.ValueRef backing_tag;
	internal CApi.ValueRef backing_size;
	internal uint backing_alignment;
	internal int exception_class { get; private set; default = -1; }
	internal bool checked_constructor { get; private set; }
	internal int unwind_field_count { get; private set; }
	internal LlvmScopedExceptionShape? exception_shape;
	private GenericArray<int> members = new GenericArray<int> ();
	private GenericArray<LlvmScopedMemberPath> paths = new GenericArray<LlvmScopedMemberPath> ();
	private GenericArray<int> inputs = new GenericArray<int> ();
	private GenericArray<int> owners = new GenericArray<int> ();
	private GenericArray<LlvmScopedOwnerGraph?> graphs = new GenericArray<LlvmScopedOwnerGraph?> ();
	internal LlvmScopedOwnerGraph? graph(int field) {
		return graphs[field];
	}
	internal uint count { get { return members.length; } }
	internal string path(int field) {
		return paths[field].key;
	}
	internal bool empty_exception {
		get {
			if (!constructor || exception_class < 0 || !default_backing || count == 0) {
				return false;
			}
			for (int f = 0;
			     f < count;
			     f++) {
				if (!empty_field (f)) {
					return false;
				}
			}
			return true;
		}
	}
	internal bool empty_field(int field) {
		return publishes && inputs[field] < 0;
	}
	internal int input(int field) {
		return inputs[field];
	}
	internal int owner(int field) {
		return owners[field];
	}
	private int path_index(LlvmScopedMemberPath path) {
		for (int i = 0; i < paths.length; i++) {
			if (paths[i].key == path.key) {
				return i;
			}
		}
		return -1;
	}
	private bool track(LlvmModuleArtifact artifact, NativeClassPlan child, int member, LlvmScopedMemberPath path, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs) throws LlvmError {
		if (!child.allocation_policy_valid ()) {
			return false;
		}
		var policy = child.allocation_policy;
		if ((policy == null || policy.kind != AllocationKind.CONTEXT || policy.context_mode != "scoped-affine") && LlvmScopedClassGraph.scope_free (child, classes)) {
			return true;
		}
		LlvmScopedOwnerGraph? graph = null;
		if (!LlvmScopedClassGraph.value_scope_free (child, classes)) {
			graph = LlvmScopedOwnerGraph.from_native (artifact, child, classes, structs);
			if (graph == null) {
				return false;
			}
		}
		if (path_index (path) >= 0) {
			return false;
		}
		members.add (member);
		paths.add (path);
		owners.add (child.ordinal);
		graphs.add (graph);
		inputs.add (-1);
		return true;
	}
	internal LlvmScopedExceptionShape? empty_base_shape;
	internal static LlvmScopedFieldContract empty_error(CApi.TypeRef layout, LlvmScopedExceptionShape shape, LlvmScopedExceptionShape parent) {
		var result = new LlvmScopedFieldContract ();
		result.layout = layout;
		result.default_backing = true;
		result.exception_shape = shape;
		result.empty_base_shape = parent;
		return result;
	}
	internal static LlvmScopedFieldContract? from_native(LlvmModuleArtifact artifact, CApi.ValueRef function, NativeFunction source, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs) throws LlvmError {
		if (!source.declaring_type_is_class || source.kind != NativeCallableKind.CONSTRUCTOR && source.kind != NativeCallableKind.DESTRUCTOR && source.kind != NativeCallableKind.METHOD || source.declaring_type_ordinal < 0 || source.declaring_type_ordinal >= classes.length || source.signature.receiver == null || source.signature.result != null || source.signature.exception_plan != null && (source.kind != NativeCallableKind.CONSTRUCTOR || source.constructor_unwind == null)) {
			return null;
		}
		var owner = classes[source.declaring_type_ordinal];
		if (!owner.allocation_policy_valid () || owner.parent_ordinal != -1 || owner.polymorphic && !owner.exception_root || owner.is_interface || owner.concurrency_policy != null || owner.lazy_caches.length != 0 || owner.foreign_export != null) {
			return null;
		}
		// Lifetime paths use declaration ordinals. Exception roots prepend their
		// descriptor and original throw location in the physical Class layout.
		int prefix = owner.polymorphic ? 2 : 0;
		var all_members = new GenericArray<int> ();
		var all_owners = new GenericArray<int> ();
		var all_buffers = new GenericArray<NativeBufferValuePlan?> ();
		var all_records = new GenericArray<NativeStructValuePlan?> ();
		var result = new LlvmScopedFieldContract ();
		result.constructor = source.kind == NativeCallableKind.CONSTRUCTOR;
		result.mutation = source.kind == NativeCallableKind.METHOD;
		result.checked_constructor = source.signature.exception_plan != null;
		result.receiver = CApi.get_param (function, 0);
		result.default_backing = owner.allocation_policy == null;
		if (owner.exception_root) {
			result.exception_class = owner.ordinal;
		}
		foreach (var field in owner.fields) {
			if (field.owns_record) {
				if (LlvmScopedPlainRecords.children (field, classes) == null) {
					return null;
				}
				result.plain_records = true;
				all_members.add (field.ordinal);
				all_owners.add (-3);
				all_buffers.add (null);
				all_records.add (field.record_value);
				foreach (var resource in field.record_value.ownership) {
					if (!result.track (artifact, classes[resource.cleanup_class_ordinal], field.ordinal + prefix, new LlvmScopedMemberPath.record (field.ordinal + prefix, resource), classes, structs)) {
						return null;
					}
				}
				continue;
			}
			if (field.owns_buffer) {
				if (!LlvmScopedPlainBuffers.field (field)) {
					return null;
				}
				result.plain_buffers = true;
				result.buffer_members.add (field.ordinal + prefix);
				all_members.add (field.ordinal);
				all_owners.add (-2);
				all_buffers.add (field.buffer_value);
				all_records.add (null);
				continue;
			}
			var scalar = field.storage_type as NativeScalarAbiType;
			if (scalar == null || field.storage_type.get_type () != typeof (NativeScalarAbiType) || field.text_snapshot || field.owns_buffer || field.owns_record || field.resource_owner != null || scalar.scalar_type == NativeScalarType.F32 || scalar.scalar_type == NativeScalarType.F64) {
				return null;
			}
			if (scalar.scalar_type != NativeScalarType.PTR) {
				if (field.owned_class_ordinal >= 0) {
					return null;
				}
				continue;
			}
			if (field.owned_class_ordinal < 0 || field.owned_class_ordinal >= classes.length) {
				return null;
			}
			var child = classes[field.owned_class_ordinal];
			if (!child.allocation_policy_valid ()) {
				return null;
			}
			all_members.add (field.ordinal);
			all_owners.add (field.owned_class_ordinal);
			all_buffers.add (null);
			all_records.add (null);
			if (!result.track (artifact, child, field.ordinal + prefix, new LlvmScopedMemberPath (field.ordinal + prefix), classes, structs)) {
				return null;
			}
		}
		result.scoped_receiver = owner.allocation_policy != null && owner.allocation_policy.kind == AllocationKind.CONTEXT && owner.allocation_policy.context_mode == "scoped-affine";
		// The scoped verifier reconstructs the bounded initialized-field stack
		// and checks exceptional input retirement before a caller may delegate
		// its failed-construction child obligations to this exact sealed body.
		if (result.checked_constructor) {
			result.unwind_field_count = source.constructor_unwind.field_count;
		}
		// A scoped outer object is itself an allocation obligation even when
		// its owned children use independent, scope-free heap storage.
		if (result.count == 0 && !result.scoped_receiver) {
			return null;
		}
		result.layout = structs.class_layout (owner.ordinal, owner.name);
		if (result.scoped_receiver || result.count != 0) {
			if (artifact.class_target == null) {
				artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
			}
			var data = artifact.class_target.enum_target_data (artifact);
			result.receiver_tag = new LlvmPolicyAllocation (artifact).tag (owner.name, "object");
			result.receiver_size = CApi.const_int (CApi.int_type_in_context (artifact.context, 64), CApi.abi_size_of_type (data, result.layout), 0);
			result.receiver_alignment = CApi.const_int (CApi.int32_type_in_context (artifact.context), uint.max (CApi.abi_alignment_of_type (data, result.layout), (owner.allocation_policy == null ? 1 : owner.allocation_policy.alignment)), 0);
			result.backing_mode = result.scoped_receiver ? 3 : -1;
			result.backing_tag = result.receiver_tag;
			result.backing_size = result.receiver_size;
			result.backing_alignment = (uint) CApi.const_int_zext (result.receiver_alignment);
		}
		if (owner.allocation_policy != null && owner.allocation_policy.kind == AllocationKind.CONTEXT && owner.allocation_policy.context_mode != "scoped-affine") {
			var policy = owner.allocation_policy;
			result.backing_mode = policy.context_mode == "owned-concurrent" ? 2 : policy.context_mode == "owned-transfer" ? 1 : 0;
			result.backing_tag = new LlvmPolicyAllocation (artifact).tag (owner.name, "object");
			if (artifact.class_target == null) {
				artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
			}
			result.backing_alignment = uint.max (CApi.abi_alignment_of_type (artifact.class_target.enum_target_data (artifact), result.layout), policy.alignment);
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			if (!summary.complete || !summary.matches_exception (source.signature.exception_plan != null) || summary.equations.requirements (summary.result).length != 0 || summary.has_exception && summary.equations.requirements (summary.exception).length != 0) {
				return null;
			}
			var updates = summary.updated_inputs ();
			if (updates.length != 1 || updates[0] != -1) {
				return null;
			}
			var root = summary.equations.requirements (summary.update (-1), "", false);
			if (root.length != 1 || root[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || root[0].ordinal != -1 || root[0].path != "" || root[0].descendants) {
				return null;
			}
			var record_origins = new HashTable<int, NativeObjectOriginPlan> (direct_hash, direct_equal);
			if (!LlvmScopedRecordInputs.bind (source.signature, classes, record_origins)) {
				return null;
			}
			var all_inputs = new GenericArray<int> ();
			for (int f = 0; f < all_members.length; f++) {
				var roots = summary.equations.requirements (summary.update (-1), "f%d".printf (all_members[f]));
				int tracked = result.path_index (new LlvmScopedMemberPath (all_members[f] + prefix));
				if (!result.publishes) {
					if (roots.length != 0) {
						return null;
					}
					continue;
				}
				if (result.constructor && roots.length == 0 && all_records[f] == null && all_buffers[f] == null) {
					continue;
				}
				if (all_records[f] != null) {
					var positions = LlvmScopedPlainRecords.inputs (summary, all_members[f], all_records[f], source.signature);
					if (positions == null || roots.length != positions.length || positions.length != all_records[f].ownership.length) {
						return null;
					}
					for (int p = 0; p < positions.length; p++) {
						int position = positions[p];
						if (all_inputs.find (position)) {
							return null;
						}
						all_inputs.add (position);
						int nested = result.path_index (new LlvmScopedMemberPath.record (all_members[f] + prefix, all_records[f].ownership[p]));
						if (nested >= 0) {
							result.inputs[nested] = position;
						}
					}
					continue;
				}
				if (roots.length != 1 || roots[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || roots[0].path != "" || !roots[0].descendants || roots[0].exclusion_count != 0 || roots[0].ordinal < 0 || roots[0].ordinal >= source.signature.parameters.length) {
					return null;
				}
				int position = roots[0].ordinal;
				if (all_inputs.find (position)) {
					return null;
				}
				if (all_buffers[f] != null) {
					var incoming = LlvmScopedPlainBuffers.parameter (source.signature, position);
					if (incoming == null || incoming.element_spelling () != all_buffers[f].element_spelling ()) {
						return null;
					}
				} else {
					var origin = source.signature.parameters[position].object_origin ?? record_origins.lookup (position);
					if (origin == null || !origin.heap || origin.class_ordinal != all_owners[f] || origin.class_name != classes[all_owners[f]].name) {
						return null;
					}
				} all_inputs.add (position);
				if (tracked >= 0) {
					result.inputs[tracked] = position;
				}
			}
			if (summary.store_count != (result.publishes ? all_members.length : 0)) {
				return null;
			}
			var stored = new HashTable<int, bool> (direct_hash, direct_equal);
			for (uint s = 0; s < summary.store_count; s++) {
				var effect = summary.store (s);
				var roots = summary.equations.requirements (effect.value);
				if (effect.parameter != -1 || roots.length == 0 && !result.constructor) {
					return null;
				}
				foreach (var origin in roots) {
					if (origin.kind != RuntimeScopeOriginKind.OWNER_PARAMETER || origin.path != "" || !origin.descendants || origin.exclusion_count != 0 || !all_inputs.find (origin.ordinal) || stored.contains (origin.ordinal)) {
						return null;
					}
					stored.insert (origin.ordinal, true);
				}
			}
			if (result.publishes && stored.size () != all_inputs.length) {
				return null;
			}

		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("scoped Class field lifetime contract: %s", failure.message);
		}
		return result;
	}
	internal bool accepts_receiver(uint position, CApi.ValueRef tag, CApi.ValueRef count, CApi.ValueRef size, CApi.ValueRef alignment) throws LlvmError {
		if ((!scoped_receiver && this.count == 0) || position != 0) {
			return false;
		}
		if ((void*) tag != (void*) receiver_tag || (void*) size != (void*) receiver_size || (void*) alignment != (void*) receiver_alignment || (void*) CApi.is_constant_int (count) == null || CApi.const_int_zext (count) != 1) {
			throw new LlvmError.VERIFICATION ("scoped lifecycle receiver lost its exact Class allocation shape");
		}
		return true;
	}
	internal bool buffer_address(CApi.ValueRef value, CApi.TypeRef type) {
		if ((void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.GEP || CApi.operand_count (value) != 3 || (void*) CApi.gep_source_type (value) != (void*) layout || (void*) CApi.operand (value, 0) != (void*) receiver || (void*) CApi.is_constant_int (CApi.operand (value, 1)) == null || CApi.const_int_zext (CApi.operand (value, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (value, 2)) == null) {
			return false;
		}
		uint64 member = CApi.const_int_zext (CApi.operand (value, 2));
		if (member >= CApi.count_struct_element_types (layout) || !buffer_members.find ((int) member) || (void*) type != (void*) CApi.struct_get_type_at_index (layout, (uint) member) || CApi.type_kind (type) != CApi.TypeKind.STRUCT || CApi.count_struct_element_types (type) != 2) {
			return false;
		}
		return CApi.type_kind (CApi.struct_get_type_at_index (type, 0)) == CApi.TypeKind.POINTER && (void*) CApi.struct_get_type_at_index (type, 1) == (void*) CApi.int32_type_in_context (CApi.type_context (type));
	}
	internal bool address(CApi.ValueRef value, int field) {
		return paths[field].matches (value, receiver, layout);
	}
	internal bool null_initialization(CApi.ValueRef function, CApi.ValueRef end, int field, HashTable<void*, LlvmScopedOwnedInputs>? contracts) throws LlvmError {
		bool initialized = false;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var store = CApi.first_instruction (block); (void*) store != null; store = CApi.next_instruction (store)) {
				if (CApi.opcode (store) != CApi.Opcode.STORE || !address (CApi.operand (store, 1), field)) {
					continue;
				}
				if (CApi.get_volatile (store) != 0 || CApi.get_ordering (store) != 0) {
					return false;
				}
				var value = CApi.operand (store, 0);
				bool absent = (void*) CApi.is_constant_pointer_null (value) != null;
				if (!absent && (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.CALL && contracts != null) {
					var target = contracts.lookup ((void*) CApi.called_value (value));
					absent = target != null && target.literal_null_call (value);
				}
				if (!absent) {
					return false;
				}
				initialized = initialized || LlvmBufferExchangeOrder.precedes (store, end);
			}
		}
		return initialized;
	}
	internal CApi.ValueRef load(CApi.ValueRef function, int field) throws LlvmError {
		CApi.ValueRef found = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.LOAD && CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.POINTER && address (CApi.operand (instruction, 0), field)) {
					if ((void*) found == null) {
						found = instruction;
					}
				}
			}
		}
		if ((void*) found == null) {
			throw new LlvmError.VERIFICATION ("scoped field cleanup lost its original physical owner load");
		}
		return found;
	}
}
// Forwarding preserves the complete existing field carrier. Copy its physical
// scoped members and shapes without retaining a native declaration graph.
internal class LlvmScopedOwnerGraph : Object {
	internal CApi.TypeRef layout;
	internal GenericArray<int> members = new GenericArray<int> ();
	private GenericArray<LlvmScopedMemberPath> paths = new GenericArray<LlvmScopedMemberPath> ();
	internal string path(int field) {
		return paths[field].key;
	}
	internal GenericArray<LlvmScopedOwnerGraph?> children = new GenericArray<LlvmScopedOwnerGraph?> ();
	private GenericArray<void*> tags = new GenericArray<void*> ();
	private GenericArray<void*> sizes = new GenericArray<void*> ();
	private GenericArray<void*> alignments = new GenericArray<void*> ();
	internal static LlvmScopedOwnerGraph? from_native(LlvmModuleArtifact artifact, NativeClassPlan owner, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs) throws LlvmError {
		return build (artifact, owner, classes, structs, new HashTable<NativeClassPlan, bool> (direct_hash, direct_equal));
	}
	private static LlvmScopedOwnerGraph? build(LlvmModuleArtifact artifact, NativeClassPlan owner, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs, HashTable<NativeClassPlan, bool> visiting) throws LlvmError {
		if (visiting.contains (owner) || owner.parent_ordinal >= 0 || owner.polymorphic || owner.foreign_export != null || owner.concurrency_policy != null || owner.lazy_caches.length != 0 || !owner.allocation_policy_valid ()) {
			return null;
		}
		if (owner.allocation_policy != null && owner.allocation_policy.kind != AllocationKind.CONTEXT) {
			return null;
		}
		visiting.insert (owner, true);
		var result = new LlvmScopedOwnerGraph ();
		result.layout = structs.class_layout (owner.ordinal, owner.name);
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		var data = artifact.class_target.enum_target_data (artifact);
		foreach (var field in owner.fields) {
			if (field.owns_record) {
				if (LlvmScopedPlainRecords.children (field, classes) == null) {
					return null;
				}
				foreach (var resource in field.record_value.ownership) {
					var child = classes[resource.cleanup_class_ordinal];
					if (!result.child (artifact, child, field.ordinal, new LlvmScopedMemberPath.record (field.ordinal, resource), classes, structs, visiting, data)) {
						return null;
					}
				}
				continue;
			}

			// Numeric/vector buffers retain the separately checked complete pair
			// and exact lifecycle body; they introduce no scoped child debt.
			if (LlvmScopedPlainRecords.scope_free (field, classes) || LlvmScopedPlainBuffers.field (field)) {
				continue;
			}
			var scalar = field.storage_type as NativeScalarAbiType;
			if (scalar == null || field.storage_type.get_type () != typeof (NativeScalarAbiType) || field.owns_buffer || field.owns_record || field.resource_owner != null || field.text_snapshot) {
				return null;
			}
			if (scalar.scalar_type != NativeScalarType.PTR) {
				if (field.owned_class_ordinal >= 0) {
					return null;
				}
				continue;
			}
			if (field.owned_class_ordinal < 0 || field.owned_class_ordinal >= classes.length) {
				return null;
			}
			if (!result.child (artifact, classes[field.owned_class_ordinal], field.ordinal, new LlvmScopedMemberPath (field.ordinal), classes, structs, visiting, data)) {
				return null;
			}
		}
		visiting.remove (owner);
		return result.members.length == 0 ? null : result;
	}
	private bool child(LlvmModuleArtifact artifact, NativeClassPlan child, int member, LlvmScopedMemberPath path, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs, HashTable<NativeClassPlan, bool> visiting, CApi.TargetDataRef data) throws LlvmError {
		if (!child.allocation_policy_valid ()) {
			return false;
		}
		var policy = child.allocation_policy;
		if ((policy == null || policy.kind != AllocationKind.CONTEXT || policy.context_mode != "scoped-affine") && LlvmScopedClassGraph.scope_free (child, classes)) {
			return true;
		}
		LlvmScopedOwnerGraph? nested = null;
		if (!LlvmScopedClassGraph.value_scope_free (child, classes)) {
			nested = build (artifact, child, classes, structs, visiting);
			if (nested == null) {
				return false;
			}
		}
		foreach (var existing in paths) {
			if (existing.key == path.key) {
				return false;
			}
		}
		var layout = structs.class_layout (child.ordinal, child.name);
		members.add (member);
		paths.add (path);
		children.add (nested);
		tags.add ((void*) new LlvmPolicyAllocation (artifact).tag (child.name, "object"));
		sizes.add ((void*) CApi.const_int (CApi.int_type_in_context (artifact.context, 64), CApi.abi_size_of_type (data, layout), 0));
		alignments.add ((void*) CApi.const_int (CApi.int32_type_in_context (artifact.context), uint.max (CApi.abi_alignment_of_type (data, layout), (policy == null ? 1 : policy.alignment)), 0));
		return true;
	}
	internal bool matches(int field, CApi.ValueRef tag, CApi.ValueRef size, CApi.ValueRef alignment) {
		return tags[field] == (void*) tag && sizes[field] == (void*) size && alignments[field] == (void*) alignment;
	}
}

// Physical Class ownership channels. Complete native effects may consume
// inputs or forward one unchanged owner; actual returns/retirement are checked.
// Copied native declaration effects prove that both inherited lifecycle
// operations leave every owning base field empty. No producer body is kept.
internal class LlvmScopedEmptyImport : Object {
	private RuntimeLifetimeSummary constructor;
	private RuntimeLifetimeSummary destructor;
	private GenericArray<string> paths = new GenericArray<string> ();
	private LlvmNativeModuleBinding cleanup;
	internal LlvmScopedEmptyImport (NativeFunction source, NativeFunction destroy, NativeClassPlan parent, CApi.ValueRef target) throws RuntimeLifetimeError {
		constructor = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
		destructor = RuntimeLifetimeSummary.decode (destroy.runtime_lifetimes);
		foreach (var field in parent.fields) {
			if (field.owned_class_ordinal >= 0 || field.owns_buffer || field.owns_record || field.resource_owner != null) {
				paths.add ("f%d".printf (field.ordinal));
			}
		}
		size_t length;
		cleanup = new LlvmNativeModuleBinding (target, CApi.global_value_type (target), CApi.value_name (target, out length), true);
	}
	private void effect(RuntimeLifetimeSummary summary) throws RuntimeLifetimeError, LlvmError {
		if (!summary.complete || summary.has_exception || summary.equations.requirements (summary.result).length != 0) {
			throw new LlvmError.VERIFICATION ("opaque empty lifecycle requires its complete nonthrowing effects");
		}
		var updates = summary.updated_inputs ();
		if (updates.length != 1 || updates[0] != -1) {
			throw new LlvmError.VERIFICATION ("opaque empty lifecycle lost its receiver update");
		}
		var root = summary.equations.requirements (summary.update (-1), "", false);
		if (root.length != 1 || root[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || root[0].ordinal != -1 || root[0].path != "" || root[0].descendants) {
			throw new LlvmError.VERIFICATION ("opaque empty lifecycle lost its original receiver");
		}
		foreach (var path in paths) {
			if (summary.equations.requirements (summary.update (-1), path).length != 0) {
				throw new LlvmError.VERIFICATION ("opaque empty lifecycle retains a base payload");
			}
		}
		for (uint s = 0; s < summary.store_count; s++) {
			var store = summary.store (s);
			if (store.parameter != -1 || summary.equations.requirements (store.value).length != 0) {
				throw new LlvmError.VERIFICATION ("opaque empty lifecycle acquires a stored owner");
			}
		}
	}
	internal void verify() throws LlvmError {
		try {
			effect (constructor);
			effect (destructor);
			cleanup.verify ();
		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.VERIFICATION ("opaque empty lifecycle lost its versioned effects: %s", failure.message);
		}
	}
}
internal class LlvmScopedOwnedInputs : Object {
	private CApi.ValueRef function;
	private CApi.TypeRef type;
	private uint parameter_count;
	private bool null_result;
	internal int returned_parameter { get; private set; default = -1; }
	internal int returned_slot { get; private set; default = -1; }
	private GenericArray<int> result_slots = new GenericArray<int> ();
	private CApi.TypeRef aggregate_type;
	internal uint aggregate_fields { get { return result_slots.length; } }
	internal int result_slot(int field) {
		return result_slots[field];
	}
	internal int result_field(uint position) {
		for (int f = 0; f < result_slots.length; f++) {
			int slot = result_slots[f];
			if (slot >= 0 && positions[slot] == position) {
				return f;
			}
		}
		return -1;
	}
	private CApi.ValueRef success_output = (CApi.ValueRef) null;
	internal bool checked_success { get { return (void*) success_output != null; } }
	internal CApi.ValueRef success_slot() {
		return success_output;
	}
	internal CApi.TypeRef success_type() {
		return aggregate_type;
	}
	internal LlvmScopedFieldContract? fields { get; private set; }
	internal int error_class { get; private set; default = -1; }
	internal bool deferred_error { get; private set; }
	private LlvmScopedEmptyImport? empty_import;
	private CApi.ValueRef empty_base_target = (CApi.ValueRef) null;
	private CApi.TypeRef empty_base_layout;
	private CApi.TypeRef empty_derived_layout;
	private int empty_class = -1;
	private int empty_parent = -1;
	private CApi.ValueRef empty_destroy = (CApi.ValueRef) null;
	private CApi.ValueRef empty_parent_destroy = (CApi.ValueRef) null;
	internal LlvmScopedFieldContract? empty_backing { get; private set; }
	internal bool empty_constructor_call(CApi.ValueRef call) throws LlvmError {
		if (empty_backing == null || !empty_base && (fields == null || !fields.empty_exception)) {
			return false;
		}
		verify ();
		return (void*) CApi.called_value (call) == (void*) function && (void*) CApi.called_function_type (call) == (void*) type && CApi.argument_count (call) == parameter_count && CApi.instruction_call_conv (call) == LlvmLowering.CALL_CONVENTION;
	}
	private void verify_empty_cleanup() throws LlvmError {
		if (empty_backing == null) {
			return;
		}
		if (!empty_base) {
			if (fields == null || !fields.empty_exception || !fields.exception_shape.same (empty_backing.exception_shape) || !empty_backing.exception_shape.same (empty_backing.empty_base_shape)) {
				throw new LlvmError.VERIFICATION ("empty root error lost its exact null-field constructor shape");
			}
			empty_backing.exception_shape.verify_descriptor ();
			return;
		}
		if (imported_body != null) {
			if (empty_import == null) {
				throw new LlvmError.VERIFICATION ("opaque empty cleanup lacks its declared effects");
			}
			empty_import.verify ();
			empty_backing.exception_shape.verify_empty_parent (empty_backing.empty_base_shape);
			return;
		}
		if ((void*) empty_destroy == null || (void*) empty_parent_destroy == null || CApi.count_basic_blocks (empty_destroy) != 1 || CApi.count_params (empty_destroy) != 1 || (void*) CApi.global_value_type (empty_destroy) != (void*) CApi.global_value_type (empty_parent_destroy) || CApi.function_call_conv (empty_destroy) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("empty inherited error lost its exact cleanup ABI");
		}
		var call = CApi.first_instruction (CApi.first_block (empty_destroy));
		if ((void*) call == null || CApi.opcode (call) != CApi.Opcode.CALL || (void*) CApi.called_value (call) != (void*) empty_parent_destroy || (void*) CApi.called_function_type (call) != (void*) CApi.global_value_type (empty_parent_destroy) || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION || CApi.argument_count (call) != 1 || (void*) CApi.operand (call, 0) != (void*) CApi.get_param (empty_destroy, 0)) {
			throw new LlvmError.VERIFICATION ("empty inherited error requires its exact base cleanup");
		}
		var end = CApi.next_instruction (call);
		if ((void*) end == null || CApi.opcode (end) != CApi.Opcode.RET || CApi.operand_count (end) != 0 || (void*) CApi.next_instruction (end) != null) {
			throw new LlvmError.VERIFICATION ("empty inherited error cannot acquire cleanup side effects");
		}
		empty_backing.exception_shape.verify_empty_parent (empty_backing.empty_base_shape);
	}
	internal bool empty_base { get { return (void*) empty_base_target != null; } }
	private void verify_empty_base() throws LlvmError {
		if (!empty_base) {
			return;
		}
		if (imported_body != null) {
			if (empty_import == null) {
				throw new LlvmError.VERIFICATION ("opaque empty constructor lacks its declared effects");
			}
			imported_body.verify ();
			empty_import.verify ();
			return;
		}
		if (CApi.count_basic_blocks (function) != 1) {
			throw new LlvmError.VERIFICATION ("empty inherited constructor requires its exact single initialization body");
		}
		uint calls = 0;
		for (var instruction = CApi.first_instruction (CApi.first_block (function)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			var opcode = CApi.opcode (instruction);
			if (opcode == CApi.Opcode.INSERT_VALUE) {
				continue;
			}
			if (opcode == CApi.Opcode.RET && CApi.operand_count (instruction) == 0) {
				continue;
			}
			if (opcode != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) empty_base_target || CApi.argument_count (instruction) < 1 || (void*) CApi.operand (instruction, 0) != (void*) CApi.get_param (function, 0) || (void*) CApi.called_function_type (instruction) != (void*) CApi.global_value_type (empty_base_target) || CApi.instruction_call_conv (instruction) != LlvmLowering.CALL_CONVENTION) {
				throw new LlvmError.VERIFICATION ("empty inherited constructor lost its exact base initialization");
			}
			for (uint p = 1; p < CApi.argument_count (instruction); p++) {
				if ((void*) CApi.is_constant_pointer_null (CApi.operand (instruction, p)) == null) {
					throw new LlvmError.VERIFICATION ("empty inherited constructor cannot acquire a base payload");
				}
			}
			calls++;
		}
		if (calls != 1) {
			throw new LlvmError.VERIFICATION ("empty inherited constructor requires exactly one base initialization");
		}
	}
	internal bool empty_base_call(CApi.ValueRef call, LlvmScopedOwnedInputs target) throws LlvmError {
		if (!empty_base || target.fields == null || !target.fields.constructor || (void*) target.fields.layout != (void*) empty_base_layout || (void*) CApi.called_value (call) != (void*) empty_base_target) {
			return false;
		}
		verify ();
		target.field_call (call);
		return true;
	}
	internal CApi.TypeRef error_layout;
	internal LlvmScopedExceptionShape? error_shape;
	private GenericArray<int> error_members = new GenericArray<int> ();
	private GenericArray<int> error_slots = new GenericArray<int> ();
	internal uint error_count { get { return error_members.length; } }
	internal int error_member(int field) {
		return error_members[field];
	}
	internal int error_slot(int field) {
		return error_slots[field];
	}
	private GenericArray<int> positions = new GenericArray<int> ();
	private GenericArray<void*> values = new GenericArray<void*> ();
	private GenericArray<void*> sizes = new GenericArray<void*> ();
	private GenericArray<void*> alignments = new GenericArray<void*> ();
	private GenericArray<void*> tags = new GenericArray<void*> ();
	private LlvmSumSequence? body;
	private bool cold_shape;
	internal CApi.TypeRef plain_task_result = (CApi.TypeRef) null;
	private LlvmNativeModuleBinding? imported_body;
	private GenericArray<LlvmScopedOwnerGraph?> input_graphs = new GenericArray<LlvmScopedOwnerGraph?> ();
	private GenericArray<bool> contextual_inputs = new GenericArray<bool> ();
	private GenericArray<bool> scoped_inputs = new GenericArray<bool> ();
	internal bool scoped_input(int slot) {
		return scoped_inputs[slot];
	}
	internal bool contextual_input(int slot) {
		return contextual_inputs[slot];
	}
	internal LlvmScopedOwnerGraph? input_graph(int slot) {
		return slot < 0 || slot >= input_graphs.length ? null : input_graphs[slot];
	}
	internal LlvmScopedOwnerGraph? owner_graph { get; private set; }
	internal int graph_parameter { get; private set; default = -1; }
	internal bool graph_forwarding { get { return owner_graph != null && returned_parameter >= 0; } }
	private LlvmScopedOwnedInputs (CApi.ValueRef function, CApi.TypeRef type) {
		this.function = function;
		this.type = type;
		parameter_count = CApi.count_params (function);
	}
	private void shape(LlvmModuleArtifact artifact, NativeClassPlan owner, LlvmStructRegistry structs, LlvmScopedOwnerGraph? graph = null) throws LlvmError {
		input_graphs.add (graph);
		contextual_inputs.add (owner.allocation_policy != null);
		scoped_inputs.add (owner.allocation_policy != null && owner.allocation_policy.kind == AllocationKind.CONTEXT && owner.allocation_policy.context_mode == "scoped-affine");
		var layout = structs.class_layout (owner.ordinal, owner.name);
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		var data = artifact.class_target.enum_target_data (artifact);
		uint64 bytes = CApi.abi_size_of_type (data, layout);
		uint alignment = uint.max (CApi.abi_alignment_of_type (data, layout), (owner.allocation_policy == null ? 1 : owner.allocation_policy.alignment));
		sizes.add ((void*) CApi.const_int (CApi.int_type_in_context (artifact.context, 64), bytes, 0));
		alignments.add ((void*) CApi.const_int (CApi.int32_type_in_context (artifact.context), alignment, 0));
		tags.add ((void*) new LlvmPolicyAllocation (artifact).tag (owner.name, "object"));
	}
	internal static bool required(NativeSignature signature, NativeAbiProgram program) throws LlvmError {
		var inventory = new LlvmScopedGraphInventory (program);
		foreach (var parameter in signature.parameters) {
			var origin = parameter.object_origin;
			if (origin != null) {
				if (origin.class_ordinal < 0 || origin.class_ordinal >= program.classes.length || program.classes[origin.class_ordinal].name != origin.class_name || !program.classes[origin.class_ordinal].allocation_policy_valid ()) {
					throw new LlvmError.INVALID_INPUT ("scoped formal lost its exact native Class origin");
				}
				if (origin.heap) {
					inventory.add_class (origin.class_ordinal);
				} else {
					inventory.add_value_class (origin.class_ordinal);
				}
			}
			if (parameter.borrowed_class_ordinal >= 0) {
				int borrowed = parameter.borrowed_class_ordinal;
				if (borrowed >= program.classes.length || !program.classes[borrowed].allocation_policy_valid ()) {
					throw new LlvmError.INVALID_INPUT ("borrowed scoped graph lost its exact native Class declaration");
				}
				inventory.add_class (borrowed);
			}
			inventory.add_type (parameter.abi_type);
		}
		foreach (var parameter in signature.struct_parameters) {
			inventory.add_record (parameter.value_plan);
		}
		foreach (var parameter in signature.buffer_parameters) {
			inventory.add_buffer (parameter.value_plan);
		}
		if (signature.result != null) {
			inventory.add_type (signature.result.abi_type);
		}
		if (signature.struct_result != null) {
			inventory.add_record (signature.struct_result);
		}
		if (signature.buffer_result != null) {
			inventory.add_buffer (signature.buffer_result);
		}
		var outputs = new GenericArray<NativeObjectOriginPlan> ();
		if (signature.heap_result != null) {
			outputs.add (signature.heap_result);
		}
		if (signature.object_result != null && signature.object_result.object_origin != null) {
			outputs.add (signature.object_result.object_origin);
		}
		foreach (var origin in outputs) {
			if (origin.class_ordinal < 0 || origin.class_ordinal >= program.classes.length || program.classes[origin.class_ordinal].name != origin.class_name || !program.classes[origin.class_ordinal].allocation_policy_valid ()) {
				throw new LlvmError.INVALID_INPUT ("scoped result lost its exact native Class origin");
			}
			if (origin.heap) {
				inventory.add_class (origin.class_ordinal);
			} else {
				inventory.add_value_class (origin.class_ordinal);
			}
		}
		return inventory.contains_scope ();
	}
	private static NativeObjectOriginPlan? single_record_result(NativeStructValuePlan? record, GenericArray<NativeClassPlan> classes) throws LlvmError {
		if (record == null || record.mode != NativeStructValueMode.MOVE_VALUE || record.result_carrier != NativeStructResultCarrier.SINGLE_LEAF || record.leaves.length != 1 || record.ownership.length != 1) {
			return null;
		}
		var leaf = record.leaves[0];
		var owner = record.ownership[0];
		var scalar = leaf.abi_type as NativeScalarAbiType;
		if (leaf.buffer_component != -1 || scalar == null || leaf.abi_type.get_type () != typeof (NativeScalarAbiType) || scalar.scalar_type != NativeScalarType.PTR || owner.field_path != leaf.storage_path || owner.buffer_cleanup != null || owner.cleanup_symbol != "" || owner.cleanup_class_ordinal < 0 || owner.cleanup_class_ordinal >= classes.length) {
			return null;
		}
		var object_class = classes[owner.cleanup_class_ordinal];
		if (object_class.name != owner.type_name || !object_class.allocation_policy_valid ()) {
			throw new LlvmError.INVALID_INPUT ("single-owner record result lost its exact native Class origin");
		}
		return new NativeObjectOriginPlan (object_class.ordinal, object_class.name, true);
	}

	internal static LlvmScopedOwnedInputs? from_native(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.TypeRef type, NativeFunction source, NativeAbiProgram program, LlvmStructRegistry structs, bool cold_factory = false, bool deferred_shapes = false) throws LlvmError {
		var classes = program.classes;
		var signature = source.signature;
		if (!cold_factory && source.kind == NativeCallableKind.CONSTRUCTOR && source.declaring_type_is_class && source.declaring_type_ordinal >= 0 && source.declaring_type_ordinal < classes.length && signature.receiver != null && signature.exception_plan == null && signature.result == null && signature.object_result == null && signature.struct_result == null && signature.buffer_result == null && signature.sum_result == null && signature.struct_parameters.length == 0 && signature.buffer_parameters.length == 0) {
			var owner = classes[source.declaring_type_ordinal];
			if (owner.parent_ordinal >= 0 && owner.parent_ordinal < classes.length && owner.fields.length == 0 && owner.lazy_caches.length == 0 && owner.allocation_policy == null && owner.concurrency_policy == null && owner.foreign_export == null && classes[owner.parent_ordinal].exception_root && LlvmScopedClassGraph.contains_scope (classes[owner.parent_ordinal], program)) {
				bool plain = true;
				foreach (var parameter in signature.parameters) {
					if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType) && parameter.abi_type.get_type () != typeof (NativeTextType) || parameter.object_origin != null || parameter.borrowed_class_ordinal >= 0 || parameter.resource != null || parameter.owns_resource) {
						plain = false;
					}
				}
				var target = artifact.class_constructor (owner.parent_ordinal);
				if (plain && (void*) target != null) {
					var empty = new LlvmScopedOwnedInputs (function, type);
					empty.empty_base_target = target;
					empty.empty_base_layout = structs.class_layout (owner.parent_ordinal, classes[owner.parent_ordinal].name);
					empty.empty_derived_layout = structs.class_layout (owner.ordinal, owner.name);
					empty.empty_destroy = artifact.class_destructor (owner.ordinal);
					empty.empty_parent_destroy = artifact.class_destructor (owner.parent_ordinal);
					empty.empty_class = owner.ordinal;
					empty.empty_parent = owner.parent_ordinal;
					foreach (var destroy in program.functions) {
						if (destroy.kind == NativeCallableKind.DESTRUCTOR && destroy.declaring_type_is_class && destroy.declaring_type_ordinal == owner.ordinal && (void*) empty.empty_destroy != null) {
							try {
								empty.empty_import = new LlvmScopedEmptyImport (source, destroy, classes[owner.parent_ordinal], empty.empty_destroy);
							} catch (RuntimeLifetimeError failure) {
								throw new LlvmError.INVALID_INPUT ("empty inherited lifecycle has invalid native effects: %s", failure.message);
							}
						}
					}
					return empty;
				}
			}
		}
		var record_result = single_record_result (signature.struct_result, classes);
		var fields = LlvmScopedFieldContract.from_native (artifact, function, source, classes, structs);
		if (signature.receiver != null && fields == null || signature.object_result != null || signature.sum_result != null || signature.struct_result != null && record_result == null && signature.struct_result.result_carrier != NativeStructResultCarrier.LEAF_AGGREGATE || signature.buffer_result != null || signature.buffer_parameters.length != 0 && (fields == null || !LlvmScopedPlainBuffers.groups (signature))) {
			return null;
		}
		var records = new HashTable<int, NativeObjectOriginPlan> (direct_hash, direct_equal);
		if (!LlvmScopedRecordInputs.bind (signature, classes, records)) {
			return null;
		}
		if (signature.result != null && (signature.result.abi_type.get_type () != typeof (NativeScalarAbiType) || (signature.result.scalar_type == NativeScalarType.PTR && signature.heap_result == null))) {
			return null;
		}
		var result = new LlvmScopedOwnedInputs (function, type);
		result.cold_shape = cold_factory;
		result.fields = fields;
		int offset = cold_factory ? 0 : (fields == null ? 0 : 1) + (signature.has_exception_success_slot ? 1 : 0);
		for (int p = 0; p < signature.parameters.length; p++) {
			var parameter = signature.parameters[p];
			if (LlvmScopedPlainBuffers.component (signature, p)) {
				continue;
			}
			var context = parameter.abi_type as NativeContextHandleType;
			if (context != null) {
				if (cold_factory || parameter.owns_resource || signature.struct_parameters.length != 0 && !artifact.has_scoped_context_inputs (function)) {
					return null;
				}
				if (!context.valid () || parameter.resource == null || parameter.resource.type_name != context.name || parameter.resource.cleanup_symbol != context.cleanup) {
					throw new LlvmError.INVALID_INPUT ("owned scoped input lost its exact borrowed allocator role");
				}
				continue;
			}
			if (parameter.borrowed_class_ordinal >= 0) {
				int borrowed = parameter.borrowed_class_ordinal;
				if (borrowed >= classes.length || !classes[borrowed].allocation_policy_valid ()) {
					throw new LlvmError.INVALID_INPUT ("borrowed Class companion lost its exact native origin");
				}
				var policy = classes[borrowed].allocation_policy;
				if (policy != null && policy.kind == AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") {
					if (!artifact.has_scoped_class_loans (function)) {
						return null;
					}
					continue;
				}
				if (LlvmScopedClassGraph.scope_free (classes[borrowed], classes)) {
					continue;
				}
				return null;
			}
			if (parameter.abi_type is NativeTextType && signature.parameters.length == 1 && fields != null && fields.constructor) {
				continue;
			}
			if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType)) {
				return null;
			}
			if (parameter.scalar_type != NativeScalarType.PTR) {
				continue;
			}
			var origin = records.lookup (p) ?? parameter.object_origin;
			if (origin == null || !origin.heap || origin.class_ordinal < 0 || origin.class_ordinal >= classes.length) {
				return null;
			}
			var owner = classes[origin.class_ordinal];
			var policy = owner.allocation_policy;
			if (owner.name != origin.class_name || !owner.allocation_policy_valid ()) {
				return null;
			}
			if ((policy == null || policy.kind != AllocationKind.CONTEXT || policy.context_mode != "scoped-affine") && LlvmScopedClassGraph.scope_free (owner, classes)) {
				continue;
			}
			// Whole-owner calls need a separate nested-field transport proof.
			LlvmScopedOwnerGraph? graph = null;
			if (!LlvmScopedClassGraph.value_scope_free (owner, classes)) {
				graph = LlvmScopedOwnerGraph.from_native (artifact, owner, classes, structs);
				if (graph == null) {
					return null;
				}
				if (fields == null) {
					if (result.owner_graph != null || signature.exception_plan != null || signature.struct_result != null || signature.struct_parameters.length != 0 || signature.heap_result != null && signature.heap_result.class_ordinal != owner.ordinal) {
						return null;
					}
					result.owner_graph = graph;
					result.graph_parameter = p + offset;
				}
			}
			result.shape (artifact, owner, structs, graph);
			result.positions.add (p + offset);
			result.values.add ((void*) CApi.get_param (function, p + offset));
		}
		if (fields != null && !fields.constructor) {
			for (int f = 0; f < fields.count; f++) {
				result.shape (artifact, classes[fields.owner (f)], structs, fields.graph (f));
				result.positions.add (-1);
				result.values.add (null);
			}
		}
		bool empty_output = result.values.length == 0 && fields == null && signature.receiver == null && signature.exception_plan == null && signature.heap_result != null && signature.heap_result.class_ordinal >= 0 && signature.heap_result.class_ordinal < classes.length && LlvmScopedClassGraph.contains_scope (classes[signature.heap_result.class_ordinal], program);
		if (result.values.length == 0 && !empty_output && fields == null && !(cold_factory && deferred_shapes && signature.struct_result != null)) {
			return null;
		}
		if (fields != null) {
			return cold_factory ? null : result;
		}
		if (cold_factory) {
			if (signature.result != null && signature.result.scalar_type != NativeScalarType.PTR) {
				result.plain_task_result = new LlvmTypeMapper (artifact.context).abi_type (signature.result.abi_type);
			}
			// The factory returns a task, with deferred success/error and retained
			// captures. This is input shape authority, never consuming authority.
			try {
				var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
				if (!summary.complete || summary.logical_coordinates || summary.has_exception || summary.store_count != 0 || summary.updated_inputs ().length != 0 || signature.receiver != null || result.owner_graph != null) {
					return null;
				}
				for (int p = 0; p < result.count; p++) {
					var roots = summary.equations.requirements (summary.result, "f2.f%u".printf (result.physical_position (p)));
					if (roots.length != 1 || roots[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || roots[0].ordinal != result.physical_position (p) || roots[0].path != "" || !roots[0].descendants || roots[0].exclusion_count != 0) {
						return null;
					}
				}
				// Result-bearing captures acquire their separate publication proof
				// before admission; the input shape alone cannot authorize that debt.
				if (!deferred_shapes && (summary.equations.requirements (summary.result, "f0").length != 0 || summary.equations.requirements (summary.result, "f1").length != 0)) {
					return null;
				}
				if (summary.equations.requirements (summary.result, "f1").length != 0 && !result.bind_error (source, summary, classes, structs, offset, true)) {
					return null;
				}
				if (result.deferred_error && summary.equations.requirements (summary.result, "f0").length != 0) {
					return null;
				}
				return result;
			} catch (RuntimeLifetimeError failure) {
				throw new LlvmError.INVALID_INPUT ("cold scoped capture lifetime contract: %s", failure.message);
			}
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			if (!summary.complete || !summary.matches_exception (signature.exception_plan != null) || summary.store_count != 0 || summary.updated_inputs ().length != 0) {
				return null;
			}
			if (summary.has_exception && summary.equations.requirements (summary.exception).length != 0 && !result.bind_error (source, summary, classes, structs, offset)) {
				return null;
			}
			var roots = summary.equations.requirements (summary.result);
			if (empty_output && roots.length == 0) {
				result.null_result = true;
				return result;
			}
			if (signature.struct_result != null && record_result == null) {
				if (summary.has_exception) {
					if (!signature.has_exception_success_slot || offset != 1) {
						return null;
					}
					result.success_output = CApi.get_param (function, 0);
				}
				return result.bind_record_result (artifact, signature, summary, records, classes, offset) ? result : null;
			}
			var forwarded = record_result ?? signature.heap_result;
			if (forwarded != null) {
				if (record_result == null && (signature.result == null || signature.result.scalar_type != NativeScalarType.PTR) || roots.length != 1 || roots[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || roots[0].path != "" || !roots[0].descendants || roots[0].exclusion_count != 0) {
					return null;
				}
				if (record_result != null) {
					var path = new StringBuilder ();
					foreach (var component in signature.struct_result.leaves[0].storage_path.split (".")) {
						int ordinal;
						if (!int.try_parse (component, out ordinal) || ordinal < 0) {
							return null;
						}
						if (path.len != 0) {
							path.append_c ('.');
						}
						path.append_printf ("f%d", ordinal);
					}
					var field = summary.equations.requirements (summary.result, path.str);
					if (field.length != 1 || field[0].identity () != roots[0].identity ()) {
						return null;
					}
				}
				for (int p = 0; p < result.positions.length; p++) {
					int position = result.positions[p];
					int logical = position - offset;
					var origin = records.lookup (logical) ?? signature.parameters[logical].object_origin;
					if (logical == roots[0].ordinal && origin != null && origin.class_ordinal == forwarded.class_ordinal && origin.class_name == forwarded.class_name) {
						result.returned_parameter = position;
						result.returned_slot = p;
					}
				}
				if (result.returned_slot < 0) {
					return null;
				}
				if (signature.exception_plan != null) {
					if (!signature.has_exception_success_slot || fields != null || offset != 1) {
						return null;
					}
					result.success_output = CApi.get_param (function, 0);
				}
			} else if (roots.length != 0) {
				return null;
			}
		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("owned scoped input lifetime contract: %s", failure.message);
		}
		if (result.owner_graph != null && (result.checked_success || result.error_count != 0 || result.aggregate_fields != 0 || result.count != 1)) {
			return null;
		}
		return result;
	}
	private bool bind_record_result(LlvmModuleArtifact artifact, NativeSignature signature, RuntimeLifetimeSummary summary, HashTable<int, NativeObjectOriginPlan> records, GenericArray<NativeClassPlan> classes, int offset) throws RuntimeLifetimeError, LlvmError {
		var record = signature.struct_result;
		if (record.mode != NativeStructValueMode.MOVE_VALUE || record.leaves.length < 2 || record.ownership.length == 0) {
			return false;
		}
		var types = new CApi.TypeRef[record.leaves.length];
		var mapper = new LlvmTypeMapper (artifact.context);
		var used = new HashTable<int, bool> (direct_hash, direct_equal);
		var seen = new HashTable<NativeRecordResource, bool> (direct_hash, direct_equal);
		for (int f = 0; f < record.leaves.length; f++) {
			var leaf = record.leaves[f];
			var scalar = leaf.abi_type as NativeScalarAbiType;
			if (leaf.buffer_component != -1 || scalar == null || leaf.abi_type.get_type () != typeof (NativeScalarAbiType)) {
				return false;
			}
			types[f] = mapper.scalar (scalar.scalar_type);
			var path = new StringBuilder ();
			foreach (var component in leaf.storage_path.split (".")) {
				int ordinal;
				if (!int.try_parse (component, out ordinal) || ordinal < 0) {
					return false;
				}
				if (path.len != 0) {
					path.append_c ('.');
				}
				path.append_printf ("f%d", ordinal);
			}
			var roots = summary.equations.requirements (summary.result, path.str);
			NativeRecordResource? owner = null;
			foreach (var candidate in record.ownership) {
				if (candidate.field_path == leaf.storage_path) {
					if (owner != null) {
						return false;
					}
					owner = candidate;
				}
			}
			if (owner == null) {
				if (scalar.scalar_type == NativeScalarType.PTR || roots.length != 0) {
					return false;
				}
				result_slots.add (-1);
				continue;
			}
			if (scalar.scalar_type != NativeScalarType.PTR || owner.buffer_cleanup != null || owner.cleanup_symbol != "" || owner.cleanup_class_ordinal < 0 || owner.cleanup_class_ordinal >= classes.length || seen.contains (owner) || roots.length != 1) {
				return false;
			}
			var object_class = classes[owner.cleanup_class_ordinal];
			if (owner.type_name != object_class.name || !object_class.allocation_policy_valid ()) {
				throw new LlvmError.INVALID_INPUT ("record result lost its exact native Class origin");
			}
			var root = roots[0];
			if (root.kind != RuntimeScopeOriginKind.OWNER_PARAMETER || root.path != "" || !root.descendants || root.exclusion_count != 0 || root.ordinal < 0 || root.ordinal >= signature.parameters.length) {
				return false;
			}
			var origin = records.lookup (root.ordinal) ?? signature.parameters[root.ordinal].object_origin;
			if (origin == null || !origin.heap || origin.class_ordinal != object_class.ordinal || origin.class_name != object_class.name) {
				return false;
			}
			int slot = -1;
			for (int p = 0; p < positions.length; p++) {
				if (positions[p] == root.ordinal + offset) {
					slot = p;
				}
			}
			if (slot < 0 || used.contains (slot)) {
				return false;
			}
			used.insert (slot, true);
			seen.insert (owner, true);
			result_slots.add (slot);
		}
		if (seen.size () != record.ownership.length || summary.equations.requirements (summary.result).length != seen.size ()) {
			return false;
		}
		aggregate_type = CApi.struct_type_in_context (artifact.context, types, types.length, 0);
		return true;
	}
	// Reconstruct the actual flat native tuple, with every member written once.
	// Intermediate aggregate values may only advance that publication chain.
	private bool is_publication(CApi.ValueRef instruction) {
		if (checked_success) {
			return CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.operand_count (instruction) == 2 && (void*) CApi.operand (instruction, 1) == (void*) success_output;
		}
		return CApi.opcode (instruction) == CApi.Opcode.RET && CApi.operand_count (instruction) == 1;
	}
	private GenericArray<void*> publications() {
		var result = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (is_publication (instruction)) {
					result.add ((void*) instruction);
				}
			}
		}
		return result;
	}
	private void publication_uses(CApi.ValueRef value, HashTable<void*, bool> seen) throws LlvmError {
		if (seen.contains ((void*) value)) {
			return;
		}
		seen.insert ((void*) value, true);
		for (var use = CApi.first_use (value); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) == null) {
				throw new LlvmError.VERIFICATION ("scoped record publication escaped its exact return chain");
			}
			if (is_publication (user)) {
				continue;
			}
			if (CApi.opcode (user) != CApi.Opcode.INSERT_VALUE || (void*) CApi.operand (user, 0) != (void*) value) {
				throw new LlvmError.VERIFICATION ("scoped record publication escaped its exact return chain");
			}
			publication_uses (user, seen);
		}
	}
	internal CApi.ValueRef publication(CApi.ValueRef end, int field) throws LlvmError {
		if (!is_publication (end) || (void*) CApi.type_of (CApi.operand (end, 0)) != (void*) aggregate_type) {
			throw new LlvmError.VERIFICATION ("scoped record return lost its exact aggregate type");
		}
		var value = CApi.operand (end, 0);
		CApi.ValueRef selected = (CApi.ValueRef) null;
		var seen = new HashTable<uint, bool> (direct_hash, direct_equal);
		for (uint f = 0; f < aggregate_fields; f++) {
			if ((void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.INSERT_VALUE || CApi.index_count (value) != 1 || CApi.operand_count (value) != 2) {
				throw new LlvmError.VERIFICATION ("scoped record return requires its complete actual member publication");
			}
			uint index = CApi.indices (value)[0];
			if (index >= aggregate_fields || seen.contains (index)) {
				throw new LlvmError.VERIFICATION ("scoped record return repeats or loses a physical member");
			}
			seen.insert (index, true);
			if (index == field) {
				selected = CApi.operand (value, 1);
			}
			publication_uses (value, new HashTable<void*, bool> (direct_hash, direct_equal));
			value = CApi.operand (value, 0);
		}
		if ((void*) value != (void*) CApi.const_null (aggregate_type)) {
			throw new LlvmError.VERIFICATION ("scoped record publication lost its empty aggregate base");
		}
		return selected;
	}
	internal bool publishes(CApi.ValueRef instruction, int slot) throws LlvmError {
		if (aggregate_fields == 0 || CApi.opcode (instruction) != CApi.Opcode.INSERT_VALUE || CApi.index_count (instruction) != 1) {
			return false;
		}
		uint field = CApi.indices (instruction)[0];
		if (field >= aggregate_fields || result_slots[field] != slot) {
			return false;
		}
		foreach (void* address in publications ()) {
			var end = (CApi.ValueRef) address;
			publication (end, (int) field);
			for (var value = CApi.operand (end, 0); (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.INSERT_VALUE; value = CApi.operand (value, 0)) {
				if ((void*) value == (void*) instruction) {
					return true;
				}
			}
		}
		return false;
	}
	internal int extracted_field(CApi.ValueRef value) {
		if (aggregate_fields == 0 || (void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.EXTRACT_VALUE || CApi.index_count (value) != 1) {
			return -1;
		}
		uint field = CApi.indices (value)[0];
		return field < aggregate_fields ? (int) field : -1;
	}
	internal void verify_record_call(CApi.ValueRef call) throws LlvmError {
		if (aggregate_fields == 0) {
			return;
		}
		verify ();
		if ((void*) CApi.called_value (call) != (void*) function || (void*) CApi.called_function_type (call) != (void*) type || CApi.argument_count (call) != parameter_count || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION || (checked_success ? CApi.type_kind (CApi.type_of (call)) != CApi.TypeKind.POINTER : (void*) CApi.type_of (call) != (void*) aggregate_type)) {
			throw new LlvmError.VERIFICATION ("scoped record call lost its exact physical ABI");
		}
		if (checked_success) {
			return;
		}
		for (var use = CApi.first_use (call); (void*) use != null; use = CApi.next_use (use)) {
			if (extracted_field (CApi.user (use)) < 0) {
				throw new LlvmError.VERIFICATION ("scoped record call requires exact member extraction without aggregate escape");
			}
		}
	}
	private bool bind_error(NativeFunction source, RuntimeLifetimeSummary summary, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs, int offset, bool deferred = false) throws RuntimeLifetimeError, LlvmError {
		var channel = deferred ? summary.result : summary.exception;
		string prefix = deferred ? "f1" : "";
		var signature = source.signature;
		var plan = signature.exception_plan;
		if (plan == null || plan.bound_ordinal < 0 || plan.bound_ordinal >= classes.length) {
			return false;
		}
		var owner = classes[plan.bound_ordinal];
		if (!owner.exception_root || !owner.polymorphic || owner.parent_ordinal != -1 || !owner.allocation_policy_valid () || owner.concurrency_policy != null || owner.lazy_caches.length != 0 || owner.foreign_export != null || summary.equations.requirements (channel, prefix, false).length != 0) {
			return false;
		}
		var seen = new HashTable<int, bool> (direct_hash, direct_equal);
		foreach (var field in owner.fields) {
			var scalar = field.storage_type as NativeScalarAbiType;
			if (scalar == null || field.text_snapshot || field.owns_buffer || field.owns_record || field.resource_owner != null) {
				return false;
			}
			var roots = summary.equations.requirements (channel, prefix == "" ? "f%d".printf (field.ordinal) : prefix + ".f%d".printf (field.ordinal));
			if (roots.length == 0) {
				continue;
			}
			if (scalar.scalar_type != NativeScalarType.PTR || field.owned_class_ordinal < 0 || field.owned_class_ordinal >= classes.length || roots.length != 1) {
				return false;
			}
			var root = roots[0];
			if (root.kind != RuntimeScopeOriginKind.OWNER_PARAMETER || root.ordinal < 0 || root.ordinal >= signature.parameters.length || root.path != "" || !root.descendants || root.exclusion_count != 0 || seen.contains (root.ordinal)) {
				return false;
			}
			var origin = signature.parameters[root.ordinal].object_origin;
			if (origin == null || !origin.heap || origin.class_ordinal != field.owned_class_ordinal || origin.class_name != classes[field.owned_class_ordinal].name) {
				return false;
			}
			int slot = -1;
			for (int p = 0; p < positions.length; p++) {
				if (positions[p] == root.ordinal + offset) {
					slot = p;
				}
			}
			if (slot < 0) {
				return false;
			}
			seen.insert (root.ordinal, true);
			error_members.add (field.ordinal + 2);
			error_slots.add (slot);
		}
		if (error_count == 0 || summary.equations.requirements (channel, prefix).length != error_count) {
			return false;
		}
		deferred_error = deferred;
		error_class = owner.ordinal;
		error_layout = structs.class_layout (owner.ordinal, owner.name);
		return true;
	}
	internal uint count { get { return values.length; } }
	internal CApi.ValueRef parameter(int index) {
		return (CApi.ValueRef) values[index];
	}
	internal uint physical_position(int index) {
		return (uint) positions[index];
	}
	internal CApi.ValueRef size(int index) {
		return (CApi.ValueRef) sizes[index];
	}
	internal CApi.ValueRef alignment(int index) {
		return (CApi.ValueRef) alignments[index];
	}
	internal CApi.ValueRef tag(int index) {
		return (CApi.ValueRef) tags[index];
	}
	internal int field_slot(int field) {
		return (int) count - (int) fields.count + field;
	}
	internal int input_slot(int logical) {
		for (int p = 0; p < positions.length; p++) {
			if (positions[p] == logical + 1) {
				return p;
			}
		}
		return -1;
	}
	private bool contains_instruction(CApi.ValueRef value) {
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if ((void*) instruction == (void*) value) {
					return true;
				}
			}
		}
		return false;
	}
	internal void verify_signature() throws LlvmError {
		verify_empty_base ();
		verify_empty_cleanup ();
		if (graph_forwarding && imported_body == null) {
			int returns = 0;
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				var end = CApi.block_terminator (block);
				if (CApi.opcode (end) != CApi.Opcode.RET) {
					continue;
				}
				returns++;
				if (CApi.operand_count (end) != 1 || (void*) CApi.operand (end, 0) != (void*) CApi.get_param (function, returned_parameter)) {
					throw new LlvmError.VERIFICATION ("scoped graph forwarding lost its original complete owner publication");
				}
			}
			if (returns == 0) {
				throw new LlvmError.VERIFICATION ("scoped graph forwarding requires an actual owner return");
			}
		}
		if (aggregate_fields != 0 && imported_body == null) {
			int returns = 0;
			foreach (void* address in publications ()) {
				publication ((CApi.ValueRef) address, 0);
				returns++;
			}
			if (returns == 0) {
				throw new LlvmError.VERIFICATION ("scoped record result requires an actual return publication");
			}
		}
		if (null_result && imported_body == null) {
			int returns = 0;
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				var end = CApi.block_terminator (block);
				if (CApi.opcode (end) != CApi.Opcode.RET) {
					continue;
				}
				returns++;
				if (CApi.operand_count (end) != 1 || (void*) CApi.is_constant_pointer_null (CApi.operand (end, 0)) == null) {
					throw new LlvmError.VERIFICATION ("null scoped result lost its literal-null return publication");
				}
			}
			if (returns == 0) {
				throw new LlvmError.VERIFICATION ("null scoped result requires an actual return publication");
			}
		}
		if ((void*) CApi.global_value_type (function) != (void*) type || CApi.count_params (function) != parameter_count || CApi.function_call_conv (function) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("owned scoped input lost its exact physical signature");
		}
		if (checked_success && ((void*) success_output != (void*) CApi.get_param (function, 0) || CApi.type_kind (CApi.type_of (success_output)) != CApi.TypeKind.POINTER)) {
			throw new LlvmError.VERIFICATION ("checked scoped success lost its exact output parameter");
		}
		if (fields != null && (void*) fields.receiver != (void*) CApi.get_param (function, 0)) {
			throw new LlvmError.VERIFICATION ("scoped field contract lost its original receiver");
		}
		for (int p = 0; p < positions.length; p++) {
			if (positions[p] < 0) {
				if (imported_body != null && fields != null && values[p] == null) {
					continue;
				}
				if (values[p] == null || !contains_instruction ((CApi.ValueRef) values[p]) || CApi.opcode ((CApi.ValueRef) values[p]) != CApi.Opcode.LOAD || !fields.address (CApi.operand ((CApi.ValueRef) values[p], 0), p - ((int) count - (int) fields.count))) {
					throw new LlvmError.VERIFICATION ("scoped field cleanup lost its exact original owner load");
				}
			} else if (values[p] != (void*) CApi.get_param (function, positions[p]) || CApi.type_kind (CApi.type_of ((CApi.ValueRef) values[p])) != CApi.TypeKind.POINTER) {
				throw new LlvmError.VERIFICATION ("owned scoped input lost its original parameter");
			}
		}
	}
	internal void verify_success_slot() throws LlvmError {
		if (!checked_success) {
			return;
		}
		verify_signature ();
		for (var use = CApi.first_use (success_output); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) == null || CApi.opcode (user) != CApi.Opcode.STORE || CApi.operand_count (user) != 2 || (void*) CApi.operand (user, 1) != (void*) success_output || (void*) CApi.operand (user, 0) == (void*) success_output || (aggregate_fields != 0 ? (void*) CApi.type_of (CApi.operand (user, 0)) != (void*) aggregate_type : CApi.type_kind (CApi.type_of (CApi.operand (user, 0))) != CApi.TypeKind.POINTER) || CApi.get_volatile (user) != 0 || CApi.get_ordering (user) != 0) {
				throw new LlvmError.VERIFICATION ("checked scoped success output escaped its exact publication slot");
			}
		}
	}
	internal void seal(HashTable<int, LlvmScopedDescriptorAuthority> descriptors) throws LlvmError {
		if (empty_base) {
			empty_backing = LlvmScopedFieldContract.empty_error (empty_derived_layout, new LlvmScopedExceptionShape (empty_derived_layout, descriptors.lookup (empty_class)), new LlvmScopedExceptionShape (empty_base_layout, descriptors.lookup (empty_parent)));
		}
		if (fields != null && fields.exception_class >= 0) {
			fields.exception_shape = new LlvmScopedExceptionShape (fields.layout, descriptors.lookup (fields.exception_class));
		}
		if (fields != null && fields.empty_exception) {
			empty_backing = LlvmScopedFieldContract.empty_error (fields.layout, fields.exception_shape, fields.exception_shape);
		}
		if (error_class >= 0) {
			error_shape = new LlvmScopedExceptionShape (error_layout, descriptors.lookup (error_class));
		}
		if (imported_body != null) {
			verify ();
			return;
		}
		if (body != null || CApi.count_basic_blocks (function) == 0) {
			throw new LlvmError.LOWERING ("owned scoped inputs require their unique emitted body");
		}
		if (fields != null && !fields.constructor) {
			for (int f = 0; f < fields.count; f++) {
				values[field_slot (f)] = (void*) fields.load (function, f);
			}
		}
		verify_signature ();
		body = new LlvmSumSequence (function, true);
	}
	internal void attach_import(LlvmNativeModuleBinding binding) throws LlvmError {
		if (cold_shape || body != null || imported_body != null || CApi.count_basic_blocks (function) != 0) {
			throw new LlvmError.LOWERING ("scoped native input requires its exact ordinary external declaration role");
		}
		binding.verify ();
		imported_body = binding;
		verify_signature ();
	}
	// Opaque factories carry declaration-verified capture shapes. Their producer
	// proves its coroutine body; the consumer proves the retained caller debt.
	internal void seal_imported_capture(LlvmNativeModuleBinding binding, HashTable<int, LlvmScopedDescriptorAuthority> descriptors) throws LlvmError {
		if (!cold_shape || fields != null || body != null || imported_body != null || CApi.count_basic_blocks (function) != 0) {
			throw new LlvmError.LOWERING ("imported scoped capture requires its exact opaque cold-factory role");
		}
		binding.verify ();
		if (error_class >= 0) {
			error_shape = new LlvmScopedExceptionShape (error_layout, descriptors.lookup (error_class));
		}
		verify_signature ();
		imported_body = binding;
	}
	internal bool literal_null_call(CApi.ValueRef call) throws LlvmError {
		if (!null_result) {
			return false;
		}
		verify ();
		if ((void*) CApi.called_value (call) != (void*) function || (void*) CApi.called_function_type (call) != (void*) type || CApi.argument_count (call) != parameter_count || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION || CApi.type_kind (CApi.type_of (call)) != CApi.TypeKind.POINTER) {
			throw new LlvmError.VERIFICATION ("null scoped result call lost its exact emitted body and ABI");
		}
		return true;
	}
	internal void verify() throws LlvmError {
		verify_signature ();
		if (imported_body != null) {
			if (body != null) {
				throw new LlvmError.VERIFICATION ("opaque scoped declaration gained a local body authority");
			}
			imported_body.verify ();
			return;
		}
		if (body == null) {
			throw new LlvmError.VERIFICATION ("owned scoped input body is not sealed");
		}
		body.verify ();
	}
	internal int stored_field(uint position) {
		if (fields != null && fields.publishes) {
			for (int f = 0; f < fields.count; f++) {
				if (fields.input (f) + 1 == position) {
					return f;
				}
			}
		}
		return -1;
	}
	internal bool field_call(CApi.ValueRef call) throws LlvmError {
		if (fields == null) {
			return false;
		}
		verify ();
		if ((void*) CApi.called_value (call) != (void*) function || (void*) CApi.called_function_type (call) != (void*) type || CApi.argument_count (call) != parameter_count || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("scoped field call lost its exact physical signature");
		}
		return true;
	}
	internal bool empty_error_call(CApi.ValueRef call, bool proven_null = false) throws LlvmError {
		// A caller may substitute its independently reconstructed null tuple
		// dependency for a literal null; the actual native ABI stays mandatory.
		if (error_count == 0 || CApi.argument_count (call) != parameter_count) {
			return false;
		}
		if (!proven_null) {
			for (int f = 0; f < error_count; f++) {
				if ((void*) CApi.is_constant_pointer_null (CApi.operand (call, physical_position (error_slot (f)))) == null) {
					return false;
				}
			}
		}
		verify ();
		if ((void*) CApi.called_value (call) != (void*) function || (void*) CApi.called_function_type (call) != (void*) type || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("empty scoped exception call lost its exact physical ABI");
		}
		return true;
	}
	internal bool input_shape(uint position, CApi.ValueRef allocation_tag, CApi.ValueRef count, CApi.ValueRef size, CApi.ValueRef alignment) throws LlvmError {
		verify ();
		for (int p = 0; p < positions.length; p++) {
			if (positions[p] != position) {
				continue;
			}
			if (tags[p] != (void*) allocation_tag || (void*) CApi.is_constant_int (count) == null || CApi.const_int_zext (count) != 1 || sizes[p] != (void*) size || alignments[p] != (void*) alignment) {
				throw new LlvmError.VERIFICATION ("scoped capture lost its exact physical input allocation shape");
			}
			return true;
		}
		return false;
	}
	internal bool accepts(CApi.ValueRef call, uint position, CApi.ValueRef allocation_tag, CApi.ValueRef count, CApi.ValueRef size, CApi.ValueRef alignment, bool checked_transport = false) throws LlvmError {
		if (fields != null && !fields.publishes) {
			return false;
		}
		for (int p = 0; p < positions.length; p++) {
			if (positions[p] != position) {
				continue;
			}
			if ((checked_success || error_count != 0) && !checked_transport) {
				throw new LlvmError.VERIFICATION ("checked scoped call requires its exact caller result transport");
			}
			verify ();
			if ((void*) CApi.called_value (call) != (void*) function || (void*) CApi.called_function_type (call) != (void*) type || CApi.argument_count (call) != parameter_count || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION || tags[p] != (void*) allocation_tag || (void*) CApi.is_constant_int (count) == null || CApi.const_int_zext (count) != 1 || sizes[p] != (void*) size || alignments[p] != (void*) alignment) {
				throw new LlvmError.VERIFICATION ("owned scoped call lost its exact type, extent, alignment, tag or transfer channel");
			}
			return true;
		}
		return false;
	}
}
}
