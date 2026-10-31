// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.SliceBoundNative {
private NativeAbiProgram sample(int variant = 0) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("slice-bound", "s"), 0, 1);
	var version = variant >= 1 && variant <= 5 ? (NativeAbiVersion) (variant - 1) : NativeAbiVersion.SLICE_V5;
	var group = new NativeSliceType (variant == 6 ? NativeScalarType.I32 : NativeScalarType.PTR, variant == 7 ? NativeScalarType.PTR : variant == 8 ? NativeScalarType.U32 : NativeScalarType.I32);
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter (span, span, "mode", 0, NativeScalarType.I32));
	parameters.add (new NativeParameter.typed (span, span, "s", 1, group));
	parameters.add (new NativeParameter.typed (span, span, "v", 2, new NativeVectorType (NativeScalarType.F32, 4)));
	parameters.add (new NativeParameter.typed (span, span, "t", variant == 10 ? 1 : 3, new NativeSliceType ()));
	parameters.add (new NativeParameter (span, span, "p", 4, NativeScalarType.PTR));
	var result = variant == 9 ? new NativeResult.typed (new NativeSliceType ()) : new NativeResult (NativeScalarType.I32);
	var signature = new NativeSignature (version, parameters, result);
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "f", 0, signature, NativeLinkage.NATIVE_INTERNAL));
	return new NativeAbiProgram (span, version, functions);
}

private void model() {
	try {
		NativeAbiProgram? program = sample ();
		NativeAbiVerifier.verify (program);
		assert (program.functions[0].signature.parameters.length == 5 && program.functions[0].signature.physical_parameter_count == 7);
		string dump = NativeAbiDump.format (program);
		assert (dump.contains ("slice-v5") && dump.contains ("(parameter #1 SLICE(PTR,I32))") && dump.contains ("(parameter #3 SLICE(PTR,I32))"));
		assert (new NativeSliceType ().same_type (new NativeSliceType ()));
		assert (!new NativeSliceType ().same_type (new NativeScalarAbiType (NativeScalarType.PTR)));
		assert (!new NativeSliceType ().same_type (new NativeSliceType (NativeScalarType.I32, NativeScalarType.PTR)));
		var witness = WeakRef (program.functions[0].signature.parameters[1]);
		program = null;
		assert (witness.get () == null);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 10; variant++) {
		try {
			NativeAbiVerifier.verify (sample (variant));
		} catch (NativeAbiError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed native slice group variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice-bound/nabi/independent-groups-and-lifetime", model);
	Test.add_func ("/slice-bound/nabi/old-profiles-components-results-and-ordinals", malformed);
	return Test.run ();
}
}
