// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.ObjectResultNative {
private NativeAbiProgram sample(NativeAbiVersion version, bool wrong_result = false) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("obj-ret", "c"), 0, 1);
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter (span, span, "owner", 0, NativeScalarType.PTR));
	parameters.add (new NativeParameter (span, span, "resource", 1, NativeScalarType.PTR));
	parameters.add (new NativeParameter (span, span, "n", 2, NativeScalarType.I32));
	if (version == NativeAbiVersion.VECTOR_V4 || version == NativeAbiVersion.SLICE_V5) {
		parameters.add (new NativeParameter.typed (span, span, "v", 3, new NativeVectorType (NativeScalarType.I16, 8)));
	}
	if (version == NativeAbiVersion.SLICE_V5) {
		parameters.add (new NativeParameter.typed (span, span, "s", 4, new NativeSliceType ()));
	}
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "f", 0, new NativeSignature (version, parameters, new NativeResult (wrong_result ? NativeScalarType.I32 : NativeScalarType.PTR), null, new NativeOwnedObjectResultPlan ()), NativeLinkage.NATIVE_INTERNAL));
	return new NativeAbiProgram (span, version, functions);
}

private void valid() {
	try {
		foreach (var version in new NativeAbiVersion[] { NativeAbiVersion.SCALAR_PTR_V1, NativeAbiVersion.SCALAR_INT_V2, NativeAbiVersion.SCALAR_FP_V3, NativeAbiVersion.VECTOR_V4, NativeAbiVersion.SLICE_V5 }) {
			NativeAbiProgram? p = sample (version);
			NativeAbiVerifier.verify (p);
			assert (p.functions[0].signature.physical_parameter_count == (version == NativeAbiVersion.SLICE_V5 ? 7 : version == NativeAbiVersion.VECTOR_V4 ? 5 : 4));
			assert (NativeAbiDump.format (p).contains ("(result-storage PTR first caller-provided)"));
			var witness = WeakRef (p.functions[0].signature.parameters[0]);
			p = null;
			assert (witness.get () == null);
		}
	} catch (NativeAbiError e) {
		GLib.error ("%s", e.message);
	}
}

private void wrong_shape() {
	try {
		NativeAbiVerifier.verify (sample (NativeAbiVersion.SCALAR_PTR_V1, true));
	} catch (NativeAbiError e) {
		return;
	}
	GLib.error ("object result plan cannot carry an I32 result");
}

private void invalid() {
	try {
		NativeAbiVerifier.verify (sample (NativeAbiVersion.SCALAR_V0));
	} catch (NativeAbiError e) {
		return;
	}
	GLib.error ("v0 cannot carry PTR parameters");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/nabi/independent-pointer-channels-v1-through-v5", valid);
	Test.add_func ("/obj-ret/nabi/scalar-v0-remains-unchanged", invalid);
	Test.add_func ("/obj-ret/nabi/reject-wrong-result-shape", wrong_shape);
	return Test.run ();
}

}
