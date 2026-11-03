// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.CAbi;

namespace Astra.Tests.SourcesCabi {
private void verify() {
	try {
		var functions = new GenericArray<CAbiFunction> ();
		for (int i = 0; i < 3; i++) {
			var span = SourceSpan (new SourceFile.from_text ("file%d.astra".printf (i), "f"), 0, 1);
			var signature = new CAbiSignature (CAbiProfile.SCALAR_V0, new GenericArray<CAbiParameter> (), new CAbiResult (CAbiScalarType.I32));
			functions.add (new CAbiFunction (span, span, "f%d".printf (i), i, signature, new CForeignMetadata ("foreign%d".printf (i))));
		}
		var program = new CAbiProgram (functions[0].span, CAbiProfile.SCALAR_V0, functions);
		CAbiVerifier.verify (program);
		assert (!CAbiDump.format (program).contains (".astra"));
	} catch (CAbiError error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/cabi/independent-program-global-foreign-plans", verify);
	return Test.run ();
}

}
