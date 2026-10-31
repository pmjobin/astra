// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.VectorLaneCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "lane metadata"), 0, 13);
	var type = types.vector_of (types.i16_type, 4);
	var unsigned_type = types.vector_of (types.u16_type, 4);
	var mask_type = types.vector_of (types.bool_type, 4);
	var block = new CfgBlock.reserve (span, 0);
	var scalar = new CfgIntegerValue.typed (span, types.i16_type, AstraIntegerValue.from_int64 (types.i16_type, 7));
	var unsigned_scalar = new CfgIntegerValue.typed (span, types.u16_type, AstraIntegerValue.from_int64 (types.u16_type, 7));
	var yes = new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
	SemanticType splat_type = variant == 2 ? new VectorType (types.i16_type, 16) : variant == 26 ? new VectorType (types.i16_type, 4) : type;
	var splat_instruction = new CfgVectorSplatInstruction (span, splat_type, variant == 1 ? unsigned_scalar : scalar, variant == 3 ? 3 : 4, span);
	block.instructions.add (splat_instruction);
	var splat = splat_instruction.result;
	var index = new VectorLaneIndex (span, variant == 5 ? -1 : variant == 6 ? 4 : 2);
	var extract_instruction = new CfgVectorExtractInstruction (span, variant == 7 ? types.u16_type : types.i16_type, variant == 4 ? (CfgValue) scalar : splat, index);
	block.instructions.add (extract_instruction);
	var extract = extract_instruction.result;
	var insertion_index = new VectorLaneIndex (span, variant == 11 ? -1 : variant == 12 ? 4 : 1);
	var insert_instruction = new CfgVectorInsertInstruction (span, variant == 10 ? unsigned_type : type, variant == 8 ? (CfgValue) scalar : splat, insertion_index, variant == 9 ? (CfgValue) unsigned_scalar : extract);
	block.instructions.add (insert_instruction);
	var insert = insert_instruction.result;
	var indices = new GenericArray<VectorLaneIndex> ();
	for (int i = 0; i < (variant == 14 ? 3 : variant == 15 ? 5 : 4); i++) {
		indices.add (new VectorLaneIndex (span, i == 0 && variant == 16 ? -1 : i == 0 && variant == 17 ? 4 : (3 - i + 4) % 4));
	}
	var selectors = new VectorLaneSelectors (indices);
	indices[0] = new VectorLaneIndex (span, 99);
	assert (selectors.at (0).ordinal != 99);
	var shuffle_instruction = new CfgVectorShuffleInstruction (span, variant == 18 ? types.vector_of (types.i16_type, 2) : type, variant == 13 ? (CfgValue) scalar : insert, selectors);
	block.instructions.add (shuffle_instruction);
	var shuffle = shuffle_instruction.result;
	var mask_instruction = new CfgVectorSplatInstruction (span, variant == 21 ? types.vector_of (types.bool_type, 2) : mask_type, yes, variant == 21 ? 2 : 4, span);
	block.instructions.add (mask_instruction);
	var mask = mask_instruction.result;
	var other_instruction = new CfgVectorSplatInstruction (span, unsigned_type, unsigned_scalar, 4, span);
	block.instructions.add (other_instruction);
	var other = other_instruction.result;
	var select_instruction = new CfgVectorSelectInstruction (span, variant == 23 ? unsigned_type : type, variant == 19 ? (CfgValue) yes : variant == 20 ? (CfgValue) splat : mask, variant == 24 ? (CfgValue) scalar : shuffle, variant == 22 ? other : splat);
	block.instructions.add (select_instruction);
	var select = select_instruction.result;
	block.complete (span, new CfgReturn (span, select));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions);
}

private void values() {
	try {
		CfgProgram? program = sample ();
		var weak_function = WeakRef (program.functions[0]);
		CfgVerifier.verify (program);
		string dump = CfgDump.format (program);
		foreach (string name in new string[] {"splat", "extract", "insert", "shuffle", "select"}) {
			assert (dump.contains ("vector-" + name));
		}
		assert (program.functions[0].blocks.length == 1 && program.functions[0].locals.length == 0 && program.functions[0].temporaries.length == 0);
		assert (program.functions[0].entry.instructions.length == 7);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		program = null;
		assert (weak_function.get () == null);
		for (int variant = 1; variant <= 26; variant++) {
			if (variant == 25) {
				continue;
			}
			bool rejected = false;
			try {
				CfgVerifier.verify (sample (variant));
			} catch (CfgError error) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("Accepted malformed Cfg vector primitive variant %d", variant);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec-lane/cfg/standalone-values-and-verifier", values);
	return Test.run ();
}
}
