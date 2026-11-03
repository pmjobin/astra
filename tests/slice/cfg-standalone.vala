// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.SliceCfg {
private CfgProgram sample(bool vector, int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("slice", "a"), 0, 1);
	SemanticType element = vector ? (SemanticType) t.vector_of (t.i16_type, 8) : t.i16_type;
	var array = t.array_of (element, 2);
	var type = t.slice_of (element);
	switch (variant) {
	case 1:
		type = new SliceType (t.bool_type);
		break;
	case 2:
		type = new SliceType (t.vector_of (t.bool_type, 4));
		break;
	case 3:
		type = new SliceType (t.pointer_to (element));
		break;
	case 4:
		type = new SliceType (type);
		break;
	case 5:
		type = new SliceType (array);
		break;
	case 9:
		type = t.slice_of (t.f32_type);
		break;
	}
	var parameters = new GenericArray<CfgParameter> ();
	var input = new CfgParameter (span, span, "value", variant == 20 ? (SemanticType) type : element, 0);
	var index_parameter = new CfgParameter (span, span, "i", t.i8_type, 1);
	parameters.add (input);
	parameters.add (index_parameter);
	var storage = new CfgLocalPlace (span, span, "a", array, 0);
	var foreign = new CfgLocalPlace (span, span, "foreign", array, 0);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (storage);
	var local = new CfgLocalPlace (span, span, "s", type, 1);
	locals.add (local);
	CfgValue input_value = new CfgParameterValue (span, input);
	CfgValue index = new CfgParameterValue (span, index_parameter);
	var zero = new CfgIntegerValue.typed (span, t.i8_type, AstraIntegerValue.from_int64 (t.i8_type, 0));
	var two = new CfgIntegerValue.typed (span, t.u32_type, AstraIntegerValue.from_int64 (t.u32_type, 2));
	var boolean = new CfgBooleanValue (span, t.bool_type, BooleanLiteral.TRUE);
	CfgValue? start = zero;
	CfgValue? count = two;
	if (variant == 10) {
		count = null;
	}
	if (variant == 11) {
		start = null;
	}
	if (variant == 12) {
		index = boolean;
	}
	if (variant == 13) {
		start = boolean;
	}
	var provenance = new DataPointerProvenance (variant == 14 ? DataPointerOrigin.NULL : DataPointerOrigin.LOCAL, variant == 15 ? 42 : 0, 0);
	var elements = new GenericArray<CfgValue> ();
	elements.add (input_value);
	elements.add (input_value);
	var block = new CfgBlock.reserve (span, 0);
	if (variant != 16) {
		block.instructions.add (new CfgArrayInitialize (span, storage, elements));
	}
	if (start != null) {
		var captured = new CfgEvaluatedValue (span, start.semantic_type);
		block.instructions.add (new CfgEvaluateInstruction (span, start, captured));
		start = captured;
	}
	if (count != null) {
		var captured = new CfgEvaluatedValue (span, count.semantic_type);
		block.instructions.add (new CfgEvaluateInstruction (span, count, captured));
		count = captured;
	}
	CfgValue construction = new CfgSliceFromArrayValue (span, variant == 6 ? new SliceType (element) : type, variant == 7 ? foreign : storage, variant == 8 ? t.array_of (element, 3) : array, start, count, provenance);
	if (variant == 29) {
		construction = new CfgNullPointerValue (span, type);
	}
	var constructed = new CfgEvaluatedValue (span, construction.semantic_type);
	block.instructions.add (new CfgEvaluateInstruction (span, construction, constructed));
	block.instructions.add (new CfgInitialize (span, local, constructed));
	var view = new CfgEvaluatedValue (span, type);
	block.instructions.add (new CfgEvaluateInstruction (span, new CfgLoadValue (span, local), view));
	var other = new CfgEvaluatedValue (span, type);
	block.instructions.add (new CfgEvaluateInstruction (span, new CfgLoadValue (span, local), other));
	var length = new CfgSliceLengthValue (span, variant == 24 ? t.u32_type : t.int_type, variant == 25 ? input_value : view);
	block.instructions.add (new CfgEvaluateInstruction (span, length, new CfgEvaluatedValue (span, length.semantic_type)));
	var checked_index = new CfgEvaluatedValue (span, variant == 26 ? t.bool_type : index.semantic_type);
	var bounds = new CfgSliceBoundsCheck (span, variant == 27 ? input_value : view, index, checked_index);
	if (variant != 21 && variant != 23) {
		block.instructions.add (bounds);
		index = checked_index;
	}
	if (variant == 23) {
		index = checked_index;
	}
	var place = new CfgSliceElementPlace (span, variant == 22 ? other : view, variant == 17 ? t.slice_of (t.f32_type) : type, index, provenance);
	if (variant == 28) {
		block.instructions.add (new CfgInitialize (span, place, input_value));
	}
	block.instructions.add (new CfgStore (span, place, input_value));
	if (variant == 23) {
		block.instructions.add (bounds);
	}
	block.complete (span, new CfgReturn (span, new CfgLoadValue (span, variant == 18 ? (CfgPlace) storage : place)));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", variant == 19 ? (SemanticType) type : element, 0, parameters, locals, blocks, block));
	return new CfgProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CfgProgram? program = sample (vector);
			CfgVerifier.verify (program);
			string dump = CfgDump.format (program);
			assert (dump.contains ("slice-from-array") && dump.contains ("slice-element-place") && dump.contains ("slice-length") && dump.contains ("load") && dump.contains ("store"));
			var witness = WeakRef (program.functions[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 29; variant++) {
		try {
			CfgVerifier.verify (sample (false, variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed slice variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice/cfg/standalone-model-and-lifetime", model);
	Test.add_func ("/slice/cfg/standalone-malformed", malformed);
	return Test.run ();
}

}
