// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.F64Native {
private NativeAbiProgram sample(NativeAbiVersion version, int variant = 0) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("native", "no semantic objects"), 0, 19);
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter (span, span, "double", 0, NativeScalarType.F64));
	foreach (var channel in new NativeScalarType[] {NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.F32, NativeScalarType.B1, NativeScalarType.PTR, NativeScalarType.F64}) {
		parameters.add (new NativeParameter (span, span, "scalar", parameters.length, channel));
	}
	parameters.add (new NativeParameter.typed (span, span, "vector", parameters.length, new NativeVectorType (variant == 1 || variant == 3 ? NativeScalarType.F64 : NativeScalarType.F32, variant == 3 ? 2 : 4)));
	parameters.add (new NativeParameter.typed (span, span, "slice", parameters.length, new NativeSliceType ()));
	var signature = new NativeSignature (version, parameters, new NativeResult (variant == 2 ? NativeScalarType.PTR : NativeScalarType.F64), null, variant == 2 ? new NativeOwnedObjectResultPlan () : null);
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "f", 0, signature, NativeLinkage.NATIVE_INTERNAL));
	return new NativeAbiProgram (span, version, functions);
}

private void profiles() {
	try {
		foreach (int variant in new int[] {0, 2, 3}) {
			var program = sample (NativeAbiVersion.FP64_V6, variant);
			NativeAbiVerifier.verify (program);
			string dump = NativeAbiDump.format (program);
			assert (dump.contains ("fp64-v6") && dump.contains ("F64") && dump.contains (variant == 3 ? "VECTOR(F64,2)" : "VECTOR(F32,4)") && dump.contains ("SLICE(PTR,I32)"));
		}
		foreach (var version in new NativeAbiVersion[] {NativeAbiVersion.SCALAR_V0, NativeAbiVersion.SCALAR_PTR_V1, NativeAbiVersion.SCALAR_INT_V2, NativeAbiVersion.SCALAR_FP_V3, NativeAbiVersion.VECTOR_V4, NativeAbiVersion.SLICE_V5}) {
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (sample (version));
			} catch (NativeAbiError error) {
				rejected = error.message.contains ("F64 channel requires fp64-v6");
			}
			assert (rejected);
		}
		bool rejected_vector = false;
		try {
			NativeAbiVerifier.verify (sample (NativeAbiVersion.FP64_V6, 1));
		} catch (NativeAbiError error) {
			rejected_vector = error.message.contains ("numeric vector payload");
		}
		assert (rejected_vector);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f64/nabi/v6-all-channels-old-profile-rejection", profiles);
	return Test.run ();
}
}
