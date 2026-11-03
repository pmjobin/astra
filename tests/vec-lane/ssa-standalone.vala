// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.VectorLaneSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "lane metadata"), 0, 13);
	var type = types.vector_of (types.i16_type, 4);
	var unsigned_type = types.vector_of (types.u16_type, 4);
	var mask_type = types.vector_of (types.bool_type, 4);
	var block = new SsaBlock (span, 0, 0);
	var scalar = new SsaIntegerConstant.typed (span, types.i16_type, AstraIntegerValue.from_int64 (types.i16_type, 7));
	var unsigned_scalar = new SsaIntegerConstant.typed (span, types.u16_type, AstraIntegerValue.from_int64 (types.u16_type, 7));
	var yes = new SsaBooleanConstant (span, types.bool_type, BooleanLiteral.TRUE);
	SemanticType splat_type = variant == 2 ? new VectorType (types.i16_type, 16) : variant == 26 ? new VectorType (types.i16_type, 4) : type;
	var splat_instruction = new SsaVectorSplatInstruction (span, splat_type, 0, variant == 1 ? unsigned_scalar : scalar, variant == 3 ? 3 : 4, span);
	block.instructions.add (splat_instruction);
	var splat = splat_instruction.result;
	var index = new VectorLaneIndex (span, variant == 5 ? -1 : variant == 6 ? 4 : 2);
	var extract_instruction = new SsaVectorExtractInstruction (span, variant == 7 ? types.u16_type : types.i16_type, 1, variant == 4 ? (SsaValue) scalar : splat, index);
	block.instructions.add (extract_instruction);
	var extract = extract_instruction.result;
	var insertion_index = new VectorLaneIndex (span, variant == 11 ? -1 : variant == 12 ? 4 : 1);
	var insert_instruction = new SsaVectorInsertInstruction (span, variant == 10 ? unsigned_type : type, 2, variant == 8 ? (SsaValue) scalar : splat, insertion_index, variant == 9 ? (SsaValue) unsigned_scalar : extract);
	block.instructions.add (insert_instruction);
	var insert = insert_instruction.result;
	var indices = new GenericArray<VectorLaneIndex> ();
	for (int i = 0; i < (variant == 14 ? 3 : variant == 15 ? 5 : 4); i++) {
		indices.add (new VectorLaneIndex (span, i == 0 && variant == 16 ? -1 : i == 0 && variant == 17 ? 4 : (3 - i + 4) % 4));
	}
	var selectors = new VectorLaneSelectors (indices);
	indices[0] = new VectorLaneIndex (span, 99);
	assert (selectors.at (0).ordinal != 99);
	var shuffle_instruction = new SsaVectorShuffleInstruction (span, variant == 18 ? types.vector_of (types.i16_type, 2) : type, 3, variant == 13 ? (SsaValue) scalar : insert, selectors);
	block.instructions.add (shuffle_instruction);
	var shuffle = shuffle_instruction.result;
	var mask_instruction = new SsaVectorSplatInstruction (span, variant == 21 ? types.vector_of (types.bool_type, 2) : mask_type, 4, yes, variant == 21 ? 2 : 4, span);
	block.instructions.add (mask_instruction);
	var mask = mask_instruction.result;
	var other_instruction = new SsaVectorSplatInstruction (span, unsigned_type, 5, unsigned_scalar, 4, span);
	block.instructions.add (other_instruction);
	var other = other_instruction.result;
	var select_instruction = new SsaVectorSelectInstruction (span, variant == 23 ? unsigned_type : type, 6, variant == 19 ? (SsaValue) yes : variant == 20 ? (SsaValue) splat : mask, variant == 24 ? (SsaValue) scalar : shuffle, variant == 22 ? other : splat);
	block.instructions.add (select_instruction);
	var select = select_instruction.result;
	if (variant == 25) {
		block.instructions.remove_index (0);
	}
	block.complete (new SsaReturn (span, select));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", type, 0, new GenericArray<SsaFunctionParameter> (), blocks, block));
	return new SsaProgram (span, functions);
}

private void values() {
	try {
		SsaProgram? program = sample ();
		var weak_function = WeakRef (program.functions[0]);
		SsaVerifier.verify (program);
		string dump = SsaDump.format (program);
		foreach (string name in new string[] {"splat", "extract", "insert", "shuffle", "select"}) {
			assert (dump.contains ("vector-" + name));
		}
		assert (program.functions[0].blocks.length == 1 && program.functions[0].storage.length == 0);
		assert (program.functions[0].entry.instructions.length == 7);
		assert (dump.contains ("%1 : i16 = vector-extract") && dump.contains ("%2 : i16<4> = vector-insert") && dump.contains ("%3 : i16<4> = vector-shuffle") && dump.contains ("%6 : i16<4> = vector-select"));
		program = null;
		assert (weak_function.get () == null);
		for (int variant = 1; variant <= 26; variant++) {
			bool rejected = false;
			try {
				SsaVerifier.verify (sample (variant));
			} catch (SsaError error) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("Accepted malformed Ssa vector primitive variant %d", variant);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec-lane/ssa/standalone-values-and-verifier", values);
	return Test.run ();
}

}
