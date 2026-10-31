// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.SharedLifetime {
[CCode (cheader_filename = "llvm-c/Core.h", cname = "LLVMInstructionEraseFromParent")]
private static extern void erase_instruction(CApi.ValueRef instruction);
[CCode (cheader_filename = "llvm-c/Core.h", cname = "LLVMCountIncoming")]
private static extern uint incoming_count(CApi.ValueRef instruction);
[CCode (cheader_filename = "llvm-c/Core.h", cname = "LLVMGetBasicBlockName")]
private static extern unowned string block_name(CApi.BasicBlockRef block);
private CheckedProgram source() {
	string text = "class P{int value;init(int n){this.value=n;}deinit(){}}class Q{init(){}}"
	    + "int read(borrowed P p){return p.value;}int main(){var p=new P(7);var s=shared_acquire(move p);var copy=shared_clone(s);var w=shared_downgrade(s);var again=weak_upgrade(w);if(again==null){return 81;}return read(shared_borrow(again));}";
	var parsed = Parser.parse(new SourceFile.from_text("shared-contract", text));
	if (parsed.diagnostic != null) {
		GLib.error("%s", parsed.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze(parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error("%s", checked.diagnostic.message);
	}
	return checked.program;
}
private void authority() {
	try {
		var checked = source();
		LocalSymbol? unique = null;
		foreach (var function in checked.functions) {
			foreach (var local in function.locals) {
				if (local.heap_object) {
					unique = local;
					break;
				}
			}
		}
		assert(unique != null);
		unique.heap_object = false;
		bool rejected = false;
		try{
			CoreBuilder.build(checked);
		} catch (CoreError error) {
			rejected = true;
			Test.message("Checked heap origin: %s", error.message);
		}
		assert(rejected);
		var core = CoreBuilder.build(source());
		CoreVerifier.verify(core);
		CoreCleanupContract? contract = null;
		foreach (var cleanup in core.cleanups) {
			if (cleanup.shared_type != null) {
				contract = cleanup;
				break;
			}
		}
		assert(contract != null);
		var payload = contract.shared_payload;
		contract.shared_payload = core.classes[1];
		rejected = false;
		try{
			CoreVerifier.verify(core);
		} catch (CoreError error) {
			rejected = true;
			Test.message("Core payload authority: %s", error.message);
		}
		assert(rejected);
		contract.shared_payload = payload;
		CoreVerifier.verify(core);
		var cfg = CfgBuilder.build(core);
		CfgVerifier.verify(cfg);
		CfgCleanupContract? cfg_contract = null;
		foreach (var cleanup in cfg.cleanups) {
			if (cleanup.shared_type != null) {
				cfg_contract = cleanup;
				break;
			}
		}
		assert(cfg_contract != null);
		var cfg_payload = cfg_contract.shared_payload;
		cfg_contract.shared_payload = cfg.classes[1];
		rejected = false;
		try{
			CfgVerifier.verify(cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message("CFG payload authority: %s", error.message);
		}
		assert(rejected);
		cfg_contract.shared_payload = cfg_payload;
		CfgVerifier.verify(cfg);
		var ssa = SsaBuilder.build(cfg);
		SsaVerifier.verify(ssa);
		SsaCleanupContract? ssa_contract = null;
		foreach (var cleanup in ssa.cleanups) {
			if (cleanup.shared_type != null) {
				ssa_contract = cleanup;
				break;
			}
		}
		assert(ssa_contract != null);
		var ssa_payload = ssa_contract.shared_payload;
		ssa_contract.shared_payload = ssa.classes[1];
		rejected = false;
		try{
			SsaVerifier.verify(ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message("SSA payload authority: %s", error.message);
		}
		assert(rejected);
		ssa_contract.shared_payload = ssa_payload;
		SsaVerifier.verify(ssa);
		int transitions = 0;
		int reads = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaSharedOperation;
					if (operation == null || operation.source_owner == null) {
						continue;
					}
					assert(i > 0);
					var read = block.instructions[i - 1];
					block.instructions.remove_index(i - 1);
					rejected = false;
					try{
						SsaVerifier.verify(ssa);
					} catch (SsaError error) {
						rejected = true;
						Test.message("SSA missing live owner READ: %s", error.message);
					}
					assert(rejected);
					block.instructions.insert(i - 1, read);
					SsaVerifier.verify(ssa);
					reads++;
				}
			}
		}
		assert(reads > 0);
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaSharedOperation;
					if (operation == null || operation.action == SharedAction.BORROW) {
						continue;
					}
					var saved = block.instructions[i];
					block.instructions[i] = new SsaSharedOperation(operation.span, operation.result.semantic_type, SharedAction.BORROW, operation.operand, operation.cleanup, operation.borrower, operation.result.ordinal);
					rejected = false;
					try{
						SsaVerifier.verify(ssa);
					} catch (SsaError error) {
						rejected = true;
						Test.message("SSA typed transition: %s", error.message);
					}
					assert(rejected);
					block.instructions[i] = saved;
					SsaVerifier.verify(ssa);
					transitions++;
				}
			}
		}
		assert(transitions >= 4);
		var native = NativeAbiBuilder.build(ssa);
		NativeAbiVerifier.verify(native);
		assert(native.shared_operations.length >= 4);
		var native_saved = native.shared_operations[0];
		native.shared_operations[0] = new NativeSharedOperationPlan(native_saved.caller, native_saved.block, native_saved.instruction, native_saved.action, new NativeSharedHandleType("forged-payload", false));
		rejected = false;
		try{
			NativeAbiVerifier.verify(native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message("Native payload authority: %s", error.message);
		}
		assert(rejected);
		native.shared_operations[0] = native_saved;
		NativeAbiVerifier.verify(native);
		var mapping = new HashTable<SsaFunction, NativeFunction>(direct_hash, direct_equal);
		foreach (var function in ssa.functions) {
			mapping.insert(function, native.functions[function.ordinal]);
		}
		native.shared_operations.remove_index(0);
		rejected = false;
		try{
			NativeAbiValidator.validate_ssa_calls(ssa, native, mapping);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message("Native missing lifecycle plan: %s", error.message);
		}
		assert(rejected);
		native.shared_operations.insert(0, native_saved);
		NativeAbiVerifier.verify(native);
		NativeAbiValidator.validate_ssa_calls(ssa, native, mapping);
		var artifact = LlvmLowering.lower(ssa, native, CAbiBuilder.build(ssa, native));
		artifact.verify();
		int arithmetic = 0;
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			if ((void*)CApi.is_instruction(instruction) == null || (CApi.opcode(instruction) != CApi.Opcode.ADD && CApi.opcode(instruction) != CApi.Opcode.SUB)) {
				continue;
			}
			var saved = CApi.operand(instruction, 1);
			CApi.set_operand(instruction, 1, CApi.const_null(CApi.type_of(saved)));
			rejected = false;
			try{
				artifact.verify();
			} catch (LlvmError error) {
				rejected = true;
				Test.message("LLVM count correspondence: %s", error.message);
			}
			assert(rejected);
			CApi.set_operand(instruction, 1, saved);
			artifact.verify();
			arithmetic++;
		}
		assert(arithmetic > 0);
		var mutation = CApi.create_builder_in_context(artifact.context);
		int missing_increment = 0;
		int missing_free = 0;
		int doubled_destructor = 0;
		int false_upgrade = 0;
		int overflow_guards = 0;
		int underflow_guards = 0;
		foreach (var binding in artifact.class_branches) {
			var instruction = binding.instruction;
			string name = block_name(CApi.successor(instruction, 0));
			if (!name.contains("overflow.trap") && !name.contains("underflow.trap")) {
				continue;
			}
			var saved = CApi.operand(instruction, 0);
			CApi.set_operand(instruction, 0, CApi.const_null(CApi.type_of(saved)));
			rejected = false;
			try{
				artifact.verify();
			} catch (LlvmError error) {
				rejected = true;
				Test.message("LLVM missing count guard: %s", error.message);
			}
			assert(rejected);
			CApi.set_operand(instruction, 0, saved);
			artifact.verify();
			if (name.contains("overflow.trap")) {
				overflow_guards++;
			} else{
				underflow_guards++;
			}
		}
		assert(overflow_guards > 0 && underflow_guards > 0);
		foreach (var binding in artifact.shared_atomics) {
			var instruction = binding.instruction;
			if (CApi.opcode(instruction) != CApi.Opcode.ATOMIC_CMP_XCHG) {
				continue;
			}
			var stored = CApi.operand(instruction, 2);
			if ((void*)CApi.is_instruction(stored) == null || CApi.opcode(stored) != CApi.Opcode.ADD) {
				continue;
			}
			var next = CApi.next_instruction(instruction);
			assert((void*)next != null);
			CApi.remove_instruction(instruction);
			rejected = false;
			try{
				artifact.verify();
			} catch (LlvmError error) {
				rejected = true;
				Test.message("LLVM missing increment publication: %s", error.message);
			}
			assert(rejected);
			CApi.position_builder_before(mutation, next);
			CApi.insert_instruction(mutation, instruction);
			artifact.verify();
			missing_increment++;
			break;
		}
		assert(missing_increment == 1);
		foreach (var binding in artifact.class_calls) {
			var instruction = binding.instruction;
			size_t name_length;
			string target_name = CApi.value_name(CApi.called_value(instruction), out name_length);
			size_t argument_length;
			string allocation = CApi.argument_count(instruction) == 1?CApi.value_name(CApi.operand(instruction, 0), out argument_length):"";
			if (target_name == "free" && allocation.has_prefix("shared.block.base")) {
				var next = CApi.next_instruction(instruction);
				assert((void*)next != null);
				CApi.remove_instruction(instruction);
				rejected = false;
				try{
					artifact.verify();
				} catch (LlvmError error) {
					rejected = true;
					Test.message("LLVM missing control block free: %s", error.message);
				}
				assert(rejected);
				CApi.position_builder_before(mutation, next);
				CApi.insert_instruction(mutation, instruction);
				artifact.verify();
				missing_free++;
				break;
			}
		}
		assert(missing_free == 1);
		foreach (var binding in artifact.class_calls) {
			var instruction = binding.instruction;
			var signature = CApi.called_function_type(instruction);
			if (CApi.argument_count(instruction) != 1 || CApi.instruction_call_conv(instruction) != LlvmLowering.CALL_CONVENTION || CApi.type_kind(CApi.return_type(signature)) != CApi.TypeKind.VOID) {
				continue;
			}
			CApi.position_builder_before(mutation, instruction);
			var argument = CApi.operand(instruction, 0);
			var duplicate = CApi.build_call(mutation, signature, CApi.called_value(instruction), &argument, 1, "");
			CApi.set_instruction_call_conv(duplicate, LlvmLowering.CALL_CONVENTION);
			rejected = false;
			try{
				artifact.verify();
			} catch (LlvmError error) {
				rejected = true;
				Test.message("LLVM duplicated payload destructor: %s", error.message);
			}
			assert(rejected);
			erase_instruction(duplicate);
			artifact.verify();
			doubled_destructor++;
			break;
		}
		assert(doubled_destructor == 1);
		for (var function = CApi.first_function(artifact.module); (void*)function != null; function = CApi.next_function(function)) {
			for (var block = CApi.first_block(function); (void*)block != null; block = CApi.next_block(block)) {
				for (var instruction = CApi.first_instruction(block); (void*)instruction != null; instruction = CApi.next_instruction(instruction)) {
					if (CApi.opcode(instruction) != CApi.Opcode.PHI || incoming_count(instruction) != 3) {
						continue;
					}
					size_t name_length;
					string name = CApi.value_name(instruction, out name_length);
					if (!name.has_prefix("shared.result")) {
						continue;
					}
					var saved = CApi.operand(instruction, 0);
					CApi.set_operand(instruction, 0, CApi.incoming_value(instruction, 1));
					rejected = false;
					try{
						artifact.verify();
					} catch (LlvmError error) {
						rejected = true;
						Test.message("LLVM false expired upgrade publication: %s", error.message);
					}
					assert(rejected);
					CApi.set_operand(instruction, 0, saved);
					artifact.verify();
					false_upgrade++;
				}
			}
		}
		assert(false_upgrade > 0);
		CApi.dispose_builder(mutation);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
public int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/shared/exact-native-lifetime-authority", authority);
	return Test.run();
}
}
