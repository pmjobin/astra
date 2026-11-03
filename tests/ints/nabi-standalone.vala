// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.IntegersNative {
private NativeAbiProgram sample(NativeAbiVersion version, NativeScalarType result, bool mixed) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("native", "signature"), 0, 9);
	var parameters = new GenericArray<NativeParameter> ();
	NativeScalarType[] channels = mixed ? new NativeScalarType[] {
		NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.B1, NativeScalarType.PTR
	} : new NativeScalarType[] {
		result
	};
	foreach (var channel in channels) {
		parameters.add (new NativeParameter (span, span, "p", parameters.length, channel));
	}
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "f", 0, new NativeSignature (version, parameters, new NativeResult (result)), NativeLinkage.NATIVE_INTERNAL));
	return new NativeAbiProgram (span, version, functions);
}

private void channels() {
	try {
		foreach (var type in new NativeScalarType[] {NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.PTR, NativeScalarType.B1}) {
			NativeAbiProgram? program = sample (NativeAbiVersion.SCALAR_INT_V2, type, true);
			var function = WeakRef (program.functions[0]);
			NativeAbiVerifier.verify (program);
			var dump = NativeAbiDump.format (program);
			assert (dump.contains ("scalar-int-v2") && dump.contains ("(result " + type.spelling ()));
			assert (dump.contains ("(parameter #0 I8)") && dump.contains ("(parameter #1 U8)"));
			program = null;
			assert (function.get () == null);
		}
		NativeAbiVerifier.verify (sample (NativeAbiVersion.SCALAR_V0, NativeScalarType.I32, false));
		NativeAbiVerifier.verify (sample (NativeAbiVersion.SCALAR_PTR_V1, NativeScalarType.PTR, false));
		foreach (var type in new NativeScalarType[] {NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.U32}) {
			foreach (var version in new NativeAbiVersion[] {NativeAbiVersion.SCALAR_V0, NativeAbiVersion.SCALAR_PTR_V1}) {
				bool rejected = false;
				try {
					NativeAbiVerifier.verify (sample (version, type, false));
				} catch (NativeAbiError error) {
					rejected = error.message.contains ("requires scalar-int-v2");
				}
				assert (rejected);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ints/nabi/standalone-channels-profiles-lifetime", channels);
	Test.add_func ("/ints/nabi/immutable-generic-private-provenance", Astra.Tests.NativeProvenance.check);
	return Test.run ();
}

}
