// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private CfgProgram loop_model() throws CfgError {
	var span = SourceSpan (new SourceFile.from_text ("cycle.astra", ""), 0, 0);
	var types = new BuiltinTypes ();
	var blocks = new GenericArray<CfgBlock> ();
	for (int b = 0; b < 4; b++) {
		blocks.add (new CfgBlock.reserve (span, b));
	}
	blocks[0].complete (span, new CfgBranch (span, blocks[1]));
	blocks[1].complete (span, new CfgConditionalBranch (span, new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE), blocks[2], blocks[3]));
	blocks[2].complete (span, new CfgBranch (span, blocks[1]));
	blocks[3].complete (span, new CfgReturn (span, null));
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "cycle", types.void_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, blocks[0]));
	return new CfgProgram (span, functions);
}

private void loop_lifetime() {
	try {
		CfgProgram? program = loop_model ();
		var function_ref = WeakRef (program.functions[0]);
		var entry_ref = WeakRef (program.functions[0].entry);
		var header_ref = WeakRef (program.functions[0].blocks[1]);
		var body_ref = WeakRef (program.functions[0].blocks[2]);
		var exit_ref = WeakRef (program.functions[0].blocks[3]);
		var backedge = (CfgBranch) program.functions[0].blocks[2].terminator;
		var condition = (CfgConditionalBranch) program.functions[0].blocks[1].terminator;
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		{
			var reachable = CfgReachability.analyze (program.functions[0]);
			for (int b = 0; b < 4; b++) {
				assert (reachable.is_reachable (program.functions[0].blocks[b]));
			}
		}
		assert (CfgDump.format (program).contains ("(branch #1)"));
		program = null;
		assert (function_ref.get () == null && entry_ref.get () == null && header_ref.get () == null && body_ref.get () == null && exit_ref.get () == null);
		assert (backedge.target == null && backedge.successors ().length == 0);
		assert (condition.true_target == null && condition.false_target == null && condition.successors ().length == 0);
	} catch (CfgError error) {
		GLib.error ("Standalone cycle failed: %s", error.message);
	}
}

private void expired_loop_targets() {
	for (int kind = 0; kind < 3; kind++) {
		try {
			var span = SourceSpan (new SourceFile.from_text ("expired.astra", ""), 0, 0);
			var types = new BuiltinTypes ();
			var entry = new CfgBlock.reserve (span, 0);
			CfgBlock? missing = new CfgBlock (span, 1, new GenericArray<CfgInstruction> (), new CfgReturn (span, null));
			if (kind == 0) {
				entry.complete (span, new CfgBranch (span, missing));
			} else {
				entry.complete (span, new CfgConditionalBranch (span, new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE), kind == 1 ? missing : entry, kind == 2 ? missing : entry));
			}
			missing = null;
			var blocks = new GenericArray<CfgBlock> ();
			blocks.add (entry);
			var functions = new GenericArray<CfgFunction> ();
			functions.add (new CfgFunction (span, span, "f", types.void_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, entry));
			var program = new CfgProgram (span, functions);
			for (int repeat = 0; repeat < 2; repeat++) {
				try {
					CfgDump.format (program);
					GLib.error ("Expired target passed verification");
				} catch (CfgError error) {
					assert (error.message.contains (kind == 0 ? "branch successors must match its target" : "conditional successors must match true and false targets"));
				}
			}
		} catch (CfgError error) {
			GLib.error ("Expired target setup failed: %s", error.message);
		}
	}
}

private void multiple_control_edges() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("multiple-edges.astra", ""), 0, 0);
		var types = new BuiltinTypes ();
		var condition = new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
		var blocks = new GenericArray<CfgBlock> ();
		for (int i = 0; i < 7; i++) {
			blocks.add (new CfgBlock.reserve (span, i));
		}
		blocks[0].complete (span, new CfgBranch (span, blocks[1]));
		blocks[1].complete (span, new CfgConditionalBranch (span, condition, blocks[2], blocks[3]));
		blocks[2].complete (span, new CfgConditionalBranch (span, condition, blocks[4], blocks[5]));
		blocks[3].complete (span, new CfgReturn (span, null));
		blocks[4].complete (span, new CfgBranch (span, blocks[1]));
		blocks[5].complete (span, new CfgConditionalBranch (span, condition, blocks[3], blocks[6]));
		blocks[6].complete (span, new CfgBranch (span, blocks[1]));
		var functions = new GenericArray<CfgFunction> ();
		functions.add (new CfgFunction (span, span, "multiple", types.void_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, blocks[0]));
		CfgProgram? program = new CfgProgram (span, functions);
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null && CfgDump.format (program).contains ("(branch #1)"));
		var backedge = (CfgBranch) blocks[4].terminator;
		var exit_edge = (CfgConditionalBranch) blocks[5].terminator;
		var header_ref = WeakRef (blocks[1]);
		var exit_ref = WeakRef (blocks[3]);
		program = null;
		functions.remove_range (0, functions.length);
		blocks.remove_range (0, blocks.length);
		assert (header_ref.get () == null && exit_ref.get () == null);
		assert (backedge.target == null && exit_edge.true_target == null && exit_edge.false_target == null);
	} catch (CfgError error) {
		GLib.error ("Standalone multiple edges: %s", error.message);
	}
}

private void register_loop_tests() {
	Test.add_func ("/cfg-standalone/loopctrl/multiple-edges-lifetime", multiple_control_edges);
	Test.add_func ("/cfg-standalone/loop/model-reachability-lifetime", loop_lifetime);
	Test.add_func ("/cfg-standalone/loop/expired-targets", expired_loop_targets);
}

}
