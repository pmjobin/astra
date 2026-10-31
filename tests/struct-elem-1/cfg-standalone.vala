// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.StructElementsCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var s = SourceSpan (new SourceFile.from_text ("cfg-record-slice", "x"), 0, 1);
	var t = new BuiltinTypes ();
	var record = new CfgStruct (s, s, "S", new StructType ("S"));
	record.fields.add (new CfgStructField (s, s, "x", record, variant == 1 ? (SemanticType) t.string_type : t.int_type, 0));
	record.fields.add (new CfgStructField (s, s, "y", record, t.int_type, 1));
	var structures = new GenericArray<CfgStruct> ();
	if (variant != 2) {
		structures.add (record);
	}
	var slice = t.slice_of (record.semantic_type);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (s, s, "a", slice, 0, PointerParameterContract.BORROWED_NOESCAPE));
	parameters.add (new CfgParameter (s, s, "b", slice, 1, PointerParameterContract.BORROWED_NOESCAPE));
	parameters.add (new CfgParameter (s, s, "i", t.int_type, 2));
	var block = new CfgBlock.reserve (s, 0);
	var view = new CfgEvaluatedValue (s, slice);
	var index = new CfgEvaluatedValue (s, t.int_type);
	var checked_index = new CfgEvaluatedValue (s, t.int_type);
	block.instructions.add (new CfgEvaluateInstruction (s, new CfgParameterValue (s, parameters[0]), view));
	block.instructions.add (new CfgEvaluateInstruction (s, new CfgParameterValue (s, parameters[2]), index));
	var guard = new CfgSliceBoundsCheck (s, view, index, checked_index);
	if (variant != 3 && variant != 4) {
		block.instructions.add (guard);
	}
	var root = new CfgSliceElementPlace (s, variant == 5 ? (CfgValue) new CfgParameterValue (s, parameters[1]) : view, slice, checked_index, new DataPointerProvenance (variant == 6 ? DataPointerOrigin.NULL : DataPointerOrigin.PARAMETER, 0, 0));
	var first = new CfgFieldPlace (s, root, record.fields[0]);
	var second = new CfgFieldPlace (s, root, record.fields[1]);
	var captured = new CfgEvaluatedValue (s, t.int_type);
	block.instructions.add (new CfgEvaluateInstruction (s, new CfgLoadValue (s, first), captured));
	block.instructions.add (new CfgStore (s, second, captured));
	if (variant == 4) {
		block.instructions.add (guard);
	}
	block.complete (s, new CfgReturn (s, new CfgLoadValue (s, second)));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var function = new CfgFunction (s, s, "f", t.int_type, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	return new CfgProgram (s, functions, null, null, structures);
}
private void qualify() {
	try {
		CfgProgram? program = sample ();
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		var owner = WeakRef (program.structs[0]);
		program = null;
		assert (owner.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant <= 6; variant++) {
		bool rejected = false;
		try {
			CfgVerifier.verify (sample (variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-elements/cfg/independent-indexed-root-bounds-and-malformed-models", qualify);
	return Test.run ();
}
}
