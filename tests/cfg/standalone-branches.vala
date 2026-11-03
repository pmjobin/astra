// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private void conditional_model() {
	try {
		var file = new SourceFile.from_text ("conditional-standalone.astra", "007");
		var span = SourceSpan (file, 0, file.length);
		var types = new BuiltinTypes ();
		var parameters = new GenericArray<CfgParameter> ();
		var parameter = new CfgParameter (span, span, "a", types.int_type, 0);
		parameters.add (parameter);
		var locals = new GenericArray<CfgLocalPlace> ();
		var local = new CfgLocalPlace (span, span, "y", types.bool_type, 0);
		locals.add (local);
		var comparison = new CfgBinaryValue (span, types.bool_type, BinaryOperator.LESS, new CfgParameterValue (span, parameter), new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (7)));
		var condition = new CfgPrefixValue (span, types.bool_type, PrefixOperator.NOT, comparison);
		var yes = new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
		var no = new CfgBooleanValue (span, types.bool_type, BooleanLiteral.FALSE);
		var blocks = new GenericArray<CfgBlock> ();
		for (int i = 0; i < 5; i++) {
			blocks.add (new CfgBlock.reserve (span, i));
		}
		// Execution goes #3 -> #4/#2 -> #1, skipping unreachable #0.
		blocks[0].complete (span, new CfgFunctionEnd (span));
		blocks[1].complete (span, new CfgReturn (span, new CfgLoadValue (span, local)));
		blocks[2].instructions.add (new CfgStore (span, local, no));
		blocks[2].complete (span, new CfgBranch (span, blocks[1]));
		blocks[3].instructions.add (new CfgInitialize (span, local, no));
		blocks[3].complete (span, new CfgConditionalBranch (span, condition, blocks[4], blocks[2]));
		blocks[4].instructions.add (new CfgStore (span, local, yes));
		blocks[4].complete (span, new CfgBranch (span, blocks[1]));
		var functions = new GenericArray<CfgFunction> ();
		functions.add (new CfgFunction (span, span, "f", types.bool_type, 0, parameters, locals, blocks, blocks[3]));
		var program = new CfgProgram (span, functions);
		CfgVerifier.verify (program);
		var reachability = CfgReachability.analyze (functions[0]);
		for (int i = 0; i < 5; i++) {
			assert (reachability.is_reachable (blocks[i]) == (i != 0));
		}
		assert (CfgFlowChecker.check (program).diagnostic == null);
		var successors = blocks[3].terminator.successors ();
		assert (successors.length == 2 && successors[0] == blocks[4] && successors[1] == blocks[2]);
		successors[0] = blocks[0];
		assert (blocks[3].terminator.successors ()[0] == blocks[4]);
		var branch_successors = blocks[4].terminator.successors ();
		branch_successors.remove_index (0);
		assert (blocks[4].terminator.successors ().length == 1);
		assert (!CfgReachability.analyze (functions[0]).is_reachable (blocks[0]));
		string dump = CfgDump.format (program);
		assert (dump.contains ("(true #4)") && dump.contains ("(false #2)") && dump.contains ("(branch #1)"));
		assert (((CfgStore) blocks[2].instructions[0]).target == local && ((CfgStore) blocks[4].instructions[0]).target == local);
		assert (((CfgLoadValue) ((CfgReturn) blocks[1].terminator).value).source == local);
		try {
			blocks[3].complete (span, new CfgFunctionEnd (span));
			GLib.error ("Completed block accepted a second terminator");
		} catch (CfgError error) {
			assert (error.message == "internal CFG construction error: block #3 already has a terminator");
		}
		assert (dump.contains ("(bool true : bool)") && dump.contains ("(bool false : bool)"));
		assert (dump.contains ("(prefix ! : bool") && dump.contains ("(binary < : bool"));
		assert (dump.contains ("(load : bool") && !dump.contains ("LLVM"));
	} catch (CfgError error) {
		GLib.error ("Unexpected standalone conditional failure: %s", error.message);
	}
}

}
