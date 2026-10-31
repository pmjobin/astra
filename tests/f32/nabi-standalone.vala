// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.F32Native {
private NativeAbiProgram sample(NativeAbiVersion version, NativeScalarType result, bool mixed) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("native", "signature"), 0, 9);
	var parameters = new GenericArray<NativeParameter> ();
	NativeScalarType[] channels = mixed ? new NativeScalarType[] {
		NativeScalarType.F32, NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.B1, NativeScalarType.PTR
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
		foreach (var type in new NativeScalarType[] {NativeScalarType.F32, NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.PTR, NativeScalarType.B1}) {
			NativeAbiProgram? program = sample (NativeAbiVersion.SCALAR_FP_V3, type, true);
			var function = WeakRef (program.functions[0]);
			NativeAbiVerifier.verify (program);
			var dump = NativeAbiDump.format (program);
			assert (dump.contains ("scalar-fp-v3") && dump.contains ("(result " + type.spelling ()));
			assert (dump.contains ("(parameter #0 F32)") && dump.contains ("(parameter #1 I8)"));
			program = null;
			assert (function.get () == null);
		}
		NativeAbiVerifier.verify (sample (NativeAbiVersion.SCALAR_V0, NativeScalarType.I32, false));
		NativeAbiVerifier.verify (sample (NativeAbiVersion.SCALAR_PTR_V1, NativeScalarType.PTR, false));
		foreach (var type in new NativeScalarType[] {NativeScalarType.F32, NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.U32}) {
			foreach (var version in new NativeAbiVersion[] {NativeAbiVersion.SCALAR_V0, NativeAbiVersion.SCALAR_PTR_V1, NativeAbiVersion.SCALAR_INT_V2}) {
				if (version == NativeAbiVersion.SCALAR_INT_V2 && type != NativeScalarType.F32) {
					NativeAbiVerifier.verify (sample (version, type, false));
					continue;
				}
				bool rejected = false;
				try {
					NativeAbiVerifier.verify (sample (version, type, false));
				} catch (NativeAbiError error) {
					rejected = error.message.contains (type == NativeScalarType.F32 ? "requires scalar-fp-v3" : "requires scalar-int-v2");
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
	Test.add_func ("/f32/nabi/standalone-channels-profiles-lifetime", channels);
	return Test.run ();
}
}
