// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.SliceBoundCfg {
private CfgProgram sample(bool vector, int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("slice-bound", "s"), 0, 1);
	SemanticType element = vector ? (SemanticType) t.vector_of (t.i16_type, 8) : t.int_type;
	var type = t.slice_of (element);
	if (variant == 3) {
		type = new SliceType (t.bool_type);
	}
	var contract = variant == 1 ? PointerParameterContract.UNMANAGED : variant == 2 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	var parameters = new GenericArray<CfgParameter> ();
	var slice = new CfgParameter (span, span, "s", type, 0, contract);
	var value = new CfgParameter (span, span, "value", element, 1);
	var index = new CfgParameter (span, span, "i", t.int_type, 2);
	parameters.add (slice);
	parameters.add (value);
	parameters.add (index);
	var foreign = new CfgParameter (span, span, "s", type, 0, PointerParameterContract.BORROWED_NOESCAPE);
	var provenance = new DataPointerProvenance (variant == 4 ? DataPointerOrigin.NULL : DataPointerOrigin.PARAMETER, 0, variant == 5 ? 1 : 0);
	var block = new CfgBlock.reserve (span, 0);
	var view = new CfgEvaluatedValue (span, type);
	block.instructions.add (new CfgEvaluateInstruction (span, new CfgParameterValue (span, variant == 8 ? foreign : slice), view));
	var locals = new GenericArray<CfgLocalPlace> ();
	var local = new CfgLocalPlace (span, span, "copy", type, 0);
	locals.add (local);
	block.instructions.add (new CfgInitialize (span, local, view));
	var checked_index = new CfgEvaluatedValue (span, t.int_type);
	if (variant != 9) {
		block.instructions.add (new CfgSliceBoundsCheck (span, view, new CfgParameterValue (span, index), checked_index));
	}
	var place = new CfgSliceElementPlace (span, view, variant == 7 ? t.slice_of (t.f32_type) : type, variant == 9 ? (CfgValue) new CfgParameterValue (span, index) : checked_index, provenance);
	block.instructions.add (new CfgStore (span, place, new CfgParameterValue (span, value)));
	block.instructions.add (new CfgStore (span, place, new CfgLoadValue (span, place)));
	block.complete (span, new CfgReturn (span, new CfgSliceLengthValue (span, t.int_type, new CfgLoadValue (span, local))));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", variant == 6 ? (SemanticType) type : t.int_type, 0, parameters, locals, blocks, block));
	return new CfgProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CfgProgram? program = sample (vector);
			CfgVerifier.verify (program);
			assert (program.functions[0].parameters.length == 3 && program.functions[0].parameters[0].semantic_type is SliceType);
			assert (program.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
			string dump = CfgDump.format (program);
			assert (dump.contains ("borrowed-noescape") && dump.contains ("slice-length") && dump.contains ("slice-element-place"));
			var witness = WeakRef (program.functions[0].parameters[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 9; variant++) {
		try {
			CfgVerifier.verify (sample (false, variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed slice parameter variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice-bound/cfg/independent-parameters-places-and-lifetime", model);
	Test.add_func ("/slice-bound/cfg/malformed-contracts-types-and-provenance", malformed);
	return Test.run ();
}

}
