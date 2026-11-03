// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Backend.LLVM {
internal class LlvmSlotsLayoutBinding : Object {
	private CApi.TypeRef descriptor;
	private CApi.TypeRef slot;
	internal LlvmSlotsLayoutBinding (CApi.TypeRef descriptor, CApi.TypeRef slot) {
		this.descriptor = descriptor;
		this.slot = slot;
	}

	internal void verify(CApi.TargetDataRef data) throws LlvmError {
		if (CApi.abi_size_of_type (data, descriptor) != 16 || CApi.abi_alignment_of_type (data, descriptor) != 8 || CApi.offset_of_element (data, descriptor, 0) != 0 || CApi.offset_of_element (data, descriptor, 1) != 8 || CApi.offset_of_element (data, descriptor, 2) != 12 || CApi.abi_size_of_type (data, slot) != 8 || CApi.abi_alignment_of_type (data, slot) != 8) {
			throw new LlvmError.VERIFICATION ("owner-slot descriptor/element lost qualified LP64 extent, stride or alignment");
		}
	}

}

// Private per-exact-Class operations. All arguments and complete bodies are
// bound to the verified SSA operations; no source/IR graph survives lowering.
internal class LlvmSlotsLowering : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private HashTable<SsaFunction, LlvmFunctionBinding> functions;
	private LlvmClassRuntime classes;
	private HashTable<SsaCleanupContract, Astra.CAbi.CAbiCleanupFunction> cleanup_correspondence;
	private HashTable<Astra.CAbi.CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions;
	internal LlvmSlotsLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types, HashTable<SsaFunction, LlvmFunctionBinding> functions, HashTable<SsaCleanupContract, Astra.CAbi.CAbiCleanupFunction> cleanup_correspondence, HashTable<Astra.CAbi.CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions, LlvmClassRuntime classes) {
		this.classes = classes;
		this.artifact = artifact;
		this.types = types;
		this.functions = functions;
		this.cleanup_correspondence = cleanup_correspondence;
		this.cleanup_functions = cleanup_functions;
	}

	internal CApi.ValueRef invoke(CApi.BuilderRef caller, SsaStructField field, string action, CApi.ValueRef[] arguments, string name, CApi.ValueRef receiver = (CApi.ValueRef) null) throws LlvmError {
		CApi.ValueRef[] call_arguments = arguments;
		var element = field.semantic_type as OwnerSlotsType;
		var cleanup = field.slots_cleanup;
		var record = classes.slot_record (field);
		if (element == null || (cleanup == null && record == null)) {
			throw new LlvmError.INVALID_INPUT ("owner-slot operation lost its element and cleanup declaration");
		}
		bool valid = record != null && cleanup == null && element.element is StructType && record.struct_name == element.element.display_name ();
		if (cleanup != null) {
			valid = record == null && element.element.get_type () == typeof (HandleType) && !cleanup.is_object && !cleanup.is_buffer && cleanup.external_symbol != "";
			if (element.element is ClassType) {
				valid = record == null && cleanup.is_heap_object && cleanup.object_class.semantic_type == element.element;
			}
		}
		if (!valid) {
			throw new LlvmError.INVALID_INPUT ("owner-slot operation lost exact nominal field/element authority");
		}
		var container = field.containing_type as SsaClass;
		if (action == "reserve" && container != null && container.allocation_policy != null && container.allocation_policy.kind == Astra.Source.AllocationKind.CONTEXT) {
			if ((void*) receiver == null) {
				throw new LlvmError.LOWERING ("context container growth lost its live receiver origin");
			}
			var extended = new CApi.ValueRef[arguments.length + 1];
			for (int i = 0; i < arguments.length; i++) {
				extended[i] = arguments[i];
			}
			extended[arguments.length] = new LlvmPolicyAllocation (artifact).origin (caller, receiver, container.name);
			call_arguments = (owned) extended;
		}
		var target = helper (cleanup, record, action, container);
		var signature = CApi.global_value_type (target);
		var call = CApi.build_call (caller, signature, target, call_arguments, call_arguments.length, name);
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, signature, call_arguments, LlvmLowering.CALL_CONVENTION, "exact owner-slot " + action));
		return call;
	}

	private CApi.TypeRef record_tuple(NativeStructValuePlan record) throws LlvmError {
		var fields = new CApi.TypeRef[record.leaves.length];
		for (int l = 0; l < fields.length; l++) {
			fields[l] = types.abi_type (record.leaves[l].abi_type);
		}
		return CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
	}

	internal CApi.TypeRef record_type(SsaStructField field) throws LlvmError {
		var record = classes.slot_record (field);
		if (record == null) {
			throw new LlvmError.LOWERING ("record slot operation requires its exact complete value layout");
		}
		return record_tuple (record);
	}

	private CApi.ValueRef member(CApi.BuilderRef builder, CApi.ValueRef descriptor, uint index, string name) {
		var address = CApi.build_struct_gep (builder, types.owner_slots_descriptor (), descriptor, index, name);
		artifact.class_addresses.add (new LlvmClassAddressBinding (address, descriptor, types.owner_slots_descriptor (), index));
		return address;
	}

	private CApi.ValueRef slot_address(CApi.BuilderRef builder, CApi.TypeRef element_type, CApi.ValueRef backing, CApi.ValueRef index, string name) throws LlvmError {
		CApi.ValueRef[] indices = {
			index
		};
		return CApi.build_gep (builder, element_type, backing, indices, 1, name);
	}

	private CApi.BasicBlockRef block(CApi.ValueRef function, string name) {
		return CApi.append_basic_block_in_context (artifact.context, function, name);
	}

	private void destroy_resource(CApi.BuilderRef builder, CApi.ValueRef function, SsaCleanupContract cleanup, CApi.ValueRef value, LlvmBlockState state) throws LlvmError {
		var foreign = cleanup_functions.lookup (cleanup_correspondence.lookup (cleanup));
		if (foreign == null) {
			throw new LlvmError.INVALID_INPUT ("owner-slot Resource lost its original declared destructor binding");
		}
		var dispose = block (function, "slots.resource.dispose");
		var next = block (function, "slots.resource.done");
		var empty = CApi.build_icmp (builder, CApi.IntPredicate.EQ, value, CApi.const_null (types.scalar (NativeScalarType.PTR)), "slots.resource.null");
		CApi.build_cond_br (builder, empty, next, dispose);
		CApi.position_builder_at_end (builder, dispose);
		var arguments = new CApi.ValueRef[] {
			value
		};
		var call = CApi.build_call (builder, foreign.type, foreign.value, arguments, 1, "");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		foreign.calls.add ((void*) call);
		artifact.class_calls.add (new LlvmClassCallBinding (call, foreign.value, foreign.type, arguments, CApi.CallConv.C, "owner-slot exact Resource destructor"));
		CApi.build_br (builder, next);
		CApi.position_builder_at_end (builder, next);
		state.end = next;
	}

	private void destroy_record(CApi.BuilderRef builder, CApi.ValueRef function, LlvmBufferAllocation allocator, NativeStructValuePlan plan, CApi.ValueRef value, LlvmBlockState state, string name) throws LlvmError {
		var leaves = new CApi.ValueRef[plan.leaves.length];
		for (int l = 0; l < leaves.length; l++) {
			leaves[l] = CApi.build_extract_value (builder, value, (uint) l, name + ".leaf%d".printf (l));
		}
		new LlvmRecordOwnership (artifact, types, classes, cleanup_correspondence, cleanup_functions).destroy_record (builder, function, allocator, plan, leaves, state, name);
	}

	private CApi.ValueRef helper(SsaCleanupContract? cleanup, NativeStructValuePlan? record, string action, SsaClass? container) throws LlvmError {
		var element = cleanup == null ? null : cleanup.object_class;
		bool heap = cleanup != null && cleanup.is_heap_object;
		var policy = container == null ? null : container.allocation_policy;
		string container_name = container == null ? "" : container.name;
		string name = record != null ? "astra.slots.record.%d.%s".printf (record.struct_ordinal, action) : heap ? "astra.slots.%d.%s".printf (element.ordinal, action) : "astra.slots.resource.%d.%s".printf (cleanup.ordinal, action);
		if (policy != null) {
			name += ".domain." + policy.identity + ".owner.%d".printf (container.ordinal);
		}
		var prior = CApi.named_function (artifact.module, name);
		if ((void*) prior != null) {
			if (artifact.slots_helpers.lookup (name) != (void*) prior) {
				throw new LlvmError.INVALID_INPUT ("owner-slot helper symbol conflicts with an unrelated declaration");
			}
			return prior;
		}
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		if (policy == null) {
			LlvmBufferAllocation.qualify (artifact.class_target.triple);
			artifact.requires_hosted_buffers = true;
		}
		var pointer = types.scalar (NativeScalarType.PTR);
		var i32 = types.scalar (NativeScalarType.I32);
		var bit = types.scalar (NativeScalarType.B1);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var element_type = record == null ? pointer : record_tuple (record);
		var descriptor = types.owner_slots_descriptor ();
		var layout = new LlvmSlotsLayoutBinding (descriptor, pointer);
		layout.verify (artifact.class_target.enum_target_data (artifact));
		artifact.slots_layouts.add (layout);
		if (record != null) {
			artifact.class_allocations.add (new LlvmClassAllocationBinding (element_type, artifact.class_target.enum_target_data (artifact)));
		}
		CApi.TypeRef result = action == "reserve" ? bit : (action == "borrow" || action == "take") ? element_type : action == "length" || action == "capacity" ? i32 : CApi.void_type_in_context (artifact.context);
		CApi.TypeRef[] parameters = action == "replace" ? new CApi.TypeRef[] {
			pointer, i32, element_type
		} : action == "append" ? new CApi.TypeRef[] {
			pointer, element_type
		} : action == "reserve" || action == "borrow" || action == "take" ? new CApi.TypeRef[] {
			pointer, i32
		} : new CApi.TypeRef[] {
			pointer
		};
		bool contextual = action == "reserve" && policy != null && policy.kind == Astra.Source.AllocationKind.CONTEXT;
		if (contextual) {
			var extended = new CApi.TypeRef[parameters.length + 1];
			for (int i = 0; i < parameters.length; i++) {
				extended[i] = parameters[i];
			}
			extended[parameters.length] = pointer;
			parameters = extended;
		}
		var signature = CApi.function_type (result, parameters, parameters.length, 0);
		var function = CApi.add_function (artifact.module, name, signature);
		CApi.set_linkage (function, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (function, LlvmLowering.CALL_CONVENTION);
		var builder = CApi.create_builder_in_context (artifact.context);
		try {
			var entry = block (function, "entry");
			CApi.position_builder_at_end (builder, entry);
			var state = new LlvmBlockState (entry);
			var scalars = new LlvmScalarLowering (artifact, types, builder, function);
			var allocator = new LlvmBufferAllocation (artifact, builder, function, scalars);
			var owner = CApi.get_param (function, 0);
			scalars.guard_nonnull (owner, "slots.receiver", state);
			var base_address = member (builder, owner, 0, "slots.base.address");
			var length_address = member (builder, owner, 1, "slots.length.address");
			var capacity_address = member (builder, owner, 2, "slots.capacity.address");
			if (action == "initialize") {
				CApi.build_store (builder, CApi.const_null (pointer), base_address);
				CApi.build_store (builder, CApi.const_null (i32), length_address);
				CApi.build_store (builder, CApi.const_null (i32), capacity_address);
				CApi.build_ret_void (builder);
			} else {
				var backing = CApi.build_load (builder, pointer, base_address, "slots.base");
				var length = CApi.build_load (builder, i32, length_address, "slots.length");
				var capacity = CApi.build_load (builder, i32, capacity_address, "slots.capacity");
				var negative = CApi.build_icmp (builder, CApi.IntPredicate.SLT, length, CApi.const_null (i32), "slots.negative.length");
				var bad_capacity = CApi.build_icmp (builder, CApi.IntPredicate.SLT, capacity, length, "slots.invalid.capacity");
				var empty = CApi.build_icmp (builder, CApi.IntPredicate.EQ, capacity, CApi.const_null (i32), "slots.empty.backing");
				var null_base = CApi.build_icmp (builder, CApi.IntPredicate.EQ, backing, CApi.const_null (pointer), "slots.null.base");
				var bad_base = CApi.build_icmp (builder, CApi.IntPredicate.NE, empty, null_base, "slots.base.capacity.mismatch");
				scalars.guard_slice_condition (CApi.build_or (builder, negative, CApi.build_or (builder, bad_capacity, bad_base, "slots.invalid.descriptor"), "slots.invalid"), "slots.descriptor", state);
				if (action == "length" || action == "capacity") {
					CApi.build_ret (builder, action == "length" ? length : capacity);
				} else if (action == "append") {
					var incoming = CApi.get_param (function, 1);
					if (heap) {
						scalars.guard_nonnull (incoming, "slots.append.nonnull", state);
					}
					scalars.guard_slice_condition (CApi.build_icmp (builder, CApi.IntPredicate.SGE, length, capacity, "slots.append.full"), "slots.append.capacity", state);
					var address = slot_address (builder, element_type, backing, length, "slots.append.address");
					if (record == null) {
						var previous = CApi.build_load (builder, pointer, address, "slots.append.empty");
						scalars.guard_slice_condition (CApi.build_icmp (builder, CApi.IntPredicate.NE, previous, CApi.const_null (pointer), "slots.append.occupied"), "slots.append.empty", state);
					}
					// One indivisible language effect; no further checks or user calls.
					CApi.build_store (builder, incoming, address);
					var next = CApi.build_add (builder, length, CApi.const_int (i32, 1, 0), "slots.append.next");
					CApi.build_store (builder, next, length_address);
					CApi.build_ret_void (builder);
				} else if (action == "borrow") {
					var index = CApi.get_param (function, 1);
					var below = CApi.build_icmp (builder, CApi.IntPredicate.SLT, index, CApi.const_null (i32), "slots.index.negative");
					var above = CApi.build_icmp (builder, CApi.IntPredicate.SGE, index, length, "slots.index.outside.live");
					scalars.guard_slice_condition (CApi.build_or (builder, below, above, "slots.index.invalid"), "slots.index", state);
					var value = CApi.build_load (builder, element_type, slot_address (builder, element_type, backing, index, "slots.borrow.address"), "slots.borrow.element");
					if (heap) {
						scalars.guard_nonnull (value, "slots.borrow.occupied", state);
					}
					CApi.build_ret (builder, value);
				} else if (action == "replace") {
					var index = CApi.get_param (function, 1);
					var incoming = CApi.get_param (function, 2);
					var below = CApi.build_icmp (builder, CApi.IntPredicate.SLT, index, CApi.const_null (i32), "replace.negative");
					var above = CApi.build_icmp (builder, CApi.IntPredicate.SGE, index, length, "replace.outside.live");
					scalars.guard_slice_condition (CApi.build_or (builder, below, above, "replace.invalid"), "slots.replace.index", state);
					if (heap) {
						scalars.guard_nonnull (incoming, "replace.incoming", state);
					}
					var address = slot_address (builder, element_type, backing, index, "replace.slot");
					var retired = CApi.build_load (builder, element_type, address, "replace.retired");
					if (heap) {
						scalars.guard_nonnull (retired, "replace.occupied", state);
					}
					// Admit the new owner before invoking the old owner's destructor.
					CApi.build_store (builder, incoming, address);
					if (record != null) {
						destroy_record (builder, function, allocator, record, retired, state, "replace.record");
					}
					if (heap) {
						classes.release_owned (builder, function, allocator, element, retired, state, "replace.retired");
					} else if (cleanup != null) {
						destroy_resource (builder, function, cleanup, retired, state);
					}
					CApi.build_ret_void (builder);
				} else if (action == "take") {
					var index = CApi.get_param (function, 1);
					var below = CApi.build_icmp (builder, CApi.IntPredicate.SLT, index, CApi.const_null (i32), "take.negative");
					var above = CApi.build_icmp (builder, CApi.IntPredicate.SGE, index, length, "take.outside.live");
					scalars.guard_slice_condition (CApi.build_or (builder, below, above, "take.invalid"), "slots.take.index", state);
					var first = slot_address (builder, element_type, backing, index, "take.first");
					var taken = CApi.build_load (builder, element_type, first, "take.owner");
					if (heap) {
						scalars.guard_nonnull (taken, "take.occupied", state);
					}
					var last = CApi.build_sub (builder, length, CApi.const_int (i32, 1, 0), "take.last");
					var predecessor = state.end;
					var header = block (function, "take.shift.header");
					var shift = block (function, "take.shift.slot");
					var done = block (function, "take.commit");
					CApi.build_br (builder, header);
					CApi.position_builder_at_end (builder, header);
					var cursor = CApi.build_phi (builder, i32, "take.cursor");
					CApi.add_incoming (cursor, &index, &predecessor, 1);
					CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.SLT, cursor, last, "take.has.next"), shift, done);
					CApi.position_builder_at_end (builder, shift);
					var next = CApi.build_add (builder, cursor, CApi.const_int (i32, 1, 0), "take.next");
					var moving = CApi.build_load (builder, element_type, slot_address (builder, element_type, backing, next, "take.source"), "take.shifted.owner");
					CApi.build_store (builder, moving, slot_address (builder, element_type, backing, cursor, "take.destination"));
					CApi.build_br (builder, header);
					CApi.add_incoming (cursor, &next, &shift, 1);
					CApi.position_builder_at_end (builder, done);
					CApi.build_store (builder, CApi.const_null (element_type), slot_address (builder, element_type, backing, last, "take.vacated"));
					CApi.build_store (builder, last, length_address);
					CApi.build_ret (builder, taken);
				} else if (action == "reserve") {
					var requested = CApi.get_param (function, 1);
					var rejected = block (function, "reserve.rejected");
					var extent = block (function, "reserve.extent");
					var accepted = block (function, "reserve.accepted");
					var noop = block (function, "reserve.noop");
					var grow = block (function, "reserve.grow");
					CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.SLT, requested, CApi.const_null (i32), "reserve.negative"), rejected, extent);
					CApi.position_builder_at_end (builder, rejected);
					CApi.build_ret (builder, CApi.const_null (bit));
					CApi.position_builder_at_end (builder, extent);
					state.end = extent;
					var count = CApi.build_zext (builder, requested, size, "reserve.count");
					string intrinsic_name = "llvm.umul.with.overflow";
					uint id = CApi.lookup_intrinsic_id (intrinsic_name, intrinsic_name.length);
					CApi.TypeRef[] overloads = {
						size
					};
					var multiplication = CApi.get_intrinsic_declaration (artifact.module, id, overloads, overloads.length);
					var multiplication_type = CApi.intrinsic_get_type (artifact.context, id, overloads, overloads.length);
					CApi.ValueRef[] factors = {
						count, CApi.size_of (element_type)
					};
					var product = CApi.build_call (builder, multiplication_type, multiplication, factors, 2, "reserve.checked.bytes");
					var overflow = CApi.build_extract_value (builder, product, 1, "reserve.overflow");
					var bytes = CApi.build_extract_value (builder, product, 0, "reserve.bytes");
					var unaddressable = CApi.build_icmp (builder, CApi.IntPredicate.UGT, bytes, CApi.const_int (size, 0x7fffffffffffffffUL, 0), "reserve.unaddressable");
					CApi.build_cond_br (builder, CApi.build_or (builder, overflow, unaddressable, "reserve.invalid.extent"), rejected, accepted);
					CApi.position_builder_at_end (builder, accepted);
					CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.SLE, requested, capacity, "reserve.sufficient"), noop, grow);
					CApi.position_builder_at_end (builder, noop);
					CApi.build_ret (builder, CApi.const_int (bit, 1, 0));
					CApi.position_builder_at_end (builder, grow);
					state.end = grow;
					var replacement = allocator.allocate (requested, element_type, "reserve.replacement", state, false, null, false, policy, container_name, "slots", policy != null, contextual ? CApi.get_param (function, parameters.length - 1) : (CApi.ValueRef) null);
					if (policy != null) {
						var admitted = block (function, "reserve.admitted");
						CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, replacement, CApi.const_null (pointer), "reserve.exhausted"), rejected, admitted);
						CApi.position_builder_at_end (builder, admitted);
						state.end = admitted;
					}
					var predecessor = state.end;
					var header = block (function, "reserve.transfer.header");
					var transfer = block (function, "reserve.transfer.slot");
					var commit = block (function, "reserve.commit");
					CApi.build_br (builder, header);
					CApi.position_builder_at_end (builder, header);
					var index = CApi.build_phi (builder, i32, "reserve.index");
					var zero = CApi.const_null (i32);
					CApi.add_incoming (index, &zero, &predecessor, 1);
					CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.SLT, index, length, "reserve.live.slot"), transfer, commit);
					CApi.position_builder_at_end (builder, transfer);
					var old_slot = slot_address (builder, element_type, backing, index, "reserve.old.slot");
					var new_slot = slot_address (builder, element_type, replacement, index, "reserve.new.slot");
					var value = CApi.build_load (builder, element_type, old_slot, "reserve.moved.carrier");
					CApi.build_store (builder, value, new_slot);
					CApi.build_store (builder, CApi.const_null (element_type), old_slot);
					var next = CApi.build_add (builder, index, CApi.const_int (i32, 1, 0), "reserve.next");
					CApi.build_br (builder, header);
					CApi.add_incoming (index, &next, &transfer, 1);
					CApi.position_builder_at_end (builder, commit);
					state.end = commit;
					CApi.build_store (builder, replacement, base_address);
					CApi.build_store (builder, length, length_address);
					CApi.build_store (builder, requested, capacity_address);
					allocator.deallocate (backing, "reserve.old.empty.backing", state, policy, container_name, "slots");
					CApi.build_ret (builder, CApi.const_int (bit, 1, 0));
				} else if (action == "drop") {
					var predecessor = state.end;
					var header = block (function, "drop.reverse.header");
					var retire = block (function, "drop.reverse.slot");
					var complete = block (function, "drop.backing");
					CApi.build_br (builder, header);
					CApi.position_builder_at_end (builder, header);
					var remaining = CApi.build_phi (builder, i32, "drop.remaining");
					CApi.add_incoming (remaining, &length, &predecessor, 1);
					CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.SGT, remaining, CApi.const_null (i32), "drop.has.element"), retire, complete);
					CApi.position_builder_at_end (builder, retire);
					state.end = retire;
					var index = CApi.build_sub (builder, remaining, CApi.const_int (i32, 1, 0), "drop.index");
					var address = slot_address (builder, element_type, backing, index, "drop.slot.address");
					var value = CApi.build_load (builder, element_type, address, "drop.element");
					// Occupied slots are nonnull by the verified append invariant.
					CApi.build_store (builder, CApi.const_null (element_type), address);
					CApi.build_store (builder, index, length_address);
					if (record != null) {
						destroy_record (builder, function, allocator, record, value, state, "drop.record");
					}
					if (heap) {
						classes.release_owned (builder, function, allocator, element, value, state, "drop.element");
					} else if (cleanup != null) {
						destroy_resource (builder, function, cleanup, value, state);
					}
					var retired = state.end;
					CApi.build_br (builder, header);
					CApi.add_incoming (remaining, &index, &retired, 1);
					CApi.position_builder_at_end (builder, complete);
					state.end = complete;
					allocator.deallocate (backing, "drop.backing.free", state, policy, container_name, "slots");
					CApi.build_store (builder, CApi.const_null (pointer), base_address);
					CApi.build_store (builder, CApi.const_null (i32), length_address);
					CApi.build_store (builder, CApi.const_null (i32), capacity_address);
					CApi.build_ret_void (builder);
				} else {
					throw new LlvmError.INVALID_INPUT ("unknown owner-slot primitive");
				}
			}
			// Full instruction/edge/operand sequence, in addition to typed calls,
			// field addresses and target layout, is independently reverified.
			artifact.class_functions.add (new LlvmClassFunctionBinding (function, signature));
		} finally {
			CApi.dispose_builder (builder);
		}
		artifact.slots_helpers.insert (name, (void*) function);
		return function;
	}

}
}
