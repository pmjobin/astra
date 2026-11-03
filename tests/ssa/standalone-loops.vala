// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SsaStandalone {
private SsaEdge cycle_edge(SsaBlock target, SsaValue[] values) {
	var arguments = new GenericArray<SsaValue> ();
	foreach (var value in values) {
		arguments.add (value);
	}
	return new SsaEdge (target, arguments);
}

private SsaProgram loop_model(int invalid = 0) throws SsaError {
	var span = SourceSpan (new SourceFile.from_text ("cycle.astra", ""), 0, 0);
	var types = new BuiltinTypes ();
	var blocks = new GenericArray<SsaBlock> ();
	for (int b = 0; b < 4; b++) {
		blocks.add (new SsaBlock (span, b, b));
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "n", types.int_type, 0));
	var current = new SsaBlockParameter (span, span, "i", types.int_type, 1, 0);
	blocks[1].parameters.add (current);
	var zero = new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (0));
	var one = new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (1));
	var wrong_type = new SsaBooleanConstant (span, types.bool_type, BooleanLiteral.FALSE);
	var next = new SsaBinaryInstruction (span, types.int_type, 3, BinaryOperator.ADD, current, one);
	var condition = new SsaBinaryInstruction (span, types.bool_type, 2, BinaryOperator.LESS, invalid == 6 ? (SsaValue) next.result : current, parameters[0]);
	blocks[1].instructions.add (condition);
	blocks[2].instructions.add (next);
	SsaValue initial = invalid == 3 ? (SsaValue) wrong_type : invalid == 5 ? (SsaValue) next.result : zero;
	SsaValue carried = invalid == 4 ? (SsaValue) wrong_type : next.result;
	blocks[0].complete (new SsaBranch (span, invalid == 1 ? cycle_edge (blocks[1], {}) : cycle_edge (blocks[1], {initial})));
	blocks[1].complete (new SsaConditionalBranch (span, condition.result, cycle_edge (blocks[2], {}), cycle_edge (blocks[3], {})));
	blocks[2].complete (new SsaBranch (span, invalid == 2 ? cycle_edge (blocks[1], {}) : cycle_edge (blocks[1], {carried})));
	blocks[3].complete (new SsaReturn (span, invalid == 7 ? (SsaValue) next.result : current));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "cycle", types.int_type, 0, parameters, blocks, blocks[0]));
	return new SsaProgram (span, functions);
}

private void loop_model_lifetime() {
	try {
		SsaProgram? program = loop_model ();
		var function_ref = WeakRef (program.functions[0]);
		var entry_ref = WeakRef (program.functions[0].entry);
		var header_ref = WeakRef (program.functions[0].blocks[1]);
		var body_ref = WeakRef (program.functions[0].blocks[2]);
		var exit_ref = WeakRef (program.functions[0].blocks[3]);
		var parameter_ref = WeakRef (program.functions[0].blocks[1].parameters[0]);
		var next_ref = WeakRef (program.functions[0].blocks[2].instructions[0].result);
		SsaVerifier.verify (program);
		string dump = SsaDump.format (program);
		assert (dump.contains ("(arguments") && dump.contains ("(branch #1 (%3))") && dump == SsaDump.format (program));
		program = null;
		assert (function_ref.get () == null && entry_ref.get () == null && header_ref.get () == null && body_ref.get () == null && exit_ref.get () == null);
		assert (parameter_ref.get () == null && next_ref.get () == null);
	} catch (SsaError error) {
		GLib.error ("Standalone SSA loop failed: %s", error.message);
	}
}

private void invalid_loop_edges_and_uses() {
	for (int invalid = 1; invalid <= 7; invalid++) {
		try {
			var program = loop_model (invalid);
			for (int repeat = 0; repeat < 2; repeat++) {
				try {
					SsaDump.format (program);
					GLib.error ("Invalid cyclic SSA case %d accepted", invalid);
				} catch (SsaError error) {
					assert (error.message.contains (invalid <= 2 ? "edge argument count" : invalid <= 4 ? "edge argument type" : "does not dominate its use"));
				}
			}
		} catch (SsaError error) {
			GLib.error ("Invalid cycle setup failed: %s", error.message);
		}
	}
}

private void expired_loop_edge() {
	try {
		SsaProgram? program = loop_model ();
		var edge = ((SsaBranch) program.functions[0].blocks[2].terminator).edge;
		var header_ref = WeakRef (program.functions[0].blocks[1]);
		program = null;
		assert (header_ref.get () == null);
		assert (edge.target == null);
		var span = edge.arguments[0].span;
		var entry = new SsaBlock (span, 0, 0);
		entry.complete (new SsaBranch (span, edge));
		var blocks = new GenericArray<SsaBlock> ();
		blocks.add (entry);
		var functions = new GenericArray<SsaFunction> ();
		functions.add (new SsaFunction (span, span, "expired", edge.arguments[0].semantic_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, entry));
		try {
			SsaDump.format (new SsaProgram (span, functions));
			GLib.error ("Expired SSA target passed verification");
		} catch (SsaError error) {
			assert (error.message.contains ("successor block is not owned by the containing function"));
		}
	} catch (SsaError error) {
		GLib.error ("Expired loop edge failed: %s", error.message);
	}
}

private void multiple_control_edges() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("multiple-edges.astra", ""), 0, 0);
		var types = new BuiltinTypes ();
		var blocks = new GenericArray<SsaBlock> ();
		for (int i = 0; i < 7; i++) {
			blocks.add (new SsaBlock (span, i, i));
		}
		var parameters = new GenericArray<SsaFunctionParameter> ();
		parameters.add (new SsaFunctionParameter (span, span, "c", types.bool_type, 0));
		var current = new SsaBlockParameter (span, span, "x", types.int_type, 1, 0);
		var merged = new SsaBlockParameter (span, span, "x", types.int_type, 2, 0);
		blocks[1].parameters.add (current);
		blocks[3].parameters.add (merged);
		var one = new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (1));
		var two = new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (2));
		var first = new SsaBinaryInstruction (span, types.int_type, 3, BinaryOperator.ADD, current, one);
		var second = new SsaBinaryInstruction (span, types.int_type, 4, BinaryOperator.ADD, current, two);
		blocks[4].instructions.add (first);
		blocks[6].instructions.add (second);
		blocks[0].complete (new SsaBranch (span, cycle_edge (blocks[1], {one})));
		blocks[1].complete (new SsaConditionalBranch (span, parameters[0], cycle_edge (blocks[2], {}), cycle_edge (blocks[3], {current})));
		blocks[2].complete (new SsaConditionalBranch (span, parameters[0], cycle_edge (blocks[4], {}), cycle_edge (blocks[5], {})));
		blocks[3].complete (new SsaReturn (span, merged));
		blocks[4].complete (new SsaBranch (span, cycle_edge (blocks[1], {first.result})));
		blocks[5].complete (new SsaConditionalBranch (span, parameters[0], cycle_edge (blocks[3], {two}), cycle_edge (blocks[6], {})));
		blocks[6].complete (new SsaBranch (span, cycle_edge (blocks[1], {second.result})));
		var functions = new GenericArray<SsaFunction> ();
		functions.add (new SsaFunction (span, span, "multiple", types.int_type, 0, parameters, blocks, blocks[0]));
		SsaProgram? program = new SsaProgram (span, functions);
		SsaVerifier.verify (program);
		assert (SsaDump.format (program).contains ("(branch #1 (%3))"));
		var edge = ((SsaBranch) blocks[4].terminator).edge;
		var header_ref = WeakRef (blocks[1]);
		var exit_ref = WeakRef (blocks[3]);
		program = null;
		functions.remove_range (0, functions.length);
		blocks.remove_range (0, blocks.length);
		assert (header_ref.get () == null && exit_ref.get () == null && edge.target == null);
	} catch (SsaError error) {
		GLib.error ("Standalone multiple SSA edges: %s", error.message);
	}
}

private void register_loop_tests() {
	Test.add_func ("/ssa-standalone/loopctrl/multiple-edges-values-lifetime", multiple_control_edges);
	Test.add_func ("/ssa-standalone/loop/model-lifetime", loop_model_lifetime);
	Test.add_func ("/ssa-standalone/loop/invalid-edges-and-uses", invalid_loop_edges_and_uses);
	Test.add_func ("/ssa-standalone/loop/expired-edge", expired_loop_edge);
}

}
