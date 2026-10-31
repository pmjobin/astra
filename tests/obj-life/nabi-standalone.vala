// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.LifecycleNabi {
private NativeAbiProgram sample(int shape = 0, int variant = 0) throws NativeAbiError {
	var s = SourceSpan (new SourceFile.from_text ("lifecycle", "C"), 0, 1);
	var version = shape == 2 ? NativeAbiVersion.VECTOR_V4 : shape == 3 ? NativeAbiVersion.SLICE_V5 : NativeAbiVersion.SCALAR_PTR_V1;
	if (variant == 1) {
		version = NativeAbiVersion.SCALAR_V0;
	}
	var parameters = new GenericArray<NativeParameter> ();
	if (shape != 0) {
		NativeAbiType channel = shape == 2 ? (NativeAbiType) new NativeVectorType (NativeScalarType.I16, 8) : shape == 3 ? (NativeAbiType) new NativeSliceType () : new NativeScalarAbiType (shape == 4 ? NativeScalarType.PTR : NativeScalarType.I32);
		parameters.add (new NativeParameter.typed (s, s, "value", 0, channel));
	}
	var receiver = variant == 2 ? null : new NativeScalarAbiType (variant == 3 ? NativeScalarType.I32 : NativeScalarType.PTR);
	var signature = new NativeSignature (version, parameters, variant == 4 ? new NativeResult (NativeScalarType.PTR) : null, receiver);
	var constructor = new NativeFunction (s, s, "init", 0, signature, NativeLinkage.NATIVE_INTERNAL, 0, -1, true, NativeCallableKind.CONSTRUCTOR);
	var dsig = new NativeSignature (version, variant == 5 ? parameters : new GenericArray<NativeParameter> (), null, new NativeScalarAbiType (NativeScalarType.PTR));
	var destructor = new NativeFunction (s, s, "deinit", 1, dsig, NativeLinkage.NATIVE_INTERNAL, variant == 6 ? -1 : 0, -1, true, NativeCallableKind.DESTRUCTOR);
	var functions = new GenericArray<NativeFunction> ();
	functions.add (constructor);
	functions.add (destructor);
	if (variant == 7) {
		functions.add (new NativeFunction (s, s, "init", 2, signature, NativeLinkage.NATIVE_INTERNAL, 0, -1, true, NativeCallableKind.CONSTRUCTOR));
	}
	return new NativeAbiProgram (s, version, functions);
}
private void channels() {
	try {
		for (int shape = 0; shape < 5; shape++) {
			NativeAbiProgram? p = sample (shape);
			NativeAbiVerifier.verify (p);
			assert (p.functions[0].signature.result == null && p.functions[1].signature.result == null);
			assert (p.functions[0].signature.physical_parameter_count == (shape == 0 ? 1 : shape == 3 ? 3 : 2));
			assert (p.functions[1].signature.physical_parameter_count == 1);
			assert (NativeAbiDump.format (p).contains ("constructor initializing") && NativeAbiDump.format (p).contains ("destructor live"));
			var witness = WeakRef (p.functions[0]);
			p = null;
			assert (witness.get () == null);
		}
	} catch (NativeAbiError e) {
		GLib.error ("%s", e.message);
	}
}
private void invalid() {
	for (int i = 1; i <= 7; i++) {
		try {
			NativeAbiVerifier.verify (sample (1, i));
		} catch (NativeAbiError e) {
			Test.message ("variant %d: %s", i, e.message);
			continue;
		}
		GLib.error ("accepted malformed lifecycle NABI %d", i);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/nabi/void-receiver-scalar-vector-slice-resource", channels);
	Test.add_func ("/obj-life/nabi/reject-wrong-receiver-result-profile-and-identity", invalid);
	return Test.run ();
}
}
