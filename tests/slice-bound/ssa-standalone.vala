// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SliceBoundSsa {
private SsaProgram sample(bool vector, int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("slice-bound", "s"), 0, 1);
	SemanticType element = vector ? (SemanticType) t.vector_of (t.i16_type, 8) : t.int_type;
	var type = t.slice_of (element);
	if (variant == 3) {
		type = new SliceType (t.bool_type);
	}
	var contract = variant == 1 ? PointerParameterContract.UNMANAGED : variant == 2 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var slice = new SsaFunctionParameter (span, span, "s", type, 0, contract);
	var value = new SsaFunctionParameter (span, span, "value", element, 1);
	var index = new SsaFunctionParameter (span, span, "i", t.int_type, 2);
	parameters.add (slice);
	parameters.add (value);
	parameters.add (index);
	var foreign = new SsaFunctionParameter (span, span, "s", type, 0, PointerParameterContract.BORROWED_NOESCAPE);
	var provenance = new DataPointerProvenance (variant == 4 ? DataPointerOrigin.NULL : DataPointerOrigin.PARAMETER, 0, variant == 5 ? 1 : 0);
	var block = new SsaBlock (span, 0, 0);
	SsaValue view = variant == 8 ? foreign : slice;
	var bounds = new SsaSliceBoundsCheck (span, view, index, 3);
	if (variant != 9) {
		block.instructions.add (bounds);
	}
	var place = new SsaSliceElementPlace (span, view, variant == 7 ? t.slice_of (t.f32_type) : type, variant == 9 ? (SsaValue) index : bounds.result, provenance);
	block.instructions.add (new SsaStoreInstruction (span, place, value));
	var load = new SsaLoadInstruction (span, place, 4);
	block.instructions.add (load);
	block.instructions.add (new SsaStoreInstruction (span, place, load.result));
	var length = new SsaSliceLengthInstruction (span, t.int_type, view, 5);
	block.instructions.add (length);
	block.complete (new SsaReturn (span, length.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", variant == 6 ? (SemanticType) type : t.int_type, 0, parameters, blocks, block));
	return new SsaProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			SsaProgram? program = sample (vector);
			SsaVerifier.verify (program);
			assert (program.functions[0].parameters.length == 3 && program.functions[0].parameters[0].semantic_type is SliceType);
			assert (program.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
			string dump = SsaDump.format (program);
			assert (dump.contains ("borrowed-noescape") && dump.contains ("slice-length") && dump.contains ("slice-element-place"));
			var witness = WeakRef (program.functions[0].parameters[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 9; variant++) {
		try {
			SsaVerifier.verify (sample (false, variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed slice parameter variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice-bound/ssa/independent-parameters-places-and-lifetime", model);
	Test.add_func ("/slice-bound/ssa/malformed-contracts-types-and-provenance", malformed);
	return Test.run ();
}
}
