// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.PropNative {
private NativeAbiProgram sample(int shape = 0, int variant = 0) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("prop", "p"), 0, 1);
	var scalar = shape == 1 ? NativeScalarType.B1 : shape == 2 ? NativeScalarType.F32 : shape == 3 ? NativeScalarType.F64 : NativeScalarType.I32;
	NativeAbiType type = shape == 4 ? (NativeAbiType) new NativeVectorType (NativeScalarType.I16, 8) : new NativeScalarAbiType (scalar);
	var version = variant == 7 ? NativeAbiVersion.SCALAR_PTR_V1 : shape == 3 ? NativeAbiVersion.FP64_V6 : shape == 4 ? NativeAbiVersion.VECTOR_V4 : shape == 2 ? NativeAbiVersion.SCALAR_FP_V3 : NativeAbiVersion.SCALAR_PTR_V1;
	var receiver = new NativeScalarAbiType (variant == 1 ? NativeScalarType.I32 : NativeScalarType.PTR);
	var get_parameters = new GenericArray<NativeParameter> ();
	var set_parameters = new GenericArray<NativeParameter> ();
	set_parameters.add (new NativeParameter.typed (span, span, "next", 0, variant == 2 ? (NativeAbiType) new NativeScalarAbiType (NativeScalarType.PTR) : type));
	if (variant == 3) {
		get_parameters.add (set_parameters[0]);
	}
	var functions = new GenericArray<NativeFunction> ();
	var get_signature = new NativeSignature (version, get_parameters, new NativeResult.typed (type), receiver);
	var getter = new NativeFunction (span, span, "get", 0, get_signature, NativeLinkage.NATIVE_INTERNAL, 0, -1, false, NativeCallableKind.PROPERTY_GETTER, 0);
	functions.add (getter);
	var set_signature = new NativeSignature (version, set_parameters, variant == 4 ? new NativeResult.typed (type) : null, receiver);
	functions.add (new NativeFunction (span, span, "set", 1, set_signature, NativeLinkage.NATIVE_INTERNAL, 0, -1, variant == 5, NativeCallableKind.PROPERTY_SETTER, variant == 6 ? 1 : 0));
	return new NativeAbiProgram (span, version, functions);
}
private void profiles() {
	try {
		for (int shape = 0; shape < 5; shape++) {
			var program = sample (shape);
			NativeAbiVerifier.verify (program);
			assert (program.functions[0].signature.physical_parameter_count == 1 && program.functions[1].signature.physical_parameter_count == 2);
			assert (NativeAbiDump.format (program).contains ("(property #0) (getter)"));
			if (shape == 3) {
				assert (program.abi_version == NativeAbiVersion.FP64_V6 && program.functions[0].signature.result.scalar_type == NativeScalarType.F64);
			}
		}
		for (int variant = 1; variant <= 7; variant++) {
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (sample (3, variant));
			} catch (NativeAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/prop/nabi/existing-channels-property-identity-and-malformed-signatures", profiles);
	return Test.run ();
}
}
