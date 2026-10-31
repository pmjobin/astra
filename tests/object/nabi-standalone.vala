// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.ObjectNabi {
private NativeAbiProgram sample(int shape, int variant = 0) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("method", "f"), 0, 1);
	var version = shape == 2 ? NativeAbiVersion.VECTOR_V4 : shape == 3 ? NativeAbiVersion.SLICE_V5 : NativeAbiVersion.SCALAR_PTR_V1;
	if (variant == 1) {
		version = NativeAbiVersion.SCALAR_V0;
	}
	var parameters = new GenericArray<NativeParameter> ();
	if (shape != 0) {
		NativeAbiType channel = shape == 2 ? (NativeAbiType) new NativeVectorType (NativeScalarType.I16, 8) : shape == 3 ? (NativeAbiType) new NativeSliceType () : new NativeScalarAbiType (shape == 4 ? NativeScalarType.PTR : NativeScalarType.I32);
		parameters.add (new NativeParameter.typed (span, span, "n", 0, channel));
	}
	var receiver = variant == 2 ? null : new NativeScalarAbiType (variant == 3 ? NativeScalarType.I32 : NativeScalarType.PTR);
	var signature = new NativeSignature (version, parameters, new NativeResult (NativeScalarType.I32), receiver);
	var method = new NativeFunction (span, span, "f", 0, signature, NativeLinkage.NATIVE_INTERNAL, variant == 4 ? -1 : 0, 0, true);
	var functions = new GenericArray<NativeFunction> ();
	functions.add (method);
	if (variant == 5) {
		functions.add (new NativeFunction (span, span, "f", 1, signature, NativeLinkage.NATIVE_INTERNAL, 0, 0, true));
	}
	return new NativeAbiProgram (span, version, functions);
}
private void channels() {
	try {
		for (int shape = 0; shape < 5; shape++) {
			NativeAbiProgram? p = sample (shape);
			NativeAbiVerifier.verify (p);
			assert (p.functions[0].signature.physical_parameter_count == (shape == 0 ? 1 : shape == 3 ? 3 : 2));
			assert (NativeAbiDump.format (p).contains ("(receiver PTR (class #0) (method #0) first)"));
			var witness = WeakRef (p.functions[0]);
			p = null;
			assert (witness.get () == null);
		}
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}
private void malformed() {
	for (int variant = 1; variant <= 5; variant++) {
		try {
			NativeAbiVerifier.verify (sample (0, variant));
		} catch (NativeAbiError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed method ABI %d", variant);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/object/nabi/existing-receiver-scalar-vector-slice-resource-channels", channels);
	Test.add_func ("/object/nabi/malformed-receiver-profile-and-identity", malformed);
	return Test.run ();
}
}
