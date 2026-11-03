// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.SliceCore {
private CoreProgram sample(bool vector, int variant = 0) throws CoreError {
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
	var parameters = new GenericArray<CoreParameter> ();
	var input = new CoreParameter (span, span, "value", variant == 20 ? (SemanticType) type : element, 0);
	var index_parameter = new CoreParameter (span, span, "i", t.i8_type, 1);
	parameters.add (input);
	parameters.add (index_parameter);
	var storage = new CoreLocalPlace (span, span, "a", array, 0);
	var foreign = new CoreLocalPlace (span, span, "foreign", array, 0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (storage);
	var local = new CoreLocalPlace (span, span, "s", type, 1);
	locals.add (local);
	CoreValue input_value = new CoreParameterValue (span, input);
	CoreValue index = new CoreParameterValue (span, index_parameter);
	var zero = new CoreIntegerValue.typed (span, t.i8_type, AstraIntegerValue.from_int64 (t.i8_type, 0));
	var two = new CoreIntegerValue.typed (span, t.u32_type, AstraIntegerValue.from_int64 (t.u32_type, 2));
	var boolean = new CoreBooleanValue (span, t.bool_type, BooleanLiteral.TRUE);
	CoreValue? start = zero;
	CoreValue? count = two;
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
	var elements = new GenericArray<CoreValue> ();
	elements.add (input_value);
	elements.add (input_value);
	if (variant == 21) {
		start = new CoreIntegerValue.typed (span, t.i8_type, AstraIntegerValue.from_int64 (t.i8_type, -1));
	}
	if (variant == 22) {
		count = new CoreIntegerValue.typed (span, t.u32_type, AstraIntegerValue.from_int64 (t.u32_type, 3));
	}
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	if (variant != 16) {
		body.statements.add (new CoreArrayInitialize (span, storage, elements));
	}
	CoreValue construction = new CoreSliceFromArrayValue (span, variant == 6 ? new SliceType (element) : type, variant == 7 ? foreign : storage, variant == 8 ? t.array_of (element, 3) : array, start, count, provenance);
	if (variant == 29) {
		construction = new CoreNullPointerValue (span, type);
	}
	body.statements.add (new CoreInitialize (span, local, construction));
	CoreValue view = new CoreLoadValue (span, local);
	if (variant == 27) {
		view = input_value;
	}
	var length_local = new CoreLocalPlace (span, span, "n", variant == 24 ? t.u32_type : t.int_type, 2);
	locals.add (length_local);
	body.statements.add (new CoreInitialize (span, length_local, new CoreSliceLengthValue (span, length_local.semantic_type, variant == 25 ? input_value : view)));
	var place = new CoreSliceElementPlace (span, view, variant == 17 ? t.slice_of (t.f32_type) : type, index, provenance);
	if (variant == 23) {
		body.statements[0] = new CoreStore (span, place, input_value);
	}
	if (variant == 26) {
		place = new CoreSliceElementPlace (span, view, type, boolean, provenance);
	}
	if (variant == 28) {
		body.statements.add (new CoreInitialize (span, place, input_value));
	}
	body.statements.add (new CoreStore (span, place, input_value));
	body.statements.add (new CoreReturn (span, new CoreLoadValue (span, variant == 18 ? (CorePlace) storage : place)));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", variant == 19 ? (SemanticType) type : element, parameters, locals, body));
	return new CoreProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CoreProgram? program = sample (vector);
			CoreVerifier.verify (program);
			string dump = CoreDump.format (program);
			assert (dump.contains ("slice-from-array") && dump.contains ("slice-element-place") && dump.contains ("slice-length") && dump.contains ("load") && dump.contains ("store"));
			var witness = WeakRef (program.functions[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 29; variant++) {
		try {
			CoreVerifier.verify (sample (false, variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed slice variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice/core/standalone-model-and-lifetime", model);
	Test.add_func ("/slice/core/standalone-malformed", malformed);
	return Test.run ();
}

}
