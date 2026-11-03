// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.CAbi;
namespace Astra.Tests.CAbiFpStandalone {
private CAbiProgram sample(CAbiProfile profile, CAbiScalarType scalar, int shape, bool exported, int bad = 0) throws CAbiError {
	var span = SourceSpan (new SourceFile.from_text ("physical", "echo"), 0, 4);
	var parameters = new GenericArray<CAbiParameter> ();
	if (shape != 1) {
		foreach (var type in new CAbiScalarType[] {CAbiScalarType.I32, CAbiScalarType.F32, CAbiScalarType.F64, CAbiScalarType.PTR, scalar}) {
			parameters.add (new CAbiParameter (span, span, "x", parameters.length, type, bad == 1 ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED));
		}
	}
	var signature = new CAbiSignature (bad == 2 ? CAbiProfile.SCALAR_V0 : profile, parameters, shape == 2 ? null : new CAbiResult (scalar));
	var imports = new GenericArray<CAbiFunction> ();
	var exports = new GenericArray<CAbiExport> ();
	if (exported) {
		exports.add (new CAbiExport (span, span, "echo", 0, signature, 0));
	} else {
		imports.add (new CAbiFunction (span, span, "echo", 0, signature, new CForeignMetadata ("echo")));
	}
	return new CAbiProgram (span, profile, imports, exports);
}

private void channels() {
	try {
		foreach (var scalar in new CAbiScalarType[] {CAbiScalarType.F32, CAbiScalarType.F64}) {
			for (int e = 0; e < 2; e++) {
				for (int shape = 0; shape < 3; shape++) {
					CAbiProgram? program = sample (CAbiProfile.SCALAR_FP_V2, scalar, shape, e == 1);
					string dump = CAbiDump.format (program);
					assert (dump.contains ("scalar-fp-v2") && dump.contains ("c-type " + (scalar == CAbiScalarType.F32 ? "float" : "double")));
					assert (dump == CAbiDump.format (program));
					var reference = WeakRef (program);
					program = null;
					assert (reference.get () == null);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	foreach (var scalar in new CAbiScalarType[] {CAbiScalarType.F32, CAbiScalarType.F64}) {
		foreach (var profile in new CAbiProfile[] {CAbiProfile.SCALAR_V0, CAbiProfile.SCALAR_PTR_V1}) {
			for (int e = 0; e < 2; e++) {
				for (int shape = 0; shape < 2; shape++) {
					bool rejected = false;
					try {
						CAbiVerifier.verify (sample (profile, scalar, shape, e == 1));
					} catch (CAbiError error) {
						rejected = error.message.contains ("requires scalar-fp-v2");
					}
					assert (rejected);
				}
			}
		}
		for (int bad = 1; bad <= 2; bad++) {
			bool rejected = false;
			try {
				CAbiVerifier.verify (sample (CAbiProfile.SCALAR_FP_V2, scalar, 0, false, bad));
			} catch (CAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/cabi-fp/standalone/import-export-channels-void-zero-multiple-mixed-lifetime", channels);
	Test.add_func ("/cabi-fp/standalone/frozen-profiles-and-malformed-contracts", malformed);
	return Test.run ();
}

}
