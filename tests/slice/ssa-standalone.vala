// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SliceSsa {
private SsaProgram sample(bool vector, int variant = 0) throws SsaError {
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
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var input = new SsaFunctionParameter (span, span, "value", variant == 20 ? (SemanticType) type : element, 0);
	var index_parameter = new SsaFunctionParameter (span, span, "i", t.i8_type, 1);
	parameters.add (input);
	parameters.add (index_parameter);
	var storage = new SsaAddressableLocal (span, span, "a", array, 0, 0);
	var foreign = new SsaAddressableLocal (span, span, "foreign", array, 0, 0);
	SsaValue input_value = input;
	SsaValue index = index_parameter;
	var zero = new SsaIntegerConstant.typed (span, t.i8_type, AstraIntegerValue.from_int64 (t.i8_type, 0));
	var two = new SsaIntegerConstant.typed (span, t.u32_type, AstraIntegerValue.from_int64 (t.u32_type, 2));
	var boolean = new SsaBooleanConstant (span, t.bool_type, BooleanLiteral.TRUE);
	SsaValue? start = zero;
	SsaValue? count = two;
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
	var elements = new GenericArray<SsaValue> ();
	elements.add (input_value);
	elements.add (input_value);
	var block = new SsaBlock (span, 0, 0);
	if (variant != 16) {
		block.instructions.add (new SsaArrayInitialize (span, storage, elements));
	}
	var construction = new SsaSliceConstructInstruction (span, type, variant == 7 ? foreign : storage, variant == 8 ? t.array_of (element, 3) : array, start, count, provenance, 2);
	block.instructions.add (construction);
	var other = new SsaSliceConstructInstruction (span, variant == 6 ? new SliceType (element) : type, storage, array, start, count, provenance, 3);
	block.instructions.add (other);
	SsaValue view = construction.result;
	if (variant == 29) {
		view = new SsaNullPointerConstant (span, type);
	}
	block.instructions.add (new SsaSliceLengthInstruction (span, variant == 24 ? t.u32_type : t.int_type, variant == 25 ? input_value : view, 4));
	var bounds = new SsaSliceBoundsCheck (span, variant == 27 ? input_value : view, variant == 26 ? boolean : index, 5);
	if (variant != 21 && variant != 23) {
		block.instructions.add (bounds);
		index = bounds.result;
	}
	if (variant == 23) {
		index = bounds.result;
	}
	var place = new SsaSliceElementPlace (span, variant == 22 ? other.result : view, variant == 17 ? t.slice_of (t.f32_type) : type, index, provenance);
	if (variant == 28) {
		block.instructions.add (new SsaInitializeInstruction (span, place, input_value));
	}
	block.instructions.add (new SsaStoreInstruction (span, place, input_value));
	if (variant == 23) {
		block.instructions.add (bounds);
	}
	var load = new SsaLoadInstruction (span, variant == 18 ? (SsaMemoryPlace) new SsaLocalMemoryPlace (span, storage) : place, 6);
	block.instructions.add (load);
	block.complete (new SsaReturn (span, load.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var function = new SsaFunction (span, span, "f", variant == 19 ? (SemanticType) type : element, 0, parameters, blocks, block);
	function.storage.add (storage);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	return new SsaProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			SsaProgram? program = sample (vector);
			SsaVerifier.verify (program);
			string dump = SsaDump.format (program);
			assert (dump.contains ("slice-from-array") && dump.contains ("slice-element-place") && dump.contains ("slice-length") && dump.contains ("load") && dump.contains ("store"));
			var witness = WeakRef (program.functions[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 29; variant++) {
		try {
			SsaVerifier.verify (sample (false, variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed slice variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice/ssa/standalone-model-and-lifetime", model);
	Test.add_func ("/slice/ssa/standalone-malformed", malformed);
	return Test.run ();
}

}
