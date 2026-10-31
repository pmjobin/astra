// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Backend.LLVM {
// One hosted physical strategy. Core/CFG operations have no C symbol or
// size_t type. The selected Windows interop profile separately limits source
// storage; both qualified allocators use 64-bit size_t and natural alignment.
internal class LlvmBufferAllocation : Object {
	private LlvmModuleArtifact artifact;
	private CApi.BuilderRef builder;
	private CApi.ValueRef function;
	private LlvmScalarLowering scalars;
	internal LlvmBufferAllocation (LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef function, LlvmScalarLowering scalars) {
		this.artifact = artifact;
		this.builder = builder;
		this.function = function;
		this.scalars = scalars;
	}

	internal static void qualify(string triple) throws LlvmError {
		// GNU LP64 is qualified. In particular, Linux gnux32 also names the
		// x86_64 architecture but has 32-bit pointers and size_t.
		if (triple != LlvmTargetMachineArtifact.WINDOWS_INTEROP && !(triple.has_prefix ("x86_64-") && triple.has_suffix ("-linux-gnu"))) {
			throw new LlvmError.TARGET ("error: owned runtime-array allocator is not qualified for target '%s' (requires hosted x86-64 Linux GNU LP64 or selected Windows interop storage)", triple);
		}
	}

	// LLVM's builtin allocation elimination may erase an observable OOM trap.
	// Disable that libc-specific interpretation on declaration AND call; the
	// remaining optimizer still sees ordinary direct effectful C calls.
	private CApi.AttributeRef non_builtin() {
		return CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("nobuiltin", 9), 0);
	}

	private CApi.ValueRef declaration(string symbol, CApi.TypeRef type) throws LlvmError {
		var existing = CApi.named_function (artifact.module, symbol);
		if ((void*) existing != null) {
			if ((void*) CApi.global_value_type (existing) != (void*) type) {
				throw new LlvmError.LOWERING ("host buffer allocator symbol '%s' has an incompatible physical declaration", symbol);
			}
			CApi.add_attribute (existing, uint.MAX, non_builtin ());
			return existing;
		}
		var value = CApi.add_function (artifact.module, symbol, type);
		CApi.add_attribute (value, uint.MAX, non_builtin ());
		CApi.set_function_call_conv (value, CApi.CallConv.C);
		CApi.set_linkage (value, CApi.Linkage.EXTERNAL);
		return value;
	}

	internal static NativeAbi.NativeContextSliceType? buffer_origin (Astra.Semantic.SliceType type) throws LlvmError {
		if (!(type is Astra.Semantic.ContextBytesType)) {
			return null;
		}
		try {
			return NativeAbi.NativeTypeMapper.context_buffer_type (type);
		} catch (NativeAbi.NativeAbiError error) {
			throw new LlvmError.LOWERING (error.message);
		}
	}
	private static Astra.Source.AllocationPolicy buffer_policy(NativeAbi.NativeContextSliceType origin) throws LlvmError {
		if (!origin.valid ()) {
			throw new LlvmError.LOWERING ("byte buffer lost its exact native origin contract");
		}
		return new Astra.Source.AllocationPolicy (Astra.Source.AllocationKind.CONTEXT, "ContextBytes", 0, 0, 1, null, null, origin.allocator.mode);
	}
	internal CApi.ValueRef allocate_buffer(CApi.ValueRef count, Astra.Semantic.SliceType type, CApi.TypeRef element, string name, LlvmBlockState state, LlvmBlockState? failure = null, CApi.ValueRef context = (CApi.ValueRef) null) throws LlvmError {
		var origin = buffer_origin (type);
		if ((origin != null) != ((void*) context != null)) {
			throw new LlvmError.LOWERING ("byte allocation lost its original selected context channel");
		}
		if (origin != null && artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		return allocate (count, element, name, state, type.element_type is Astra.Semantic.StructType, failure, false, origin == null ? null : buffer_policy (origin), origin == null ? "" : origin.name, "buffer", false, context);
	}
	internal void deallocate_buffer(CApi.ValueRef pointer, string name, LlvmBlockState state, NativeAbi.NativeContextSliceType? origin = null) throws LlvmError {
		deallocate (pointer, name, state, origin == null ? null : buffer_policy (origin), origin == null ? "" : origin.name, "buffer");
	}

	internal CApi.ValueRef allocate(CApi.ValueRef count, CApi.TypeRef element, string name, LlvmBlockState state, bool record = false, LlvmBlockState? failure = null, bool object = false, Astra.Source.AllocationPolicy? policy = null, string class_name = "", string role = "object", bool fallible = false, CApi.ValueRef context = (CApi.ValueRef) null) throws LlvmError {
		if (policy == null) {
			artifact.requires_hosted_buffers = true;
		}
		if (object) {
			if (artifact.class_target == null) {
				artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
			}
			if (policy == null) {
				qualify (artifact.class_target.triple);
			}
			var binding = new LlvmClassAllocationBinding (element, artifact.class_target.enum_target_data (artifact));
			binding.verify (artifact.class_target.enum_target_data (artifact));
			artifact.class_allocations.add (binding);
		}
		var i32 = CApi.int32_type_in_context (artifact.context);
		var size_type = CApi.int_type_in_context (artifact.context, 64);
		var pointer_type = CApi.pointer_type_in_context (artifact.context, 0);
		scalars.guard_slice_condition (CApi.build_icmp (builder, CApi.IntPredicate.SLT, count, CApi.const_null (i32), name + ".negative"), name + ".count", state);
		var predecessor = state.end;
		var nonempty = CApi.append_basic_block_in_context (artifact.context, function, name + ".nonempty");
		var joined = CApi.append_basic_block_in_context (artifact.context, function, name + ".joined");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, count, CApi.const_null (i32), name + ".empty"), joined, nonempty);
		CApi.position_builder_at_end (builder, nonempty);
		state.end = nonempty;
		var length = CApi.build_zext (builder, count, size_type, name + ".size.count");
		var element_size = CApi.size_of (element);
		string intrinsic_name = "llvm.umul.with.overflow";
		uint id = CApi.lookup_intrinsic_id (intrinsic_name, intrinsic_name.length);
		CApi.TypeRef[] overloads = {
			size_type
		};
		var checked_multiply = CApi.get_intrinsic_declaration (artifact.module, id, overloads, overloads.length);
		var checked_type = CApi.intrinsic_get_type (artifact.context, id, overloads, overloads.length);
		CApi.ValueRef[] factors = {
			length, element_size
		};
		var product = CApi.build_call (builder, checked_type, checked_multiply, factors, factors.length, name + ".bytes.checked");
		scalars.guard_slice_condition (CApi.build_extract_value (builder, product, 1, name + ".overflow"), name + ".size", state);
		if (record) {
			var bytes = CApi.build_extract_value (builder, product, 0, name + ".bytes");
			scalars.guard_slice_condition (CApi.build_icmp (builder, CApi.IntPredicate.UGT, bytes, CApi.const_int (size_type, NativeAbi.NativeRecordLayout.MAX_EXTENT, 0), name + ".address.overflow"), name + ".address", state);
		}
		CApi.TypeRef[] parameter_types = {
			size_type, size_type
		};
		var type = CApi.function_type (pointer_type, parameter_types, parameter_types.length, 0);
		var allocation = policy == null ? CApi.build_call(builder, type, declaration ("calloc", type), factors, factors.length, name + ".allocation") : new LlvmPolicyAllocation (artifact).allocate (builder, policy, class_name, role, length, element, name + ".allocation", object, context);
		CApi.set_instruction_call_conv (allocation, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (product, checked_multiply, checked_type, new CApi.ValueRef[] { length, CApi.size_of (element) }, CApi.CallConv.C, "checked complete allocation extent"));
		if (policy == null) {
			artifact.class_calls.add (new LlvmClassCallBinding (allocation, declaration ("calloc", type), type, new CApi.ValueRef[] { length, CApi.size_of (element) }, CApi.CallConv.C, "zeroed complete allocation extent"));
		}
		if ((void*) CApi.is_instruction (length) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (length, CApi.Opcode.ZEXT, size_type, new CApi.ValueRef[] { count }, "allocation count"));
		}
		CApi.add_call_attribute (allocation, uint.MAX, non_builtin ());
		if (failure == null && !fallible) {
			scalars.guard_nonnull (allocation, name + ".oom", state);
		} else if (failure != null) {
			var allocated = CApi.append_basic_block_in_context (artifact.context, function, name + ".allocated");
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, allocation, CApi.const_null (pointer_type), name + ".oom"), failure.primary, allocated);
			CApi.position_builder_at_end (builder, allocated);
			state.end = allocated;
		}
		var successful = state.end;
		CApi.build_br (builder, joined);
		CApi.position_builder_at_end (builder, joined);
		var pointer = CApi.build_phi (builder, pointer_type, name + ".base");
		var empty = CApi.const_null (pointer_type);
		CApi.add_incoming (pointer, &empty, &predecessor, 1);
		CApi.add_incoming (pointer, &allocation, &successful, 1);
		state.end = joined;
		return pointer;
	}

	internal void guard_record_offset(CApi.ValueRef ordinal, CApi.TypeRef element, string name, LlvmBlockState state) throws LlvmError {
		var size_type = CApi.int_type_in_context (artifact.context, 64);
		string intrinsic_name = "llvm.umul.with.overflow";
		uint id = CApi.lookup_intrinsic_id (intrinsic_name, intrinsic_name.length);
		CApi.TypeRef[] overloads = {
			size_type
		};
		var intrinsic = CApi.get_intrinsic_declaration (artifact.module, id, overloads, overloads.length);
		var type = CApi.intrinsic_get_type (artifact.context, id, overloads, overloads.length);
		CApi.ValueRef[] factors = {
			ordinal, CApi.size_of (element)
		};
		var product = CApi.build_call (builder, type, intrinsic, factors, factors.length, name + ".offset.checked");
		scalars.guard_slice_condition (CApi.build_extract_value (builder, product, 1, name + ".offset.overflow"), name + ".offset", state);
		var bytes = CApi.build_extract_value (builder, product, 0, name + ".offset.bytes");
		scalars.guard_slice_condition (CApi.build_icmp (builder, CApi.IntPredicate.UGT, bytes, CApi.const_int (size_type, NativeAbi.NativeRecordLayout.MAX_EXTENT, 0), name + ".address.overflow"), name + ".address", state);
	}

	internal void deallocate(CApi.ValueRef pointer, string name, LlvmBlockState state, Astra.Source.AllocationPolicy? policy = null, string class_name = "", string role = "object") throws LlvmError {
		if (policy == null) {
			artifact.requires_hosted_buffers = true;
		}
		var pointer_type = CApi.pointer_type_in_context (artifact.context, 0);
		var live = CApi.append_basic_block_in_context (artifact.context, function, name + ".live");
		var joined = CApi.append_basic_block_in_context (artifact.context, function, name + ".done");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, pointer, CApi.const_null (pointer_type), name + ".empty"), joined, live);
		CApi.position_builder_at_end (builder, live);
		if (policy == null) {
			var type = CApi.function_type (CApi.void_type_in_context (artifact.context), &pointer_type, 1, 0);
			var call = CApi.build_call (builder, type, declaration ("free", type), &pointer, 1, "");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			artifact.class_calls.add (new LlvmClassCallBinding (call, declaration ("free", type), type, new CApi.ValueRef[] { pointer }, CApi.CallConv.C, "original owner deallocation"));
			CApi.add_call_attribute (call, uint.MAX, non_builtin ());
		} else {
			var released = new LlvmPolicyAllocation (artifact).release (builder, policy, class_name, role, pointer, name + ".origin");
			var word = CApi.int32_type_in_context (artifact.context);
			scalars.guard_slice_condition (CApi.build_icmp (builder, CApi.IntPredicate.NE, released, CApi.const_int (word, 1, 0), name + ".invalid.origin"), name + ".origin", state);
		}
		CApi.build_br (builder, joined);
		CApi.position_builder_at_end (builder, joined);
		state.end = joined;
	}
}
}
