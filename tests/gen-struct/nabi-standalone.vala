// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.GenStructNabi {
private void pointer() {
	try {
		var s = SourceSpan (new SourceFile.from_text ("pointer", "p"), 0, 1);
		var parameters = new GenericArray<NativeParameter> ();
		parameters.add (new NativeParameter.typed (s, s, "p", 0, new NativeScalarAbiType (NativeScalarType.PTR)));
		var signature = new NativeSignature (NativeAbiVersion.SCALAR_PTR_V1, parameters, new NativeResult.typed (new NativeScalarAbiType (NativeScalarType.I32)));
		var functions = new GenericArray<NativeFunction> ();
		functions.add (new NativeFunction (s, s, "pointer", 0, signature, NativeLinkage.NATIVE_INTERNAL));
		var program = new NativeAbiProgram (s, NativeAbiVersion.SCALAR_PTR_V1, functions);
		NativeAbiVerifier.verify (program);
		assert (signature.physical_parameter_count == 1 && signature.parameters[0].abi_type is NativeScalarAbiType && ((NativeScalarAbiType) signature.parameters[0].abi_type).scalar_type == NativeScalarType.PTR);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-struct/nabi/ordinary-ptr-one-channel-v1", pointer);
	return Test.run ();
}
}
