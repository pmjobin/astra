// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Cfg;

namespace Astra.Tests.OwnershipDataflow {
private void release(Fixture fixture, int block, int owner) {
	fixture.function.blocks[block].instructions.add (new CfgOwnershipReleaseInstruction (fixture.span, fixture.function.locals[owner], fixture.cleanup));
}

private void release_lattice() throws GLib.Error {
	var o = OwnershipState.OWNED;
	var m = OwnershipState.MOVED;
	var r = OwnershipState.RELEASED;
	assert (OwnershipState.join (o, o) == o);
	assert (OwnershipState.join (o, m).display_name () == "MAYBE_OWNED");
	assert (OwnershipState.join (o, r).display_name () == "{OWNED, RELEASED}");
	assert (OwnershipState.join (m, r).display_name () == "{MOVED, RELEASED}");
	assert (OwnershipState.join (OwnershipState.join (o, m), r).display_name () == "{OWNED, MOVED, RELEASED}");
	OwnershipState[] states = {
		o, m, r, OwnershipState.join (o, m), OwnershipState.join (o, r), OwnershipState.join (m, r), OwnershipState.join (OwnershipState.join (o, m), r)
	};
	foreach (var left in states) {
		assert (left.definitely_owned () == (left == o));
		assert (left.definitely_moved () == (left == m));
		assert (left.definitely_released () == (left == r));
		assert (left.definitely_disarmed () == (left == m || left == r || left == OwnershipState.join (m, r)));
		assert (left.may_own () != left.definitely_disarmed ());
		assert (OwnershipState.join (left, left) == left);
		foreach (var right in states) {
			var joined = OwnershipState.join (left, right);
			assert (joined == OwnershipState.join (right, left));
			foreach (var concrete in new OwnershipState[] {o, m, r}) {
				assert (((joined & concrete) != 0) == ((left & concrete) != 0 || (right & concrete) != 0));
			}
			foreach (var third in states) {
				assert (OwnershipState.join (joined, third) == OwnershipState.join (left, OwnershipState.join (right, third)));
			}
		}
	}
}

private void release_linear(string mode) throws GLib.Error {
	bool moving = mode == "moved-source" || mode == "destination";
	var fixture = new Fixture (moving ? 2 : 1, 2);
	fixture.acquire (0, 0);
	if (mode == "borrow-first") {
		fixture.borrow (0, 0);
		fixture.borrow (0, 0);
	}
	if (moving) {
		fixture.move (0, 0, 1);
	}
	release (fixture, 0, mode == "destination" ? 1 : 0);
	fixture.branch (0, 1);
	if (mode == "double") {
		release (fixture, 1, 0);
	}
	if (mode == "borrow-after") {
		fixture.borrow (1, 0);
	}
	if (moving) {
		fixture.clean (1, 1);
	}
	fixture.clean (1, 0);
	fixture.finish (1);
	var result = fixture.analyze ();
	if (mode == "double") {
		assert (result.diagnostic.message == "owned value 'a' has already been released");
	} else if (mode == "moved-source") {
		assert (result.diagnostic.message == "cannot release moved owned value 'a'");
	} else if (mode == "borrow-after") {
		assert (result.diagnostic.message == "cannot borrow released owned value 'a'");
	} else {
		assert (result.diagnostic == null);
		assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[mode == "destination" ? 1 : 0]) == OwnershipState.RELEASED);
	}
}

private Fixture release_diamond(string mode) throws CfgError {
	bool moved = mode == "three-way" || mode == "all-disarmed";
	var fixture = new Fixture (moved ? 2 : 1, moved ? 6 : mode == "unreachable" ? 5 : 4);
	fixture.acquire (0, 0);
	fixture.split (0, 1, 2);
	if (mode == "unreachable") {
		release (fixture, 4, 0);
		fixture.branch (4, 3);
	} else {
		release (fixture, 1, 0);
	}
	if (mode == "terminating") {
		fixture.clean (1, 0);
		fixture.finish (1);
	} else {
		fixture.branch (1, 3);
	}
	if (mode == "both") {
		release (fixture, 2, 0);
	}
	if (moved) {
		fixture.split (2, 4, 5);
		fixture.move (4, 0, 1);
		fixture.clean (4, 1);
		fixture.branch (4, 3);
		if (mode == "all-disarmed") {
			release (fixture, 5, 0);
		}
		fixture.branch (5, 3);
	} else {
		fixture.branch (2, 3);
	}
	fixture.clean (3, 0);
	fixture.finish (3);
	return fixture;
}

private void release_join(string mode) throws GLib.Error {
	var fixture = release_diamond (mode);
	var result = fixture.analyze ();
	var o = OwnershipState.OWNED;
	var r = OwnershipState.RELEASED;
	var m = OwnershipState.MOVED;
	var expected = mode == "both" ? r : mode == "terminating" || mode == "unreachable" ? o : mode == "three-way" ? OwnershipState.join (OwnershipState.join (o, m), r) : mode == "all-disarmed" ? OwnershipState.join (m, r) : OwnershipState.join (o, r);
	assert (result.diagnostic == null && result.entry_state (fixture.function.blocks[3], fixture.function.locals[0]) == expected);
	assert (result.dump () == fixture.analyze ().dump ());
	fixture.borrow (3, 0, 0);
	var borrowed = fixture.analyze ();
	assert ((borrowed.diagnostic == null) == expected.definitely_owned ());
	if (mode == "unreachable") {
		assert (!result.dump ().contains ("block #4"));
	}
}

private void release_loop(string mode) throws GLib.Error {
	var fixture = new Fixture (mode == "fresh-move" ? 2 : 1, 4);
	bool fresh = mode == "fresh" || mode == "fresh-move";
	if (!fresh) {
		fixture.acquire (0, 0);
	}
	fixture.branch (0, 1);
	fixture.split (1, 2, 3);
	if (fresh) {
		fixture.acquire (2, 0);
	}
	if (mode == "fresh-move") {
		fixture.move (2, 0, 1);
	}
	release (fixture, 2, mode == "fresh-move" ? 1 : 0);
	if (mode == "fresh-move") {
		fixture.clean (2, 1);
	}
	if (fresh || mode == "return") {
		fixture.clean (2, 0);
	}
	if (mode == "return") {
		fixture.finish (2);
	} else {
		fixture.branch (2, mode == "break" ? 3 : 1);
	}
	if (!fresh) {
		fixture.clean (3, 0);
	}
	fixture.finish (3);
	var result = fixture.analyze ();
	assert (result.iterations <= 4 * fixture.function.blocks.length && result.dump () == fixture.analyze ().dump ());
	assert ((result.diagnostic != null) == (mode == "backedge"));
	if (mode == "backedge") {
		assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == OwnershipState.join (OwnershipState.OWNED, OwnershipState.RELEASED));
		assert (result.diagnostic.message.contains ("cannot be released"));
	} else if (mode == "break") {
		assert (result.entry_state (fixture.function.blocks[3], fixture.function.locals[0]) == OwnershipState.join (OwnershipState.OWNED, OwnershipState.RELEASED));
	} else if (mode == "return") {
		assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == OwnershipState.OWNED);
	} else {
		assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == null);
	}
}

private void release_flow_lifetime() throws GLib.Error {
	Fixture? fixture = release_diamond ("three-way");
	var owner = WeakRef (fixture.function.locals[0]);
	var event = WeakRef (fixture.function.blocks[1].instructions[0]);
	OwnershipFlowResult? flow = fixture.analyze ();
	fixture = null;
	assert (flow.dump ().contains ("{OWNED, MOVED, RELEASED}"));
	flow = null;
	assert (owner.get () == null && event.get () == null);
}

private void register_release() {
	add ("release/lattice", release_lattice);
	add ("release/lifetime", release_flow_lifetime);
	foreach (string mode in new string[] {"basic", "double", "moved-source", "destination", "borrow-first", "borrow-after"}) {
		add ("release/linear/" + mode, () => release_linear (mode));
	}
	foreach (string mode in new string[] {"conditional", "both", "terminating", "unreachable", "three-way", "all-disarmed"}) {
		add ("release/join/" + mode, () => release_join (mode));
	}
	foreach (string mode in new string[] {"backedge", "break", "return", "fresh", "fresh-move"}) {
		add ("release/loop/" + mode, () => release_loop (mode));
	}
}

}
