// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.StructElementsSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var s = SourceSpan (new SourceFile.from_text ("ssa-record-slice", "x"), 0, 1);
	var t = new BuiltinTypes ();
	var record = new SsaStruct (s, s, "S", new StructType ("S"));
	record.fields.add (new SsaStructField (s, s, "x", record, variant == 1 ? (SemanticType) t.string_type : t.int_type, 0));
	record.fields.add (new SsaStructField (s, s, "y", record, t.int_type, 1));
	var structures = new GenericArray<SsaStruct> ();
	if (variant != 2) {
		structures.add (record);
	}
	var slice = t.slice_of (record.semantic_type);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (s, s, "a", slice, 0, PointerParameterContract.BORROWED_NOESCAPE));
	parameters.add (new SsaFunctionParameter (s, s, "b", slice, 1, PointerParameterContract.BORROWED_NOESCAPE));
	parameters.add (new SsaFunctionParameter (s, s, "i", t.int_type, 2));
	var block = new SsaBlock (s, 0, 0);
	var guard = new SsaSliceBoundsCheck (s, parameters[0], parameters[2], 3);
	if (variant != 3 && variant != 4) {
		block.instructions.add (guard);
	}
	var root = new SsaSliceElementPlace (s, parameters[variant == 5 ? 1 : 0], slice, guard.result, new DataPointerProvenance (variant == 6 ? DataPointerOrigin.NULL : DataPointerOrigin.PARAMETER, 0, 0));
	var first = new SsaFieldPlace.projection (s, root, record.fields[0]);
	var second = new SsaFieldPlace.projection (s, root, record.fields[1]);
	var load = new SsaLoadInstruction (s, first, 4);
	block.instructions.add (load);
	block.instructions.add (new SsaStoreInstruction (s, second, load.result));
	if (variant == 4) {
		block.instructions.add (guard);
	}
	block.complete (new SsaReturn (s, load.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (s, s, "f", t.int_type, 0, parameters, blocks, block));
	return new SsaProgram (s, functions, null, null, structures);
}
private void qualify() {
	try {
		SsaProgram? program = sample ();
		SsaVerifier.verify (program);
		assert (program.functions[0].storage.length == 0);
		var owner = WeakRef (program.structs[0]);
		program = null;
		assert (owner.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant <= 6; variant++) {
		bool rejected = false;
		try {
			SsaVerifier.verify (sample (variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-elements/ssa/independent-indexed-root-bounds-and-malformed-models", qualify);
	return Test.run ();
}
}
