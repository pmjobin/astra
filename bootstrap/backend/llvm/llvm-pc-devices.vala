// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Foreign;

namespace Astra.Backend.LLVM {
internal class LlvmPcAtomicBinding : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef pointer;
	private CApi.ValueRef input;
	private CApi.TypeRef type;
	private PcDeviceOperation operation;
	internal LlvmPcAtomicBinding (CApi.ValueRef instruction, CApi.ValueRef pointer, CApi.ValueRef input, CApi.TypeRef type, PcDeviceOperation operation) {
		this.instruction = instruction;
		this.pointer = pointer;
		this.input = input;
		this.type = type;
		this.operation = operation;
	}

	internal void verify() throws LlvmError {
		var opcode = operation.atomic_load () ? CApi.Opcode.LOAD : operation.atomic_store () ? CApi.Opcode.STORE : CApi.Opcode.ATOMIC_RMW;
		int address_operand = operation.atomic_store () ? 1 : 0;
		if (CApi.opcode (instruction) != opcode || CApi.get_alignment (instruction) != 4 || (uint) CApi.get_ordering (instruction) != (uint) operation.ordering () || CApi.get_volatile (instruction) != 0 || (void*) CApi.operand (instruction, address_operand) != (void*) pointer || (operation.atomic_add () && CApi.atomic_rmw_operation (instruction) != 1)) {
			throw new LlvmError.VERIFICATION ("PC atomic operation lost its exact word, width, alignment, operation or memory order");
		}
		if (operation.atomic_store () || operation.atomic_add ()) {
			if ((void*) CApi.operand (instruction, operation.atomic_store () ? 0 : 1) != (void*) input || (void*) CApi.type_of (input) != (void*) type) {
				throw new LlvmError.VERIFICATION ("PC atomic operation lost its exact input");
			}
		} else if ((void*) CApi.type_of (instruction) != (void*) type) {
			throw new LlvmError.VERIFICATION ("PC atomic load lost its exact result type");
		}
	}

}

// These are compiler-defined operations at fixed selected-target registers,
// not calls into a C implementation. The existing C signature channel carries
// only exact i32 values; no raw address or foreign ownership is admitted.
internal class LlvmPcDevices : Object {
	internal static LlvmSumSequence emit(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.TypeRef signature, PcDeviceContract contract) throws LlvmError {
		if (!contract.valid () || (void*) CApi.global_value_type (function) != (void*) signature || CApi.count_params (function) != contract.operation.argument_count ()) {
			throw new LlvmError.INVALID_INPUT ("invalid admitted PC device operation or signature");
		}
		artifact.requires_pc_devices = true;
		CApi.set_linkage (function, CApi.Linkage.INTERNAL);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, function, "device.entry"));
		var word = CApi.int32_type_in_context (artifact.context);
		var pointer_type = CApi.pointer_type_in_context (artifact.context, 0);
		var operation = contract.operation;
		var input = operation.argument_count () == 0 ? CApi.const_null (word) : CApi.get_param (function, 0);
		var result = input;
		if (operation == PcDeviceOperation.UART_TX8 || operation == PcDeviceOperation.BREAKPOINT) {
			string assembly;
			string constraints;
			CApi.TypeRef assembly_type;
			CApi.ValueRef argument;
			if (operation == PcDeviceOperation.UART_TX8) {
				var invalid = CApi.append_basic_block_in_context (artifact.context, function, "uart.invalid.width");
				var valid = CApi.append_basic_block_in_context (artifact.context, function, "uart.byte");
				CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.UGT, input, CApi.const_int (word, 255, 0), "uart.out.of.range"), invalid, valid);
				CApi.position_builder_at_end (builder, invalid);
				string name = "llvm.trap";
				uint id = CApi.lookup_intrinsic_id (name, name.length);
				var trap = CApi.get_intrinsic_declaration (artifact.module, id, null, 0);
				CApi.build_call (builder, CApi.intrinsic_get_type (artifact.context, id, null, 0), trap, null, 0, "");
				CApi.build_unreachable (builder);
				CApi.position_builder_at_end (builder, valid);
				var byte = CApi.int_type_in_context (artifact.context, 8);
				assembly_type = CApi.function_type (CApi.void_type_in_context (artifact.context), &byte, 1, 0);
				argument = CApi.build_trunc (builder, input, byte, "uart.value");
				assembly = "movw $$1021, %dx\n1:\ninb %dx, %al\ntestb $$32, %al\njz 1b\nmovb %cl, %al\nmovw $$1016, %dx\noutb %al, %dx";
				constraints = "{cl},~{ax},~{dx},~{memory},~{flags}";
			} else {
				assembly_type = CApi.function_type (word, &word, 1, 0);
				argument = input;
				assembly = "int $$3";
				constraints = "={ax},0,~{memory},~{flags}";
			}
			var code = CApi.inline_assembly (assembly_type, assembly, assembly.length, constraints, constraints.length, 1, 0, 0, 0);
			var call = CApi.build_call (builder, assembly_type, code, &argument, 1, operation == PcDeviceOperation.BREAKPOINT ? "trap.returned" : "");
			if (operation == PcDeviceOperation.BREAKPOINT) {
				result = call;
			}
		} else if (operation == PcDeviceOperation.EDU_READ32 || operation == PcDeviceOperation.EDU_WRITE32) {
			var pointer = CApi.const_int_to_ptr (CApi.const_int (CApi.int_type_in_context (artifact.context, 64), 0xf0000004, 0), pointer_type);
			bool write = operation == PcDeviceOperation.EDU_WRITE32;
			var access = write ? CApi.build_store (builder, input, pointer) : CApi.build_load (builder, word, pointer, "edu.liveness");
			CApi.set_volatile (access, 1);
			CApi.set_alignment (access, 4);
			artifact.volatile_accesses.add (new LlvmVolatileAccess (access, pointer, word, 4, write, input));
			if (!write) {
				result = access;
			}
		} else {
			var cell = CApi.named_global (artifact.module, "astra.pc.atomic.word");
			if ((void*) cell == null) {
				cell = CApi.add_global (artifact.module, word, "astra.pc.atomic.word");
				CApi.set_linkage (cell, CApi.Linkage.INTERNAL);
				CApi.set_alignment (cell, 4);
				CApi.set_initializer (cell, CApi.const_null (word));
			}
			var access = operation.atomic_load () ? CApi.build_load (builder, word, cell, "atomic.read") : operation.atomic_store () ? CApi.build_store (builder, input, cell) : CApi.build_atomic_rmw (builder, 1, cell, input, operation.ordering (), 0);
			if (!operation.atomic_add ()) {
				CApi.set_ordering (access, operation.ordering ());
			}
			CApi.set_alignment (access, 4);
			artifact.pc_atomics.add (new LlvmPcAtomicBinding (access, cell, input, word, operation));
			if (!operation.atomic_store ()) {
				result = access;
			}
		}
		CApi.build_ret (builder, result);
		CApi.dispose_builder (builder);
		return new LlvmSumSequence (function, true);
	}

}
}
