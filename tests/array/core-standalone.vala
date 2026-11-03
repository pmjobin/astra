// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.ArrayCore {
private CoreProgram sample(bool vector, int variant = 0) throws CoreError {
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
	var parameters = new GenericArray<CoreParameter> ();
	var input = new CoreParameter (span, span, "value", variant == 21 ? (SemanticType) type : element, 0);
	var index_parameter = new CoreParameter (span, span, "i", t.i8_type, 1);
	parameters.add (input);
	parameters.add (index_parameter);
	var storage = new CoreLocalPlace (span, span, "a", type, 0);
	var foreign = new CoreLocalPlace (span, span, "foreign", type, 0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (storage);
	CoreValue input_value = new CoreParameterValue (span, input);
	CoreValue index = new CoreParameterValue (span, index_parameter);
	var boolean = new CoreBooleanValue (span, t.bool_type, BooleanLiteral.TRUE);
	var elements = new GenericArray<CoreValue> ();
	elements.add (variant == 9 ? (CoreValue) boolean : input_value);
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
		index = new CoreIntegerValue.typed (span, t.i8_type, AstraIntegerValue.from_int64 (t.i8_type, variant == 13 ? -1 : 2));
	}
	var provenance = new DataPointerProvenance (DataPointerOrigin.LOCAL, variant == 15 ? 1 : 0, 0);
	var place = new CoreArrayElementPlace (span, variant == 10 ? foreign : storage, variant == 11 ? t.array_of (element, 3) : type, index, provenance);
	var init = new CoreArrayInitialize (span, storage, elements);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	if (variant == 18) {
		elements[0] = new CoreLoadValue (span, place);
	}
	if (variant != 16) {
		body.statements.add (init);
	}
	if (variant == 17) {
		body.statements.add (init);
	}
	body.statements.add (new CoreStore (span, variant == 19 ? (CorePlace) storage : place, input_value));
	body.statements.add (new CoreReturn (span, new CoreLoadValue (span, place)));
	if (variant == 22) {
		var duplicate = new CoreLocalPlace (span, span, "duplicate", new ArrayType (element, 2), 1);
		locals.add (duplicate);
		body.statements.add (new CoreArrayInitialize (span, duplicate, elements));
	}
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", variant == 20 ? (SemanticType) type : element, parameters, locals, body));
	return new CoreProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CoreProgram? program = sample (vector);
			CoreVerifier.verify (program);
			string dump = CoreDump.format (program);
			assert (dump.contains ("array-initialize") && dump.contains ("array-element-place") && dump.contains ("load") && dump.contains ("store"));
			var witness = WeakRef (program.functions[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 22; variant++) {
		try {
			CoreVerifier.verify (sample (false, variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed array variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/array/core/standalone-model-and-lifetime", model);
	Test.add_func ("/array/core/standalone-malformed", malformed);
	return Test.run ();
}

}
