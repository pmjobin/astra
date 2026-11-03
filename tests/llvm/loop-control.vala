// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private void control_phi_predecessors(CApi.ValueRef function) {
	foreach (var phi in operations (function, CApi.Opcode.PHI)) {
		var destination = CApi.instruction_parent (phi);
		uint count = 0;
		foreach (var block in blocks (function)) {
			var terminator = CApi.block_terminator (block);
			for (uint edge = 0; edge < CApi.successor_count (terminator); edge++) {
				if ((void*) CApi.successor (terminator, edge) != (void*) destination) {
					continue;
				}
				count++;
				uint matches = 0;
				for (uint i = 0; i < CApi.incoming_count (phi); i++) {
					if ((void*) CApi.incoming_block (phi, i) == (void*) block) {
						matches++;
					}
				}
				assert (matches == 1);
			}
		}
		assert (CApi.incoming_count (phi) == count);
	}
}

private void control_merge_phis() throws GLib.Error {
	var artifact = lower (fixture ("tests/loopctrl/fixtures/continue-merge.astra"));
	var f = functions (artifact)[0];
	var b = blocks (f);
	var ps = operations (f, CApi.Opcode.PHI);
	assert (ps.length == 2);
	foreach (var phi in ps) {
		assert (CApi.incoming_count (phi) == 3 && (void*) CApi.instruction_parent (phi) == (void*) b[1]);
		assert (constant (CApi.incoming_value (phi, 0), 0));
		assert ((void*) CApi.incoming_block (phi, 0) == (void*) b[0]);
		assert ((void*) CApi.incoming_block (phi, 1) == (void*) b[4]);
		assert ((void*) CApi.incoming_block (phi, 2) == (void*) b[5]);
	}
	var next = operations (f, CApi.Opcode.ADD)[0];
	assert ((void*) CApi.incoming_value (ps[0], 1) == (void*) next && (void*) CApi.incoming_value (ps[0], 2) == (void*) next);
	assert (constant (CApi.incoming_value (ps[1], 1), 10) && constant (CApi.incoming_value (ps[1], 2), 20));
	control_phi_predecessors (f);
	artifact = lower (fixture ("tests/loopctrl/fixtures/break-merge.astra"));
	f = functions (artifact)[0];
	b = blocks (f);
	ps = operations (f, CApi.Opcode.PHI);
	assert (ps.length == 2 && (void*) CApi.instruction_parent (ps[1]) == (void*) b[3]);
	assert ((void*) CApi.incoming_value (ps[1], 0) == (void*) ps[0] && constant (CApi.incoming_value (ps[1], 1), 1));
	assert ((void*) CApi.incoming_block (ps[1], 0) == (void*) b[1] && (void*) CApi.incoming_block (ps[1], 1) == (void*) b[4]);
	assert ((void*) returned (f) == (void*) ps[1]);
	control_phi_predecessors (f);
}

private void control_multiple_phis() throws GLib.Error {
	var artifact = lower (fixture ("tests/loopctrl/fixtures/multiple-sites.astra"));
	var fs = functions (artifact);
	var b = blocks (fs[0]);
	var ps = operations (fs[0], CApi.Opcode.PHI);
	assert (CApi.incoming_count (ps[0]) == 4 && CApi.incoming_count (ps[1]) == 4);
	int[] sources = {
		0, 4, 6, 7
	};
	for (uint i = 0; i < sources.length; i++) {
		assert ((void*) CApi.incoming_block (ps[0], i) == (void*) b[sources[i]]);
		assert ((void*) CApi.incoming_block (ps[1], i) == (void*) b[sources[i]]);
		if (i > 0) {
			assert ((void*) CApi.incoming_value (ps[1], i) == (void*) CApi.first_instruction (b[sources[i]]));
		}
	}
	b = blocks (fs[1]);
	ps = operations (fs[1], CApi.Opcode.PHI);
	assert (ps.length == 4 && CApi.incoming_count (ps[3]) == 3);
	assert ((void*) CApi.instruction_parent (ps[3]) == (void*) b[3]);
	assert ((void*) CApi.incoming_value (ps[3], 0) == (void*) ps[1]);
	assert (constant (CApi.incoming_value (ps[3], 1), 10) && constant (CApi.incoming_value (ps[3], 2), 20));
	assert ((void*) CApi.incoming_block (ps[3], 1) == (void*) b[4] && (void*) CApi.incoming_block (ps[3], 2) == (void*) b[6]);
	foreach (var f in fs) {
		control_phi_predecessors (f);
	}
}

private void control_trap_predecessors() throws GLib.Error {
	var artifact = lower (fixture ("tests/loopctrl/fixtures/trap-control.astra"));
	assert (audit_division (artifact) == 3);
	var fs = functions (artifact);
	var b = blocks (fs[0]);
	var ps = operations (fs[0], CApi.Opcode.PHI);
	var continuation = CApi.instruction_parent (ps[2]);
	assert (CApi.block_name (continuation).has_suffix (".continue") && (void*) continuation != (void*) b[4]);
	assert (CApi.incoming_count (ps[0]) == 3 && CApi.incoming_count (ps[1]) == 3);
	assert ((void*) CApi.incoming_block (ps[0], 1) == (void*) continuation && (void*) CApi.incoming_block (ps[1], 1) == (void*) continuation);
	assert ((void*) CApi.incoming_value (ps[1], 1) == (void*) ps[2]);
	assert ((void*) CApi.successor (CApi.block_terminator (continuation), 0) == (void*) b[1]);
	b = blocks (fs[1]);
	ps = operations (fs[1], CApi.Opcode.PHI);
	assert (ps.length == 6 && CApi.incoming_count (ps[2]) == 3 && CApi.incoming_count (ps[3]) == 3);
	for (uint i = 1; i <= 2; i++) {
		continuation = CApi.instruction_parent (ps[3 + i]);
		assert (CApi.block_name (continuation).has_suffix (".continue"));
		assert ((void*) CApi.incoming_block (ps[2], i) == (void*) continuation && (void*) CApi.incoming_block (ps[3], i) == (void*) continuation);
		assert ((void*) CApi.incoming_value (ps[3], i) == (void*) ps[3 + i]);
		assert ((void*) CApi.successor (CApi.block_terminator (continuation), 0) == (void*) b[3]);
	}
	foreach (var f in fs) {
		control_phi_predecessors (f);
	}
}

private void control_nested_calls() throws GLib.Error {
	var artifact = lower (fixture ("tests/loopctrl/fixtures/nested-loop-control.astra"));
	var f = functions (artifact)[0];
	var b = blocks (f);
	assert ((void*) CApi.successor (CApi.block_terminator (b[7]), 0) == (void*) b[4]);
	assert ((void*) CApi.successor (CApi.block_terminator (b[9]), 0) == (void*) b[6]);
	assert ((void*) CApi.successor (CApi.block_terminator (b[11]), 0) == (void*) b[1]);
	assert ((void*) CApi.successor (CApi.block_terminator (b[13]), 0) == (void*) b[3]);
	control_phi_predecessors (f);
	artifact = lower (fixture ("tests/loopctrl/fixtures/unreachable.astra"));
	var fs = functions (artifact);
	for (int i = 1; i <= 2; i++) {
		var calls = operations (fs[i], CApi.Opcode.CALL);
		assert (calls.length == 2);
		assert ((void*) CApi.called_value (calls[0]) == (void*) fs[0] && (void*) CApi.called_value (calls[1]) == (void*) fs[0]);
		assert ((void*) CApi.operand (calls[1], 0) == (void*) calls[0] && (void*) CApi.next_instruction (calls[0]) == (void*) calls[1]);
		var branch = CApi.next_instruction (calls[1]);
		assert (CApi.opcode (branch) == CApi.Opcode.BR && (void*) CApi.successor (branch, 0) == (void*) blocks (fs[i])[i == 1 ? 3 : 1]);
		control_phi_predecessors (fs[i]);
	}
}

private void control_lifetime() throws GLib.Error {
	SsaProgram? source = build_ssa (fixture ("tests/loopctrl/fixtures/nested-loop-control.astra"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (source);
	var source_ref = WeakRef (source);
	var function_ref = WeakRef (source.functions[0]);
	var inner_ref = WeakRef (source.functions[0].blocks[4]);
	var outer_ref = WeakRef (source.functions[0].blocks[1]);
	var edge = ((SsaBranch) source.functions[0].blocks[7].terminator).edge;
	var artifact = LlvmLowering.lower (source, nabi, Astra.CAbi.CAbiBuilder.build (source, nabi));
	source = null;
	nabi = null;
	assert (source_ref.get () == null && function_ref.get () == null && inner_ref.get () == null && outer_ref.get () == null && edge.target == null);
	artifact.verify ();
	control_phi_predecessors (functions (artifact)[0]);
	assert (artifact.dump () == artifact.dump ());
}

private void register_loop_control_tests() {
	add ("/llvm/loopctrl/merge-phis", control_merge_phis);
	add ("/llvm/loopctrl/multiple-phis", control_multiple_phis);
	add ("/llvm/loopctrl/trap-physical-predecessors", control_trap_predecessors);
	add ("/llvm/loopctrl/nested-and-call-order", control_nested_calls);
	add ("/llvm/loopctrl/stage-lifetime", control_lifetime);
	add ("/llvm/loopctrl/all-fixtures-verify", () => {
			foreach (string name in new string[] {"break-basic", "continue-basic", "break-merge", "continue-merge", "nested-loop-control", "multiple-sites", "edge-state", "unreachable", "trap-control"}) {
				var artifact = lower (fixture ("tests/loopctrl/fixtures/" + name + ".astra"));
				foreach (var f in functions (artifact)) {
					control_phi_predecessors (f);
				}
				assert (!artifact.dump ().contains ("undef") && !artifact.dump ().contains ("poison"));
			}
		});
}

}
