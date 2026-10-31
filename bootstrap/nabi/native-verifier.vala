// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
// Structural verification has no upstream stage or semantic dependencies.
public class NativeAbiVerifier : Object {
	private static bool callback_scalar(NativeScalarType type) {
		return type == NativeScalarType.I32 || type == NativeScalarType.U32 || type == NativeScalarType.I64 || type == NativeScalarType.U64 || type == NativeScalarType.F32 || type == NativeScalarType.F64 || type == NativeScalarType.B1;
	}
	private static bool send_leaf(NativeAbiType? type, NativeAbiProgram program, HashTable<int, bool> seen, bool mailbox_graph = false, bool affinity_only = false) {
		var bytes = type as NativeContextSliceType;
		if (bytes != null) {
			return bytes.valid () && bytes.allocator.mode == "owned-concurrent";
		}
		var context = type as NativeContextHandleType;
		if (context != null) {
			return context.valid () && context.mode == "owned-concurrent";
		}
		var shared = type as NativeSharedHandleType;
		if (shared != null) {
			foreach (var owner in program.classes) {
				if (owner.name == shared.payload) {
					return (affinity_only || owner.concurrency_policy != null && owner.concurrency_policy.monitor) && send_class (owner.ordinal, program, seen, mailbox_graph, affinity_only);
				}
			}
			return false;
		}
		if (affinity_only && type is NativeClosureHandleType) {
			foreach (var owner in program.classes) {
				if (owner.name == ((NativeClosureHandleType) type).environment) {
					return send_class (owner.ordinal, program, seen, mailbox_graph, true);
				}
			}
			return false;
		}
		if (type is NativeClosureHandleType && ((NativeClosureHandleType) type).actor) {
			var actor = (NativeClosureHandleType) type;
			if (mailbox_graph || actor.threaded || actor.checked_error != null) {
				return false;
			}
			bool receiver = false;
			bool message = actor.actor_message == null;
			foreach (var owner in program.classes) {
				if (owner.name == actor.environment) {
					receiver = owner.concurrency_policy != null && owner.concurrency_policy.identity == 16 && !owner.polymorphic && !owner.is_interface && send_class (owner.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal), true);
				}
				if (owner.name == actor.actor_message) {
					message = !owner.polymorphic && !owner.is_interface && owner.generic_instance == null && send_class (owner.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal), true);
				}
			}
			return receiver && message;
		}
		if (type is NativeClosureHandleType || type is NativeFunctionPointerType) {
			return false;
		}
		var scalar = type as NativeScalarAbiType;
		return scalar != null && (affinity_only || scalar.scalar_type != NativeScalarType.PTR) || type is NativeVectorType || type is NativeTextType;
	}
	private static bool send_record(NativeStructValuePlan record, NativeAbiProgram program, HashTable<int, bool> seen, bool mailbox_graph = false, bool affinity_only = false) {
		foreach (var leaf in record.leaves) {
			bool covered = false;
			foreach (var owner in record.ownership) {
				if (owner.field_path != leaf.storage_path) {
					continue;
				}
				if (owner.buffer_cleanup != null) {
					if (owner.buffer_cleanup.context_origin != null && !send_leaf (owner.buffer_cleanup.context_origin, program, seen, mailbox_graph, affinity_only)) {
						return false;
					}
					covered = true;
				} else if (owner.cleanup_class_ordinal >= 0 && send_class (owner.cleanup_class_ordinal, program, seen, mailbox_graph, affinity_only)) {
					covered = true;
				} else if (!affinity_only) {
					return false;
				}
			}
			if (!covered && !send_leaf (leaf.abi_type, program, seen, mailbox_graph, affinity_only)) {
				return false;
			}
		}
		return true;
	}
	private static bool send_class(int ordinal, NativeAbiProgram program, HashTable<int, bool> seen, bool mailbox_graph = false, bool affinity_only = false) {
		if (ordinal < 0 || ordinal >= program.classes.length) {
			return false;
		}
		var owner = program.classes[ordinal];
		var policy = owner.concurrency_policy;
		if (!owner.concurrency_policy_valid () || !owner.matches_slot_declarations () || policy != null && (policy.thread_bound || !affinity_only && policy.shared && !policy.monitor)) {
			return false;
		}
		if (owner.allocation_policy != null) {
			var allocation = owner.allocation_policy;
			if (!allocation.valid () || (allocation.kind == Astra.Source.AllocationKind.CONTEXT ? allocation.context_mode != "owned-concurrent" : !affinity_only)) {
				return false;
			}
		}
		if (seen.contains (ordinal)) {
			return true;
		}
		seen.insert (ordinal, true);
		if (owner.polymorphic) {
			foreach (var derived in program.classes) {
				if (derived.ordinal == ordinal) {
					continue;
				}
				int steps = 0;
				for (int parent = derived.parent_ordinal; parent >= 0; parent = program.classes[parent].parent_ordinal) {
					if (parent >= program.classes.length || steps++ >= program.classes.length) {
						return false;
					}
					if (parent == ordinal) {
						if (!send_class (derived.ordinal, program, seen, mailbox_graph, affinity_only)) {
							return false;
						}
						break;
					}
				}
			}
		}
		if (owner.parent_ordinal >= 0 && !send_class (owner.parent_ordinal, program, seen, mailbox_graph, affinity_only)) {
			return false;
		}
		foreach (var field in owner.fields) {
			if (field.owned_class_ordinal >= 0) {
				if (!send_class (field.owned_class_ordinal, program, seen, mailbox_graph, affinity_only)) {
					return false;
				}
				continue;
			}
			if (field.record_ordinal >= 0) {
				bool valid = false;
				foreach (var record in program.struct_values) {
					if (record.struct_ordinal == field.record_ordinal && send_record (record, program, seen, mailbox_graph, affinity_only)) {
						valid = true;
					}
				}
				if (!valid) {
					return false;
				}
				continue;
			}
			var slots = field.storage_type as NativeOwnerSlotsType;
			if (slots != null) {
				if (slots.record_value != null ? !send_record (slots.record_value, program, seen, mailbox_graph, affinity_only) : !send_class (slots.element_ordinal, program, seen, mailbox_graph, affinity_only)) {
					return false;
				}
				continue;
			}
			if (field.storage_type is NativeSliceType && field.owns_buffer) {
				if (field.storage_type is NativeContextSliceType && !send_leaf (field.storage_type, program, seen, mailbox_graph, affinity_only)) {
					return false;
				}
				continue;
			}
			if (!send_leaf (field.storage_type, program, seen, mailbox_graph, affinity_only)) {
				return false;
			}
		}
		return true;
	}
	private static void fail(string path, string message) throws NativeAbiError {
		throw new NativeAbiError.INVALID_ABI ("internal native ABI verification error at %s: %s", path, message);
	}
	private static void verify_record_cleanup(NativeRecordResource field, NativeAbiProgram program) throws NativeAbiError {
		if (field.type_name == "" || field.depth == 0) {
			fail ("record cleanup", "requires a nonempty exact nominal leaf path and type");
		}
		if (field.buffer_cleanup != null) {
			if (field.cleanup_class_ordinal != -1 || field.cleanup_symbol != "" || (field.buffer_cleanup.record_element != null && !program.record_elements.find (field.buffer_cleanup.record_element))) {
				fail ("record cleanup", "buffer field requires complete pair ownership and static element layout");
			}
			verify_buffer_plan (field.buffer_cleanup, program.abi_version, "record buffer cleanup");
			return;
		}
		if (field.cleanup_class_ordinal == -1) {
			if (field.cleanup_symbol == "") {
				fail ("record cleanup", "Resource field requires its foreign cleanup identity");
			}
			return;
		}
		int ordinal = field.cleanup_class_ordinal;
		if (ordinal < 0 || ordinal >= program.classes.length || program.classes[ordinal].name != field.type_name || program.classes[ordinal].polymorphic || field.cleanup_symbol != "") {
			fail ("record cleanup", "Class field requires its exact nonpolymorphic native heap authority");
		}
	}

	private static void verify_scalar(NativeScalarType scalar_type, NativeAbiVersion profile, string path) throws NativeAbiError {
		if (profile == NativeAbiVersion.OWNER_SLOTS_V15) {
			profile = NativeAbiVersion.NATIVE_EXCEPTIONS_V14;
		}
		if (scalar_type == NativeScalarType.F64) {
			if (profile != NativeAbiVersion.FP64_V6 && profile != NativeAbiVersion.AGGREGATE_V7 && profile != NativeAbiVersion.BUFFER_V8 && profile != NativeAbiVersion.TEXT_V9 && profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14) {
				fail (path, "F64 channel requires fp64-v6");
			}
			return;
		}
		if (scalar_type == NativeScalarType.F32) {
			if (profile != NativeAbiVersion.SCALAR_FP_V3 && profile != NativeAbiVersion.VECTOR_V4 && profile != NativeAbiVersion.SLICE_V5 && profile != NativeAbiVersion.FP64_V6 && profile != NativeAbiVersion.AGGREGATE_V7 && profile != NativeAbiVersion.BUFFER_V8 && profile != NativeAbiVersion.TEXT_V9 && profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14) {
				fail (path, "F32 channel requires scalar-fp-v3");
			}
			return;
		}
		bool exact_integer = scalar_type == NativeScalarType.I8 || scalar_type == NativeScalarType.U8 || scalar_type == NativeScalarType.I16 || scalar_type == NativeScalarType.U16 || scalar_type == NativeScalarType.U32 || scalar_type == NativeScalarType.I64 || scalar_type == NativeScalarType.U64;
		if (exact_integer) {
			if (profile != NativeAbiVersion.SCALAR_INT_V2 && profile != NativeAbiVersion.SCALAR_FP_V3 && profile != NativeAbiVersion.VECTOR_V4 && profile != NativeAbiVersion.SLICE_V5 && profile != NativeAbiVersion.FP64_V6 && profile != NativeAbiVersion.AGGREGATE_V7 && profile != NativeAbiVersion.BUFFER_V8 && profile != NativeAbiVersion.TEXT_V9 && profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14) {
				fail (path, "exact-width integer channel requires scalar-int-v2");
			}
			return;
		}
		if (scalar_type != NativeScalarType.I32 && scalar_type != NativeScalarType.B1 && scalar_type != NativeScalarType.PTR) {
			fail (path, "unsupported native scalar type");
		}
		if (scalar_type == NativeScalarType.PTR && profile == NativeAbiVersion.SCALAR_V0) {
			fail (path, "PTR requires scalar-ptr-v1");
		}
	}

	internal static void verify_type(NativeAbiType type, NativeAbiVersion profile, string path) throws NativeAbiError {
		if (type is NativeContextSliceType) {
			if (!((NativeContextSliceType) type).valid ()) {
				fail (path, "context byte pair requires exact versioned allocator and origin release authority");
			}
			verify_type (new NativeSliceType (), profile, path);
			return;
		}
		if (type is NativeContextHandleType) {
			if (!((NativeContextHandleType) type).valid ()) {
				fail (path, "allocator context requires exact versioned nominal lifetime/thread/release authority");
			}
			verify_scalar (NativeScalarType.PTR, profile, path);
			return;
		}
		if (type is NativeClosureHandleType) {
			var closure = (NativeClosureHandleType) type;
			if (closure.environment == "" || closure.scalar_type != NativeScalarType.PTR || closure.actor && (closure.threaded || closure.checked_error != null || closure.signature.result_scalar () != NativeScalarType.I32 || closure.signature.parameter_types.length != 1 || closure.signature.parameter_types[0].get_type () != typeof (NativeScalarAbiType) || (closure.actor_message == null ? ((NativeScalarAbiType) closure.signature.parameter_types[0]).scalar_type == NativeScalarType.PTR : ((NativeScalarAbiType) closure.signature.parameter_types[0]).scalar_type != NativeScalarType.PTR))) {
				fail (path, "closure handle requires exact environment identity and linear carrier PTR");
			}
			if (closure.actor) {
				verify_scalar (NativeScalarType.PTR, profile, path);
				verify_scalar (((NativeScalarAbiType) closure.signature.parameter_types[0]).scalar_type, profile, path + "/message");
			} else {
				verify_type (closure.signature, profile, path + "/code");
			} return;
		}
		if (type is NativeSharedHandleType) {
			if (((NativeSharedHandleType) type).payload == "" || ((NativeSharedHandleType) type).scalar_type != NativeScalarType.PTR) {
				fail (path, "shared handle requires exact payload identity and control-block PTR");
			}
			verify_scalar (NativeScalarType.PTR, profile, path);
			return;
		}
		if (type is NativeFunctionPointerType) {
			var signature = (NativeFunctionPointerType) type;
			if (type is NativeCallbackType) {
				var callback = (NativeCallbackType) type;
				if (!callback.call_scoped || callback.carrier_fields != 2 || callback.record_parameters.length != 0 || callback.borrowed_parameters.length != 0 || callback.owned_parameters.length != 0 || callback.owned_result != null || callback.record_result != null || callback.parameter_types.length > 256) {
					fail (path, "Callback requires an exact call-only code/context view and copied scalar signature");
				}
				foreach (var parameter in callback.parameter_types) {
					if (parameter.get_type () != typeof (NativeScalarAbiType) || !callback_scalar (((NativeScalarAbiType) parameter).scalar_type)) {
						fail (path, "Callback argument requires an exact supported copied scalar");
					}
				}
				if (!callback.void_result && (callback.result_scalar () == null || !callback_scalar (callback.result_scalar ()))) {
					fail (path, "Callback result requires a copied scalar or explicit void");
				}
			}
			if (!signature.record_parameter_modes_valid ()) {
				fail (path, "record signature requires its exact complete copied declaration and original move/borrow channel");
			}
			if (!signature.record_parameter_leaves_valid ()) {
				fail (path, "record signature leaf differs from its declared storage");
			}
			if (!signature.record_result_valid () || (signature.void_result ? signature.result_scalar () != null || signature.record_result != null || signature.owned_result != null : (signature.result_scalar () == null) != (signature.record_result != null))) {
				fail (path, "native code result requires exactly one original scalar, record or void declaration");
			}
			if (!signature.owned_channels_valid ()) {
				fail (path, "native code pointer lost its original owned channel declarations");
			}
			if (signature.scalar_type != NativeScalarType.PTR || (signature.result_scalar () == NativeScalarType.PTR ? signature.owned_result == null || signature.owned_result.ordinal != -1 || signature.owned_result.type_name == "" : signature.owned_result != null) || signature.parameter_types.length > 4096) {
				fail (path, "native code pointer requires bounded copied scalar signature");
			}
			int physical = 0;
			int logical = 0;
			int group = 0;
			while (physical < signature.parameter_types.length) {
				var record = group < signature.record_parameters.length ? signature.record_parameters[group] : null;
				if (record != null && record.first_leaf == physical) {
					if (record.source_ordinal != logical || record.record_name == "" || (record.mode != NativeStructValueMode.COPY_VALUE && record.mode != NativeStructValueMode.MOVE_VALUE && record.mode != NativeStructValueMode.BORROW_VALUE) || record.leaves.length == 0 || physical + record.leaves.length > signature.parameter_types.length) {
						fail (path, "code pointer record requires exact nominal ordered complete group");
					}
					foreach (var leaf in record.leaves) {
						if (leaf.field_path == "" || !leaf.abi_type.same_type (signature.parameter_types[physical++])) {
							fail (path, "code pointer record leaf differs from physical signature");
						}
					}
					group++;
				} else {
					physical++;
				}
				logical++;
			}
			if (logical > ((type is NativeCallbackType) ? 256 : 4) || group != signature.record_parameters.length) {
				fail (path, "code pointer requires bounded ordered logical parameters");
			}
			if (signature.result_scalar () != null) {
				verify_scalar (signature.result_scalar (), profile, path);
			}
			if (signature.record_result != null) {
				var result = signature.record_result;
				if (signature.owned_result != null || result.record_name == "" || result.leaves.length == 0 || result.leaves.length > 4096 || (result.mode != NativeStructValueMode.COPY_VALUE && result.mode != NativeStructValueMode.MOVE_VALUE)) {
					fail (path, "record code result requires its exact complete value mode");
				}
				foreach (var leaf in result.leaves) {
					if (leaf.field_path == "") {
						fail (path, "record code result lost its ordered field path");
					}
					verify_type (leaf.abi_type, profile, path + "/result-leaf");
				}
			}
			int borrow_index = 0;
			int owned_index = 0;
			for (int p = 0; p < signature.parameter_types.length; p++) {
				var parameter = signature.parameter_types[p];
				var borrow = borrow_index < signature.borrowed_parameters.length ? signature.borrowed_parameters[borrow_index] : null;
				bool borrowed = borrow != null && borrow.ordinal == p;
				var owned = owned_index < signature.owned_parameters.length ? signature.owned_parameters[owned_index] : null;
				bool transferred = owned != null && owned.ordinal == p;
				bool copied_leaf = false;
				foreach (var record in signature.record_parameters) {
					if (p >= record.first_leaf && p < record.first_leaf + record.leaves.length) {
						copied_leaf = true;
					}
				}
				if (copied_leaf) {
					if (borrowed || transferred || !(parameter.get_type () == typeof (NativeScalarAbiType) || parameter is NativeVectorType || parameter is NativeFunctionPointerType)) {
						fail (path, "copied record leaf requires its exact copyable ABI type without borrow or transfer authority");
					}
				} else {
					var scalar_parameter = parameter as NativeScalarAbiType;
					if (parameter.get_type () != typeof (NativeScalarAbiType) || (scalar_parameter.scalar_type == NativeScalarType.PTR) != (borrowed || transferred) || borrowed && borrow.type_name == "" || transferred && owned.type_name == "" || borrowed && transferred) {
						fail (path, "native code pointer requires exact copied or nominal borrowed channels");
					}
				}
				if (borrowed) {
					borrow_index++;
				}
				if (transferred) {
					owned_index++;
				}
				verify_type (parameter, profile, path + "/parameter%d".printf (p));
			}
			if (borrow_index != signature.borrowed_parameters.length || owned_index != signature.owned_parameters.length) {
				fail (path, "native code pointer borrow channels lost unique physical order");
			}
			return;
		}
		if (profile == NativeAbiVersion.OWNER_SLOTS_V15) {
			profile = NativeAbiVersion.NATIVE_EXCEPTIONS_V14;
		}
		if (type is NativeSumType) {
			if (profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || ((NativeSumType) type).identity.name == "" || ((NativeSumType) type).channel != NativeScalarType.PTR || (((NativeSumType) type).role != NativeSumRole.SNAPSHOT_READONLY && ((NativeSumType) type).role != NativeSumRole.RESULT_CALLER_STORAGE && ((NativeSumType) type).role != NativeSumRole.OWNED_TRANSFER && ((NativeSumType) type).role != NativeSumRole.OWNED_RESULT_STORAGE)) {
				fail (path, "sum-values-v12 requires exact nominal snapshot storage");
			}
			if (profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && (((NativeSumType) type).role == NativeSumRole.OWNED_TRANSFER || ((NativeSumType) type).role == NativeSumRole.OWNED_RESULT_STORAGE)) {
				fail (path, "owning sum transport requires owned-sums-v13");
			}
			return;
		}
		if (type is NativeTextType) {
			var text = (NativeTextType) type;
			if (profile != NativeAbiVersion.TEXT_V9 && profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || text.base_type != NativeScalarType.PTR || text.length_type != NativeScalarType.I32 || (text.contract != NativeTextContract.BORROWED_NOESCAPE && text.contract != NativeTextContract.STATIC_TEXT && !(profile == NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && text.contract == NativeTextContract.RECEIVER_TEXT))) {
				fail (path, "text-v9 requires exact ordered PTR/I32 text group and bounded contract");
			}
			return;
		}
		if (type is NativeTextSliceType) {
			var text_slice = (NativeTextSliceType) type;
			if (profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || !text_slice.valid ()) {
				fail (path, "text-slice-v10 requires exact descriptor roles, natural layout, read access and deep borrow");
			}
		}
		if (type is NativeRecordSliceType) {
			var record = (NativeRecordSliceType) type;
			if (profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || record.element == null || record.access != NativeSliceAccess.READ_WRITE || !record.borrowed_noescape) {
				fail (path, "record slice requires struct-elements-v11 with exact mutable borrowed storage shape");
			}
		}
		var slice = type as NativeSliceType;
		if (slice != null) {
			if ((profile != NativeAbiVersion.SLICE_V5 && profile != NativeAbiVersion.FP64_V6 && profile != NativeAbiVersion.AGGREGATE_V7 && profile != NativeAbiVersion.BUFFER_V8 && profile != NativeAbiVersion.TEXT_V9 && profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14) || slice.base_type != NativeScalarType.PTR || slice.length_type != NativeScalarType.I32) {
				fail (path, "slice parameter group requires slice-v5 and ordered base PTR, length I32");
			}
			return;
		}
		if (type is NativeScalarAbiType) {
			verify_scalar (((NativeScalarAbiType) type).scalar_type, profile, path);
			return;
		}
		var vector = type as NativeVectorType;
		if (vector == null || (profile != NativeAbiVersion.VECTOR_V4 && profile != NativeAbiVersion.SLICE_V5 && profile != NativeAbiVersion.FP64_V6 && profile != NativeAbiVersion.AGGREGATE_V7 && profile != NativeAbiVersion.BUFFER_V8 && profile != NativeAbiVersion.TEXT_V9 && profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14)) {
			fail (path, "vector channel requires vector-v4");
			return;
		}
		if (vector.lanes != 2 && vector.lanes != 4 && vector.lanes != 8 && vector.lanes != 16) {
			fail (path, "unsupported vector lane count");
		}
		if (vector.element == NativeScalarType.B1) {
			return;
		}
		int bits;
		switch (vector.element) {
		case NativeScalarType.I8: case NativeScalarType.U8: bits = 8;
			break;
		case NativeScalarType.I16:
		case NativeScalarType.U16:
			bits = 16;
			break;
		case NativeScalarType.I32:
		case NativeScalarType.U32:
		case NativeScalarType.F32:
			bits = 32;
			break;
		case NativeScalarType.F64:
			verify_scalar (vector.element, profile, path);
			bits = 64;
			break;
		case NativeScalarType.I64:
		case NativeScalarType.U64:
			bits = 64;
			break;
		default:
			fail (path, "unsupported vector element channel; PTR vectors are forbidden");
			return;
		}
		if (bits * vector.lanes > 128) {
			fail (path, "unsupported VEC-1 numeric vector payload");
		}
	}

	private static void verify_readonly_channels(NativeFunction function) throws NativeAbiError {
		if (function.scoped_readonly) {
			var declared = function.signature;
			if (function.kind == NativeCallableKind.CONSTRUCTOR || function.kind == NativeCallableKind.DESTRUCTOR ||
			    function.async_callable != null || declared.exception_plan != null || declared.object_result != null ||
			    declared.heap_result != null || declared.resource_result != null || declared.buffer_result != null || declared.buffer_parameters.length != 0 ||
			    declared.struct_result != null && declared.struct_result_mode == NativeStructValueMode.MOVE_VALUE) {
				fail ("readonly native effect", "cannot acquire, suspend, throw or transfer an owning result");
			}
			foreach (var parameter in declared.parameters) {
				if (parameter.owns_resource || parameter.object_origin != null) {
					fail ("readonly native effect", "cannot consume a capture");
				}
			}
			foreach (var group in declared.struct_parameters) {
				if (group.mode == NativeStructValueMode.MOVE_VALUE) {
					fail ("readonly native effect", "cannot consume an owning record");
				}
			}
		}
	}

	private static void verify_signature_channels(NativeSignature signature, string path) throws NativeAbiError {
		if (!signature.matches_resource_parameters ()) {
			fail (path, "owned or borrowed Resource cleanup/transfer differs from its original signature");
		}
		if (signature.resource_result != null) {
			var resource = signature.resource_result;
			if (resource.class_ordinal != -1 || resource.type_name == "" || resource.cleanup_symbol == "" || signature.result == null || !(signature.result.abi_type is NativeScalarAbiType) || signature.result.scalar_type != NativeScalarType.PTR || signature.heap_result != null || signature.object_result != null || signature.struct_result != null || signature.sum_result != null || signature.buffer_result != null) {
				fail (path, "Resource result requires an exact nominal owned PTR and declared destructor");
			}
		}
		if (signature.heap_result != null && (!signature.heap_result.heap || signature.object_result != null || signature.result == null || !(signature.result.abi_type is NativeScalarAbiType) || signature.result.scalar_type != NativeScalarType.PTR)) {
			fail (path, "heap result requires one owned heap PTR without lexical candidate storage");
		}
		if (signature.generic_owner_result_origin != null) {
			var origin = signature.heap_result ?? (signature.object_result == null ? null : signature.object_result.object_origin);
			if (!signature.generic_owner_result_origin.valid () || !signature.generic_owner_result_origin.general_bodies || signature.generic_owner_result_class < 0 || origin == null || origin.heap != signature.generic_owner_result_heap || origin.class_ordinal != signature.generic_owner_result_class) {
				fail (path, "generic Class result lost its original owned storage channel");
			}
		} else if (signature.generic_owner_result_class != -1) {
			fail (path, "generic Class result lost its original declaration");
		}
		if (signature.exception_plan != null) {
			var plan = signature.exception_plan;
			if (signature.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || plan.bound_ordinal < 0 || plan.root_ordinal < 0 || plan.bound_name == "" || plan.root_name == "" || signature.object_result != null) {
				fail (path, "private exception plan requires exact native class bound, root and supported success grouping");
			}
		}
		if (signature.sum_result != null) {
			verify_type (signature.sum_result, signature.abi_version, path + "/sum-result");
			if ((signature.sum_result.role != NativeSumRole.RESULT_CALLER_STORAGE && signature.sum_result.role != NativeSumRole.OWNED_RESULT_STORAGE) || signature.result != null || signature.struct_result != null || signature.buffer_result != null || signature.object_result != null) {
				fail (path, "sum result requires one hidden caller storage channel and no direct result");
			}
		}
		for (int p = 0; p < signature.parameters.length; p++) {
			var parameter = signature.parameters[p];
			string parameter_path = path + "/parameter #%d".printf (p);
			if (parameter.scalar_pointee != null) {
				var scalar = parameter.scalar_pointee.scalar_type;
				if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR || parameter.object_origin != null || parameter.borrowed_class_ordinal != -1 || parameter.resource != null || parameter.generic_owner_origin != null || parameter.generic_borrow_origin != null || !(scalar == NativeScalarType.I32 || scalar == NativeScalarType.U32 || scalar == NativeScalarType.I64 || scalar == NativeScalarType.U64 || scalar == NativeScalarType.F32 || scalar == NativeScalarType.F64 || scalar == NativeScalarType.B1)) {
					fail (parameter_path, "scalar reference requires its exclusive typed noescape PTR channel");
				}
			}
			if (parameter.generic_owner_origin != null) {
				var origin = parameter.object_origin;
				if (!parameter.generic_owner_origin.valid () || !parameter.generic_owner_origin.general_bodies || parameter.generic_owner_class < 0 || origin == null || origin.heap != parameter.generic_owner_heap || origin.class_ordinal != parameter.generic_owner_class || parameter.borrowed_class_ordinal != -1 || parameter.generic_borrow_origin != null || parameter.resource != null || parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR) {
					fail (parameter_path, "generic Class parameter lost its original owned storage channel");
				}
			} else if (parameter.generic_owner_class != -1) {
				fail (parameter_path, "generic Class parameter lost its original declaration");
			}
			if (parameter.resource != null) {
				var resource = parameter.resource;
				if (resource.class_ordinal != -1 || resource.type_name == "" || resource.cleanup_symbol == "" || !(parameter.abi_type is NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR || parameter.object_origin != null || parameter.borrowed_class_ordinal != -1 || parameter.generic_borrow_origin != null) {
					fail (parameter_path, "Resource parameter requires an exact nominal PTR ownership contract");
				}
			} else if (parameter.owns_resource) {
				fail (parameter_path, "Resource ownership requires its nominal destructor declaration");
			}
			if (parameter.com_unknown_borrow != null && (!parameter.com_unknown_borrow.valid () || parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR || parameter.resource != null || parameter.object_origin != null || parameter.scalar_pointee != null || parameter.borrowed_class_ordinal != -1)) {
				fail (parameter_path, "IUnknown acquisition lost exact raw pointer, noescape or queried interface provenance");
			}
			if (parameter.ordinal != p) {
				fail (parameter_path, "parameter ordinals must be unique and in source order");
			}
			if (parameter.abi_type is NativeTextType && ((NativeTextType) parameter.abi_type).contract != NativeTextContract.BORROWED_NOESCAPE) {
				fail (parameter_path, "text parameter requires borrowed-noescape");
			}
			if (parameter.abi_type is NativeSumType && ((NativeSumType) parameter.abi_type).role != NativeSumRole.SNAPSHOT_READONLY && ((NativeSumType) parameter.abi_type).role != NativeSumRole.OWNED_TRANSFER) {
				fail (parameter_path, "sum input requires readonly snapshot role");
			}
			verify_type (parameter.abi_type, signature.abi_version, parameter_path);
		}
		if (signature.result != null) {
			if (signature.result.abi_type is NativeCallbackType) {
				fail (path, "call-scoped Callback cannot escape through a result");
			}
			if (signature.result.abi_type is NativeSumType) {
				fail (path, "sum result requires hidden caller storage instead of a direct value");
			}
			if (signature.result.abi_type is NativeSliceType) {
				fail (path + "/result", "native slice results are unsupported");
			}
			verify_type (signature.result.abi_type, signature.abi_version, path + "/result");
		}
	}

	// Retained continuation signatures have no containing program. Reuse the
	// channel/profile and group checks without inventing program membership.
	internal static void verify_detached_signature(NativeSignature signature, string path) throws NativeAbiError {
		if (signature.abi_version < NativeAbiVersion.SCALAR_V0 || signature.abi_version > NativeAbiVersion.NATIVE_EXCEPTIONS_V14) {
			fail (path, "unsupported native ABI version");
		}
		verify_signature_channels (signature, path);
		var plans = new HashTable<NativeStructValuePlan, bool> (direct_hash, direct_equal);
		if (signature.struct_result != null) {
			plans.insert (signature.struct_result, true);
		}
		foreach (var group in signature.struct_parameters) {
			plans.insert (group.value_plan, true);
		}
		foreach (var plan in plans.get_keys ()) {
			verify_struct_plan (plan, signature.abi_version);
		}
		verify_struct_groups (signature, plans, path);
	}

	private static void verify_struct_plan(NativeStructValuePlan plan, NativeAbiVersion profile) throws NativeAbiError {
		if (plan.leaves.length != plan.leaf_count) {
			fail ("struct-plan", "physical channels must retain every original declared leaf");
		}
		if (plan.ownership.length != plan.ownership_field_count || (plan.mode == NativeStructValueMode.COPY_VALUE ? plan.ownership.length != 0 : plan.mode != NativeStructValueMode.MOVE_VALUE || plan.ownership.length == 0)) {
			fail ("struct-plan", "copy/move mode requires the original complete field responsibility set");
		}
		NativeRecordResource? previous_owner = null;
		for (int i = 0; i < plan.ownership.length; i++) {
			var owner = plan.ownership[i];
			if (owner.acquisition_rank != i || (previous_owner != null && previous_owner.compare_path (owner) >= 0)) {
				fail ("struct-plan", "MOVE_VALUE requires exact declaration-ordered owner paths");
			}
			int matches = 0;
			foreach (var leaf in plan.leaves) {
				var scalar = leaf.abi_type as NativeScalarAbiType;
				if (leaf.storage_path == owner.field_path && scalar != null && scalar.scalar_type == NativeScalarType.PTR && leaf.buffer_component == (owner.buffer_cleanup == null ? -1 : 0)) {
					matches++;
				}
			}
			if (matches != 1) {
				fail ("struct-plan", "MOVE_VALUE field cleanup must bind one exact physical pointer channel");
			}
			previous_owner = owner;
		}
		if (profile == NativeAbiVersion.OWNER_SLOTS_V15) {
			profile = NativeAbiVersion.NATIVE_EXCEPTIONS_V14;
		}
		if (plan.leaves.length == 0 || plan.result_carrier != (plan.leaves.length == 1 ? NativeStructResultCarrier.SINGLE_LEAF : NativeStructResultCarrier.LEAF_AGGREGATE)) {
			fail ("struct-plan", "nonempty ordered leaves require the exact single/multiple result carrier");
		}
		string[]? previous = null;
		for (int l = 0; l < plan.leaves.length; l++) {
			var leaf = plan.leaves[l];
			if (leaf.abi_type is NativeTextType || leaf.abi_type is NativeSliceType) {
				fail ("struct-plan", "struct leaves must be scalar or whole vector channels");
			}
			verify_type (leaf.abi_type, profile, "struct-plan/leaf");
			if (leaf.buffer_component != -1) {
				if (plan.mode != NativeStructValueMode.MOVE_VALUE || leaf.buffer_component != 0 || l + 1 >= plan.leaves.length || leaf.field_path != leaf.storage_path + "@base" || !leaf.abi_type.same_type (new NativeScalarAbiType (NativeScalarType.PTR))) {
					fail ("struct-plan", "buffer field requires an ordered complete PTR/I32 pair");
				}
				var length = plan.leaves[++l];
				if (length.buffer_component != 1 || length.storage_path != leaf.storage_path || length.field_path != leaf.storage_path + "@length" || !length.abi_type.same_type (new NativeScalarAbiType (NativeScalarType.I32))) {
					fail ("struct-plan", "buffer field split or substituted its exact length channel");
				}
				int owners = 0;
				foreach (var owner in plan.ownership) {
					if (owner.field_path == leaf.storage_path && owner.buffer_cleanup != null) {
						owners++;
					}
				}
				if (owners != 1) {
					fail ("struct-plan", "buffer field requires one original static element cleanup obligation");
				}
			} else if (leaf.field_path != leaf.storage_path) {
				fail ("struct-plan", "scalar field cannot masquerade as a buffer component");
			}
			var path = leaf.storage_path.split (".");
			foreach (string component in path) {
				int ordinal;
				if (!int.try_parse (component, out ordinal) || ordinal < 0 || ordinal.to_string () != component) {
					fail ("struct-plan", "leaf path requires exact nonnegative declaration ordinals");
				}
			}
			if (previous == null) {
				foreach (string component in path) {
					if (component != "0") {
						fail ("struct-plan", "first leaf must begin at declaration zero recursively");
					}
				}
			} else {
				int shared = 0;
				while (shared < previous.length && shared < path.length && previous[shared] == path[shared]) {
					shared++;
				}
				if (shared == previous.length || shared == path.length || int.parse (path[shared]) != int.parse (previous[shared]) + 1) {
					fail ("struct-plan", "leaf paths must be complete, distinct and recursively declaration ordered");
				}
				for (int i = shared + 1; i < path.length; i++) {
					if (path[i] != "0") {
						fail ("struct-plan", "nested leaf traversal must start at declaration zero");
					}
				}
			}
			previous = path;
		}
	}

	private static void verify_record_declarations(NativeAbiProgram program) throws NativeAbiError {
		int previous = -1;
		foreach (var declaration in program.record_declarations) {
			if (declaration.struct_ordinal <= previous || declaration.name == "" || declaration.fields.length == 0 || declaration.fields.length != declaration.field_count) {
				fail ("record declaration", "requires exact ordered nominal identity and the original complete owner field set");
			}
			previous = declaration.struct_ordinal;
			NativeRecordResource? prior = null;
			foreach (var field in declaration.fields) {
				if (field.depth == 0 || field.acquisition_rank != -1 || (prior != null && prior.compare_path (field) >= 0)) {
					fail ("record declaration", "owner paths must be complete, distinct and declaration ordered");
				}
				for (int i = 0; i < field.depth; i++) {
					if (field.path_ordinal (i) < 0) {
						fail ("record declaration", "owner path requires nonnegative declaration ordinals");
					}
				}
				verify_record_cleanup (field, program);
				prior = field;
			}
		}
	}

	private static void verify_declared_fields(GenericArray<NativeRecordResource> fields, NativeRecordDeclarationPlan declaration) throws NativeAbiError {
		if (fields.length != declaration.field_count) {
			fail ("record declaration", "responsibility must cover every original declared owner field");
		}
		for (int i = 0; i < fields.length; i++) {
			var field = fields[i];
			var original = declaration.fields[i];
			if (field.compare_path (original) != 0 || field.type_name != original.type_name || !field.same_cleanup (original)) {
				fail ("record declaration", "responsibility changed an original field path, nominal type or cleanup identity");
			}
		}
	}

	private static void verify_struct_groups(NativeSignature signature, HashTable<NativeStructValuePlan, bool> plans, string path) throws NativeAbiError {
		bool move_value = signature.struct_result != null && signature.struct_result.mode == NativeStructValueMode.MOVE_VALUE;
		foreach (var parameter in signature.struct_parameters) {
			move_value |= parameter.value_plan.mode == NativeStructValueMode.MOVE_VALUE;
		}
		if ((move_value || signature.has_struct_transport_declaration) && !signature.matches_struct_transport ()) {
			fail (path, "record channels must preserve their complete original copy/move signature declaration");
		}
		if (signature.struct_result != null && (!plans.contains (signature.struct_result) || signature.result != null || signature.object_result != null || (signature.abi_version != NativeAbiVersion.AGGREGATE_V7 && signature.abi_version != NativeAbiVersion.BUFFER_V8 && signature.abi_version != NativeAbiVersion.TEXT_V9 && signature.abi_version != NativeAbiVersion.TEXT_SLICE_V10 && signature.abi_version != NativeAbiVersion.STRUCT_ELEMENTS_V11 && signature.abi_version != NativeAbiVersion.SUM_VALUES_V12 && signature.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && signature.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14))) {
			fail (path, "struct result requires exact aggregate-v7 plan without scalar result or hidden storage");
		}
		if (signature.struct_result != null && !signature.struct_result_mode.matches_storage (signature.struct_result) || signature.struct_result == null && signature.struct_result_mode != NativeStructValueMode.COPY_VALUE) {
			fail (path, "record result operation lost its exact storage and ownership graph");
		}
		if (!signature.matches_buffer_transport ()) {
			fail (path, "buffer channels must preserve their complete original ownership declaration");
		}
		int physical = 0;
		int logical = 0;
		int group_index = 0;
		int buffer_index = 0;
		while (physical < signature.parameters.length) {
			var buffer = buffer_index < signature.buffer_parameters.length ? signature.buffer_parameters[buffer_index] : null;
			if (buffer != null && buffer.first_leaf <= physical) {
				verify_buffer_plan (buffer.value_plan, signature.abi_version, path);
				if (buffer.first_leaf != physical || buffer.source_ordinal != logical || physical + 1 >= signature.parameters.length || !signature.parameters[physical].abi_type.same_type (new NativeScalarAbiType (NativeScalarType.PTR)) || !signature.parameters[physical + 1].abi_type.same_type (new NativeScalarAbiType (NativeScalarType.I32))) {
					fail (path, "owned buffer requires exact ordered complete PTR/I32 parameter grouping");
				}
				physical += 2;
				logical++;
				buffer_index++;
				continue;
			}
			var group = group_index < signature.struct_parameters.length ? signature.struct_parameters[group_index] : null;
			if (group != null && group.first_leaf <= physical) {
				if (!plans.contains (group.value_plan) || group.first_leaf != physical || group.source_ordinal != logical || group.value_plan.leaves.length > signature.parameters.length - physical || (signature.abi_version != NativeAbiVersion.AGGREGATE_V7 && signature.abi_version != NativeAbiVersion.BUFFER_V8 && signature.abi_version != NativeAbiVersion.TEXT_V9 && signature.abi_version != NativeAbiVersion.TEXT_SLICE_V10 && signature.abi_version != NativeAbiVersion.STRUCT_ELEMENTS_V11 && signature.abi_version != NativeAbiVersion.SUM_VALUES_V12 && signature.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && signature.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14)) {
					fail (path, "struct parameters require exact ordered aggregate-v7 source grouping");
				}
				if (!group.mode.matches_storage (group.value_plan)) {
					fail (path, "record parameter operation lost its original storage and ownership graph");
				}
				foreach (var leaf in group.value_plan.leaves) {
					var parameter = signature.parameters[physical++];
					if (!parameter.abi_type.same_type (leaf.abi_type)) {
						fail (path, "struct parameter channel type or order mismatch");
					}
					if (group.mode == NativeStructValueMode.BORROW_VALUE) {
						NativeRecordResource? owner = null;
						foreach (var responsibility in group.value_plan.ownership) {
							if (responsibility.field_path == leaf.storage_path) {
								owner = responsibility;
							}
						}
						if (parameter.object_origin != null || parameter.owns_resource || parameter.generic_owner_origin != null) {
							fail (path, "borrowed record leaf cannot acquire cleanup or allocation authority");
						}
						if (owner != null && owner.cleanup_class_ordinal >= 0) {
							if (parameter.borrowed_class_ordinal != owner.cleanup_class_ordinal || parameter.resource != null) {
								fail (path, "borrowed record Class leaf requires its exact nominal noescape identity");
							}
						} else if (owner != null && owner.buffer_cleanup == null) {
							if (parameter.resource == null || parameter.resource.type_name != owner.type_name || parameter.resource.cleanup_symbol != owner.cleanup_symbol || parameter.borrowed_class_ordinal != -1) {
								fail (path, "borrowed record Resource leaf requires its exact nonowning destructor identity");
							}
						} else if (parameter.resource != null || parameter.borrowed_class_ordinal != -1 || parameter.generic_borrow_origin != null) {
							fail (path, "borrowed record copied or buffer component cannot acquire foreign owner identity");
						}
					}
					if (group.value_plan.mode == NativeStructValueMode.COPY_VALUE && (parameter.object_origin != null || parameter.resource != null || parameter.owns_resource || parameter.borrowed_class_ordinal != -1 || parameter.generic_borrow_origin != null)) {
						fail (path, "copied record leaf cannot acquire owner or nominal Class authority");
					}
				}
				group_index++;
			} else {
				physical++;
			}
			logical++;
		}
		if (buffer_index != signature.buffer_parameters.length) {
			fail (path, "buffer parameter group exceeds leaf parameters");
		}
		if (group_index != signature.struct_parameters.length) {
			fail (path, "struct parameter grouping exceeds concrete channels");
		}
	}

	internal static void verify_buffer_plan(NativeBufferValuePlan plan, NativeAbiVersion profile, string path) throws NativeAbiError {
		if (plan.context_origin != null) {
			if (!plan.context_origin.valid () || plan.record_element != null || plan.element_type == null || !plan.element_type.same_type (new NativeScalarAbiType (NativeScalarType.U8))) {
				fail (path, "context byte ownership requires its exact u8 extent and original allocator release contract");
			}
		}
		if (profile == NativeAbiVersion.OWNER_SLOTS_V15) {
			profile = NativeAbiVersion.NATIVE_EXCEPTIONS_V14;
		}
		if ((profile != NativeAbiVersion.BUFFER_V8 && profile != NativeAbiVersion.TEXT_V9 && profile != NativeAbiVersion.TEXT_SLICE_V10 && profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14) || !plan.transfers_ownership || plan.base_type != NativeScalarType.PTR || plan.length_type != NativeScalarType.I32 || plan.element_type is NativeTextType || plan.element_type is NativeSliceType) {
			fail (path, "owned buffer transfer requires buffer-v8, PTR/I32 and static deallocation responsibility");
		}
		if (plan.record_element != null) {
			if (profile != NativeAbiVersion.STRUCT_ELEMENTS_V11 && profile != NativeAbiVersion.SUM_VALUES_V12 && profile != NativeAbiVersion.OWNED_SUMS_V13 && profile != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || plan.element_type != null) {
				fail (path, "record owner requires one exact struct-elements-v11 element shape");
			}
			return;
		}
		if (!(plan.element_type is NativeScalarAbiType || plan.element_type is NativeVectorType)) {
			fail (path, "buffer element requires the existing concrete primitive/vector storage domain");
		}
		verify_type (plan.element_type, profile, path + "/element");
	}

	private static void verify_record_element(NativeRecordElement record, HashTable<NativeRecordElement, bool> members, HashTable<NativeRecordElement, bool> visited) throws NativeAbiError {
		if (!members.contains (record)) {
			fail ("record-element", "nested element must have its exact program-owned storage declaration");
		}
		if (visited.contains (record)) {
			if (!visited.lookup (record)) {
				fail ("record-element", "recursive by-value element layout");
			}
			return;
		}
		visited.insert (record, false);
		if (record.fields.length == 0 || !record.natural_layout || !record.structural_zero || !record.trivial_destruction) {
			fail ("record-element", "nonempty element requires natural complete storage, structural zero and trivial destruction");
		}
		var names = new HashTable<string, bool> (str_hash, str_equal);
		for (int i = 0; i < record.fields.length; i++) {
			var field = record.fields[i];
			if (field.ordinal != i || field.name == "" || names.contains (field.name) || (field.record == null) == (field.leaf == null)) {
				fail ("record-element", "fields require exact declaration order, unique names and one complete leaf or record type");
			}
			names.insert (field.name, true);
			if (field.record != null) {
				verify_record_element (field.record, members, visited);
			} else {
				if (!(field.leaf is NativeScalarAbiType || field.leaf is NativeVectorType)) {
					fail ("record-element", "record field is outside the trivial zeroable leaf domain");
				}
				verify_type (field.leaf, NativeAbiVersion.STRUCT_ELEMENTS_V11, "record-element/field");
			}
		}
		visited.insert (record, true);
	}

	private static void verify_record_uses(NativeSignature signature, HashTable<NativeRecordElement, bool> members) throws NativeAbiError {
		foreach (var parameter in signature.parameters) {
			var record = parameter.abi_type as NativeRecordSliceType;
			if (record != null && !members.contains (record.element)) {
				fail ("record-slice", "slice must reference its exact program-owned element");
			}
		}
		if (signature.buffer_result != null && signature.buffer_result.record_element != null && !members.contains (signature.buffer_result.record_element)) {
			fail ("record-result", "owner result must reference its exact program-owned element");
		}
		foreach (var parameter in signature.buffer_parameters) {
			if (parameter.value_plan.record_element != null && !members.contains (parameter.value_plan.record_element)) {
				fail ("record-owner", "owner parameter must reference its exact program-owned element");
			}
		}
	}

	private static void verify_callable_records(NativeAbiType type, NativeAbiProgram program) throws NativeAbiError {
		var signature = (type is NativeClosureHandleType) ? ((NativeClosureHandleType) type).signature : (type as NativeFunctionPointerType);
		if (signature == null) {
			return;
		}
		var channels = new GenericArray<NativeCallableOwnedChannel> ();
		foreach (var channel in signature.owned_parameters) {
			channels.add (channel);
		}
		if (signature.owned_result != null) {
			channels.add (signature.owned_result);
		}
		foreach (var channel in channels) {
			int matches = 0;
			if (channel.is_class) {
				foreach (var owner in program.classes) {
					if (owner.name == channel.type_name && !owner.is_interface) {
						matches++;
					}
				}
			} else {
				foreach (var resource in program.callable_resources) {
					if (resource.type_name == channel.type_name && resource.class_ordinal == -1 && resource.cleanup_symbol != "") {
						matches++;
					}
				}
			}
			if (matches != 1) {
				fail ("native callable owner", "owned channel requires one exact nominal Class or Resource cleanup declaration");
			}
		}
		foreach (var borrow in signature.borrowed_parameters) {
			int matches = 0;
			if (borrow.is_class) {
				foreach (var owner in program.classes) {
					if (owner.name == borrow.type_name) {
						matches++;
					}
				}
			} else {
				foreach (var resource in program.callable_resources) {
					if (resource.type_name == borrow.type_name && resource.class_ordinal == -1 && resource.cleanup_symbol != "") {
						matches++;
					}
				}
			} if (matches != 1) {
				fail ("native callable borrow", "channel requires one exact nominal Class or Resource declaration");
			}
		}
		foreach (var parameter in signature.parameter_types) {
			verify_callable_records (parameter, program);
		}
		if (signature.record_result != null) {
			var result = signature.record_result;
			int matches = 0;
			foreach (var declared in program.struct_values) {
				if (result.matches (declared.struct_name, declared.mode, declared.leaves)) {
					matches++;
				}
			}
			if (matches != 1) {
				fail ("native callable result", "record signature requires one exact complete nominal declaration");
			}
			foreach (var leaf in result.leaves) {
				verify_callable_records (leaf.abi_type, program);
			}
		}
		foreach (var group in signature.record_parameters) {
			NativeStructValuePlan? declared = null;
			foreach (var candidate in program.struct_values) {
				if (candidate.struct_name == group.record_name) {
					if (declared != null) {
						fail ("native function value", "record signature has ambiguous nominal declaration");
					}
					declared = candidate;
				}
			}
			if (declared == null || !group.mode.matches_storage (declared) || declared.leaves.length != group.leaves.length) {
				fail ("native function value", "record signature requires its exact complete copied declaration");
			}
			for (int l = 0; l < group.leaves.length; l++) {
				if (group.leaves[l].field_path != declared.leaves[l].field_path || group.leaves[l].storage_path != declared.leaves[l].storage_path || group.leaves[l].buffer_component != declared.leaves[l].buffer_component || !group.leaves[l].abi_type.same_type (declared.leaves[l].abi_type)) {
					fail ("native function value", "record signature leaf differs from its declared storage");
				}
			}
		}
	}

	private static void verify_callable_record_result(NativeFunctionPointerType signature, NativeStructValuePlan? result, bool original, NativeAbiProgram program, string path) throws NativeAbiError {
		if (!original || (signature.record_result == null ? result != null : result == null || !program.struct_values.find (result) || !signature.record_result.matches (result.struct_name, result.mode, result.leaves))) {
			fail (path, "indirect record result lost its exact original native value declaration");
		}
	}

	private static void verify_callable_result(NativeFunctionPointerType signature, NativeScalarOwner? owner, bool original, NativeAbiProgram program, string path) throws NativeAbiError {
		var channel = signature.owned_result;
		if (!original || (channel == null ? owner != null : owner == null || owner.type_name != channel.type_name || (channel.is_class ? owner.class_ordinal < 0 : owner.class_ordinal != -1 || owner.cleanup_symbol == ""))) {
			fail (path, "indirect result lost its original exact owned Resource acquisition");
		}
		if (owner == null) {
			return;
		}
		if (channel.is_class) {
			if (owner.class_ordinal >= program.classes.length || program.classes[owner.class_ordinal].name != owner.type_name || program.classes[owner.class_ordinal].is_interface || owner.cleanup_symbol != "") {
				fail (path, "indirect Class result requires its exact nominal heap cleanup declaration");
			}
			return;
		}
		int matches = 0;
		foreach (var resource in program.callable_resources) {
			if (resource.same_owner (owner)) {
				matches++;
			}
		}
		if (matches != 1) {
			fail (path, "indirect result cleanup differs from its nominal Resource declaration");
		}
	}

	private static void verify_callable_transfers(GenericArray<NativeCallableOwnedArgument> transfers, NativeFunctionPointerType signature, NativeAbiProgram program, string path) throws NativeAbiError {
		if (transfers.length != signature.owned_parameters.length) {
			fail (path, "indirect invocation lost its complete owned argument inventory");
		}
		var sources = new HashTable<int, bool> (direct_hash, direct_equal);
		for (int p = 0; p < transfers.length; p++) {
			var transfer = transfers[p];
			var channel = signature.owned_parameters[p];
			int matches = 0;
			if (channel.is_class) {
				int ordinal = transfer.resource.class_ordinal;
				if (ordinal >= 0 && ordinal < program.classes.length && program.classes[ordinal].name == channel.type_name && !program.classes[ordinal].is_interface && transfer.resource.cleanup_symbol == "") {
					matches++;
				}
			} else {
				foreach (var resource in program.callable_resources) {
					if (resource.same_owner (transfer.resource)) {
						matches++;
					}
				}
			}
			if (transfer.ordinal != channel.ordinal || transfer.resource.type_name != channel.type_name || matches != 1 || (transfer.source_ordinal < 0 ? !transfer.null_argument || transfer.committed_null : !transfer.committed_null || sources.contains (transfer.source_ordinal))) {
				fail (path, "indirect ownership transfer lost exact Resource identity, destructor or committed source");
			}
			if (transfer.source_ordinal >= 0) {
				sources.insert (transfer.source_ordinal, true);
			}
		}
	}

	public static void verify(NativeAbiProgram program) throws NativeAbiError {
		if (!program.record_applications_valid ()) {
			fail ("native record applications", "lost original nominal application declaration inventory");
		}
		var application_records = new HashTable<NativeStructValuePlan, bool> (direct_hash, direct_equal);
		foreach (var application in program.record_applications) {
			if (application.definition_name == "" || application.argument_count == 0 || !program.struct_values.find (application.record) || application_records.contains (application.record)) {
				fail ("native record applications", "requires one exact program-owned nominal record application");
			}
			application_records.insert (application.record, true);
			if (application.owned_declaration != null) {
				string record_failure;
				bool declared = application.owned_declaration.valid (application, program, out record_failure);
				if (!declared) {
					fail ("native owning record", "lost exact declared argument, field type or recursive cleanup authority: " + application.nominal_name + ": " + record_failure);
				}
			}
			for (int a = 0; a < application.argument_count; a++) {
				if (!application.argument (a).valid (program)) {
					fail ("native record applications", "invalid exact ordered type argument");
				}
			}
		}
		if (!program.callable_resources_valid ()) {
			fail ("native callable resources", "lost original nominal cleanup declaration inventory");
		}
		var callable_resources = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var resource in program.callable_resources) {
			if (resource.class_ordinal != -1 || resource.type_name == "" || resource.cleanup_symbol == "" || callable_resources.contains (resource.type_name)) {
				fail ("native callable resources", "requires unique exact nominal Resource cleanup declarations");
			}
			callable_resources.insert (resource.type_name, true);
		}
		if (!program.gobject_imports_valid ()) {
			fail ("GObjectImport", "lost admitted typed bridge/header origin inventory");
		}
		foreach (var root in program.class_imports) {
			for (uint m = 0; m < root.api.member_count; m++) {
				int matches = 0;
				foreach (var function in program.functions) {
					var plan = function.foreign_import;
					if (plan != null && plan.binding.root.equal (root) && plan.binding.member_index == m) {
						matches++;
					}
				}
				if (matches != 1) {
					fail ("CImport", "missing or duplicate native adapter for a declared member");
				}
			}
		}
		if (!Astra.Source.ForeignImportContract.distinct (program.class_imports)) {
			fail ("foreign imports", "requires distinct nominal roots, prefixes and COM IIDs with exact declared parents");
		}
		if (!program.class_imports_valid ()) {
			fail ("CImport", "lost imported nominal root inventory");
		}
		foreach (var function in program.functions) {
			if (function.foreign_signal != null && !function.foreign_signal.valid (program, function)) {
				fail ("native signal", "lost exact native shared root and intrinsic member authority");
			}
		}
		foreach (var function in program.functions) {
			if (function.foreign_import != null && !function.foreign_import.valid (program, function)) {
				fail ("CImport", "native import lost exact signature, ownership or exception factory");
			}
		}
		foreach (var function in program.functions) {
			foreach (var parameter in function.signature.parameters) {
				if (parameter.com_unknown_borrow != null && (function.foreign_import == null || function.foreign_import.binding.root.com == null || function.foreign_import.binding.member.kind != Astra.Source.ForeignMemberKind.CONSTRUCTOR)) {
					fail ("IUnknown acquisition", "call-only unknown provenance cannot enter an unrelated native function");
				}
			}
		}
		if (!program.com_imports_valid ()) {
			fail ("COMImport", "lost admitted IID/vtable/cleanup/context identity or declaration order");
		}
		foreach (var function in program.functions) {
			if (!function.runtime_lifetimes_valid ()) {
				fail ("runtime lifetimes", "native summary differs from its original immutable equations/effects");
			}
			if (!function.effects_valid () || !function.stack_objects_valid () || !function.exact_calls_valid () || !function.shared_elisions_valid () || (function.span.file.native_interface && !function.imported_effects_valid ())) {
				throw new NativeAbiError.INVALID_ABI ("derived effects lost their admitted body/interface authority");
			}
		}
		foreach (var function in program.functions) {
			if (!function.vector_memory_valid ()) {
				throw new NativeAbiError.INVALID_ABI ("native vector memory lost its admitted body plans");
			}
			foreach (var memory in function.vector_memory) {
				if (!memory.valid () || memory.vector_type.element == NativeScalarType.B1) {
					throw new NativeAbiError.INVALID_ABI ("forged native vector memory contract");
				}
				verify_type (memory.vector_type, NativeAbiVersion.OWNER_SLOTS_V15, "vector-memory/body-shape");
			}
		}
		foreach (var function in program.functions) {
			if (!function.floating_policy_valid ()) {
				throw new NativeAbiError.INVALID_ABI ("floating policy differs from its admitted declaration");
			}
		}
		foreach (var function in program.functions) {
			foreach (var parameter in function.signature.parameters) {
				int borrowed = parameter.borrowed_class_ordinal;
				if (borrowed >= 0 && (borrowed >= program.classes.length || parameter.object_origin != null || !(parameter.abi_type is NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR)) {
					fail ("native borrowed Class", "requires exact program-owned nominal Class and nonowning PTR channel");
				}
			}
			var channels = new GenericArray<NativeAbiType> ();
			foreach (var parameter in function.signature.parameters) {
				channels.add (parameter.abi_type);
			}
			if (function.signature.result != null) {
				channels.add (function.signature.result.abi_type);
			}
			foreach (var channel in channels) {
				verify_callable_records (channel, program);
				var shared = channel as NativeSharedHandleType;
				var closure = channel as NativeClosureHandleType;
				if (shared == null && closure == null) {
					continue;
				}
				string identity = shared != null ? shared.payload : closure.environment;
				NativeClassPlan? exact = null;
				foreach (var owner in program.classes) {
					if (owner.name == identity) {
						exact = owner;
					}
				}
				bool generic_environment = exact != null && exact.generic_instance != null;
				bool declared_closure = closure != null && !closure.threaded && !closure.actor && exact != null && exact.generic_instance != null && exact.generic_instance.declared_structure != null;
				if (exact == null || exact.is_interface && (shared == null || !shared.intrusive || !shared.is_weak) || generic_environment && !declared_closure || (closure != null && exact.polymorphic)) {
					fail ("native lifetime channel", "requires exact program-owned concrete payload/environment identity");
				}
			}
		}
		var actor_sites = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var plan in program.actor_operations) {
			string site = "%d/%d/%d".printf (plan.caller, plan.block, plan.instruction);
			if (plan.caller < 0 || plan.caller >= program.functions.length || plan.block < 0 || plan.instruction < 0 || actor_sites.contains (site) || plan.action < Astra.Source.ActorAction.SEND || plan.action > Astra.Source.ActorAction.CANCEL || !plan.sender.actor || plan.error_class < 0 || plan.error_class >= program.classes.length) {
				fail ("native Actor", "requires exact finite action, sender and one checked Error operation site");
			}
			actor_sites.insert (site, true);
			verify_type (plan.sender, program.abi_version, "native Actor");
			var error = program.classes[plan.error_class];
			if (!error.exception_root || error.parent_ordinal != -1 || error.concurrency_policy != null) {
				fail ("native Actor", "requires ordinary nominated Error lifetime");
			}
			int constructors = 0;
			foreach (var function in program.functions) {
				if (function.kind == NativeCallableKind.CONSTRUCTOR && function.declaring_type_is_class && function.declaring_type_ordinal == error.ordinal) {
					constructors++;
					if (function.signature.exception_plan != null || function.signature.parameters.length != 1 || !(function.signature.parameters[0].abi_type is NativeTextType)) {
						fail ("native Actor", "requires exact nonthrowing Error(string) constructor");
					}
				}
			}
			if (constructors != 1) {
				fail ("native Actor", "nominated Error constructor must remain uniquely bound");
			}
			NativeClassPlan? receiver = null;
			foreach (var owner in program.classes) {
				if (owner.name == plan.sender.environment) {
					receiver = owner;
				}
			}
			if (receiver == null || receiver.concurrency_policy == null || receiver.concurrency_policy.identity != 16 || receiver.polymorphic || receiver.is_interface || !send_class (receiver.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal), true)) {
				fail ("native Actor", "sender lost exact exclusive transferable receiver");
			}
			if (plan.sender.actor_message != null) {
				NativeClassPlan? message = null;
				foreach (var owner in program.classes) {
					if (owner.name == plan.sender.actor_message) {
						message = owner;
					}
				}
				if (message == null || message.polymorphic || message.is_interface || message.generic_instance != null || !send_class (message.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal), true)) {
					fail ("native Actor", "message lost exact independently owned transferable Class");
				}
			}
		}
		if (!program.retained_operations_valid ()) {
			fail ("native retained callback", "lost exact original action, environment or callback signature inventory");
		}
		var retained_sites = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var plan in program.retained_operations) {
			string site = "%d/%d/%d".printf (plan.caller, plan.block, plan.instruction);
			NativeClassPlan? retained_environment = null;
			foreach (var owner in program.classes) {
				if (owner.name == plan.handle.environment) {
					retained_environment = owner;
				}
			}
			if (retained_environment == null || retained_environment.is_interface || retained_environment.polymorphic || !send_class (retained_environment.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal), false, true) || plan.handle.threaded && !send_class (retained_environment.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal)) || plan.caller < 0 || plan.caller >= program.functions.length || plan.block < 0 || plan.instruction < 0 || !plan.valid_signature () || retained_sites.contains (site)) {
				fail ("native retained callback", "requires exact single-threaded i32 C thunk and unique lifecycle action");
			}
			retained_sites.insert (site, true);
			verify_type (plan.handle, program.abi_version, "native retained callback");
		}
		var closure_sites = new HashTable<string, bool> (str_hash, str_equal);
		if (!program.callback_views_valid ()) {
			fail ("captured callback", "lost original projection inventory or signature");
		}
		var callback_sites = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var view in program.callback_views) {
			bool environment = false;
			foreach (var owner in program.classes) {
				environment |= owner.name == view.closure.environment && !owner.polymorphic && !owner.is_interface;
			}
			if (!view.valid () || !environment || view.caller >= program.functions.length || callback_sites.contains (view.identity ())) {
				fail ("captured callback", "requires exact nonpolymorphic environment and one borrowed scalar projection");
			}
			verify_type (view.closure, program.abi_version, "captured callback source");
			verify_type (view.callback, program.abi_version, "captured callback view");
			callback_sites.insert (view.identity (), true);
		}
		foreach (var plan in program.closures) {
			string site = "%d/%d/%d".printf (plan.caller, plan.block, plan.instruction);
			NativeClassPlan? environment = null;
			foreach (var owner in program.classes) {
				if (owner.name == plan.handle.environment) {
					environment = owner;
				}
			}
			if (environment == null || environment.is_interface || environment.polymorphic || plan.handle.threaded && !send_class (environment.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal)) || plan.caller < 0 || plan.caller >= program.functions.length || plan.block < 0 || plan.instruction < 0 || closure_sites.contains (site)) {
				fail ("native closure", "requires exact nonpolymorphic environment and one typed operation site");
			}
			if (plan.handle.actor) {
				if (!plan.binding || plan.actor_binding == null || !plan.actor_binding.valid () || environment.concurrency_policy == null || environment.concurrency_policy.identity != 16 || environment.parent_ordinal != -1 || environment.generic_instance != null || !send_class (environment.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal), true)) {
					fail ("native Actor", "lost admitted FIFO/executor, exclusive receiver or transferable state");
				}
				if (plan.handle.actor_message != null) {
					NativeClassPlan? message = null;
					foreach (var owner in program.classes) {
						if (owner.name == plan.handle.actor_message) {
							message = owner;
						}
					}
					if (message == null || message.is_interface || message.polymorphic || message.generic_instance != null || !send_class (message.ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal), true)) {
						fail ("native Actor", "message lost exact independent transferable Class identity");
					}
				}
			} else if (plan.actor_binding != null || environment.concurrency_policy != null && environment.concurrency_policy.actor) {
				fail ("native Actor", "Actor receiver requires its mailbox adapter exclusively");
			}
			closure_sites.insert (site, true);
			verify_type (plan.handle, program.abi_version, "native closure");
			verify_callable_records (plan.handle, program);
			if (!plan.owned_arguments_valid ()) {
				fail ("native closure", "lost original ownership transfer facts");
			}
			if (!plan.binding) {
				verify_callable_result (plan.handle.signature, plan.result_owner, plan.result_owner_valid (), program, "native closure result");
				verify_callable_record_result (plan.handle.signature, plan.record_result, plan.record_result_valid (), program, "native closure record result");
			} else if (plan.result_owner != null || !plan.result_owner_valid ()) {
				fail ("native closure result", "binding cannot acquire a code result");
			}
			if (plan.binding) {
				if (plan.borrowed_arguments.length != 0 || plan.record_arguments.length != 0 || plan.owned_arguments.length != 0) {
					fail ("native closure", "binding cannot carry unrelated invocation loans");
				}
			} else {
				verify_callable_transfers (plan.owned_arguments, plan.handle.signature, program, "native closure");
				if (plan.record_arguments.length != plan.handle.signature.record_parameters.length) {
					fail ("native closure", "record arguments lost the complete closure signature groups");
				}
				for (int g = 0; g < plan.record_arguments.length; g++) {
					if (!plan.record_arguments[g].same_type (plan.handle.signature.record_parameters[g])) {
						fail ("native closure", "record argument nominal identity differs from carried closure code");
					}
				}
				if (plan.borrowed_arguments.length != plan.handle.signature.borrowed_parameters.length) {
					fail ("native closure", "borrowed arguments lost the complete closure signature channels");
				}
				for (int p = 0; p < plan.borrowed_arguments.length; p++) {
					if (!plan.borrowed_arguments[p].same_channel (plan.handle.signature.borrowed_parameters[p])) {
						fail ("native closure", "borrowed argument nominal identity differs from carried closure code");
					}
				}
			}
			if (plan.binding) {
				if (plan.target < 0 || plan.target >= program.functions.length || plan.destructor != environment.destructor_ordinal) {
					fail ("native closure", "bind requires exact native code and environment destruction channel");
				}
				var code = program.functions[plan.target];
				var signature = code.signature;
				var result_channel = plan.handle.signature.owned_result;
				if (result_channel != null && result_channel.is_class) {
					if (signature.heap_result == null || !signature.heap_result.heap || signature.heap_result.class_name != result_channel.type_name || signature.resource_result != null) {
						fail ("native closure result", "bound Class result differs from its exact nominal heap origin");
					}
				} else if (result_channel == null ? signature.resource_result != null || signature.heap_result != null : signature.resource_result == null || signature.resource_result.type_name != result_channel.type_name || signature.heap_result != null) {
					fail ("native closure result", "bound code result differs from its exact nominal ownership channel");
				}
				if (code.kind != NativeCallableKind.FUNCTION || (plan.handle.checked_error == null ? signature.exception_plan != null : signature.exception_plan == null || signature.exception_plan.bound_name != plan.handle.checked_error) || signature.receiver != null || signature.parameters.length != plan.handle.signature.parameter_types.length + 1 || (plan.handle.signature.void_result ? signature.struct_result != null || signature.result != null : plan.handle.signature.record_result == null ? signature.struct_result != null || signature.result == null || !signature.result.abi_type.same_type (new NativeScalarAbiType (plan.handle.signature.result_scalar ())) : signature.result != null || signature.struct_result == null || !plan.handle.signature.record_result.matches (signature.struct_result.struct_name, signature.struct_result_mode, signature.struct_result.leaves)) || !signature.parameters[0].abi_type.same_type (new NativeScalarAbiType (NativeScalarType.PTR)) || signature.parameters[0].borrowed_class_ordinal != environment.ordinal) {
					fail ("native closure", "bound code requires exact borrowed environment and copied scalar call signature");
				}
				if (signature.struct_parameters.length != plan.handle.signature.record_parameters.length) {
					fail ("native closure", "bound code lost exact nominal record parameter groups");
				}
				for (int g = 0; g < signature.struct_parameters.length; g++) {
					var bound = signature.struct_parameters[g];
					var carried = plan.handle.signature.record_parameters[g];
					if (bound.source_ordinal != carried.source_ordinal + 1 || bound.first_leaf != carried.first_leaf + 1 || bound.mode != carried.mode || bound.value_plan.struct_name != carried.record_name || bound.value_plan.leaves.length != carried.leaves.length) {
						fail ("native closure", "bound record parameter differs from exact carried nominal group");
					}
					for (int l = 0; l < carried.leaves.length; l++) {
						if (bound.value_plan.leaves[l].field_path != carried.leaves[l].field_path || !bound.value_plan.leaves[l].abi_type.same_type (carried.leaves[l].abi_type)) {
							fail ("native closure", "bound record parameter leaf differs from carried code signature");
						}
					}
				}
				foreach (var channel in plan.handle.signature.borrowed_parameters) {
					var parameter = signature.parameters[channel.ordinal + 1];
					if (!channel.is_class) {
						NativeScalarOwner? resource = null;
						foreach (var declaration in program.callable_resources) {
							if (declaration.type_name == channel.type_name) {
								resource = declaration;
							}
						}
						if (resource == null || !resource.same_owner (parameter.resource)) {
							fail ("native closure", "bound borrowed Resource cleanup differs from its original nominal declaration");
						}
					}
					if (channel.is_class ? parameter.borrowed_class_ordinal < 0 || parameter.borrowed_class_ordinal >= program.classes.length || program.classes[parameter.borrowed_class_ordinal].name != channel.type_name || parameter.object_origin != null || parameter.resource != null : parameter.resource == null || parameter.owns_resource || parameter.resource.type_name != channel.type_name || parameter.borrowed_class_ordinal != -1 || parameter.object_origin != null) {
						fail ("native closure", "bound borrowed parameter differs from exact nominal code channel");
					}
				}
				foreach (var channel in plan.handle.signature.owned_parameters) {
					var parameter = signature.parameters[channel.ordinal + 1];
					if (channel.is_class) {
						var origin = parameter.object_origin;
						if (origin == null || !origin.heap || origin.class_name != channel.type_name || parameter.resource != null || parameter.borrowed_class_ordinal != -1) {
							fail ("native closure", "bound owned Class parameter differs from its exact heap transfer channel");
						}
					} else {
						NativeScalarOwner? resource = null;
						foreach (var declaration in program.callable_resources) {
							if (declaration.type_name == channel.type_name) {
								resource = declaration;
							}
						}
						if (resource == null || parameter.resource == null || !resource.same_owner (parameter.resource) || !parameter.owns_resource || parameter.object_origin != null || parameter.borrowed_class_ordinal != -1) {
							fail ("native closure", "bound owned Resource parameter differs from its exact cleanup and transfer channel");
						}
					}
				}
				for (int a = 1; a < signature.parameters.length; a++) {
					if (plan.handle.actor && plan.handle.actor_message != null && (signature.parameters[a].object_origin == null || !signature.parameters[a].object_origin.heap || signature.parameters[a].object_origin.class_name != plan.handle.actor_message)) {
						fail ("native Actor", "handler message must own the exact heap Class");
					}
					if (!signature.parameters[a].abi_type.same_type (plan.handle.signature.parameter_types[a - 1])) {
						fail ("native closure", "bound scalar argument differs from carried signature");
					}
				}
			} else if (plan.target != -1 || plan.destructor != -1) {
				fail ("native closure", "invoke obtains code and destructor from its typed carrier");
			}
		}
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				if (field.storage_type is NativeCallbackType) {
					fail ("Class field", "call-scoped Callback cannot be stored");
				}
				if (field.storage_type != null) {
					verify_callable_records (field.storage_type, program);
				}
			}
		}
		var shared_sites = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var plan in program.shared_operations) {
			if (plan.handle.actor_sender != null) {
				var actor = plan.handle.actor_sender;
				string site = "%d/%d/%d".printf (plan.caller, plan.block, plan.instruction);
				if (plan.action != 1 || plan.handle.is_weak || plan.handle.intrusive || !actor.actor || plan.handle.payload != actor.environment || plan.caller < 0 || plan.caller >= program.functions.length || plan.block < 0 || plan.instruction < 0 || shared_sites.contains (site) || !send_leaf (actor, program, new HashTable<int, bool> (direct_hash, direct_equal))) {
					fail ("native Actor clone", "requires exact strong sender clone and transferable mailbox identity");
				}
				verify_type (actor, program.abi_version, "native Actor clone");
				shared_sites.insert (site, true);
				continue;
			}
			string site = "%d/%d/%d".printf (plan.caller, plan.block, plan.instruction);
			bool payload = false;
			foreach (var owner in program.classes) {
				if (owner.name == plan.handle.payload && (!owner.is_interface || plan.handle.intrusive) && (plan.action != 6 || owner.concurrency_policy != null && owner.concurrency_policy.identity == 7) && plan.handle.intrusive == (owner.concurrency_policy != null && owner.concurrency_policy.shared)) {
					payload = true;
				}
			}
			if (!payload || plan.caller < 0 || plan.caller >= program.functions.length || plan.block < 0 || plan.instruction < 0 || plan.action < 0 || plan.action > 6 || shared_sites.contains (site) || ((plan.action == 0 || plan.action == 1 || plan.action == 2 || plan.action == 5 || plan.action == 6) && plan.handle.is_weak) || ((plan.action == 3 || plan.action == 4) && !plan.handle.is_weak)) {
				fail ("native shared operation", "requires exact concrete payload, handle flavor and unique typed operation site");
			}
			shared_sites.insert (site, true);
			verify_type (plan.handle, program.abi_version, "native shared operation");
		}
		var function_sites = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var plan in program.function_values) {
			verify_callable_result (plan.signature, plan.result_owner, plan.result_owner_valid (), program, "native function result");
			verify_callable_record_result (plan.signature, plan.record_result, plan.record_result_valid (), program, "native function record result");
			string site = "%d/%d/%d".printf (plan.caller, plan.block, plan.instruction);
			if (plan.caller < 0 || plan.caller >= program.functions.length || plan.block < 0 || plan.instruction < 0 || function_sites.contains (site)) {
				fail ("native function value", "requires one exact caller/block/instruction site");
			}
			function_sites.insert (site, true);
			verify_type (plan.signature, program.abi_version, "native function value");
			verify_callable_records (plan.signature, program);
			if (!plan.owned_arguments_valid ()) {
				fail ("native function value", "lost original ownership transfer facts");
			}
			verify_callable_transfers (plan.owned_arguments, plan.signature, program, "native function value");
			if (plan.borrowed_arguments.length != plan.signature.borrowed_parameters.length) {
				fail ("native function value", "borrowed arguments lost their exact nominal signature channels");
			}
			for (int p = 0; p < plan.borrowed_arguments.length; p++) {
				if (!plan.borrowed_arguments[p].same_channel (plan.signature.borrowed_parameters[p])) {
					fail ("native function value", "borrowed argument nominal identity differs from carried signature");
				}
			}
			if (plan.record_arguments.length != plan.signature.record_parameters.length) {
				fail ("native function value", "record call arguments lost their exact nominal signature groups");
			}
			for (int g = 0; g < plan.record_arguments.length; g++) {
				if (!plan.record_arguments[g].same_type (plan.signature.record_parameters[g])) {
					fail ("native function value", "record argument nominal identity differs from carried signature");
				}
			}
		}
		int utf8_factories = 0;
		foreach (var function in program.functions) {
			if (!function.utf8_factory) {
				continue;
			}
			var signature = function.signature;
			if (++utf8_factories != 1 || function.kind != NativeCallableKind.FUNCTION || function.linkage != NativeLinkage.NATIVE_INTERNAL || signature.receiver != null || signature.heap_result == null || signature.exception_plan == null || signature.parameters.length != 1 || !(signature.parameters[0].abi_type is NativeSliceType) || signature.parameters[0].abi_type is NativeTextSliceType || signature.parameters[0].abi_type is NativeRecordSliceType || signature.result == null || !signature.result.abi_type.same_type (new NativeScalarAbiType (NativeScalarType.PTR))) {
				fail ("UTF-8 factory", "requires one native checked heap result with exact borrowed byte-slice channel");
			}
		}
		int prior_async = -1;
		var task_frames = new bool[program.functions.length];
		foreach (var frame in program.async_frames) {
			frame.verify ();
			if (frame.provider == Astra.Source.AsyncProviderKind.POSIX_THREADED) {
				for (uint o = 0; o < frame.owner_count; o++) {
					var owner = frame.owner (o);
					bool transferable = owner.context != null ? owner.context.valid() && owner.context.mode == "owned-concurrent" && owner.cleanup_symbol == owner.context.cleanup && owner.class_ordinal < 0 && !owner.catch_owner : owner.cleanup_symbol == "" && send_class (owner.class_ordinal, program, new HashTable<int, bool> (direct_hash, direct_equal));
					if (!transferable) {
						fail ("threaded frame owner", "requires exact structurally transferable native ownership");
					}
				}
			}
			if (frame.function_ordinal <= prior_async || frame.function_ordinal >= program.functions.length) {
				fail ("async frame", "requires unique exact program-owned body membership in declaration order");
			}
			task_frames[frame.function_ordinal] = true;
			var callable = program.functions[frame.function_ordinal].async_callable;
			if (callable == null || callable.provider != frame.provider) {
				fail ("async frame provider", "lost exact declaration-only callable admission authority");
			}
			for (uint w = 0; w < frame.wait_count; w++) {
				if (frame.wait (w).bridge_definition >= 0 && !callable.composable) {
					fail ("bridge frame", "requires its explicit versioned composition effect");
				}
			}
			var signature = program.functions[frame.function_ordinal].signature;
			if (NativeAsyncFramePlan.record_identity (frame.record_result) != NativeAsyncFramePlan.record_identity (signature.struct_result)) {
				fail ("async record success", "frame result differs from the exact declared carrier and field cleanup contract");
			}
			var captured = new HashTable<int, bool> (direct_hash, direct_equal);
			for (uint o = 0; o < frame.owner_count; o++) {
				var owner = frame.owner (o);
				if (owner.closure != null) {
					verify_callable_records (owner.closure, program);
					NativeClassPlan? environment = null;
					foreach (var candidate in program.classes) {
						if (candidate.name == owner.closure.environment) {
							environment = candidate;
						}
					}
					if (environment == null || environment.polymorphic || environment.is_interface) {
						fail ("async closure owner", "requires its exact concrete environment declaration");
					}
				}
				if (owner.capture_first_leaf < 0) {
					continue;
				}
				int ordinal = owner.capture_first_leaf;
				if (ordinal >= signature.parameters.length || captured.contains (ordinal)) {
					fail ("async frame capture", "requires one exact incoming owner parameter");
				}
				captured.insert (ordinal, true);
				var parameter = signature.parameters[ordinal];
				var closure_parameter = parameter.abi_type as NativeClosureHandleType;
				var context_parameter = parameter.abi_type as NativeContextHandleType;
				if (owner.context == null ? context_parameter != null : context_parameter == null || !owner.context.same_type (context_parameter) || owner.cleanup_symbol != owner.context.cleanup) {
					fail ("async frame capture", "allocator context differs from its exact nominal lifetime/thread/release ABI");
				}
				if (owner.closure == null ? closure_parameter != null : closure_parameter == null || !owner.closure.same_type (closure_parameter)) {
					fail ("async frame capture", "closure owner differs from its complete incoming callable signature");
				}
				var origin = parameter.object_origin;
				if (origin == null && owner.class_ordinal >= 0 && owner.record_rank >= 0) {
					int matches = 0;
					foreach (var group in signature.struct_parameters) {
						int leaf = ordinal - group.first_leaf;
						if (group.mode != NativeStructValueMode.MOVE_VALUE || leaf < 0 || leaf >= group.value_plan.leaves.length) {
							continue;
						}
						foreach (var field in group.value_plan.ownership) {
							if (field.field_path == group.value_plan.leaves[leaf].storage_path && field.cleanup_class_ordinal == owner.class_ordinal && field.cleanup_class_ordinal < program.classes.length && field.type_name == program.classes[field.cleanup_class_ordinal].name && field.cleanup_symbol == "" && field.buffer_cleanup == null) {
								matches++;
								origin = new NativeObjectOriginPlan (field.cleanup_class_ordinal, field.type_name, true);
							}
						}
					}
					if (matches != 1) {
						fail ("async record capture", "Class field requires its unique complete incoming record cleanup authority");
					}
				}
				if ((origin != null || owner.class_ordinal >= 0) && (origin == null || !origin.heap || owner.class_ordinal < 0 || owner.class_ordinal >= program.classes.length || origin.class_ordinal != owner.class_ordinal || origin.class_name != program.classes[owner.class_ordinal].name || owner.cleanup_symbol != "")) {
					fail ("async frame capture", "Class cleanup differs from its exact independently heap-owned parameter");
				}
			}
			// Independent completeness: a detached frame may neither duplicate
			// nor omit the ownership promised by its physical input signature.
			for (int p = 0; p < signature.parameters.length; p++) {
				var parameter = signature.parameters[p];
				bool requires_owner = parameter.owns_resource || parameter.object_origin != null && parameter.object_origin.heap;
				foreach (var group in signature.struct_parameters) {
					if (group.mode != NativeStructValueMode.MOVE_VALUE) {
						continue;
					}
					int leaf = p - group.first_leaf;
					if (leaf < 0 || leaf >= group.value_plan.leaves.length) {
						continue;
					}
					foreach (var resource in group.value_plan.ownership) {
						if (resource.field_path == group.value_plan.leaves[leaf].storage_path && resource.buffer_cleanup == null && (resource.cleanup_class_ordinal >= 0 || resource.cleanup_symbol != "")) {
							requires_owner = true;
						}
					}
				}
				if (requires_owner && !captured.contains (p)) {
					fail ("async frame capture", "missing original incoming owner obligation");
				}
			}
			prior_async = frame.function_ordinal;
		}
		for (int f = 0; f < program.functions.length; f++) {
			var task = program.functions[f].async_callable;
			if (task_frames[f] != (task != null && !task.imported)) {
				fail ("async frame inventory", "local tasks require one frame; imported task factories carry no substitute frame");
			}
		}
		NativeSumVerifier.verify (program);
		NativeClassVerifier.verify (program);
		foreach (var function in program.functions) {
			bool required = NativeConstructorUnwindPlan.required (program, function);
			if (required != (function.constructor_unwind != null) || required && !function.constructor_unwind.valid (program, function)) {
				fail ("constructor unwind", "lost its independent complete native field/cache retirement authority");
			}
		}
		if (!program.pod_layouts_valid ()) {
			fail ("POD representation", "record lost its admitted C storage layout");
		}
		if (!program.c_bool_policies_valid ()) {
			fail ("C99 bool", "lost admitted foreign boolean policy inventory");
		}
		var pod_names = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var policy in program.pod_layouts) {
			if (!policy.valid () || pod_names.contains (policy.name)) {
				fail ("POD representation", "invalid or duplicate natural scalar C layout");
			}
			pod_names.insert (policy.name, true);
		}
		foreach (var function in program.functions) {
			if (!function.scoped_readonly_valid ()) {
				fail ("readonly native effect", "lost its original checked definition contract");
			}
			if (function.callback_input_count < 0 ||
			    !Astra.Code.CodeInputSet.valid (function.readonly_inputs, function.callback_input_count) ||
			    !Astra.Code.CodeInputSet.valid (function.callback_inputs, function.callback_input_count) ||
			    !function.scoped_readonly && function.readonly_inputs != "" ||
			    !function.callback_contract_supported && function.callback_inputs != "") {
				fail ("native callback inputs", "require canonical direct Fn input ordinals and original eligibility");
			}

			if (!function.async_callable_valid ()) {
				fail ("async callable", "lost original task declaration, runtime, result or capture channels");
			}
			var scoped_result = function.signature.result == null ? null : function.signature.result.abi_type as NativeContextHandleType;
			if (scoped_result != null && scoped_result.mode == "scoped-affine") {
				fail ("scoped context", "cannot escape through a native result");
			}
			foreach (var parameter in function.signature.parameters) {
				var context = parameter.abi_type as NativeContextHandleType;
				if (context != null && context.mode == "scoped-affine" && (parameter.owns_resource || function.async_callable != null)) {
					fail ("scoped context", "requires a synchronous nonescaping borrowed native parameter");
				}
			}
			if (!function.scoped_backings_valid () || function.scoped_backings.length != 0 && function.async_callable != null) {
				fail ("scoped backing", "lost original synchronous lexical backing authority");
			}
			if (!function.allocation_sites_valid ()) {
				fail ("allocation sites", "admitted null-construction authority was altered");
			}
			if (!function.frame_admissions_valid ()) {
				fail ("checked frame admissions", "original checked factory or caller input authority was altered");
			}
			foreach (var site in function.frame_admissions) {
				if (site.factory_ordinal >= program.functions.length || program.functions[site.factory_ordinal].async_callable == null || program.functions[site.factory_ordinal].async_callable.runtime_error == "") {
					fail ("checked frame admissions", "missing exact factory and nominated runtime Error contract");
				}
				var signature = program.functions[site.factory_ordinal].signature;
				var sources = new HashTable<int, bool> (direct_hash, direct_equal);
				foreach (var input in site.inputs) {
					if (input.parameter_ordinal >= signature.parameters.length) {
						fail ("checked frame admissions", "input ordinal is outside its physical factory signature");
					}
					var parameter = signature.parameters[input.parameter_ordinal];
					if (input.source_ordinal >= 0 && !sources.insert (input.source_ordinal, true) || input.class_ordinal >= 0 && (parameter.object_origin == null || parameter.object_origin.class_ordinal != input.class_ordinal || parameter.object_origin.heap != input.heap) || input.class_ordinal < 0 && (parameter.resource == null || !parameter.owns_resource || parameter.resource.type_name != input.resource_name || parameter.resource.cleanup_symbol != input.cleanup_symbol)) {
						fail ("checked frame admissions", "capture restoration changed exact caller or factory ownership channels");
					}
				}
				if (site.buffers.length != signature.buffer_parameters.length) {
					fail ("checked frame admissions", "missing conditional buffer capture plans");
				}
				for (int b = 0; b < site.buffers.length; b++) {
					var input = site.buffers[b];
					var parameter = signature.buffer_parameters[b];
					if (input.first_leaf != parameter.first_leaf || input.value_plan.element_spelling () != parameter.value_plan.element_spelling () || !sources.insert (input.source_ordinal, true)) {
						fail ("checked frame admissions", "conditional buffer restoration changed exact factory pair or original caller storage");
					}
				}
				int record_index = 0;
				foreach (var parameter in signature.struct_parameters) {
					if (parameter.mode != NativeStructValueMode.MOVE_VALUE) {
						continue;
					}
					if (record_index >= site.records.length) {
						fail ("checked frame admissions", "missing complete conditional record restoration plan");
					}
					var input = site.records[record_index++];
					if (input.first_leaf != parameter.first_leaf || NativeAsyncFramePlan.record_identity (input.value_plan) != NativeAsyncFramePlan.record_identity (parameter.value_plan) || !sources.insert (input.source_ordinal, true)) {
						fail ("checked frame admissions", "conditional record restoration changed exact factory carrier or caller ownership graph");
					}
				}
				if (record_index != site.records.length) {
					fail ("checked frame admissions", "unrelated conditional record restoration plan");
				}
			}
			var sites = new HashTable<int, bool> (direct_hash, direct_equal);
			foreach (var site in function.allocation_sites) {
				if (!site.valid () || !site.heap || !site.fallible || site.class_ordinal >= program.classes.length || site.constructor_ordinal >= program.functions.length || sites.contains (site.storage_ordinal)) {
					fail ("allocation site", "requires exact unique heap storage, constructor and nullable admission");
				}
				sites.insert (site.storage_ordinal, true);
				var owner = program.classes[site.class_ordinal];
				var constructor = program.functions[site.constructor_ordinal];
				if (owner.allocation_policy == null || constructor.kind != NativeCallableKind.CONSTRUCTOR || !constructor.declaring_type_is_class || constructor.declaring_type_ordinal != owner.ordinal || constructor.signature.exception_plan != null && (constructor.constructor_unwind == null || !constructor.constructor_unwind.valid (program, constructor))) {
					fail ("allocation site", "requires exact policy-owned constructor and checked partial-retirement authority");
				}
				int restored = 0;
				var sources = new HashTable<int, bool> (direct_hash, direct_equal);
				foreach (var parameter in constructor.signature.parameters) {
					bool record = false;
					foreach (var group in constructor.signature.struct_parameters) {
						if (parameter.ordinal >= group.first_leaf && parameter.ordinal < group.first_leaf + group.value_plan.leaves.length) {
							if (group.mode == NativeStructValueMode.BORROW_VALUE) {
								fail ("allocation site", "record constructor input lacks copied or owning complete value authority");
							}
							record = true;
						}
					}
					if (record) {
						continue;
					}
					bool buffer = false;
					foreach (var group in constructor.signature.buffer_parameters) {
						if (parameter.ordinal == group.first_leaf || parameter.ordinal == group.first_leaf + 1) {
							buffer = true;
						}
					}
					if (buffer) {
						continue;
					}
					bool owning = parameter.object_origin != null || parameter.resource != null && parameter.owns_resource;
					if (owning) {
						if (restored >= site.inputs.length) {
							fail ("allocation site", "missing ownership-preserving constructor input plan");
						}
						var input = site.inputs[restored++];
						if (input.parameter_ordinal != parameter.ordinal || input.source_ordinal >= 0 && !sources.insert (input.source_ordinal, true) || (parameter.object_origin != null ? input.class_ordinal != parameter.object_origin.class_ordinal || input.heap != parameter.object_origin.heap || input.resource_name != "" || input.cleanup_symbol != "" : input.class_ordinal != -1 || input.heap || input.resource_name != parameter.resource.type_name || input.cleanup_symbol != parameter.resource.cleanup_symbol)) {
							fail ("allocation site", "input restoration changed its exact nullable caller, nominal type or cleanup origin");
						}
					} else if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type == NativeScalarType.PTR) {
						fail ("allocation site", "nullable admission requires numeric or exact owning Class/Resource inputs");
					}
				}
				if (restored != site.inputs.length) {
					fail ("allocation site", "unrelated input restoration plan");
				}
				int record_index = 0;
				foreach (var parameter in constructor.signature.struct_parameters) {
					if (parameter.mode != NativeStructValueMode.MOVE_VALUE) {
						continue;
					}
					if (record_index >= site.records.length) {
						fail ("allocation site", "missing complete conditional record capture plan");
					}
					var input = site.records[record_index++];
					if (input.first_leaf != parameter.first_leaf || NativeAsyncFramePlan.record_identity (input.value_plan) != NativeAsyncFramePlan.record_identity (parameter.value_plan) || !sources.insert (input.source_ordinal, true)) {
						fail ("allocation site", "conditional record restoration changed exact constructor carrier or original caller graph");
					}
				}
				if (record_index != site.records.length) {
					fail ("allocation site", "unrelated conditional record capture plan");
				}
				if (site.buffers.length != constructor.signature.buffer_parameters.length) {
					fail ("allocation site", "missing complete conditional buffer capture plans");
				}
				for (int b = 0; b < site.buffers.length; b++) {
					var input = site.buffers[b];
					var parameter = constructor.signature.buffer_parameters[b];
					if (input.first_leaf != parameter.first_leaf || input.value_plan.element_spelling () != parameter.value_plan.element_spelling () || !sources.insert (input.source_ordinal, true)) {
						fail ("allocation site", "conditional buffer restoration changed exact constructor pair or original caller storage");
					}
				}
			}
		}
		verify_record_declarations (program);
		foreach (var function in program.functions) {
			var locals = new HashTable<int, bool> (direct_hash, direct_equal);
			foreach (var owner in function.record_owners) {
				if (owner.declaration == null || !program.record_declarations.find (owner.declaration) || owner.declaration.name != owner.record_name) {
					fail ("record obligations", "local owner requires its exact program-owned nominal declaration");
				}
				verify_declared_fields (owner.fields, owner.declaration);
				if (owner.source_ordinal < 0 || owner.record_name == "" || locals.contains (owner.source_ordinal) || owner.fields.length == 0 || owner.fields.length != owner.obligations.length) {
					fail ("record obligations", "requires complete distinct local field obligations without aggregate transport");
				}
				locals.insert (owner.source_ordinal, true);
				NativeRecordResource? previous = null;
				foreach (var field in owner.fields) {
					if (field.depth == 0) {
						fail ("record obligations", "requires a nonempty full storage path");
					}
					for (int i = 0; i < field.depth; i++) {
						if (field.path_ordinal (i) < 0) {
							fail ("record obligations", "negative field ordinal");
						}
					}
					if (previous != null && (previous.compare_path (field) >= 0 || field.field_path.has_prefix (previous.field_path + "."))) {
						fail ("record obligations", "requires distinct leaf paths in declaration order");
					}
					verify_record_cleanup (field, program);
					previous = field;
				}
				var seen = new HashTable<string, bool> (str_hash, str_equal);
				var ranks = new HashTable<int, bool> (direct_hash, direct_equal);
				foreach (var obligation in owner.obligations) {
					verify_record_cleanup (obligation, program);
					bool matched = false;
					foreach (var field in owner.fields) {
						if (obligation.compare_path (field) == 0 && obligation.type_name == field.type_name && obligation.same_cleanup (field)) {
							matched = true;
						}
					}
					if (!matched || seen.contains (obligation.field_path) || obligation.acquisition_rank < 0 || obligation.acquisition_rank >= owner.fields.length || ranks.contains (obligation.acquisition_rank)) {
						fail ("record obligations", "missing, duplicate or mismatched field cleanup responsibility");
					}
					seen.insert (obligation.field_path, true);
					ranks.insert (obligation.acquisition_rank, true);
				}
			}
		}
		var continuation_ids = new HashTable<Astra.Continuations.ContinuationIdentity, bool> (direct_hash, direct_equal);
		foreach (var plan in program.continuations) {
			plan.verify ();
			if (continuation_ids.contains (plan.identity) || plan.function_ordinal >= program.functions.length) {
				fail ("continuations", "duplicate or stale region membership");
			}
			continuation_ids.insert (plan.identity, true);
			foreach (var family in plan.families) {
				foreach (var entry in family.entries) {
					if (entry.target_ordinal >= program.functions.length || entry.body_signature != program.functions[entry.target_ordinal].signature) {
						fail ("continuations", "stale code/signature membership");
					}
				}
			}
		}
		if (program.abi_version != NativeAbiVersion.SCALAR_V0 && program.abi_version != NativeAbiVersion.SCALAR_PTR_V1 && program.abi_version != NativeAbiVersion.SCALAR_INT_V2 && program.abi_version != NativeAbiVersion.SCALAR_FP_V3 && program.abi_version != NativeAbiVersion.VECTOR_V4 && program.abi_version != NativeAbiVersion.SLICE_V5 && program.abi_version != NativeAbiVersion.FP64_V6 && (program.abi_version != NativeAbiVersion.AGGREGATE_V7 && program.abi_version != NativeAbiVersion.BUFFER_V8 && program.abi_version != NativeAbiVersion.TEXT_V9 && program.abi_version != NativeAbiVersion.TEXT_SLICE_V10 && program.abi_version != NativeAbiVersion.STRUCT_ELEMENTS_V11 && program.abi_version != NativeAbiVersion.SUM_VALUES_V12 && program.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && program.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && program.abi_version != NativeAbiVersion.OWNER_SLOTS_V15)) {
			fail ("program", "unsupported native ABI version");
		}
		var records = new HashTable<NativeRecordElement, bool> (direct_hash, direct_equal);
		var record_ordinals = new HashTable<int, bool> (direct_hash, direct_equal);
		int prior_record = -1;
		foreach (var record in program.record_elements) {
			if (program.abi_version != NativeAbiVersion.STRUCT_ELEMENTS_V11 && program.abi_version != NativeAbiVersion.SUM_VALUES_V12 && program.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && program.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && program.abi_version != NativeAbiVersion.OWNER_SLOTS_V15 || record.struct_ordinal <= prior_record || record.struct_name == "" || records.contains (record) || record_ordinals.contains (record.struct_ordinal)) {
				fail ("record-element", "record storage plans require unique exact declaration identities in source order");
			}
			records.insert (record, true);
			record_ordinals.insert (record.struct_ordinal, true);
			prior_record = record.struct_ordinal;
		}
		var visited_records = new HashTable<NativeRecordElement, bool> (direct_hash, direct_equal);
		foreach (var record in program.record_elements) {
			verify_record_element (record, records, visited_records);
		}
		var plans = new HashTable<NativeStructValuePlan, bool> (direct_hash, direct_equal);
		int previous_struct = -1;
		foreach (var plan in program.struct_values) {
			if ((program.abi_version != NativeAbiVersion.AGGREGATE_V7 && program.abi_version != NativeAbiVersion.BUFFER_V8 && program.abi_version != NativeAbiVersion.TEXT_V9 && program.abi_version != NativeAbiVersion.TEXT_SLICE_V10 && program.abi_version != NativeAbiVersion.STRUCT_ELEMENTS_V11 && program.abi_version != NativeAbiVersion.SUM_VALUES_V12 && program.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && program.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && program.abi_version != NativeAbiVersion.OWNER_SLOTS_V15) || plans.contains (plan) || plan.struct_ordinal <= previous_struct || plan.struct_name == "") {
				fail ("struct-plan", "aggregate-v7 plans require exact unique source declaration identity in order");
			}
			verify_struct_plan (plan, program.abi_version);
			if (plan.foreign_record != null && !NativeForeignApi.record (program, plan, plan.foreign_record)) {
				fail ("foreign record", "lost exact nominal declaration or copied scalar leaf order");
			}
			if (plan.mode == NativeStructValueMode.MOVE_VALUE) {
				if (plan.declaration == null || !program.record_declarations.find (plan.declaration) || plan.declaration.struct_ordinal != plan.struct_ordinal || plan.declaration.name != plan.struct_name) {
					fail ("struct-plan", "MOVE_VALUE requires its exact program-owned nominal cleanup declaration");
				}
				verify_declared_fields (plan.ownership, plan.declaration);
			} else if (plan.declaration != null) {
				fail ("struct-plan", "COPY_VALUE cannot acquire a record cleanup declaration");
			}
			foreach (var owner in plan.ownership) {
				verify_record_cleanup (owner, program);
			}
			plans.insert (plan, true);
			previous_struct = plan.struct_ordinal;
		}
		var methods = new HashTable<string, bool> (str_hash, str_equal);
		var functions = new HashTable<NativeFunction, NativeFunction> (direct_hash, direct_equal);
		for (int f = 0; f < program.functions.length; f++) {
			var function = program.functions[f];
			string path = "function #%d".printf (f);
			if (functions.contains (function) || function.ordinal != f) {
				fail (path, "function identity/ordinal must be unique and in source order");
			}
			functions.insert (function, function);
			if (function.owner != program) {
				fail (path, "function is not owned by the containing program");
			}
			if (function.linkage != NativeLinkage.NATIVE_INTERNAL) {
				fail (path, "unsupported native linkage");
			}
			var signature = function.signature;
			if (signature == null) {
				fail (path + "/signature", "missing native signature");
				return;
			}
			verify_record_uses (signature, records);
			verify_struct_groups (signature, plans, path);
			verify_readonly_channels (function);
			var origins = new GenericArray<NativeObjectOriginPlan> ();
			if (signature.heap_result != null) {
				origins.add (signature.heap_result);
			}
			foreach (var parameter in signature.parameters) {
				if (parameter.object_origin != null) {
					if (!(parameter.abi_type is NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR) {
						fail (path, "object origin requires an owned pointer parameter");
					}
					origins.add (parameter.object_origin);
				}
			}
			foreach (var origin in origins) {
				if (origin.class_ordinal < 0 || origin.class_ordinal >= program.classes.length || program.classes[origin.class_ordinal].name != origin.class_name) {
					fail (path, "object origin requires its exact independent class declaration");
				}
			}
			if (signature.buffer_result != null) {
				verify_buffer_plan (signature.buffer_result, signature.abi_version, path);
				if (signature.result != null || signature.struct_result != null || signature.object_result != null || function.kind == NativeCallableKind.CONSTRUCTOR || function.kind == NativeCallableKind.DESTRUCTOR || function.kind == NativeCallableKind.PROPERTY_GETTER || function.kind == NativeCallableKind.PROPERTY_SETTER) {
					fail (path, "buffer owner result requires one complete group and no unrelated result contract");
				}
			}
			if (signature.object_result != null) {
				var plan = signature.object_result;
				if (plan.object_origin != null) {
					var origin = plan.object_origin;
					if (origin.heap || origin.class_ordinal < 0 || origin.class_ordinal >= program.classes.length || program.classes[origin.class_ordinal].name != origin.class_name) {
						fail (path, "caller-backed result requires its exact lexical Class storage origin");
					}
				}
				if (plan.candidate_storage.scalar_type != NativeScalarType.PTR || plan.owner_result.scalar_type != NativeScalarType.PTR || signature.result == null || !signature.result.abi_type.same_type (plan.owner_result)) {
					fail (path, "owned object result requires hidden candidate PTR and returned owner PTR");
				}
				verify_scalar (plan.candidate_storage.scalar_type, program.abi_version, path + "/result-storage");
			}
			if (function.receiver_borrow && (function.kind != NativeCallableKind.PROPERTY_GETTER || !function.declaring_type_is_class || signature.receiver == null || (signature.struct_result == null ? signature.result == null || !(signature.result.abi_type is NativeScalarAbiType) || signature.result.scalar_type != NativeScalarType.PTR : signature.struct_result_mode != NativeStructValueMode.BORROW_VALUE || signature.result != null) || signature.object_result != null || signature.heap_result != null || (signature.exception_plan != null && (function.lazy_cache == null || !function.lazy_cache.is_owned)) || function.virtual_slot >= 0)) {
				fail (path, "receiver borrow requires one direct nonowning Class property getter PTR result");
			}
			if (signature.struct_result != null && (signature.struct_result_mode == NativeStructValueMode.BORROW_VALUE) != function.receiver_borrow) {
				fail (path, "bounded record result requires the exact receiver-borrow authority");
			}
			var observation = function.record_observation;
			if (!function.matches_record_observation () || (observation != null) != (signature.struct_result != null && signature.struct_result_mode == NativeStructValueMode.BORROW_VALUE)) {
				fail (path, "record observation lost its original exact receiver-field binding");
			}
			if (observation != null) {
				if (observation.class_ordinal != function.declaring_type_ordinal || observation.class_ordinal < 0 || observation.class_ordinal >= program.classes.length) {
					fail (path, "record observation requires its exact containing Class");
				}
				var owner = program.classes[observation.class_ordinal];
				if (observation.field_ordinal < 0 || observation.field_ordinal >= owner.fields.length) {
					fail (path, "record observation field lies outside its receiver declaration");
				}
				var field = owner.fields[observation.field_ordinal];
				if (!field.owns_record || field.record_ordinal != observation.value_plan.struct_ordinal || observation.value_plan != signature.struct_result || field.type_name != observation.value_plan.struct_name) {
					fail (path, "record observation must retain its receiver's complete exact owned field graph");
				}
			}
			bool accessor = function.kind == NativeCallableKind.PROPERTY_GETTER || function.kind == NativeCallableKind.PROPERTY_SETTER;
			if (accessor) {
				bool getter = function.kind == NativeCallableKind.PROPERTY_GETTER;
				bool record_getter = getter && signature.struct_result != null;
				bool record_setter = !getter && signature.struct_parameters.length == 1;
				if (record_getter && (signature.struct_result_mode != (function.receiver_borrow ? NativeStructValueMode.BORROW_VALUE : NativeStructValueMode.COPY_VALUE) || signature.struct_parameters.length != 0 || signature.result != null) || record_setter && (signature.struct_parameters[0].source_ordinal != 0 || signature.struct_parameters[0].first_leaf != 0 || signature.struct_parameters[0].value_plan.mode != NativeStructValueMode.COPY_VALUE || signature.struct_result != null)) {
					fail (path, "record accessor requires one complete copied value channel");
				}
				int parameters = record_setter ? (int) signature.struct_parameters[0].value_plan.leaves.length : getter ? 0 : 1;
				if (signature.receiver == null || signature.receiver.scalar_type != NativeScalarType.PTR || function.declaring_type_ordinal < 0 || function.property_ordinal < 0 || function.method_ordinal != -1 || signature.object_result != null || signature.parameters.length != parameters || (getter ? signature.result == null && !record_getter : signature.result != null)) {
					fail (path, "accessor requires property identity, receiver PTR and exact getter/setter shape");
				}
				if (!getter && (signature.parameters[0].abi_type is NativeTextType || signature.parameters[0].abi_type is NativeSliceType)) {
					fail (path, "slice property values are unsupported");
				}
			} else if (function.property_ordinal != -1) {
				fail (path, "only accessors carry property ordinals");
			}
			if ((function.kind == NativeCallableKind.CONSTRUCTOR || function.kind == NativeCallableKind.DESTRUCTOR) && signature.struct_result != null) {
				fail (path, "lifecycle cannot return a struct");
			}
			if (signature.receiver != null) {
				if (!accessor && (signature.receiver.scalar_type != NativeScalarType.PTR || function.declaring_type_ordinal < 0 || (function.kind == NativeCallableKind.METHOD ? function.method_ordinal < 0 : function.method_ordinal != -1 || !function.declaring_type_is_class || signature.result != null || (function.kind != NativeCallableKind.CONSTRUCTOR && function.kind != NativeCallableKind.DESTRUCTOR) || (function.kind == NativeCallableKind.DESTRUCTOR && signature.parameters.length != 0)))) {
					fail (path, "method requires receiver PTR and compiler-owned member ordinals");
				}
				string key = "%d.%s.%d.%d".printf ((int) function.kind, function.declaring_type_is_class ? "class" : "struct", function.declaring_type_ordinal, accessor ? function.property_ordinal : function.method_ordinal);
				if (methods.contains (key)) {
					fail (path, "method physical identity must be unique");
				}
				methods.insert (key, true);
				verify_scalar (signature.receiver.scalar_type, program.abi_version, path + "/receiver");
			} else if (function.kind != NativeCallableKind.FUNCTION || function.declaring_type_ordinal != -1 || function.method_ordinal != -1 || function.declaring_type_is_class) {
				fail (path, "free function cannot carry method ordinals");
			}
			if (signature.abi_version != program.abi_version && (program.abi_version != NativeAbiVersion.TEXT_V9 && program.abi_version != NativeAbiVersion.TEXT_SLICE_V10 && program.abi_version != NativeAbiVersion.STRUCT_ELEMENTS_V11 && program.abi_version != NativeAbiVersion.SUM_VALUES_V12 && program.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && program.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && program.abi_version != NativeAbiVersion.OWNER_SLOTS_V15 || signature.abi_version < NativeAbiVersion.SCALAR_V0 || signature.abi_version > program.abi_version)) {
				fail (path + "/signature", "signature ABI version must match the program");
			}
			verify_signature_channels (signature, path);
			if (signature.result != null) {
				if (signature.result.abi_type is NativeTextType && (((NativeTextType) signature.result.abi_type).contract == NativeTextContract.RECEIVER_TEXT ? signature.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || function.kind != NativeCallableKind.PROPERTY_GETTER || !function.declaring_type_is_class || signature.receiver == null : ((NativeTextType) signature.result.abi_type).contract != NativeTextContract.STATIC_TEXT || accessor)) {
					fail (path, "text result requires static-text native function or method");
				}
			}
		}
		foreach (var setter in program.functions) {
			if (setter.kind != NativeCallableKind.PROPERTY_SETTER) {
				continue;
			}
			NativeFunction? getter = null;
			foreach (var candidate in program.functions) {
				if (candidate.kind == NativeCallableKind.PROPERTY_GETTER && candidate.declaring_type_is_class == setter.declaring_type_is_class && candidate.declaring_type_ordinal == setter.declaring_type_ordinal && candidate.property_ordinal == setter.property_ordinal) {
					getter = candidate;
				}
			}
			if (setter.signature.struct_parameters.length != 0) {
				if (getter == null || getter.signature.struct_result != setter.signature.struct_parameters[0].value_plan || getter.signature.result != null) {
					fail ("property", "record getter and setter require the same complete copied value plan");
				}
				continue;
			}
			if (getter == null || !getter.signature.result.abi_type.same_type (setter.signature.parameters[0].abi_type)) {
				fail ("accessors", "setter requires the exact property's getter and matching value channel");
			}
		}
	}
}
}
