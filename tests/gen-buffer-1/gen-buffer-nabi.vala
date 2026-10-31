// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.GenericBufferNative {
private NativeAbiProgram sample(int variant = 0) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("independent-owned-buffer-plan", "x"), 0, 1);
	var fields = new GenericArray<NativeRecordField> ();
	fields.add (new NativeRecordField (0, "x", new NativeScalarAbiType (NativeScalarType.I32)));
	fields.add (new NativeRecordField (1, "y", new NativeScalarAbiType (NativeScalarType.F64)));
	var element = new NativeRecordElement (0, "Element", fields);
	var plan = new NativeBufferValuePlan.for_record (element);
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter.typed (span, span, "base", 0, new NativeScalarAbiType (variant == 1 ? NativeScalarType.I32 : NativeScalarType.PTR)));
	parameters.add (new NativeParameter.typed (span, span, "count", 1, new NativeScalarAbiType (NativeScalarType.I32)));
	var signature = new NativeSignature (NativeAbiVersion.STRUCT_ELEMENTS_V11, parameters, null);
	signature.buffer_result = plan;
	signature.buffer_parameters.add (new NativeBufferParameterPlan (0, variant == 2 ? 1 : 0, plan));
	signature.bind_buffer_transport ();
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "relay", 0, signature, NativeLinkage.NATIVE_INTERNAL));
	var program = new NativeAbiProgram (span, NativeAbiVersion.STRUCT_ELEMENTS_V11, functions);
	if (variant != 3) {
		program.record_elements.add (element);
	}
	return program;
}
private void qualify() {
	try {
		NativeAbiProgram? program = sample ();
		NativeAbiVerifier.verify (program);
		var layout = NativeRecordLayout.x86_64 (program.record_elements[0]);
		var before = WeakRef (program);
		program = null;
		assert (before.get () == null);
		layout.verify_x86_64 ();
		assert (layout.stride == 16 && layout.alignment == 8);
		for (int variant = 1; variant < 4; variant++) {
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (sample (variant));
			} catch (NativeAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}
public int run_nabi(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-buffer/nabi/independent-owned-group-layout-and-lifetimes", qualify);
	return Test.run ();
}
}
