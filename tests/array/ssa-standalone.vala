// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.ArraySsa {
private SsaProgram sample(bool vector, int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("array", "a"), 0, 1);
	SemanticType element = vector ? (SemanticType) t.vector_of (t.i16_type, 4) : t.i16_type;
	var type = t.array_of (element, 2);
	switch (variant) {
	case 1:
		type = new ArrayType (element, 0);
		break;
	case 2:
		type = new ArrayType (element, 1025);
		break;
	case 3:
		type = new ArrayType (t.bool_type, 2);
		break;
	case 4:
		type = new ArrayType (t.vector_of (t.bool_type, 4), 2);
		break;
	case 5:
		type = new ArrayType (t.pointer_to (element), 2);
		break;
	case 6:
		type = new ArrayType (type, 2);
		break;
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var input = new SsaFunctionParameter (span, span, "value", variant == 21 ? (SemanticType) type : element, 0);
	var index_parameter = new SsaFunctionParameter (span, span, "i", t.i8_type, 1);
	parameters.add (input);
	parameters.add (index_parameter);
	var storage = new SsaAddressableLocal (span, span, "a", type, 0, 0);
	var foreign = new SsaAddressableLocal (span, span, "foreign", type, 0, 0);
	SsaValue input_value = input;
	SsaValue index = index_parameter;
	var boolean = new SsaBooleanConstant (span, t.bool_type, BooleanLiteral.TRUE);
	var elements = new GenericArray<SsaValue> ();
	elements.add (variant == 9 ? (SsaValue) boolean : input_value);
	if (variant != 7) {
		elements.add (input_value);
	}
	if (variant == 8) {
		elements.add (input_value);
	}
	if (variant == 12) {
		index = boolean;
	}
	if (variant == 13 || variant == 14) {
		index = new SsaIntegerConstant.typed (span, t.i8_type, AstraIntegerValue.from_int64 (t.i8_type, variant == 13 ? -1 : 2));
	}
	var provenance = new DataPointerProvenance (DataPointerOrigin.LOCAL, variant == 15 ? 1 : 0, 0);
	var block = new SsaBlock (span, 0, 0);
	var init = new SsaArrayInitialize (span, storage, elements);
	if (variant != 16) {
		block.instructions.add (init);
	}
	if (variant == 17) {
		block.instructions.add (init);
	}
	if (!(index is SsaIntegerConstant) && variant != 20) {
		var bounds = new SsaArrayBoundsCheck (span, storage, index, 2);
		block.instructions.add (bounds);
		index = bounds.result;
	}
	var place = new SsaArrayElementPlace (span, variant == 10 ? foreign : storage, variant == 11 ? t.array_of (element, 3) : type, index, provenance);
	var load = new SsaLoadInstruction (span, place, 3);
	if (variant == 18) {
		elements[0] = load.result;
	}
	block.instructions.add (new SsaStoreInstruction (span, variant == 19 ? (SsaMemoryPlace) new SsaLocalMemoryPlace (span, storage) : place, input_value));
	block.instructions.add (load);
	block.complete (new SsaReturn (span, load.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	var function = new SsaFunction (span, span, "f", element, 0, parameters, blocks, block);
	function.storage.add (storage);
	if (variant == 22) {
		var duplicate = new SsaAddressableLocal (span, span, "duplicate", new ArrayType (element, 2), 1, 1);
		function.storage.add (duplicate);
		block.instructions.add (new SsaArrayInitialize (span, duplicate, elements));
	}
	functions.add (function);
	return new SsaProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			SsaProgram? program = sample (vector);
			SsaVerifier.verify (program);
			string dump = SsaDump.format (program);
			assert (dump.contains ("array-initialize") && dump.contains ("array-element-place") && dump.contains ("load") && dump.contains ("store"));
			var witness = WeakRef (program.functions[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 22; variant++) {
		try {
			SsaVerifier.verify (sample (false, variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed array variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/array/ssa/standalone-model-and-lifetime", model);
	Test.add_func ("/array/ssa/standalone-malformed", malformed);
	return Test.run ();
}

}
