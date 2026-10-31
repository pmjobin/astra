// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Backend.LLVM {
internal class LlvmVolatileAccess : Object {
	internal CApi.ValueRef operation;
	private CApi.ValueRef pointer;
	private CApi.ValueRef stored;
	private CApi.TypeRef type;
	private CApi.BasicBlockRef block;
	private uint alignment;
	private bool write;

	internal LlvmVolatileAccess (CApi.ValueRef operation, CApi.ValueRef pointer, CApi.TypeRef type, uint alignment, bool write, CApi.ValueRef stored) {
		this.operation = operation;
		this.pointer = pointer;
		this.type = type;
		this.alignment = alignment;
		this.write = write;
		this.stored = stored;
		block = CApi.instruction_parent (operation);
	}

	internal void verify() throws LlvmError {
		bool valid = CApi.opcode (operation) == (write ? CApi.Opcode.STORE : CApi.Opcode.LOAD) && CApi.get_volatile (operation) != 0 && CApi.get_ordering (operation) == 0 && CApi.get_alignment (operation) == alignment && (void*) CApi.instruction_parent (operation) == (void*) block && (void*) CApi.operand (operation, write ? 1 : 0) == (void*) pointer;
		if (write) {
			valid &= (void*) CApi.operand (operation, 0) == (void*) stored && (void*) CApi.type_of (stored) == (void*) type;
		} else {
			valid &= (void*) CApi.type_of (operation) == (void*) type;
		}
		if (!valid) {
			throw new LlvmError.VERIFICATION ("volatile access lost its exact operation, address, width, alignment or source intent");
		}
	}
}
}
