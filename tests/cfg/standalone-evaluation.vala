// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private CfgProgram evaluation_program() {
	var file = new SourceFile.from_text ("evaluation.astra", "-((2147483648)) / -1");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var value = new CfgBinaryValue (span, types.int_type, BinaryOperator.DIVIDE, new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (AstraIntValue.MIN)), new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (-1)));
	var result = new CfgEvaluatedValue (span, types.int_type);
	var instructions = new GenericArray<CfgInstruction> ();
	instructions.add (new CfgEvaluateInstruction (span, value, result));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (new CfgBlock (span, 0, instructions, new CfgReturn (span, result)));
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", types.int_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, blocks[0]));
	return new CfgProgram (span, functions);
}

private void independent_evaluation() {
	try {
		CfgProgram? program = evaluation_program ();
		string dump = CfgDump.format (program);
		assert (dump.contains ("(evaluate %0 : int") && dump.contains ("(evaluated %0 : int)"));
		assert (dump.contains ("(integer -2147483648 : int)") && dump.contains ("(binary / : int"));
		var instruction_ref = WeakRef (program.functions[0].entry.instructions[0]);
		var result_ref = WeakRef (((CfgEvaluateInstruction) program.functions[0].entry.instructions[0]).result);
		program = null;
		assert (instruction_ref.get () == null && result_ref.get () == null);
	} catch (CfgError error) {
		GLib.error ("Standalone evaluation failed: %s", error.message);
	}
}

private void malformed_evaluation() {
	for (int variant = 0; variant < 6; variant++) {
		var program = evaluation_program ();
		var function = program.functions[0];
		var instruction = (CfgEvaluateInstruction) function.entry.instructions[0];
		string expected;
		switch (variant) {
		case 0:
			function.entry.instructions.remove_index (0);
			expected = "evaluated value must be defined earlier in the same block or on every incoming path";
			break;
		case 1:
			function.entry.instructions[0] = new CfgEvaluateInstruction (instruction.span, instruction.result, new CfgEvaluatedValue (instruction.span, instruction.result.semantic_type));
			expected = "evaluated value must be defined earlier in the same block or on every incoming path";
			break;
		case 2:
			function.entry.instructions.add (instruction);
			expected = "evaluation instruction identity occurs in more than one instruction slot";
			break;
		case 3:
			function.entry.instructions.add (new CfgEvaluateInstruction (instruction.span, instruction.value, instruction.result));
			expected = "evaluation result identity occurs in more than one definition slot";
			break;
		case 4:
			function.entry.instructions[0] = new CfgEvaluateInstruction (instruction.span, instruction.value, new CfgEvaluatedValue (instruction.span, new SemanticType (TypeKind.BOOL)));
			expected = "evaluation result type must match its value type";
			break;
		case 5:
			function.blocks.add (new CfgBlock (program.span, 1, new GenericArray<CfgInstruction> (), new CfgReturn (program.span, instruction.result)));
			expected = "evaluated value must be defined earlier in the same block or on every incoming path";
			break;
		default:
			assert_not_reached ();
		}
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				CfgDump.format (program);
			} catch (CfgError error) {
				assert (error is CfgError.INVALID_CFG && error.message.has_suffix (expected));
				continue;
			}
			GLib.error ("Malformed evaluation passed verification");
		}
	}
}

private void register_evaluation_tests() {
	Test.add_func ("/cfg-standalone/evaluation/model-and-lifetime", independent_evaluation);
	Test.add_func ("/cfg-standalone/evaluation/malformed", malformed_evaluation);
}

}
