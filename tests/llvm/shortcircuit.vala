// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private void logical_phis() throws GLib.Error {
	foreach (bool is_and in new bool[] {true, false}) {
		var artifact = lower (fixture ("tests/shortcircuit/fixtures/" + (is_and ? "logical-and" : "logical-or") + ".astra"));
		var f = functions (artifact)[0];
		var b = blocks (f);
		var phis = operations (f, CApi.Opcode.PHI);
		assert (b.length == 4 && phis.length == 1 && operations (f, CApi.Opcode.AND).length == 0);
		assert (!artifact.dump ().contains (" and i1 ") && !artifact.dump ().contains (" or i1 "));
		var branch = CApi.block_terminator (b[1]);
		assert ((void*) CApi.condition (branch) == (void*) CApi.get_param (f, 0));
		assert ((void*) CApi.successor (branch, 0) == (void*) b[is_and ? 2 : 3]);
		assert ((void*) CApi.successor (branch, 1) == (void*) b[is_and ? 3 : 2]);
		assert (CApi.int_width (CApi.type_of (phis[0])) == 1 && CApi.incoming_count (phis[0]) == 2);
		assert (constant (CApi.incoming_value (phis[0], 0), is_and ? 0 : -1));
		assert ((void*) CApi.incoming_block (phis[0], 0) == (void*) b[1]);
		assert ((void*) CApi.incoming_block (phis[0], 1) == (void*) b[2]);
		assert ((void*) CApi.incoming_value (phis[0], 1) == (void*) CApi.get_param (f, 1));
		assert ((void*) returned (f) == (void*) phis[0]);
		control_phi_predecessors (f);
	}
}
private void logical_calls() throws GLib.Error {
	var artifact = lower (fixture ("tests/shortcircuit/fixtures/call-short.astra"));
	var fs = functions (artifact);
	for (int i = 3; i <= 4; i++) {
		var b = blocks (fs[i]);
		var calls = operations (fs[i], CApi.Opcode.CALL);
		assert (calls.length == 2);
		assert ((void*) CApi.called_value (calls[0]) == (void*) fs[0] && (void*) CApi.instruction_parent (calls[0]) == (void*) b[1]);
		assert ((void*) CApi.condition (CApi.block_terminator (b[1])) == (void*) calls[0]);
		assert ((void*) CApi.called_value (calls[1]) == (void*) fs[1] && (void*) CApi.instruction_parent (calls[1]) == (void*) b[2]);
		assert ((void*) CApi.successor (CApi.block_terminator (b[1]), i == 3 ? 0 : 1) == (void*) b[2]);
		assert (operations (fs[i], CApi.Opcode.AND).length == 0);
		control_phi_predecessors (fs[i]);
	}
	var b = blocks (fs[5]);
	assert ((void*) CApi.successor (CApi.block_terminator (b[3]), 0) == (void*) b[4]);
	var calls = operations (fs[5], CApi.Opcode.CALL);
	assert (calls.length == 5 && (void*) CApi.instruction_parent (calls[4]) == (void*) b[6]);
	assert ((void*) CApi.called_value (calls[4]) == (void*) fs[2]);
	control_phi_predecessors (fs[5]);
}
private void logical_traps() throws GLib.Error {
	var artifact = lower (fixture ("tests/shortcircuit/fixtures/trap-short.astra"));
	assert (audit_division (artifact) == 2);
	var fs = functions (artifact);
	for (int i = 0; i < 2; i++) {
		var b = blocks (fs[i]);
		var ps = operations (fs[i], CApi.Opcode.PHI);
		assert (ps.length == 2 && CApi.int_width (CApi.type_of (ps[0])) == 1);
		var continuation = CApi.instruction_parent (ps[1]);
		assert (CApi.block_name (continuation).has_suffix (".continue"));
		assert ((void*) CApi.incoming_block (ps[0], 1) == (void*) continuation && (void*) continuation != (void*) b[2]);
		assert ((void*) CApi.successor (CApi.block_terminator (continuation), 0) == (void*) b[3]);
		assert ((void*) CApi.successor (CApi.block_terminator (b[1]), i == 0 ? 0 : 1) == (void*) b[2]);
		var trap = operations (fs[i], CApi.Opcode.CALL)[0];
		assert (CApi.intrinsic_id (CApi.called_value (trap)) != 0);
		assert ((void*) CApi.successor (CApi.block_terminator (b[2]), 0) == (void*) CApi.instruction_parent (trap));
		// The only and is LLVM-1's integer overflow guard in the RHS.
		var guards = operations (fs[i], CApi.Opcode.AND);
		assert (guards.length == 1 && CApi.block_name (CApi.instruction_parent (guards[0])).has_suffix (".nonzero"));
		control_phi_predecessors (fs[i]);
	}
}
private void logical_loops_nested() throws GLib.Error {
	foreach (string name in new string[] {"nested-short", "loop-short", "contexts-short"}) {
		var artifact = lower (fixture ("tests/shortcircuit/fixtures/" + name + ".astra"));
		assert (!artifact.dump ().contains (" and i1 ") && !artifact.dump ().contains (" or i1 "));
		foreach (var f in functions (artifact)) {
			control_phi_predecessors (f);
		}
		if (name != "loop-short") {
			continue;
		}
		var fs = functions (artifact);
		var b = blocks (fs[2]);
		assert ((void*) CApi.successor (CApi.block_terminator (b[2]), 0) == (void*) b[1]);
		assert ((void*) CApi.successor (CApi.block_terminator (b[1]), 0) == (void*) b[4]);
		var ps = operations (fs[2], CApi.Opcode.PHI);
		assert (ps.length == 2 && CApi.int_width (CApi.type_of (ps[0])) == 32 && CApi.int_width (CApi.type_of (ps[1])) == 1);
		assert ((void*) CApi.instruction_parent (ps[0]) == (void*) b[1] && (void*) CApi.instruction_parent (ps[1]) == (void*) b[6]);
		var call = operations (fs[2], CApi.Opcode.CALL)[0];
		assert ((void*) CApi.instruction_parent (call) == (void*) b[5]);
	}
}
private void logical_lifetime() throws GLib.Error {
	SsaProgram? ssa = build_ssa (fixture ("tests/shortcircuit/fixtures/loop-short.astra"));
	var header_ref = WeakRef (ssa.functions[0].blocks[1]);
	var join_ref = WeakRef (ssa.functions[0].blocks[6].parameters[0]);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	var nabi_ref = WeakRef (nabi);
	var artifact = LlvmLowering.lower (ssa, nabi, Astra.CAbi.CAbiBuilder.build (ssa, nabi));
	ssa = null;
	nabi = null;
	assert (header_ref.get () == null && join_ref.get () == null && nabi_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump ().contains ("phi i1"));
}
private void register_shortcircuit_tests() {
	add ("/llvm/shortcircuit/branch-phi-no-eager-ops", logical_phis);
	add ("/llvm/shortcircuit/conditional-calls-argument-order", logical_calls);
	add ("/llvm/shortcircuit/trap-physical-predecessors", logical_traps);
	add ("/llvm/shortcircuit/loop-nested-phis", logical_loops_nested);
	add ("/llvm/shortcircuit/lifetime", logical_lifetime);
}
}
