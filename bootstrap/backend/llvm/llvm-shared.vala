// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
namespace Astra.Backend.LLVM {
// A block belongs only to an explicit shared acquisition. weak includes one
// implicit sentinel until last-strong destruction has completely returned.
internal class LlvmSharedLowering : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private CApi.BuilderRef builder;
	private CApi.ValueRef function;
	private LlvmScalarLowering scalars;
	private LlvmBufferAllocation allocator;
	private LlvmClassRuntime classes;
	private HashTable<SsaFunction, LlvmFunctionBinding> functions;
	private CApi.TypeRef layout;
	private CApi.TypeRef count_type;
	private CApi.TypeRef intrusive_layout;
	private bool intrusive_mode;
	private CApi.TypeRef pointer_type;
	private int serial;
	internal LlvmSharedLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types, CApi.BuilderRef builder, CApi.ValueRef function, LlvmScalarLowering scalars, LlvmBufferAllocation allocator, LlvmClassRuntime classes, HashTable<SsaFunction, LlvmFunctionBinding> functions) throws LlvmError {
		this.artifact = artifact;
		this.types = types;
		this.builder = builder;
		this.function = function;
		this.scalars = scalars;
		this.allocator = allocator;
		this.classes = classes;
		this.functions = functions;
		count_type = CApi.int_type_in_context (artifact.context, 64);
		pointer_type = types.scalar (NativeScalarType.PTR);
		CApi.TypeRef[] fields = {
			count_type, count_type, pointer_type
		};
		layout = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (layout, fields));
		CApi.TypeRef[] header = {
			pointer_type, pointer_type, count_type, count_type, pointer_type, count_type
		};
		intrusive_layout = CApi.struct_type_in_context (artifact.context, header, header.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (intrusive_layout, header));
	}

	private CApi.BasicBlockRef block(string name) {
		return CApi.append_basic_block_in_context (artifact.context, function, "shared.%d.%s".printf (serial++, name));
	}

	private CApi.ValueRef address(CApi.ValueRef root, uint member) {
		var selected = intrusive_mode ? intrusive_layout : layout;
		uint index = intrusive_mode ? member + 2 : member;
		var result = CApi.build_struct_gep (builder, selected, root, index, "shared.member");
		artifact.class_addresses.add (new LlvmClassAddressBinding (result, root, selected, index));
		return result;
	}

	private CApi.ValueRef read(CApi.ValueRef root, uint member) {
		var place = address (root, member);
		var type = member == 2 ? pointer_type : count_type;
		var result = CApi.build_load (builder, type, place, "shared.read");
		if (member < 2) {
			CApi.set_ordering (result, 4);
			CApi.set_alignment (result, 8);
			artifact.shared_atomics.add (new LlvmSharedAtomicBinding (result, place, CApi.Opcode.LOAD, 4));
		}
		if (member == 2) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { place }, "shared exact field read"));
		}
		return result;
	}

	private void write(CApi.ValueRef root, uint member, CApi.ValueRef value) {
		var place = address (root, member);
		var result = CApi.build_store (builder, value, place);
		if (member < 2) {
			CApi.set_ordering (result, 2);
			CApi.set_alignment (result, 8);
			artifact.shared_atomics.add (new LlvmSharedAtomicBinding (result, place, CApi.Opcode.STORE, 2, (CApi.ValueRef) null, value));
		}
		if (member == 2) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value, place }, "shared exact field publication"));
		}
	}

	private CApi.ValueRef zero() {
		return CApi.const_null (count_type);
	}

	private CApi.ValueRef one() {
		return CApi.const_int (count_type, 1, 0);
	}

	private CApi.ValueRef equal(CApi.ValueRef left, CApi.ValueRef right, bool unequal = false) throws LlvmError {
		var predicate = unequal ? CApi.IntPredicate.NE : CApi.IntPredicate.EQ;
		var result = CApi.build_icmp (builder, predicate, left, right, "shared.equal");
		if ((void*) CApi.is_instruction (result) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { left, right }, "shared exact state comparison", -1, (int) predicate));
		}
		return result;
	}

	private void branch(CApi.ValueRef condition, CApi.BasicBlockRef yes, CApi.BasicBlockRef no) {
		var result = CApi.build_cond_br (builder, condition, yes, no);
		artifact.class_branches.add (new LlvmClassBranchBinding (result, condition, yes, no));
	}

	private void guard(CApi.ValueRef invalid, string name, LlvmBlockState state) throws LlvmError {
		var trap = block (name + ".trap");
		var valid = block (name + ".valid");
		branch (invalid, trap, valid);
		CApi.position_builder_at_end (builder, trap);
		scalars.emit_trap ();
		CApi.position_builder_at_end (builder, valid);
		state.end = valid;
	}

	private CApi.ValueRef adjust(CApi.ValueRef root, uint member, bool subtract, bool upgrade, LlvmBlockState state) throws LlvmError {
		var initial = read (root, member);
		var entry = state.end;
		var loop = block ("count.retry");
		var done = block ("count.done");
		CApi.build_br (builder, loop);
		CApi.position_builder_at_end (builder, loop);
		state.end = loop;
		var count = CApi.build_phi (builder, count_type, "shared.expected");
		CApi.add_incoming (count, &initial, &entry, 1);
		if (upgrade) {
			var live = block ("count.live");
			branch (equal (count, zero ()), done, live);
			CApi.position_builder_at_end (builder, live);
			state.end = live;
		} else {
			guard (equal (count, zero ()), "shared.underflow", state);
		}
		if (!subtract) {
			guard (equal (count, CApi.const_int (count_type, uint64.MAX, 0)), "shared.overflow", state);
		}
		var next = subtract ? CApi.build_sub (builder, count, one (), "shared.decrement") : CApi.build_add (builder, count, one (), "shared.increment");
		artifact.class_values.add (new LlvmClassValueBinding (next, subtract ? CApi.Opcode.SUB : CApi.Opcode.ADD, count_type, new CApi.ValueRef[] { count, one () }, "shared checked atomic count replacement"));
		var place = address (root, member);
		var cas = CApi.build_atomic_cmp_xchg (builder, place, count, next, 6, 4, 0);
		CApi.set_alignment (cas, 8);
		artifact.shared_atomics.add (new LlvmSharedAtomicBinding (cas, place, CApi.Opcode.ATOMIC_CMP_XCHG, 6, count, next));
		var observed = CApi.build_extract_value (builder, cas, 0, "shared.observed");
		var success = CApi.build_extract_value (builder, cas, 1, "shared.acquired");
		var attempt = state.end;
		branch (success, done, loop);
		CApi.add_incoming (count, &observed, &attempt, 1);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
		if (!upgrade) {
			return next;
		}
		var result = CApi.build_phi (builder, count_type, "shared.upgrade.count");
		var empty = zero ();
		CApi.add_incoming (result, &empty, &loop, 1);
		CApi.add_incoming (result, &next, &attempt, 1);
		return result;
	}

	internal CApi.ValueRef operation(SharedAction action, CApi.ValueRef operand, LlvmBlockState state, bool intrusive = false, SsaClass? singleton = null) throws LlvmError {
		intrusive_mode = intrusive;
		if (action == SharedAction.SINGLETON_SHUTDOWN) {
			if (!intrusive || singleton == null || singleton.concurrency_policy == null || singleton.concurrency_policy.identity != 7) {
				throw new LlvmError.LOWERING ("singleton shutdown lost exact admitted process root");
			}
			var absent = state.end;
			var live = block ("singleton.live");
			var retired = block ("singleton.retire");
			var done = block ("singleton.done");
			branch (equal (operand, CApi.const_null (pointer_type)), done, live);
			CApi.position_builder_at_end (builder, live);
			state.end = live;
			var status = LlvmConcurrencyRuntime.call (artifact, builder, "astra_singleton_detach", types.scalar (NativeScalarType.I32), new CApi.TypeRef[] { pointer_type, pointer_type }, new CApi.ValueRef[] { LlvmConcurrencyRuntime.singleton_key (artifact, singleton.name), operand });
			branch (equal (status, CApi.const_null (types.scalar (NativeScalarType.I32))), done, retired);
			var refused = state.end;
			CApi.position_builder_at_end (builder, retired);
			state.end = retired;
			adjust (operand, 0, false, false, state);
			release_payload (operand, singleton, false, state);
			var released = state.end;
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
			var result = CApi.build_phi (builder, pointer_type, "singleton.retired.owner");
			var empty = CApi.const_null (pointer_type);
			CApi.add_incoming (result, &empty, &absent, 1);
			CApi.add_incoming (result, &empty, &refused, 1);
			CApi.add_incoming (result, &operand, &released, 1);
			return result;
		}
		if (action == SharedAction.ACQUIRE) {
			scalars.guard_nonnull (operand, "shared.acquire.payload", state, true);
			var result = allocator.allocate (CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0), layout, "shared.block", state, false, null, true);
			write (result, 0, one ());
			write (result, 1, one ());
			write (result, 2, operand);
			return result;
		}
		if (action == SharedAction.BORROW) {
			scalars.guard_nonnull (operand, "shared.borrow.handle", state, true);
			guard (equal (read (operand, 0), zero ()), "shared.borrow.expired", state);
			var payload = read (operand, 2);
			scalars.guard_nonnull (payload, "shared.borrow.payload", state, true);
			return payload;
		}
		var live = block ("live");
		var done = block ("joined");
		var absent = state.end;
		branch (equal (operand, CApi.const_null (pointer_type)), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		if (action == SharedAction.CLONE) {
			guard (equal (read (operand, 0), zero ()), "shared.clone.expired", state);
		}
		var count = adjust (operand, action == SharedAction.DOWNGRADE || action == SharedAction.WEAK_CLONE ? 1 : 0, false, action == SharedAction.UPGRADE, state);
		var expired = state.end;
		if (action == SharedAction.UPGRADE) {
			var acquire = block ("upgrade.live");
			branch (equal (count, zero ()), done, acquire);
			CApi.position_builder_at_end (builder, acquire);
			state.end = acquire;
		}
		var acquired = state.end;
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
		var result = CApi.build_phi (builder, pointer_type, "shared.result");
		var empty = CApi.const_null (pointer_type);
		CApi.add_incoming (result, &empty, &absent, 1);
		CApi.add_incoming (result, &operand, &acquired, 1);
		if (action == SharedAction.UPGRADE) {
			CApi.add_incoming (result, &empty, &expired, 1);
		}
		return result;
	}

	internal void release(CApi.ValueRef handle, SsaCleanupContract cleanup, LlvmBlockState state) throws LlvmError {
		var owner = cleanup.is_object ? cleanup.object_class : cleanup.shared_payload;
		bool weak = cleanup.shared_type != null && cleanup.shared_type.is_weak;
		release_payload (handle, owner, weak, state);
	}

	internal CApi.ValueRef retain_foreign(CApi.ValueRef handle, LlvmBlockState state) throws LlvmError {
		intrusive_mode = true;
		scalars.guard_nonnull (handle, "foreign.retain.root", state, true);
		return adjust (handle, 0, false, false, state);
	}

	internal CApi.ValueRef release_foreign(CApi.ValueRef handle, SsaClass owner, LlvmBlockState state) throws LlvmError {
		var result = CApi.build_alloca (builder, count_type, "foreign.remaining.slot");
		var initial = CApi.build_store (builder, zero (), result);
		artifact.class_values.add (new LlvmClassValueBinding (initial, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { zero (), result }, "foreign absent-root release count"));
		release_payload (handle, owner, false, state, result);
		var count = CApi.build_load (builder, count_type, result, "foreign.remaining");
		artifact.class_values.add (new LlvmClassValueBinding (count, CApi.Opcode.LOAD, count_type, new CApi.ValueRef[] { result }, "foreign exact native release count"));
		return count;
	}

	internal void release_payload(CApi.ValueRef handle, SsaClass owner, bool weak, LlvmBlockState state, CApi.ValueRef result_slot = (CApi.ValueRef) null) throws LlvmError {
		intrusive_mode = ((ClassType) owner.semantic_type).intrinsically_shared;
		var live = block ("release.live");
		var done = block ("release.done");
		branch (equal (handle, CApi.const_null (pointer_type)), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		if (!weak) {
			var remaining = adjust (handle, 0, true, false, state);
			if ((void*) result_slot != null) {
				var store = CApi.build_store (builder, remaining, result_slot);
				artifact.class_values.add (new LlvmClassValueBinding (store, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { remaining, result_slot }, "foreign exact native release count publication"));
			}
			var last = block ("last.strong");
			branch (equal (remaining, zero ()), last, done);
			CApi.position_builder_at_end (builder, last);
			state.end = last;
			var payload = intrusive_mode ? handle : read (handle, 2);
			if (!intrusive_mode) {
				write (handle, 2, CApi.const_null (pointer_type));
			}
			if (owner == null) {
				throw new LlvmError.LOWERING ("shared release lost exact payload destruction authority");
			}
			classes.begin_foreign_retirement (builder, function, payload, owner, state);
			if (owner.polymorphic) {
				classes.destroy (builder, function, payload, "shared.payload.dynamic", state, allocator, false);
			} else {
				if (owner.destructor != null) {
					var target = functions.lookup (owner.destructor);
					if (target == null) {
						throw new LlvmError.LOWERING ("shared payload destructor has no native binding");
					}
					var call = CApi.build_call (builder, target.type, target.value, &payload, 1, "");
					CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
					artifact.class_calls.add (new LlvmClassCallBinding (call, target.value, target.type, new CApi.ValueRef[] { payload }, LlvmLowering.CALL_CONVENTION, "last strong exact payload destruction"));
				}
			}
			classes.retire_monitor (builder, payload, (ClassType) owner.semantic_type, state);
			if (owner.foreign_export != null) {
				classes.retire_foreign_wrapper (builder, function, payload, owner, state, allocator);
			}
			if (!intrusive_mode) {
				allocator.deallocate (payload, "shared.payload.free", state, owner.allocation_policy, owner.name);
			}
		}
		var last_weak = block ("last.is_weak");
		branch (equal (adjust (handle, 1, true, false, state), zero ()), last_weak, done);
		CApi.position_builder_at_end (builder, last_weak);
		state.end = last_weak;
		guard (equal (read (handle, 0), zero (), true), "shared.final.is_weak", state);
		allocator.deallocate (handle, intrusive_mode ? "shared.intrinsic.free" : "shared.block.free", state, intrusive_mode ? owner.allocation_policy : null, intrusive_mode ? owner.name : "");
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

}
}
