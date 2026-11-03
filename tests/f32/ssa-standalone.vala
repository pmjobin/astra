// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.F32Ssa {
private SsaEdge edge(SsaBlock target, SsaValue[] values) {
	var arguments = new GenericArray<SsaValue> ();
	foreach (var value in values) {
		arguments.add (value);
	}
	return new SsaEdge (target, arguments);
}

private SsaProgram sample(BuiltinTypes types, SemanticType? wrong = null) throws SsaError {
	var type = types.f32_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "no literal"), 0, 10);
	var blocks = new GenericArray<SsaBlock> ();
	for (int b = 0; b < 4; b++) {
		blocks.add (new SsaBlock (span, b, b));
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "n", type, 0));
	var current = new SsaBlockParameter (span, span, "x", type, 1, 0);
	blocks[1].parameters.add (current);
	var zero = new SsaFloatConstant (span, wrong ?? type, new AstraF32Value.from_bits (0x80000000U));
	var one = new SsaFloatConstant (span, type, new AstraF32Value.from_bits (0x3f000000U));
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
		SsaProgram? program = sample (types);
		var parameter = WeakRef (program.functions[0].blocks[1].parameters[0]);
		SsaVerifier.verify (program);
		string dump = SsaDump.format (program);
		assert (dump.contains ("(f32 0x80000000 : f32)") && dump.contains ("(f32 0x3f000000 : f32)"));
		program = null;
		assert (parameter.get () == null);
		foreach (var wrong in new SemanticType[] {types.i32_type, new BuiltinTypes ().f32_type, new SemanticType (TypeKind.F32)}) {
			bool rejected = false;
			try {
				SsaVerifier.verify (sample (types, wrong));
			} catch (SsaError error) {
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f32/ssa/standalone-loop-parameters-constants", loops);
	return Test.run ();
}

}
