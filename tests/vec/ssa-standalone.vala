// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.VectorSsa {
private SsaEdge edge(SsaBlock target, SsaValue[] values) {
	var arguments = new GenericArray<SsaValue> ();
	foreach (var value in values) {
		arguments.add (value);
	}
	return new SsaEdge (target, arguments);
}

private SsaProgram sample(BuiltinTypes types, int variant = 0) throws SsaError {
	var type = types.vector_of (types.i16_type, 4);
	var mask = types.vector_of (types.bool_type, 4);
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "provenance"), 0, 10);
	var blocks = new GenericArray<SsaBlock> ();
	for (int b = 0; b < 4; b++) {
		blocks.add (new SsaBlock (span, b, b));
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "limit", type, 0));
	var current = new SsaBlockParameter (span, span, "v", type, 1, 0);
	var condition = new SsaBlockParameter (span, span, "mask", mask, 2, 1);
	blocks[1].parameters.add (current);
	blocks[1].parameters.add (condition);
	var lanes = new GenericArray<SsaValue> ();
	for (int i = 0; i < (variant == 1 ? 3 : 4); i++) {
		var element = variant == 2 ? types.u16_type : types.i16_type;
		lanes.add (new SsaIntegerConstant.typed (span, element, AstraIntegerValue.from_int64 (element, i)));
	}
	SemanticType constructed = type;
	if (variant == 3) {
		constructed = new VectorType (types.i16_type, 16);
	}
	if (variant == 4) {
		constructed = new VectorType (types.i16_type, 4);
	}
	if (variant == 5) {
		constructed = new VectorType (type, 4);
	}
	if (variant == 6) {
		constructed = new SemanticType (TypeKind.VECTOR);
	}
	var initial = new SsaVectorConstructInstruction (span, constructed, 3, lanes);
	var initial_mask = new SsaBinaryInstruction (span, mask, 4, BinaryOperator.LESS, initial.result, parameters[0]);
	blocks[0].instructions.add (initial);
	blocks[0].instructions.add (initial_mask);
	var reduce = new SsaVectorReductionInstruction (span, variant == 7 ? (SemanticType) mask : types.bool_type, 5, variant == 8 ? (VectorReductionOperator) 99 : VectorReductionOperator.ANY, variant == 9 ? current : condition);
	blocks[1].instructions.add (reduce);
	var next = new SsaBinaryInstruction (span, type, 6, variant == 10 ? BinaryOperator.DIVIDE : BinaryOperator.ADD, current, initial.result);
	var compare = new SsaBinaryInstruction (span, variant == 11 ? types.bool_type : (SemanticType) mask, 7, BinaryOperator.LESS, next.result, parameters[0]);
	blocks[2].instructions.add (next);
	blocks[2].instructions.add (compare);
	if (variant == 12) {
		lanes[0] = next.result;
	}
	blocks[0].complete (new SsaBranch (span, edge (blocks[1], {initial.result, initial_mask.result})));
	blocks[1].complete (new SsaConditionalBranch (span, variant == 13 ? condition : (SsaValue) reduce.result, edge (blocks[2], {}), edge (blocks[3], {})));
	blocks[2].complete (new SsaBranch (span, edge (blocks[1], {next.result, compare.result})));
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
		assert (dump.contains ("%3 : i16<4> = vector-init") && dump.contains ("%6 : i16<4> = binary +") && dump.contains ("%7 : bool<4> = binary <") && dump.contains ("%5 : bool = vector-any"));
		assert (program.functions[0].blocks[1].parameters.length == 2 && program.functions[0].blocks[2].instructions.length == 2);
		assert (program.functions[0].storage.length == 0);
		program = null;
		assert (parameter.get () == null);
		for (int variant = 1; variant <= 13; variant++) {
			bool rejected = false;
			try {
				SsaVerifier.verify (sample (types, variant));
			} catch (SsaError error) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("Accepted malformed SSA vector variant %d", variant);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec/ssa/standalone-whole-vector-mask-loop-13-rejections", loops);
	return Test.run ();
}
}
