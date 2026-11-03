// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.ArrayCfg {
private CfgProgram sample(bool vector, int variant = 0) throws CfgError {
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
	var parameters = new GenericArray<CfgParameter> ();
	var input = new CfgParameter (span, span, "value", variant == 21 ? (SemanticType) type : element, 0);
	var index_parameter = new CfgParameter (span, span, "i", t.i8_type, 1);
	parameters.add (input);
	parameters.add (index_parameter);
	var storage = new CfgLocalPlace (span, span, "a", type, 0);
	var foreign = new CfgLocalPlace (span, span, "foreign", type, 0);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (storage);
	CfgValue input_value = new CfgParameterValue (span, input);
	CfgValue index = new CfgParameterValue (span, index_parameter);
	var boolean = new CfgBooleanValue (span, t.bool_type, BooleanLiteral.TRUE);
	var elements = new GenericArray<CfgValue> ();
	elements.add (variant == 9 ? (CfgValue) boolean : input_value);
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
		index = new CfgIntegerValue.typed (span, t.i8_type, AstraIntegerValue.from_int64 (t.i8_type, variant == 13 ? -1 : 2));
	}
	var provenance = new DataPointerProvenance (DataPointerOrigin.LOCAL, variant == 15 ? 1 : 0, 0);
	var block = new CfgBlock.reserve (span, 0);
	var init = new CfgArrayInitialize (span, storage, elements);
	if (variant != 16) {
		block.instructions.add (init);
	}
	if (variant == 17) {
		block.instructions.add (init);
	}
	if (!(index is CfgIntegerValue) && variant != 20) {
		var checked_index = new CfgEvaluatedValue (span, index.semantic_type);
		block.instructions.add (new CfgArrayBoundsCheck (span, storage, index, checked_index));
		index = checked_index;
	}
	var place = new CfgArrayElementPlace (span, variant == 10 ? foreign : storage, variant == 11 ? t.array_of (element, 3) : type, index, provenance);
	if (variant == 18) {
		elements[0] = new CfgLoadValue (span, place);
	}
	block.instructions.add (new CfgStore (span, variant == 19 ? (CfgPlace) storage : place, input_value));
	if (variant == 22) {
		var duplicate = new CfgLocalPlace (span, span, "duplicate", new ArrayType (element, 2), 1);
		locals.add (duplicate);
		block.instructions.add (new CfgArrayInitialize (span, duplicate, elements));
	}
	block.complete (span, new CfgReturn (span, new CfgLoadValue (span, place)));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", element, 0, parameters, locals, blocks, block));
	return new CfgProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CfgProgram? program = sample (vector);
			CfgVerifier.verify (program);
			string dump = CfgDump.format (program);
			assert (dump.contains ("array-initialize") && dump.contains ("array-element-place") && dump.contains ("load") && dump.contains ("store"));
			var witness = WeakRef (program.functions[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 22; variant++) {
		try {
			CfgVerifier.verify (sample (false, variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed array variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/array/cfg/standalone-model-and-lifetime", model);
	Test.add_func ("/array/cfg/standalone-malformed", malformed);
	return Test.run ();
}

}
