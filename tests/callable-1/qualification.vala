// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Continuations;
using Astra.Backend.LLVM;

namespace Astra.Tests.Continuations {
private LlvmModuleArtifact artifact() throws GLib.Error {
	SsaProgram? source = build ();
	var graph = WeakRef (source);
	var region = WeakRef (region_of (source));
	var function = WeakRef (source.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? foreign = CAbiBuilder.build (source, native);
	var result = LlvmLowering.lower (source, native, foreign);
	source = null;
	native = null;
	foreign = null;
	assert (graph.get () == null && region.get () == null && function.get () == null);
	result.verify ();
	return result;
}

private void lifetime() {
	try {
		for (int repeat = 0; repeat < 3; repeat++) {
			SsaProgram? source = build ();
			var graph = WeakRef (source);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			NativeContinuationRegionPlan? plan = native.continuations[0];
			source = null;
			assert (graph.get () == null);
			NativeAbiVerifier.verify (native);
			native = null;
			plan.verify ();
			plan = null;
			var lowered = artifact ();
			assert (lowered.continuation_calls.length == 11);
			new LlvmTargetMachineArtifact ().configure (lowered);
			lowered.verify ();
			var ir = lowered.dump ();
			assert (ir.contains ("continuation.runtime.code") && ir.contains ("call fastcc i32 %continuation.code") && ir.contains ("continuation.whole.move") && ir.contains ("continuation.snapshot"));
			var call = lowered.continuation_calls[lowered.continuation_calls.length - 1].call;
			var predecessor = CApi.instruction_parent (call);
			var phi = CApi.first_instruction (CApi.next_block (CApi.first_block (CApi.named_function (lowered.module, "astra.fn.%d".printf (lowered.continuation_calls[0].plan.function_ordinal)))));
			assert (CApi.opcode (phi) == CApi.Opcode.PHI && CApi.incoming_count (phi) == 1 && (void*) CApi.incoming_block (phi, 0) == (void*) predecessor && (void*) CApi.incoming_value (phi, 0) == (void*) call);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private ContinuationAction replace_owner(ContinuationAction action, int owner) {
	var captures = new int[action.capture_count];
	for (int i = 0; i < captures.length; i++) {
		captures[i] = action.capture (i);
	}
	return new ContinuationAction (action.kind, owner, action.destination, action.family, action.instance, action.witness, action.operand, action.first_entry, action.second_entry, action.role, captures);
}

private void mutate_actions(GenericArray<ContinuationAction> actions, int variant) {
	if (variant == 0) {
		actions[0] = new ContinuationAction (ContinuationActionKind.CREATE, 0, -1, 99, 0);
	}
	if (variant == 1) {
		actions[2] = new ContinuationAction (ContinuationActionKind.PUBLISH, 0, -1, -1, -1, -1, 0, 2, 0);
	}
	if (variant == 2) {
		actions[3] = new ContinuationAction (ContinuationActionKind.CREATE, 0, -1, 0, 1);
	}
	if (variant == 3) {
		actions[3] = new ContinuationAction (ContinuationActionKind.CREATE, 1, -1, 0, 0);
	}
	if (variant == 4) {
		actions.remove_index (1);
	}
	if (variant == 5) {
		actions[1] = new ContinuationAction (ContinuationActionKind.INITIALIZE, 0, -1, -1, -1, -1, 4, -1, -1, ContinuationRole.STEP, new int[] { 1, 3, 2 });
	}
	if (variant == 6) {
		actions[7] = new ContinuationAction (ContinuationActionKind.CALL, 0, -1, -1, -1, 0, 2);
	}
	if (variant == 7) {
		actions[7] = new ContinuationAction (ContinuationActionKind.CALL, 0, -1, -1, -1, 0, 1, -1, -1, ContinuationRole.DESTROY);
	}
	if (variant == 8) {
		actions[8] = new ContinuationAction (ContinuationActionKind.BEGIN, 0, -1, -1, -1, 999);
	}
	if (variant == 9) {
		actions[8] = new ContinuationAction (ContinuationActionKind.DESTROY, 0);
	}
	if (variant == 10) {
		actions[7] = new ContinuationAction (ContinuationActionKind.MOVE, 0, 99);
	}
	if (variant == 11) {
		actions[14] = replace_owner (actions[14], 0);
	}
	if (variant == 12) {
		actions[14] = new ContinuationAction (ContinuationActionKind.DESTROY, 2);
	}
	if (variant == 13) {
		actions[20] = new ContinuationAction (ContinuationActionKind.RELEASE, 1, -1, -1, -1, 100);
	}
	if (variant == 14) {
		actions[22] = new ContinuationAction (ContinuationActionKind.DESTROY, 2);
	}
	if (variant == 15) {
		actions.remove_index (21);
	}
	if (variant == 16) {
		actions[12] = new ContinuationAction (ContinuationActionKind.MOVE, 0, 1);
	}
	if (variant == 17) {
		actions[8] = new ContinuationAction (ContinuationActionKind.END, 1, -1, -1, -1, 0);
	}
}

private string[] reasons;
private void initialize_reasons() {
	reasons = {
		"wrong operation family", "step", "duplicate owning descriptor", "duplicate environment", "initializ", "capture", "signature", "role", "reentrant", "destruction", "move overlaps", "use after", "destruction", "association", "use after", "destruction", "duplicat", "association"
	};
}

private void logical_negative(int variant) {
	try {
		var source = build ();
		var region = region_of (source);
		mutate_actions (region.actions, variant);
		try {
			SsaVerifier.verify (source);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			assert (error.message.down ().contains (reasons[variant]));
			return;
		}
		GLib.error ("accepted logical continuation corruption %d", variant);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void plan_negative(int variant) {
	try {
		var source = build ();
		var native = NativeAbiBuilder.build (source);
		var plan = native.continuations[0];
		mutate_actions (plan.actions, variant);
		try {
			plan.verify ();
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			return;
		}
		GLib.error ("accepted independently forged native schedule %d", variant);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void contract_negative(int variant) {
	try {
		var source = build ();
		var region = region_of (source);
		var original = region.families[0];
		var env = original.environment;
		if (variant == 0) {
			var wrong = new SsaContinuationFamily (env, null);
			foreach (var entry in original.entries) {
				wrong.entries.add (entry);
			}
			region.families[0] = wrong;
		}
		if (variant == 1) {
			var entry = original.entries[0];
			original.entries[0] = new SsaContinuationEntry (entry.role, region.families[1].environment, entry.target);
		}
		if (variant == 2) {
			var entry = original.entries[0];
			original.entries[0] = new SsaContinuationEntry (entry.role, env, named (source, "control"));
		}
		if (variant == 3) {
			source.functions.remove_index (0);
		}
		if (variant == 4) {
			var wrong = new SsaContinuationFamily (env, original.destroy, false);
			foreach (var entry in original.entries) {
				wrong.entries.add (entry);
			}
			region.families[0] = wrong;
		}
		try {
			SsaContinuationVerifier.verify (region, source.functions, source.structs, source.cleanups);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			return;
		}
		GLib.error ("accepted logical contract corruption");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void physical_contract_negative(int variant) {
	try {
		var source = build ();
		var native = NativeAbiBuilder.build (source);
		var plan = native.continuations[0];
		var original = plan.families[0];
		var env = original.environment;
		if (variant == 0) {
			plan.families[0] = new NativeContinuationFamily (original.identity, env, original.entries, null, true);
		}
		if (variant == 1 || variant == 2 || variant == 3) {
			var entry = original.entries[0];
			original.entries[0] = new NativeContinuationEntry (entry.identity, variant == 2 ? ContinuationRole.DESTROY : entry.role, variant == 1 ? plan.families[1].environment.identity : entry.environment, entry.target_ordinal, entry.body_signature, variant == 3 ? NativeContinuationConvention.FOREIGN_C : entry.convention);
		}
		if (variant == 4) {
			var entry = original.entries[0];
			original.entries[0] = new NativeContinuationEntry (entry.identity, entry.role, entry.environment, entry.target_ordinal, plan.families[2].entries[0].body_signature);
		}
		if (variant == 5) {
			var other = original.entries[1];
			original.entries[0] = new NativeContinuationEntry (other.identity, other.role, other.environment, other.target_ordinal, other.body_signature);
		}
		if (variant == 6) {
			plan.descriptor_storage.fields[0] = new NativeRecordField (0, "cancel-drain", new NativeScalarAbiType (NativeScalarType.PTR));
		}
		try {
			plan.verify ();
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			return;
		}
		GLib.error ("accepted physical contract corruption");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void correspondence() {
	try {
		var source = build ();
		var native = NativeAbiBuilder.build (source);
		var plan = native.continuations[0];
		var family = plan.families[0];
		var a = family.entries[0];
		var b = family.entries[1];
		family.entries[0] = new NativeContinuationEntry (a.identity, a.role, a.environment, b.target_ordinal, b.body_signature);
		plan.verify ();
		try {
			NativeContinuationBuilder.validate (plan, source, native, plan.function_ordinal, plan.block_ordinal, plan.position);
		} catch (NativeAbiError error) {
			assert (error.message.contains ("different code/environment"));
			return;
		}
		GLib.error ("accepted valid substituted code plan");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void wrong_region() {
	try {
		var first = build ();
		var second = build ();
		var native = NativeAbiBuilder.build (second);
		var plan = NativeAbiBuilder.build (first).continuations[0];
		plan.verify ();
		try {
			NativeContinuationBuilder.validate (plan, second, native, plan.function_ordinal, plan.block_ordinal, plan.position);
		} catch (NativeAbiError error) {
			return;
		}
		GLib.error ("accepted shape-compatible foreign region");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void llvm_negative(int variant) {
	try {
		var lowered = artifact ();
		var binding = lowered.continuation_calls[0];
		if (variant == 0) {
			CApi.set_instruction_call_conv (binding.call, CApi.CallConv.C);
		}
		if (variant == 1) {
			CApi.set_operand (binding.call, 0, CApi.const_null (CApi.type_of (binding.environment)));
		}
		if (variant == 2) {
			CApi.set_operand (binding.code_address, 2, CApi.const_int (CApi.int32_type_in_context (lowered.context), 1, 0));
		}
		if (variant == 3) {
			CApi.set_operand (binding.environment_address, 0, lowered.continuation_calls[5].descriptor);
		}
		if (variant == 4) {
			var publication = lowered.continuation_publications[0];
			CApi.set_operand (publication.stores[0], 0, publication.cancel);
		}
		if (variant == 5) {
			var publication = lowered.continuation_publications[0];
			CApi.set_operand (publication.selected, 1, publication.cancel);
		}
		if (variant == 6) {
			var move = lowered.continuation_moves[0];
			CApi.set_operand (move.disarm, 1, move.destination);
		}
		try {
			lowered.verify ();
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			return;
		}
		GLib.error ("accepted malformed physical continuation call");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private int test_variant() {
	var path = Test.get_path ();
	return int.parse (path.substring (path.length - 2));
}

private void logical_case() {
	logical_negative (test_variant ());
}

private void plan_case() {
	plan_negative (test_variant ());
}

private void contract_case() {
	contract_negative (test_variant ());
}

private void physical_contract_case() {
	physical_contract_negative (test_variant ());
}

private void llvm_case() {
	llvm_negative (test_variant ());
}

int main(string[] args) {
	if (args.length == 3 && args[1] == "--emit") {
		try {
			var lowered = artifact ();
			var target = new LlvmTargetMachineArtifact ();
			target.configure (lowered);
			FileUtils.set_contents (args[2] + ".ll", lowered.dump ());
			target.emit_object (lowered, args[2] + ".o");
			return 0;
		} catch (GLib.Error error) {
			stderr.printf ("%s\n", error.message);
			return 1;
		}
	}
	initialize_reasons ();
	Test.init (ref args);
	register_review_probes ();
	Test.add_func ("/callable/predecessor-lifetime-and-native-plans", lifetime);
	Test.add_func ("/callable/code-plan-correspondence", correspondence);
	Test.add_func ("/callable/nominal-region-correspondence", wrong_region);
	for (int i = 0; i < reasons.length; i++) {
		Test.add_func ("/callable/logical/%02d".printf (i), logical_case);
		Test.add_func ("/callable/plan/%02d".printf (i), plan_case);
	}
	for (int i = 0; i < 5; i++) {
		Test.add_func ("/callable/contract/%02d".printf (i), contract_case);
	}
	for (int i = 0; i < 7; i++) {
		Test.add_func ("/callable/physical-contract/%02d".printf (i), physical_contract_case);
	}
	for (int i = 0; i < 7; i++) {
		Test.add_func ("/callable/llvm/%02d".printf (i), llvm_case);
	}
	return Test.run ();
}

}
