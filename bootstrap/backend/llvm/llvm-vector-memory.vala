// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.NativeAbi;

namespace Astra.Backend.LLVM {
internal class LlvmVectorMemoryBinding : Object {
	internal CApi.ValueRef operation;
	private uint alignment;
	internal GenericArray<LlvmFloatingStep> proof = new GenericArray<LlvmFloatingStep> ();
	internal LlvmVectorMemoryBinding (CApi.ValueRef operation, uint alignment) {
		this.operation = operation;
		this.alignment = alignment;
	}

	internal void verify() throws LlvmError {
		foreach (var step in proof) {
			step.verify ();
		}
		if ((CApi.opcode (operation) != CApi.Opcode.LOAD && CApi.opcode (operation) != CApi.Opcode.STORE) || CApi.get_alignment (operation) != alignment) {
			throw new LlvmError.VERIFICATION ("vector memory lost its checked alignment or operation");
		}
	}

}

internal class LlvmVectorMemory : Object {
	internal static CApi.ValueRef lower(LlvmModuleArtifact artifact, LlvmTypeMapper types, CApi.BuilderRef builder, CApi.ValueRef function, LlvmScalarLowering scalars, VectorMemoryContract contract, CApi.ValueRef view, CApi.ValueRef offset, CApi.ValueRef stored, bool store, string name, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var original = CApi.insert_block (builder);
		var preceding = CApi.last_instruction (original);
		var old_blocks = new HashTable<void*, bool> (direct_hash, direct_equal);
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			old_blocks.insert ((void*) block, true);
		}
		var integer = types.scalar (NativeScalarType.I32);
		var wide = types.scalar (NativeScalarType.U64);
		var length = CApi.build_extract_value (builder, view, 1, name + ".length");
		var count = CApi.const_int (integer, contract.vector_type.lane_count, 0);
		var nonnegative = CApi.build_icmp (builder, CApi.IntPredicate.SGE, offset, CApi.const_null (integer), name + ".nonnegative");
		var enough = CApi.build_icmp (builder, CApi.IntPredicate.SGE, length, count, name + ".enough");
		var remaining = CApi.build_sub (builder, length, count, name + ".remaining");
		var fits = CApi.build_icmp (builder, CApi.IntPredicate.SLE, offset, remaining, name + ".fits");
		var valid = CApi.build_and (builder, nonnegative, CApi.build_and (builder, enough, fits, name + ".extent"), name + ".bounded");
		scalars.guard_slice_condition (CApi.build_xor (builder, valid, CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0), name + ".invalid"), name + ".vector.bounds", state);
		var base_pointer = CApi.build_extract_value (builder, view, 0, name + ".base");
		var index = CApi.build_zext (builder, offset, wide, name + ".offset");
		var pointer = CApi.build_gep (builder, types.value_type (contract.vector_type.element_type), base_pointer, &index, 1, name + ".pointer");
		if (contract.alignment > 1) {
			var address = CApi.build_ptr_to_int (builder, pointer, wide, name + ".address");
			var low = CApi.build_and (builder, address, CApi.const_int (wide, contract.alignment - 1, 0), name + ".alignment");
			var invalid = CApi.build_icmp (builder, CApi.IntPredicate.NE, low, CApi.const_null (wide), name + ".misaligned");
			scalars.guard_slice_condition (invalid, name + ".vector.alignment", state);
		}
		string? mode = Environment.get_variable ("ASTRA_TEST_VECTOR_MEMORY");
		if (mode != null && mode != "native" && mode != "scalar") {
			throw new LlvmError.INVALID_INPUT ("ASTRA_TEST_VECTOR_MEMORY requires native or scalar");
		}
		bool scalar = mode == "scalar";
		CApi.ValueRef operation = (CApi.ValueRef) (void*) null;
		var result = store ? stored : CApi.const_null (types.value_type (contract.vector_type));
		if (!scalar) {
			operation = store ? CApi.build_store (builder, stored, pointer) : CApi.build_load (builder, types.value_type (contract.vector_type), pointer, name);
			CApi.set_alignment (operation, contract.alignment);
			if (!store) {
				result = operation;
			}
		} else {
			for (int lane = 0; lane < contract.vector_type.lane_count; lane++) {
				var ordinal = CApi.const_int (wide, lane, 0);
				var selector = CApi.const_int (integer, lane, 0);
				var address = CApi.build_gep (builder, types.value_type (contract.vector_type.element_type), pointer, &ordinal, 1, name + ".scalar.address");
				if (store) {
					operation = CApi.build_store (builder, CApi.build_extract_element (builder, stored, selector, name + ".scalar.lane"), address);
				} else {
					operation = CApi.build_load (builder, types.value_type (contract.vector_type.element_type), address, name + ".scalar.load");
					result = CApi.build_insert_element (builder, result, operation, selector, name + ".scalar.result");
				}
				CApi.set_alignment (operation, 1);
			}
		}
		var binding = new LlvmVectorMemoryBinding (operation, scalar ? 1 : contract.alignment);
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			if ((void*) block != (void*) original && old_blocks.contains ((void*) block)) {
				continue;
			}
			var first = (void*) block == (void*) original && (void*) preceding != null ? CApi.next_instruction(preceding) : CApi.first_instruction (block);
			for (var step = first; (void*) step != null; step = CApi.next_instruction (step)) {
				binding.proof.add (new LlvmFloatingStep (step));
			}
		}
		artifact.vector_memory.add (binding);
		return result;
	}

}
}
