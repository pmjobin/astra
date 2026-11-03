// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Cfg;

namespace Astra.Tests.OwnershipDataflow {
private class Fixture : Object {
	internal SemanticType owner_type;
	internal BuiltinTypes types = new BuiltinTypes ();
	internal SourceSpan span;
	internal CfgProgram program;
	internal CfgFunction function;
	internal CfgCleanupContract cleanup;
	internal CfgCFunction producer;

	internal Fixture (int owner_count, int block_count) {
		assert (types.resolve ("void*") == types.raw_pointer_type);
#if RESOURCE_HANDLES
		owner_type = new HandleType ("Resource");
#else
		owner_type = types.raw_pointer_type;
#endif
		var file = new SourceFile.from_text ("ownership-flow-model", "move a");
		span = SourceSpan (file, 0, file.length);
		cleanup = new CfgCleanupContract ("destroy", span, 0);
		producer = new CfgCFunction (span, span, "create", new CForeignMetadata ("create"), ForeignAbi.C, owner_type, new GenericArray<SemanticType> (), 0, cleanup);
		var blocks = new GenericArray<CfgBlock> ();
		for (int i = 0; i < block_count; i++) {
			blocks.add (new CfgBlock.reserve (span, i));
		}
		var locals = new GenericArray<CfgLocalPlace> ();
		for (int i = 0; i < owner_count; i++) {
			locals.add (new CfgLocalPlace (span, span, i == 0 ? "a" : i == 1 ? "b" : "c", owner_type, i, false, cleanup));
		}
		function = new CfgFunction (span, span, "f", types.void_type, 0, new GenericArray<CfgParameter> (), locals, blocks, blocks[0]);
		var functions = new GenericArray<CfgFunction> ();
		functions.add (function);
		var cleanups = new GenericArray<CfgCleanupContract> ();
		cleanups.add (cleanup);
		var imports = new GenericArray<CfgCFunction> ();
		imports.add (producer);
		program = new CfgProgram (span, functions, imports, null, null, cleanups);
#if RESOURCE_HANDLES
		program.handles.add (new CfgHandle (span, span, (HandleType) owner_type, cleanup, null, 0));
#endif
	}

	internal void borrow(int block, int owner, int position = -1) {
		CfgCFunction? inspector = program.c_functions.length > 1 ? program.c_functions[1] : null;
		if (inspector == null) {
			var parameters = new GenericArray<CfgParameter> ();
			parameters.add (new CfgParameter (span, span, "p", owner_type, 0, PointerParameterContract.BORROWED_NOESCAPE));
			var parameter_types = new GenericArray<SemanticType> ();
			parameter_types.add (owner_type);
			inspector = new CfgCFunction (span, span, "inspect", new CForeignMetadata ("inspect"), ForeignAbi.C, types.void_type, parameter_types, 1, null, parameters);
			program.c_functions.add (inspector);
		}
		var value = new CfgOwnedBorrowValue (span, function.locals[owner], inspector.parameters[0]);
		var arguments = new GenericArray<CfgValue> ();
		arguments.add (value);
		var instructions = function.blocks[block].instructions;
		int index = position < 0 ? (int) instructions.length : position;
		instructions.insert (index, new CfgOwnedBorrowInstruction (span, value));
		instructions.insert (index + 1, new CfgCCallInstruction (span, inspector, arguments, null));
	}

	internal void acquire(int block, int owner) {
		var result = new CfgCallResultValue (span, owner_type);
		function.blocks[block].instructions.add (new CfgCCallInstruction (span, producer, new GenericArray<CfgValue> (), result));
		function.blocks[block].instructions.add (new CfgInitialize (span, function.locals[owner], result, function.locals[owner]));
	}

	internal void move(int block, int source, int destination) {
		function.blocks[block].instructions.add (new CfgOwnershipTransferInstruction (span, function.locals[source], function.locals[destination], cleanup));
	}

	internal void clean(int block, int owner) {
		function.blocks[block].instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, function.locals[owner]), cleanup));
	}

	internal void branch(int block, int destination) throws CfgError {
		function.blocks[block].complete (span, new CfgBranch (span, function.blocks[destination]));
	}

	internal void split(int block, int yes, int no) throws CfgError {
		function.blocks[block].complete (span, new CfgConditionalBranch (span, new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE), function.blocks[yes], function.blocks[no]));
	}

	internal void finish(int block) throws CfgError {
		function.blocks[block].complete (span, new CfgReturn (span, null));
	}

	internal OwnershipFlowResult analyze() throws CfgError {
		CfgVerifier.verify (program);
		return OwnershipFlow.analyze (function);
	}

}
private Fixture straight() throws CfgError {
	var fixture = new Fixture (2, 2);
	fixture.acquire (0, 0);
	fixture.move (0, 0, 1);
	fixture.branch (0, 1);
	fixture.clean (1, 1);
	fixture.clean (1, 0);
	fixture.finish (1);
	return fixture;
}

private Fixture diamond(string mode) throws CfgError {
	var fixture = new Fixture (mode == "both" ? 3 : 2, mode == "unreachable" ? 5 : 4);
	fixture.acquire (0, 0);
	fixture.split (0, 1, 2);
	if (mode == "unreachable") {
		fixture.branch (1, 3);
		fixture.move (4, 0, 1);
		fixture.clean (4, 1);
		fixture.branch (4, 3);
	} else {
		fixture.move (1, 0, 1);
		fixture.clean (1, 1);
		if (mode == "terminating") {
			fixture.clean (1, 0);
			fixture.finish (1);
		} else {
			fixture.branch (1, 3);
		}
	}
	if (mode == "both") {
		fixture.move (2, 0, 2);
		fixture.clean (2, 2);
	}
	fixture.branch (2, 3);
	fixture.clean (3, 0);
	fixture.finish (3);
	return fixture;
}

private Fixture loop(string mode) throws CfgError {
	var fixture = new Fixture (2, 4);
	if (mode != "fresh") {
		fixture.acquire (0, 0);
	}
	fixture.branch (0, 1);
	fixture.split (1, 2, 3);
	if (mode == "fresh") {
		fixture.acquire (2, 0);
	}
	fixture.move (2, 0, 1);
	fixture.clean (2, 1);
	if (mode == "fresh" || mode == "return") {
		fixture.clean (2, 0);
	}
	if (mode == "return") {
		fixture.finish (2);
	} else {
		fixture.branch (2, mode == "break" ? 3 : 1);
	}
	if (mode != "fresh") {
		fixture.clean (3, 0);
	}
	fixture.finish (3);
	return fixture;
}

private void lattice() throws GLib.Error {
	OwnershipState[] states = {
		OwnershipState.OWNED, OwnershipState.MOVED, OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED)
	};
	foreach (var left in states) {
		foreach (var right in states) {
			assert (OwnershipState.join (left, right) == (left == right ? left : OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED)));
		}
	}
}

private void linear() throws GLib.Error {
	var fixture = straight ();
	var result = fixture.analyze ();
	assert (result.diagnostic == null);
	assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == OwnershipState.MOVED);
	assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[1]) == OwnershipState.OWNED);
	assert (result.dump ().contains ("owner #0 a = MOVED"));
}

private void join(string mode) throws GLib.Error {
	var fixture = diamond (mode);
	var result = fixture.analyze ();
	assert (result.diagnostic == null);
	var expected = mode == "both" ? OwnershipState.MOVED : mode == "diamond" ? OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED) : OwnershipState.OWNED;
	assert (result.entry_state (fixture.function.blocks[3], fixture.function.locals[0]) == expected);
	assert (result.entry_state (fixture.function.blocks[3], fixture.function.locals[1]) == null);
	if (mode == "unreachable") {
		assert (!result.dump ().contains ("block #4"));
	}
}

private void cycle(string mode) throws GLib.Error {
	var fixture = loop (mode);
	var result = fixture.analyze ();
	assert (result.iterations <= 3 * fixture.function.blocks.length);
	assert (result.dump () == fixture.analyze ().dump ());
	assert ((result.diagnostic != null) == (mode == "backedge"));
	if (mode == "backedge") {
		assert (result.diagnostic.message.contains ("may have been moved") && result.diagnostic.span.text () == "move a");
		assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED));
	} else if (mode == "break") {
		assert (result.entry_state (fixture.function.blocks[3], fixture.function.locals[0]) == OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED));
	} else if (mode == "return") {
		assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == OwnershipState.OWNED);
	} else {
		assert (result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == null);
	}
}

private void malformed(int variant) throws GLib.Error {
	var fixture = straight ();
	var function = fixture.function;
	var source = function.locals[0];
	var destination = function.locals[1];
	var cleanup = fixture.cleanup;
	switch (variant) {
	case 0: function.entry.instructions[2] = new CfgOwnershipTransferInstruction (fixture.span, source, source, cleanup);
		break;
	case 1:
		function.entry.instructions[2] = new CfgOwnershipTransferInstruction (fixture.span, new CfgLocalPlace (fixture.span, fixture.span, "a", fixture.owner_type, 0, false, cleanup), destination, cleanup);
		break;
	case 2:
		function.entry.instructions[2] = new CfgOwnershipTransferInstruction (fixture.span, source, destination, new CfgCleanupContract ("destroy", fixture.span, 0));
		break;
	case 3:
		function.entry.instructions.add (function.entry.instructions[2]);
		break;
	case 4:
		fixture.clean (1, 0);
		break;
	case 5:
		function.blocks[1].instructions.remove_index (1);
		break;
	case 6:
		function.entry.instructions[1] = new CfgInitialize (fixture.span, source, ((CfgInitialize) function.entry.instructions[1]).value);
		break;
	case 7:
		function.entry.instructions.add (new CfgStore (fixture.span, source, new CfgNullPointerValue (fixture.span, source.semantic_type)));
		break;
	case 8:
		function.entry.instructions[2] = new CfgOwnershipTransferInstruction (fixture.span, destination, source, cleanup);
		break;
	case 9:
		function.entry.instructions[1] = new CfgInitialize (fixture.span, source, new CfgNullPointerValue (fixture.span, source.semantic_type), source);
		break;
	case 11:
		fixture.clean (0, 0);
		break;
	case 10:
		function.blocks[1].instructions.insert (0, new CfgCleanupInstruction (fixture.span, new CfgLoadValue (fixture.span, source), cleanup));
		break;
	default:
		assert_not_reached ();
	}
	try {
		fixture.analyze ();
	} catch (CfgError error) {
		Test.message ("malformed %d rejected: %s", variant, error.message);
		return;
	}
	GLib.error ("malformed fixture %d accepted", variant);
}

private void malformed_scope_join() throws GLib.Error {
	var fixture = diamond ("diamond");
	fixture.clean (1, 0);
	try {
		fixture.analyze ();
	} catch (CfgError error) {
		assert (error.message.contains ("inconsistent lexical lifetime at reachable join"));
		return;
	}
	assert_not_reached ();
}

private void malformed_rearm() throws GLib.Error {
	var fixture = loop ("fresh");
	fixture.function.blocks[2].instructions.remove_index (4);
	try {
		fixture.analyze ();
	} catch (CfgError error) {
		assert (error.message.contains ("inconsistent lexical lifetime") || error.message.contains ("rearm"));
		return;
	}
	assert_not_reached ();
}

private void lifetime() throws GLib.Error {
	Fixture? fixture = straight ();
	var block = WeakRef (fixture.function.blocks[1]);
	var owner = WeakRef (fixture.function.locals[0]);
	var operation = WeakRef (fixture.function.entry.instructions[2]);
	OwnershipFlowResult? result = fixture.analyze ();
	fixture = null;
	assert (result.dump ().contains ("MOVED"));
	result = null;
	assert (block.get () == null && owner.get () == null && operation.get () == null);
}

private delegate void Body() throws GLib.Error;
private class Case : Object {
	internal Body body;
	internal Case (owned Body body) {
		this.body = (owned) body;
	}

}
private HashTable<string, Case> cases;
private void add(string name, owned Body body) {
	string path = "/ownership-flow/" + name;
	cases.insert (path, new Case ((owned) body));
	Test.add_func (path, () => { try {
									 cases.lookup (Test.get_path ()).body ();
								 } catch (GLib.Error error) {
									 GLib.error ("%s", error.message);
								 }
	});
}

private void borrow_state(string mode) throws GLib.Error {
	var fixture = mode == "maybe" || mode == "terminating" ? diamond (mode == "maybe" ? "diamond" : "terminating") : straight ();
	fixture.borrow (mode == "maybe" || mode == "terminating" ? 3 : 1, mode == "destination" ? 1 : 0, 0);
	var result = fixture.analyze ();
	if (mode == "moved" || mode == "maybe") {
		assert (result.diagnostic != null && result.diagnostic.message.contains (mode == "moved" ? "cannot borrow moved owned value" : "may have been moved on another control-flow path and cannot be borrowed"));
	} else {
		assert (result.diagnostic == null);
	}
}

private void borrow_loop(bool moving) throws GLib.Error {
	if (moving) {
		var fixture = loop ("backedge");
		fixture.borrow (2, 0, 0);
		assert (fixture.analyze ().diagnostic.message.contains ("cannot be borrowed"));
		return;
	}
	var fixture = new Fixture (1, 4);
	fixture.acquire (0, 0);
	fixture.borrow (0, 0);
	fixture.branch (0, 1);
	fixture.split (1, 2, 3);
	fixture.borrow (2, 0);
	fixture.borrow (2, 0);
	fixture.branch (2, 1);
	fixture.clean (3, 0);
	fixture.finish (3);
	var result = fixture.analyze ();
	assert (result.diagnostic == null && result.entry_state (fixture.function.blocks[1], fixture.function.locals[0]) == OwnershipState.OWNED);
	assert (result.iterations <= 2 * fixture.function.blocks.length);
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	register_release ();
	register_rearm ();
	foreach (string mode in new string[] {"moved", "maybe", "destination", "terminating"}) {
		add ("borrow/" + mode, () => borrow_state (mode));
	}
	add ("borrow/loop-stable", () => borrow_loop (false));
	add ("borrow/move-backedge", () => borrow_loop (true));
	add ("lattice", lattice);
	add ("linear", linear);
	add ("lifetime", lifetime);
	add ("malformed-scope-join", malformed_scope_join);
	add ("malformed-rearm", malformed_rearm);
	foreach (string mode in new string[] {"diamond", "both", "terminating", "unreachable"}) {
		add ("join/" + mode, () => join (mode));
	}
	foreach (string mode in new string[] {"backedge", "break", "return", "fresh"}) {
		add ("loop/" + mode, () => cycle (mode));
	}
	for (int i = 0; i < 12; i++) {
		int variant = i;
		add ("malformed/%d".printf (i), () => malformed (variant));
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
