// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.IntegersSsa {
private SsaEdge edge(SsaBlock target, SsaValue[] values) {
	var arguments = new GenericArray<SsaValue> ();
	foreach (var value in values) {
		arguments.add (value);
	}
	return new SsaEdge (target, arguments);
}

private SsaProgram sample(BuiltinTypes types, IntegerType type, IntegerType? wrong = null) throws SsaError {
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "no literal"), 0, 10);
	var blocks = new GenericArray<SsaBlock> ();
	for (int b = 0; b < 4; b++) {
		blocks.add (new SsaBlock (span, b, b));
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "n", type, 0));
	var current = new SsaBlockParameter (span, span, "x", type, 1, 0);
	blocks[1].parameters.add (current);
	var zero = new SsaIntegerConstant.typed (span, type, AstraIntegerValue.from_bits (wrong ?? type, 0));
	var one = new SsaIntegerConstant.typed (span, type, AstraIntegerValue.from_bits (type, 1));
	var condition = new SsaBinaryInstruction (span, types.bool_type, 2, BinaryOperator.LESS, current, parameters[0]);
	var next = new SsaBinaryInstruction (span, type, 3, BinaryOperator.ADD, current, one);
	blocks[1].instructions.add (condition);
	blocks[2].instructions.add (next);
	blocks[0].complete (new SsaBranch (span, edge (blocks[1], {zero})));
	blocks[1].complete (new SsaConditionalBranch (span, condition.result, edge (blocks[2], {}), edge (blocks[3], {})));
	blocks[2].complete (new SsaBranch (span, edge (blocks[1], {next.result})));
	blocks[3].complete (new SsaReturn (span, current));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "cycle", type, 0, parameters, blocks, blocks[0]));
	return new SsaProgram (span, functions);
}

private void loops() {
	try {
		var types = new BuiltinTypes ();
		foreach (var type in new IntegerType[] {types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
			SsaProgram? program = sample (types, type);
			var parameter = WeakRef (program.functions[0].blocks[1].parameters[0]);
			SsaVerifier.verify (program);
			assert (SsaDump.format (program).contains (" : " + type.display_name ()));
			program = null;
			assert (parameter.get () == null);
		}
		try {
			SsaVerifier.verify (sample (types, types.i8_type, types.u8_type));
		} catch (SsaError error) {
			assert (error.message.contains ("integer value must retain its exact semantic type identity"));
			return;
		}
		GLib.error ("Mismatched integer bits/type accepted");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ints/ssa/standalone-loop-parameters-constants", loops);
	return Test.run ();
}

}
