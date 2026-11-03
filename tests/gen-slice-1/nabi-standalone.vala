// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.GenericSliceNative {
private NativeAbiProgram sample(int variant = 0) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("independent-slice-plan", "x"), 0, 1);
	var fields = new GenericArray<NativeRecordField> ();
	fields.add (new NativeRecordField (0, "x", new NativeScalarAbiType (NativeScalarType.I32)));
	fields.add (new NativeRecordField (variant == 1 ? 0 : 1, "y", new NativeScalarAbiType (NativeScalarType.F64)));
	var record = new NativeRecordElement (0, "Record", fields);
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter.typed (span, span, "values", 0, new NativeRecordSliceType (record, NativeSliceAccess.READ_WRITE, variant != 2)));
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "fill", 0, new NativeSignature (NativeAbiVersion.STRUCT_ELEMENTS_V11, parameters, null), NativeLinkage.NATIVE_INTERNAL));
	var program = new NativeAbiProgram (span, NativeAbiVersion.STRUCT_ELEMENTS_V11, functions);
	if (variant != 3) {
		program.record_elements.add (record);
	}
	return program;
}

private void qualify() {
	try {
		NativeAbiProgram? program = sample ();
		NativeAbiVerifier.verify (program);
		var element = program.record_elements[0];
		var layout = NativeRecordLayout.x86_64 (element);
		var graph = WeakRef (program);
		program = null;
		assert (graph.get () == null);
		layout.verify_x86_64 ();
		assert (layout.stride == 16 && layout.fields[1].offset == 8);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant < 4; variant++) {
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (sample (variant));
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-slice/nabi/independent-exact-element-shape-and-borrow-plans", qualify);
	return Test.run ();
}

}
