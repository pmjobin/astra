// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private void loop_count() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/count.astra"));
	var f = functions (artifact)[0];
	var bs = blocks (f);
	var phis = operations (f, CApi.Opcode.PHI);
	assert (bs.length == 4 && phis.length == 1);
	var phi = phis[0];
	width (CApi.type_of (phi), 32);
	assert ((void*) CApi.first_instruction (bs[1]) == (void*) phi && CApi.incoming_count (phi) == 2);
	assert (constant (CApi.incoming_value (phi, 0), 0));
	assert ((void*) CApi.incoming_block (phi, 0) == (void*) bs[0]);
	var add = operations (f, CApi.Opcode.ADD)[0];
	assert ((void*) CApi.incoming_value (phi, 1) == (void*) add && (void*) CApi.incoming_block (phi, 1) == (void*) bs[2]);
	assert (CApi.get_nsw (add) == 0 && CApi.get_nuw (add) == 0);
	assert ((void*) CApi.operand (add, 0) == (void*) phi && constant (CApi.operand (add, 1), 1));
	var condition = CApi.next_instruction (phi);
	assert (CApi.opcode (condition) == CApi.Opcode.ICMP && CApi.predicate (condition) == CApi.IntPredicate.SLT);
	assert ((void*) CApi.operand (condition, 0) == (void*) phi && (void*) CApi.operand (condition, 1) == (void*) CApi.get_param (f, 0));
	assert ((void*) CApi.condition (CApi.block_terminator (bs[1])) == (void*) condition);
	assert ((void*) CApi.successor (CApi.block_terminator (bs[2]), 0) == (void*) bs[1]);
	assert ((void*) returned (f) == (void*) phi);
}

private void loop_multiple() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/accumulate.astra"));
	var f = functions (artifact)[0];
	var phis = operations (f, CApi.Opcode.PHI);
	var adds = operations (f, CApi.Opcode.ADD);
	assert (phis.length == 2 && adds.length == 2);
	assert ((void*) CApi.next_instruction (phis[0]) == (void*) phis[1]);
	assert ((void*) CApi.incoming_value (phis[0], 1) == (void*) adds[1]);
	assert ((void*) CApi.incoming_value (phis[1], 1) == (void*) adds[0]);
	for (uint p = 0; p < 2; p++) {
		assert (CApi.incoming_count (phis[p]) == 2 && constant (CApi.incoming_value (phis[p], 0), 0));
		assert (CApi.block_name (CApi.incoming_block (phis[p], 1)) == "b2");
	}
	assert ((void*) returned (f) == (void*) phis[1]);
}

private void loop_bool() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/bool-carried.astra"));
	var f = functions (artifact)[0];
	var phis = operations (f, CApi.Opcode.PHI);
	assert (phis.length == 2);
	width (CApi.type_of (phis[0]), 32);
	width (CApi.type_of (phis[1]), 1);
	assert (constant (CApi.incoming_value (phis[1], 0), 0));
	var flip = operations (f, CApi.Opcode.XOR)[0];
	assert ((void*) CApi.operand (flip, 0) == (void*) phis[1] && (void*) CApi.incoming_value (phis[1], 1) == (void*) flip);
	assert ((void*) CApi.condition (CApi.block_terminator (blocks (f)[3])) == (void*) phis[1]);
}

private void loop_calls() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/call-loop.astra"));
	var fs = functions (artifact);
	var f = fs[2];
	var bs = blocks (f);
	var phi = operations (f, CApi.Opcode.PHI)[0];
	var calls = operations (f, CApi.Opcode.CALL);
	assert (calls.length == 2);
	assert ((void*) CApi.instruction_parent (calls[0]) == (void*) bs[1] && (void*) CApi.next_instruction (phi) == (void*) calls[0]);
	assert ((void*) CApi.instruction_parent (calls[1]) == (void*) bs[2]);
	for (int c = 0; c < 2; c++) {
		assert ((void*) CApi.called_value (calls[c]) == (void*) fs[c]);
		assert (CApi.instruction_call_conv (calls[c]) == CApi.CallConv.FAST);
		assert ((void*) CApi.operand (calls[c], 0) == (void*) phi);
	}
	assert ((void*) CApi.condition (CApi.block_terminator (bs[1])) == (void*) calls[0]);
	assert ((void*) CApi.incoming_value (phi, 1) == (void*) calls[1]);
	assert ((void*) CApi.successor (CApi.block_terminator (bs[2]), 0) == (void*) bs[1]);
}

private void loop_nested() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/nested-loop.astra"));
	var f = functions (artifact)[0];
	var bs = blocks (f);
	var ps = operations (f, CApi.Opcode.PHI);
	assert (bs.length == 7 && ps.length == 4);
	for (uint p = 0; p < 4; p++) {
		assert (CApi.incoming_count (ps[p]) == 2);
		assert ((void*) CApi.instruction_parent (ps[p]) == (void*) bs[p < 2 ? 1 : 4]);
		assert ((void*) CApi.incoming_block (ps[p], 1) == (void*) bs[p < 2 ? 6 : 5]);
	}
	assert ((void*) CApi.incoming_value (ps[2], 0) == (void*) ps[1]);
	assert ((void*) CApi.incoming_value (ps[1], 1) == (void*) ps[2]);
	assert (constant (CApi.incoming_value (ps[3], 0), 0));
}

private void loop_return() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/return-loop.astra"));
	var f = functions (artifact)[0];
	var returns = operations (f, CApi.Opcode.RET);
	assert (returns.length == 2 && operations (f, CApi.Opcode.PHI).length == 1);
	foreach (var ret in returns) {
		assert (CApi.successor_count (ret) == 0);
	}
	assert ((void*) CApi.successor (CApi.block_terminator (blocks (f)[5]), 0) == (void*) blocks (f)[1]);
	var dead = lower (fixture ("tests/loop/fixtures/post-return.astra"));
	foreach (var df in functions (dead)) {
		assert (blocks (df).length == 1 && operations (df, CApi.Opcode.PHI).length == 0 && operations (df, CApi.Opcode.RET).length == 1);
	}
}

private void loop_trap_splits() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/trap-loop.astra"));
	assert (audit_division (artifact) == 3);
	var fs = functions (artifact);
	for (int f = 0; f < 2; f++) {
		var bs = blocks (fs[f]);
		var ps = operations (fs[f], CApi.Opcode.PHI);
		assert (ps.length == 3);
		var continuation = CApi.instruction_parent (ps[2]);
		assert (CApi.block_name (continuation).has_suffix (".continue"));
		assert ((void*) continuation != (void*) bs[2]);
		for (uint p = 0; p < 2; p++) {
			assert ((void*) CApi.incoming_block (ps[p], 1) == (void*) continuation);
		}
		assert ((void*) CApi.incoming_value (ps[1], 1) == (void*) ps[2]);
		assert ((void*) CApi.successor (CApi.block_terminator (continuation), 0) == (void*) bs[1]);
	}
	var bs = blocks (fs[2]);
	var ps = operations (fs[2], CApi.Opcode.PHI);
	var guard = CApi.next_instruction (ps[0]);
	assert ((void*) CApi.instruction_parent (guard) == (void*) bs[1] && CApi.predicate (guard) == CApi.IntPredicate.EQ);
	assert ((void*) CApi.operand (guard, 0) == (void*) CApi.get_param (fs[2], 1) && constant (CApi.operand (guard, 1), 0));
	assert ((void*) CApi.condition (CApi.block_terminator (bs[1])) == (void*) guard);
	var continuation = CApi.instruction_parent (ps[1]);
	assert ((void*) CApi.successor (CApi.block_terminator (continuation), 0) == (void*) bs[2]);
	assert ((void*) CApi.successor (CApi.block_terminator (continuation), 1) == (void*) bs[3]);
	assert ((void*) CApi.successor (CApi.block_terminator (bs[2]), 0) == (void*) bs[1]);
}

private void loop_condition_order() throws GLib.Error {
	var artifact = lower (fixture ("tests/loop/fixtures/condition-order.astra"));
	assert (audit_division (artifact) == 1);
	var fs = functions (artifact);
	var ps = operations (fs[2], CApi.Opcode.PHI);
	var first_call = CApi.next_instruction (ps[1]);
	assert (CApi.opcode (first_call) == CApi.Opcode.CALL && (void*) CApi.called_value (first_call) == (void*) fs[0]);
	var add = CApi.next_instruction (first_call);
	assert (CApi.opcode (add) == CApi.Opcode.ADD && (void*) CApi.operand (add, 0) == (void*) ps[1]);
	var second_call = CApi.next_instruction (add);
	assert (CApi.opcode (second_call) == CApi.Opcode.CALL && (void*) CApi.called_value (second_call) == (void*) fs[1]);
	assert ((void*) CApi.condition (CApi.next_instruction (second_call)) == (void*) second_call);
	assert (CApi.block_name (CApi.instruction_parent (ps[0])) == "b1");
	assert (CApi.block_name (CApi.instruction_parent (first_call)).has_suffix (".continue"));
}

private void loop_artifact_lifetime(string name) throws GLib.Error {
	SsaProgram? source = build_ssa (fixture ("tests/loop/fixtures/" + name + ".astra"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (source);
	var header_ref = WeakRef (source.functions[0].blocks[1]);
	var body_ref = WeakRef (source.functions[0].blocks[2]);
	var parameter_ref = WeakRef (source.functions[0].blocks[1].parameters[0]);
	var last_ref = WeakRef (source.functions[0].blocks[source.functions[0].blocks.length - 1]);
	var function_ref = WeakRef (source.functions[0]);
	var nabi_ref = WeakRef (nabi);
	var artifact = LlvmLowering.lower (source, nabi, Astra.CAbi.CAbiBuilder.build (source, nabi));
	source = null;
	nabi = null;
	assert (header_ref.get () == null && body_ref.get () == null && parameter_ref.get () == null && last_ref.get () == null && function_ref.get () == null && nabi_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump ().contains ("phi i32") && artifact.dump () == artifact.dump ());
}

private void register_loop_tests() {
	add ("/llvm/loop/count", loop_count);
	add ("/llvm/loop/multiple", loop_multiple);
	add ("/llvm/loop/bool", loop_bool);
	add ("/llvm/loop/calls", loop_calls);
	add ("/llvm/loop/nested", loop_nested);
	add ("/llvm/loop/return-unreachable", loop_return);
	add ("/llvm/loop/trap-splits", loop_trap_splits);
	add ("/llvm/loop/condition-order", loop_condition_order);
	add ("/llvm/loop/body-local", () => {
			var artifact = lower (fixture ("tests/loop/fixtures/body-local.astra"));
			assert (operations (functions (artifact)[0], CApi.Opcode.PHI).length == 1);
		});
	add ("/llvm/loop/lifetime-count", () => loop_artifact_lifetime ("count"));
	add ("/llvm/loop/lifetime-nested", () => loop_artifact_lifetime ("nested-loop"));
	add ("/llvm/loop/lifetime-trap", () => loop_artifact_lifetime ("trap-loop"));
}
}
