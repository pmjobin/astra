// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Cfg;

namespace Astra.Tests.OwnershipDataflow {
private void rearm(Fixture fixture, int block, int owner) {
	var result = new CfgCallResultValue (fixture.span, fixture.owner_type);
	fixture.function.blocks[block].instructions.add (new CfgCCallInstruction (fixture.span, fixture.producer, new GenericArray<CfgValue> (), result));
	fixture.function.blocks[block].instructions.add (new CfgOwnershipRearmInstruction (fixture.span, fixture.function.locals[owner], result, fixture.cleanup));
}

private void rearm_states(OwnershipState expected) throws GLib.Error {
	var fixture = new Fixture (4, 7);
	fixture.acquire (0, 0);
	fixture.split (0, 1, 2);
	fixture.split (2, 3, 4);
	var possibilities = new GenericArray<int> ();
	foreach (var state in new OwnershipState[] {OwnershipState.OWNED, OwnershipState.MOVED, OwnershipState.RELEASED}) {
		if ((expected & state) != 0) {
			possibilities.add ((int) state);
		}
	}
	int[] arms = {
		1, 3, 4
	};
	for (int i = 0; i < arms.length; i++) {
		var state = (OwnershipState) possibilities[i % possibilities.length];
		if (state == OwnershipState.RELEASED) {
			release (fixture, arms[i], 0);
		}
		if (state == OwnershipState.MOVED) {
			fixture.move (arms[i], 0, i + 1);
			fixture.clean (arms[i], i + 1);
		}
		fixture.branch (arms[i], 5);
	}
	// Unused move destinations still need one structural initialization.
	for (int i = 0; i < arms.length; i++) {
		if ((OwnershipState) possibilities[i % possibilities.length] != OwnershipState.MOVED) {
			fixture.acquire (arms[i], i + 1);
			fixture.clean (arms[i], i + 1);
		}
	}
	rearm (fixture, 5, 0);
	fixture.branch (5, 6);
	fixture.borrow (6, 0);
	fixture.clean (6, 0);
	fixture.finish (6);
	var flow = fixture.analyze ();
	assert (flow.entry_state (fixture.function.blocks[5], fixture.function.locals[0]) == expected);
	assert ((flow.diagnostic == null) == (fixture.owner_type is Astra.Semantic.HandleType || expected.definitely_disarmed ()));
	if (flow.diagnostic == null) {
		assert (flow.entry_state (fixture.function.blocks[6], fixture.function.locals[0]) == OwnershipState.OWNED);
	} else {
		assert (flow.diagnostic.message == (expected.definitely_owned () ? "owned value 'a' still owns a resource; release or move it before reassignment" : "owned value 'a' may still own a resource on another control-flow path"));
	}
}

private void rearm_loop(string discharge) throws GLib.Error {
	var fixture = new Fixture (discharge == "move" ? 2 : 1, 4);
	fixture.acquire (0, 0);
	release (fixture, 0, 0);
	fixture.branch (0, 1);
	fixture.split (1, 2, 3);
	rearm (fixture, 2, 0);
	if (discharge == "release") {
		release (fixture, 2, 0);
	}
	if (discharge == "move") {
		fixture.move (2, 0, 1);
		fixture.clean (2, 1);
	}
	fixture.branch (2, 1);
	fixture.clean (3, 0);
	fixture.finish (3);
	var flow = fixture.analyze ();
	assert ((flow.diagnostic == null) == (fixture.owner_type is Astra.Semantic.HandleType || discharge != "none"));
	var expected = discharge == "release" ? OwnershipState.RELEASED : OwnershipState.join (OwnershipState.RELEASED, discharge == "move" ? OwnershipState.MOVED : OwnershipState.OWNED);
	assert (flow.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == expected);
	assert (flow.iterations <= 4 * fixture.function.blocks.length && flow.dump () == fixture.analyze ().dump ());
	if (flow.diagnostic != null) {
		assert (flow.diagnostic.message.contains ("may still own a resource"));
	}
}

private void rearm_out_of_scope() throws GLib.Error {
	var fixture = new Fixture (1, 1);
	fixture.acquire (0, 0);
	fixture.clean (0, 0);
	rearm (fixture, 0, 0);
	fixture.clean (0, 0);
	fixture.finish (0);
	try {
		fixture.analyze ();
		assert_not_reached ();
	} catch (CfgError.INVALID_CFG error) {
		assert (error.message.contains ("rearm outside its lexical lifetime"));
	}
}

private void register_rearm() {
	for (int mask = 1; mask < 8; mask++) {
		var state = (OwnershipState) mask;
		add ("rearm/state/" + mask.to_string (), () => rearm_states (state));
	}
	foreach (string discharge in new string[] {"release", "move", "none"}) {
		add ("rearm/loop/" + discharge, () => rearm_loop (discharge));
	}
	add ("rearm/out-of-scope", rearm_out_of_scope);
}

}
