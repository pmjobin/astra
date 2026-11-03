// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.GenOwnNabi {
private void differential() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("nabi", "r"), 0, 1);
		var functions = new GenericArray<NativeFunction> ();
		for (int i = 0; i < 2; i++) {
			var parameters = new GenericArray<NativeParameter> ();
			parameters.add (new NativeParameter (span, span, "owner", 0, NativeScalarType.PTR));
			var signature = new NativeSignature (NativeAbiVersion.SCALAR_PTR_V1, parameters, new NativeResult (NativeScalarType.PTR), null, i == 0 ? null : new NativeOwnedObjectResultPlan ());
			assert (signature.physical_parameter_count == i + 1);
			functions.add (new NativeFunction (span, span, i == 0 ? "resource" : "object", i, signature, NativeLinkage.NATIVE_INTERNAL));
		}
		var p = new NativeAbiProgram (span, NativeAbiVersion.SCALAR_PTR_V1, functions);
		NativeAbiVerifier.verify (p);
		assert (NativeAbiDump.format (p).contains ("(result-storage PTR first caller-provided)"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/nabi/existing-resource-class-different-physical-signatures", differential);
	return Test.run ();
}

}
