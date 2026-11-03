// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.F64Ssa {
private SsaEdge edge(SsaBlock target, SsaValue[] values) {
	var arguments = new GenericArray<SsaValue> ();
	foreach (var value in values) {
		arguments.add (value);
	}
	return new SsaEdge (target, arguments);
}

private SsaProgram sample(BuiltinTypes types, SemanticType? wrong = null, bool wrong_format = false) throws SsaError {
	var type = types.f64_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "no literal"), 0, 10);
	var blocks = new GenericArray<SsaBlock> ();
	for (int b = 0; b < 4; b++) {
		blocks.add (new SsaBlock (span, b, b));
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "n", type, 0));
	var current = new SsaBlockParameter (span, span, "x", type, 1, 0);
	blocks[1].parameters.add (current);
	var zero = new SsaFloatConstant (span, wrong ?? type, new BinaryFloatValue.from_bits (wrong_format ? BinaryFloatFormat.BINARY32 : BinaryFloatFormat.BINARY64, wrong_format ? 0x80000000U : 0x8000000000000000UL));
	var one = new SsaFloatConstant (span, type, new BinaryFloatValue.from_bits (BinaryFloatFormat.BINARY64, 0x3fe0000000000000UL));
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
		assert (dump.contains ("(f64 0x8000000000000000 : f64)") && dump.contains ("(f64 0x3fe0000000000000 : f64)"));
		program = null;
		assert (parameter.get () == null);
		bool bad_format = false;
		try {
			SsaVerifier.verify (sample (types, null, true));
		} catch (SsaError error) {
			bad_format = error.message.contains ("matching binary format");
		}
		assert (bad_format);
		foreach (var wrong in new SemanticType[] {types.i32_type, new BuiltinTypes ().f64_type, new SemanticType (TypeKind.F64)}) {
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

private SsaProgram conversion(int variant) throws SsaError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("conversion", "no source parsing"), 0, 17);
	SemanticType source = variant == 2 ? (SemanticType) types.int_type : types.f32_type;
	SemanticType destination = variant == 3 ? (SemanticType) types.f32_type : types.f64_type;
	var kind = variant == 1 ? FloatConversionKind.FLOAT_NARROW : FloatConversionKind.FLOAT_WIDEN;
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "x", source, 0));
	var value = new SsaFloatConversionInstruction (span, source, destination, kind, 1, parameters[0]);
	var blocks = new GenericArray<SsaBlock> ();
	var block = new SsaBlock (span, 0, 0);
	block.instructions.add (value);
	block.complete (new SsaReturn (span, value.result));
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "convert", destination, 0, parameters, blocks, block));
	return new SsaProgram (span, functions);
}

private void conversions() {
	try {
		var program = conversion (0);
		SsaVerifier.verify (program);
		assert (SsaDump.format (program).contains ("float-convert (from f32) (to f64) (mode widen-exact)"));
		for (int variant = 1; variant <= 3; variant++) {
			bool rejected = false;
			try {
				SsaVerifier.verify (conversion (variant));
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
	Test.add_func ("/f64/ssa/standalone-loop-parameters-constants", loops);
	Test.add_func ("/f64/ssa/explicit-conversion-verifier", conversions);
	return Test.run ();
}

}
