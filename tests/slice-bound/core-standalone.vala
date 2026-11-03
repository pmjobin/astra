// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.SliceBoundCore {
private CoreProgram sample(bool vector, int variant = 0) throws CoreError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("slice-bound", "s"), 0, 1);
	SemanticType element = vector ? (SemanticType) t.vector_of (t.i16_type, 8) : t.int_type;
	var type = t.slice_of (element);
	if (variant == 3) {
		type = new SliceType (t.bool_type);
	}
	var contract = variant == 1 ? PointerParameterContract.UNMANAGED : variant == 2 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	var parameters = new GenericArray<CoreParameter> ();
	var slice = new CoreParameter (span, span, "s", type, 0, contract);
	var value = new CoreParameter (span, span, "value", element, 1);
	var index = new CoreParameter (span, span, "i", t.int_type, 2);
	parameters.add (slice);
	parameters.add (value);
	parameters.add (index);
	var foreign = new CoreParameter (span, span, "s", type, 0, PointerParameterContract.BORROWED_NOESCAPE);
	var provenance = new DataPointerProvenance (variant == 4 ? DataPointerOrigin.NULL : DataPointerOrigin.PARAMETER, 0, variant == 5 ? 1 : 0);
	if (variant == 9) {
		parameters[2] = value;
	}
	var view = new CoreParameterValue (span, variant == 8 ? foreign : slice);
	var place = new CoreSliceElementPlace (span, view, variant == 7 ? t.slice_of (t.f32_type) : type, new CoreParameterValue (span, index), provenance);
	var locals = new GenericArray<CoreLocalPlace> ();
	var local = new CoreLocalPlace (span, span, "copy", type, 0);
	locals.add (local);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreInitialize (span, local, view));
	body.statements.add (new CoreStore (span, place, new CoreParameterValue (span, value)));
	body.statements.add (new CoreStore (span, place, new CoreLoadValue (span, place)));
	body.statements.add (new CoreReturn (span, new CoreSliceLengthValue (span, t.int_type, new CoreLoadValue (span, local))));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", variant == 6 ? (SemanticType) type : t.int_type, parameters, locals, body));
	return new CoreProgram (span, functions);
}

private void model() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CoreProgram? program = sample (vector);
			CoreVerifier.verify (program);
			assert (program.functions[0].parameters.length == 3 && program.functions[0].parameters[0].semantic_type is SliceType);
			assert (program.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
			string dump = CoreDump.format (program);
			assert (dump.contains ("borrowed-noescape") && dump.contains ("slice-length") && dump.contains ("slice-element-place"));
			var witness = WeakRef (program.functions[0].parameters[0]);
			program = null;
			assert (witness.get () == null);
		}
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 9; variant++) {
		try {
			CoreVerifier.verify (sample (false, variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed slice parameter variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice-bound/core/independent-parameters-places-and-lifetime", model);
	Test.add_func ("/slice-bound/core/malformed-contracts-types-and-provenance", malformed);
	return Test.run ();
}

}
