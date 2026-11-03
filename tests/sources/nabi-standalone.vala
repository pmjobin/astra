// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.SourcesNabi {
private void verify() {
	try {
		var functions = new GenericArray<NativeFunction> ();
		for (int i = 0; i < 3; i++) {
			var span = SourceSpan (new SourceFile.from_text ("file%d.astra".printf (i), "f"), 0, 1);
			var signature = new NativeSignature (NativeAbiVersion.SCALAR_V0, new GenericArray<NativeParameter> (), new NativeResult (NativeScalarType.I32));
			functions.add (new NativeFunction (span, span, "f%d".printf (i), i, signature, NativeLinkage.NATIVE_INTERNAL));
		}
		var program = new NativeAbiProgram (functions[0].span, NativeAbiVersion.SCALAR_V0, functions);
		NativeAbiVerifier.verify (program);
		assert (!NativeAbiDump.format (program).contains (".astra"));
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/nabi/independent-program-global-physical-plans", verify);
	Test.add_func ("/sources/nabi/immutable-generic-private-provenance", Astra.Tests.NativeProvenance.check);
	return Test.run ();
}

}
