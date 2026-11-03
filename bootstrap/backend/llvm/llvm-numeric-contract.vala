// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Backend.LLVM {
internal class LlvmSaturationBinding : Object {
	internal CApi.ValueRef call;
	private CApi.ValueRef declaration;
	private CApi.TypeRef signature;
	private CApi.ValueRef first;
	private CApi.ValueRef second;
	private uint identity;

	internal LlvmSaturationBinding (CApi.ValueRef call, CApi.ValueRef declaration, CApi.TypeRef signature, CApi.ValueRef first, CApi.ValueRef second, uint identity) {
		this.call = call;
		this.declaration = declaration;
		this.signature = signature;
		this.first = first;
		this.second = second;
		this.identity = identity;
	}

	internal void verify() throws LlvmError {
		if (CApi.opcode (call) != CApi.Opcode.CALL || (void*) CApi.instruction_parent (call) == null || (void*) CApi.called_value (call) != (void*) declaration || CApi.intrinsic_id (declaration) != identity || (void*) CApi.called_function_type (call) != (void*) signature || CApi.argument_count (call) != 2 || (void*) CApi.operand (call, 0) != (void*) first || (void*) CApi.operand (call, 1) != (void*) second) {
			throw new LlvmError.VERIFICATION ("saturation lost its exact signed operation, lane type or operands");
		}
	}

}

internal class LlvmFloatingStep : Object {
	internal CApi.ValueRef instruction;
	private CApi.BasicBlockRef parent;
	private CApi.Opcode operation;
	private CApi.ValueRef[] operands;
	private int predicate = -1;
	private int integer_predicate = -1;
	private uint flags;
	private uint memory_alignment;
	private int memory_volatile;
	private uint call_convention;
	internal LlvmFloatingStep (CApi.ValueRef instruction) {
		this.instruction = instruction;
		parent = CApi.instruction_parent (instruction);
		operation = CApi.opcode (instruction);
		operands = new CApi.ValueRef[CApi.operand_count (instruction)];
		if (operation == CApi.Opcode.CALL) {
			call_convention = CApi.instruction_call_conv (instruction);
		}
		for (int i = 0; i < operands.length; i++) {
			operands[i] = CApi.operand (instruction, i);
		}
		if (operation == CApi.Opcode.LOAD || operation == CApi.Opcode.STORE) {
			memory_alignment = CApi.get_alignment (instruction);
			memory_volatile = CApi.get_volatile (instruction);
		}
		if (operation == CApi.Opcode.ICMP) {
			integer_predicate = (int) CApi.predicate (instruction);
		}
		if (operation == CApi.Opcode.FCMP) {
			predicate = (int) CApi.real_predicate (instruction);
		}
		if (CApi.can_use_fast_math_flags (instruction) != 0) {
			flags = CApi.get_fast_math_flags (instruction);
		}
	}

	internal void verify() throws LlvmError {
		if (operation == CApi.Opcode.CALL && CApi.instruction_call_conv (instruction) != call_convention) {
			throw new LlvmError.VERIFICATION ("derived instruction lost its original call convention");
		}
		if ((void*) CApi.instruction_parent (instruction) != (void*) parent || (void*) parent == null || CApi.opcode (instruction) != operation || CApi.operand_count (instruction) != operands.length || ((operation == CApi.Opcode.LOAD || operation == CApi.Opcode.STORE) && (CApi.get_alignment (instruction) != memory_alignment || CApi.get_volatile (instruction) != memory_volatile)) || (predicate >= 0 && (int) CApi.real_predicate (instruction) != predicate) || (integer_predicate >= 0 && (int) CApi.predicate (instruction) != integer_predicate) || (CApi.can_use_fast_math_flags (instruction) != 0 && CApi.get_fast_math_flags (instruction) != flags)) {
			throw new LlvmError.VERIFICATION ("floating domain lost its original operation, guard or continuation");
		}
		for (int i = 0; i < operands.length; i++) {
			if ((void*) CApi.operand (instruction, i) != (void*) operands[i]) {
				throw new LlvmError.VERIFICATION ("floating domain lost its checked operands or trap edge");
			}
		}
	}

}

internal class LlvmFloatingDomain : Object {
	internal GenericArray<LlvmFloatingStep> steps = new GenericArray<LlvmFloatingStep> ();
	internal void verify() throws LlvmError {
		foreach (var step in steps) {
			step.verify ();
		}
	}

}

internal class LlvmFloatingPermission : Object {
	internal CApi.ValueRef instruction;
	private uint permissions;
	private LlvmFloatingStep operation;
	internal LlvmFloatingDomain? domain;
	internal LlvmFloatingPermission (CApi.ValueRef instruction, uint permissions, LlvmFloatingDomain? domain) {
		this.instruction = instruction;
		this.permissions = permissions;
		this.domain = domain;
		operation = new LlvmFloatingStep (instruction);
	}

	internal void verify() throws LlvmError {
		operation.verify ();
		if ((permissions & 6) != 0 && domain == null) {
			throw new LlvmError.VERIFICATION ("finite floating permissions require a checked domain");
		}
		if (domain != null) {
			domain.verify ();
		}
		if ((void*) CApi.instruction_parent (instruction) == null || CApi.can_use_fast_math_flags (instruction) == 0 || CApi.get_fast_math_flags (instruction) != permissions || !Astra.Semantic.FloatingPointPolicy.valid (permissions)) {
			throw new LlvmError.VERIFICATION ("floating instruction lost its exact admitted permissions");
		}
	}

}

internal class LlvmStrictFloating : Object {
	internal static void verify(CApi.ModuleRef module, uint permitted = 0, GenericArray<LlvmFloatingPermission>? bindings = null) throws LlvmError {
		var registered = new HashTable<void*, bool> (direct_hash, direct_equal);
		if (bindings != null) {
			foreach (var binding in bindings) {
				binding.verify ();
				registered.insert ((void*) binding.instruction, true);
			}
		}
		for (var function = CApi.first_function (module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.can_use_fast_math_flags (instruction) != 0) {
						uint flags = CApi.get_fast_math_flags (instruction);
						if ((flags & ~permitted) != 0 || (bindings != null && flags != 0 && !registered.contains ((void*) instruction))) {
							throw new LlvmError.VERIFICATION ("strict floating operations cannot acquire unadmitted fast-math or contraction flags");
						}
					}
				}
			}
		}
	}

}
}
