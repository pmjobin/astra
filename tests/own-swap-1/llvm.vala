// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.OwnSwapPipeline {
private LlvmModuleArtifact artifact() throws GLib.Error {
	SsaProgram? source = build ();
	var function = WeakRef (source.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? foreign = CAbiBuilder.build (source, native);
	var lowered = LlvmLowering.lower (source, native, foreign);
	source = null;
	native = null;
	foreign = null;
	assert (function.get () == null);
	lowered.verify ();
	return lowered;
}
private void lifetime() {
	try {
		for (int i = 0; i < 3; i++) {
			var lowered = artifact ();
			assert (lowered.buffer_exchanges.length > 8);
			foreach (var exchange in lowered.buffer_exchanges) {
				exchange.verify ();
			}
			var target = new LlvmTargetMachineArtifact ();
			target.configure (lowered);
			lowered.verify ();
			var ir = lowered.dump ();
			assert (ir.contains ("buffer.exchange") && !ir.contains ("llvm.memcpy") && !ir.contains ("llvm.memmove"));
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void correspondence() {
	try {
		var source = build ();
		int tested = 0;
		foreach (var function in source.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var exchange = block.instructions[i] as SsaBufferExchangeInstruction;
					if (exchange == null) {
						continue;
					}
					var plan = LlvmBufferExchangePlan.build (function, block, i);
					plan.verify ();
					var wrong = new LlvmBufferExchangePlan (plan.span, plan.function_ordinal, plan.block_ordinal, plan.position + 1, plan.left, plan.right);
					wrong.verify ();
					try {
						wrong.validate (function, exchange);
					} catch (LlvmError error) {
						assert (error.message.contains ("different source operation"));
						tested++;
						continue;
					}
					GLib.error ("accepted valid exchange plan for a different source operation");
				}
			}
		}
		assert (tested > 8);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void malformed() {
	string[] reasons = {
		"opposite complete", "opposite complete", "different descriptor", "different declared owner", "before any store", "incomplete permutation", "intervening effect", "intervening effect", "intervening effect", "snapshot escapes"
	};
	for (int variant = 0; variant < reasons.length; variant++) {
		try {
			var lowered = artifact ();
			LlvmBufferExchangeBinding? exchange = null;
			foreach (var candidate in lowered.buffer_exchanges) {
				if (candidate.left.plan.storage >= 0 && candidate.right.plan.storage >= 0 && candidate.left.plan.storage != candidate.right.plan.storage) {
					exchange = candidate;
					break;
				}
			}
			assert (exchange != null);
			if (variant == 0) {
				CApi.set_operand (exchange.instructions[5], 0, exchange.instructions[1]);
			}
			if (variant == 1) {
				CApi.set_operand (exchange.instructions[4], 0, exchange.instructions[0]);
			}
			if (variant == 2) {
				CApi.set_operand (exchange.instructions[4], 1, exchange.right.base_address);
			}
			if (variant == 3) {
				exchange.left.address = exchange.right.address;
				exchange.left.base_address = exchange.right.base_address;
				exchange.left.count_address = exchange.right.count_address;
			}
			if (variant == 4) {
				LlvmBufferExchangeStep[] steps = {
					LlvmBufferExchangeStep.LEFT_BASE, LlvmBufferExchangeStep.LEFT_COUNT, LlvmBufferExchangeStep.STORE_LEFT_BASE, LlvmBufferExchangeStep.RIGHT_COUNT, LlvmBufferExchangeStep.RIGHT_BASE, LlvmBufferExchangeStep.STORE_LEFT_COUNT, LlvmBufferExchangeStep.STORE_RIGHT_BASE, LlvmBufferExchangeStep.STORE_RIGHT_COUNT
				};
				var p = exchange.plan;
				exchange.plan = new LlvmBufferExchangePlan (p.span, p.function_ordinal, p.block_ordinal, p.position, p.left, p.right, steps);
			}
			if (variant == 5) {
				exchange.instructions = exchange.instructions[0:7];
			}
			if (variant >= 6) {
				var builder = CApi.create_builder_in_context (lowered.context);
				if (variant == 6) {
					// A pointer store after the opposite pointer capture, before
					// its count capture: well typed LLVM, incomplete permutation.
					CApi.remove_instruction (exchange.instructions[4]);
					CApi.position_builder_before (builder, exchange.instructions[3]);
					CApi.insert_instruction (builder, exchange.instructions[4]);
				} else {
					CApi.position_builder_before (builder, variant == 9 ? CApi.next_instruction (exchange.instructions[7]) : exchange.instructions[4]);
					if (variant == 7) {
						var signature = CApi.function_type (CApi.void_type_in_context (lowered.context), null, 0, 0);
						var callback = CApi.add_function (lowered.module, "forged_exchange_callback", signature);
						CApi.build_call (builder, signature, callback, null, 0, "");
					} else {
						var hidden = CApi.build_alloca (builder, exchange.left.carrier, "forged.owner");
						CApi.build_store (builder, exchange.instructions[0], hidden);
					}
				}
				CApi.dispose_builder (builder);
			}
			try {
				lowered.verify ();
			} catch (LlvmError error) {
				Test.message ("variant %d: %s", variant, error.message);
				assert (error.message.contains (reasons[variant]));
				continue;
			}
			GLib.error ("accepted malformed LLVM exchange %d", variant);
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
}
private void field_guards() {
	string[] reasons = {
		"exact physical null guard", "exact reference", "successful guard continuation", "different receiver", "left-to-right order"
	};
	for (int variant = 0; variant < reasons.length; variant++) {
		try {
			var lowered = artifact ();
			LlvmBufferExchangeBinding? exchange = null;
			foreach (var candidate in lowered.buffer_exchanges) {
				if (candidate.left.receiver_origin != null && candidate.right.receiver_origin != null && candidate.left.receiver_origin.type is Astra.Semantic.ClassType && candidate.right.receiver_origin.type is Astra.Semantic.ClassType) {
					exchange = candidate;
					break;
				}
			}
			assert (exchange != null);
			var binding = exchange.left.receiver_origin;
			if (variant == 0) {
				binding.guard = (CApi.ValueRef) null;
			}
			if (variant == 1) {
				CApi.set_operand (binding.guard, 0, CApi.const_int (CApi.int_type_in_context (lowered.context, 1), 0, 0));
			}
			if (variant == 2 || variant == 4) {
				var builder = CApi.create_builder_in_context (lowered.context);
				var moved = variant == 2 ? exchange.left.address : CApi.condition (exchange.right.receiver_origin.guard);
				CApi.remove_instruction (moved);
				CApi.position_builder_before (builder, CApi.condition (binding.guard));
				CApi.insert_instruction (builder, moved);
				CApi.dispose_builder (builder);
			}
			if (variant == 3) {
				exchange.left.receiver_origin = exchange.right.receiver_origin;
			}
			try {
				lowered.verify ();
			} catch (LlvmError error) {
				Test.message ("field variant %d: %s", variant, error.message);
				assert (error.message.contains (reasons[variant]));
				continue;
			}
			GLib.error ("accepted malformed physical receiver proof %d", variant);
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-swap/llvm/predecessor-lifetime-and-closed-region", lifetime);
	Test.add_func ("/own-swap/llvm/source-operation-correspondence", correspondence);
	Test.add_func ("/own-swap/llvm/reject-half-mixed-and-wrong-slot-exchanges", malformed);
	Test.add_func ("/own-swap/llvm/retained-field-guard-and-projection-order", field_guards);
	Test.add_func ("/own-swap/pipeline/repeated-definition-growth-cycle-failure-success", recovery);
	return Test.run ();
}
}
