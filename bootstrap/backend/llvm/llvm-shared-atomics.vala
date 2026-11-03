// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Backend.LLVM {
// Physical correspondence is captured before observing emitted instructions.
// Count accesses require system scope, natural alignment and exact ordering.
internal class LlvmSharedAtomicBinding : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef pointer;
	private CApi.ValueRef expected;
	private CApi.ValueRef replacement;
	private CApi.Opcode opcode;
	private int ordering;
	private CApi.BasicBlockRef block;

	internal LlvmSharedAtomicBinding (CApi.ValueRef instruction, CApi.ValueRef pointer, CApi.Opcode opcode, int ordering, CApi.ValueRef expected = (CApi.ValueRef) null, CApi.ValueRef replacement = (CApi.ValueRef) null) {
		this.instruction = instruction;
		this.pointer = pointer;
		this.opcode = opcode;
		this.ordering = ordering;
		this.expected = expected;
		this.replacement = replacement;
		block = CApi.instruction_parent (instruction);
	}

	internal void verify() throws LlvmError {
		var count = opcode == CApi.Opcode.LOAD ? instruction : opcode == CApi.Opcode.STORE ? replacement : expected;
		var i64 = CApi.int_type_in_context (CApi.type_context (CApi.type_of (pointer)), 64);
		if ((void*) count == null || (void*) CApi.type_of (count) != (void*) i64 || (opcode == CApi.Opcode.ATOMIC_CMP_XCHG && (void*) CApi.type_of (replacement) != (void*) i64)) {
			throw new LlvmError.VERIFICATION ("shared atomic count lost its exact i64 width");
		}
		int address_index = opcode == CApi.Opcode.STORE ? 1 : 0;
		if (CApi.opcode (instruction) != opcode || (void*) CApi.instruction_parent (instruction) != (void*) block || CApi.get_alignment (instruction) != 8 || CApi.get_volatile (instruction) != 0 || CApi.atomic_single_thread (instruction) != 0 || (void*) CApi.operand (instruction, address_index) != (void*) pointer) {
			throw new LlvmError.VERIFICATION ("shared atomic lost its exact operation, address, system scope, alignment or block");
		}
		if (opcode == CApi.Opcode.ATOMIC_CMP_XCHG) {
			if (CApi.cmp_xchg_success_order (instruction) != 6 || CApi.cmp_xchg_failure_order (instruction) != 4 || CApi.cmp_xchg_weak (instruction) != 0 || (void*) CApi.operand (instruction, 1) != (void*) expected || (void*) CApi.operand (instruction, 2) != (void*) replacement) {
				throw new LlvmError.VERIFICATION ("shared CAS lost acquire-release success, acquire failure, checked expected count or unique replacement");
			}
		} else if ((int) CApi.get_ordering (instruction) != ordering || (opcode == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 0) != (void*) replacement)) {
			throw new LlvmError.VERIFICATION ("shared count load/publication lost its admitted memory order or initial value");
		}
	}

}
}
