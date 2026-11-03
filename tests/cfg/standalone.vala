// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private CfgProgram sample() {
	var file = new SourceFile.from_text ("standalone.astra", "007");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	assert (types.resolve ("int") == types.int_type && types.resolve ("void") == types.void_type);
	var parameters = new GenericArray<CfgParameter> ();
	var parameter = new CfgParameter (span, span, "x", types.int_type, 0);
	parameters.add (parameter);
	var locals = new GenericArray<CfgLocalPlace> ();
	var local = new CfgLocalPlace (span, span, "y", types.int_type, 0);
	locals.add (local);
	var sum = new CfgBinaryValue (span, types.int_type, BinaryOperator.ADD, new CfgParameterValue (span, parameter), new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (7)));
	var value = new CfgPrefixValue (span, types.int_type, PrefixOperator.NEGATIVE, sum);
	var blocks = new GenericArray<CfgBlock> ();
	var instructions = new GenericArray<CfgInstruction> ();
	instructions.add (new CfgInitialize (span, local, value));
	instructions.add (new CfgStore (span, local, new CfgLoadValue (span, local)));
	blocks.add (new CfgBlock (span, 0, instructions, new CfgReturn (span, new CfgLoadValue (span, local))));
	blocks.add (new CfgBlock (span, 1, new GenericArray<CfgInstruction> (), new CfgFunctionEnd (span)));
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", types.int_type, 0, parameters, locals, blocks, blocks[0]));
	return new CfgProgram (span, functions);
}

private void independent_model() {
	try {
		var program = sample ();
		CfgVerifier.verify (program);
		var function = program.functions[0];
		var reachability = CfgReachability.analyze (function);
		assert (reachability.is_reachable (function.entry));
		assert (!reachability.is_reachable (function.blocks[1]));
		assert (CfgFlowChecker.check (program).diagnostic == null);
		string dump = CfgDump.format (program);
		assert (dump.contains ("(parameter #0 : int)") && dump.contains ("(integer 7 : int)"));
		assert (dump.contains ("(prefix - : int") && dump.contains ("(binary + : int"));
		assert (dump.contains ("(local-place #0 \"y\" : int)") && dump.contains ("(load : int"));
		assert (dump.contains ("(initialize") && dump.contains ("(store"));
		assert (dump.contains ("(block #1 unreachable\n\t\t\t(function-end)"));
	} catch (CfgError error) {
		GLib.error ("Unexpected standalone CFG failure: %s", error.message);
	}
}

// Deliberately corrupt current return semantics to exercise the common
// successor checks. This is a malformed test object, not a new operation.
private class InvalidReturn : CfgReturn {
	private CfgBlock target;

	public InvalidReturn (SourceSpan span, CfgValue value, CfgBlock target) {
		base (span, value);
		this.target = target;
	}

	public override GenericArray<CfgBlock> successors() {
		var result = new GenericArray<CfgBlock> ();
		result.add (target);
		return result;
	}

}

private void invalid_successor(bool foreign) {
	var program = sample ();
	var function = program.functions[0];
	var target = foreign ? new CfgBlock (program.span, 0, new GenericArray<CfgInstruction> (), new CfgFunctionEnd (program.span)) : function.blocks[1];
	var value = ((CfgReturn) function.entry.terminator).value;
	var entry = new CfgBlock (program.span, 0, function.entry.instructions, new InvalidReturn (program.span, value, target));
	function.blocks[0] = entry;
	program.functions[0] = new CfgFunction (function.span, function.name_span, function.name, function.return_type, 0, function.parameters, function.locals, function.blocks, entry);
	string expected = "internal CFG verification error at function #0/block #0/terminator";
	expected += foreign ? "/successor #0: successor block is not owned by the containing function" : ": return and function-end must have no successors";
	for (int i = 0; i < 2; i++) {
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			assert (error is CfgError.INVALID_CFG && error.message == expected);
			continue;
		}
		GLib.error ("Malformed successors passed verification");
	}
}

private void foreign_successor() {
	invalid_successor (true);
}

private void return_successor() {
	invalid_successor (false);
}

private void foreign_place() {
	var program = sample ();
	var function = program.functions[0];
	var original = function.locals[0];
	var foreign = new CfgLocalPlace (original.span, original.name_span, original.name, original.semantic_type, original.ordinal);
	function.entry.instructions[1] = new CfgStore (function.span, foreign, new CfgLoadValue (function.span, original));
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		assert (error is CfgError.INVALID_CFG);
		assert (error.message == "internal CFG verification error at function #0/block #0/instruction #1/target: local place is not owned by the containing function");
		return;
	}
	GLib.error ("Standalone CFG accepted a foreign place");
}

int main(string[] args) {
	Test.init (ref args);
	register_owned_tests ();
	register_call_tests ();
	register_struct_tests ();
	register_tptr_tests ();
	register_shortcircuit_tests ();
	register_loop_tests ();
	register_evaluation_tests ();
	Test.add_func ("/cfg-standalone/conditional-model", conditional_model);
	Test.add_func ("/cfg-standalone/model", independent_model);
	Test.add_func ("/cfg-standalone/verifier/foreign-place", foreign_place);
	Test.add_func ("/cfg-standalone/verifier/foreign-successor", foreign_successor);
	Test.add_func ("/cfg-standalone/verifier/return-successor", return_successor);
	return Test.run ();
}

}
