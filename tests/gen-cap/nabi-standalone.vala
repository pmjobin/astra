// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.GenNabi {
private void concrete() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("instance", "x"), 0, 1);
		var types = new GenericArray<NativeAbiType> ();
		foreach (var scalar in new NativeScalarType[] {NativeScalarType.B1, NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.F32, NativeScalarType.F64, NativeScalarType.PTR}) {
			types.add (new NativeScalarAbiType (scalar));
		}
		foreach (var element in new NativeScalarType[] {NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.F32, NativeScalarType.B1}) {
			types.add (new NativeVectorType (element, 4));
		}
		foreach (var type in types) {
			var parameters = new GenericArray<NativeParameter> ();
			parameters.add (new NativeParameter.typed (span, span, "x", 0, type));
			var signature = new NativeSignature (NativeAbiVersion.FP64_V6, parameters, new NativeResult.typed (type));
			var functions = new GenericArray<NativeFunction> ();
			functions.add (new NativeFunction (span, span, "astra.gen.0.0", 0, signature, NativeLinkage.NATIVE_INTERNAL));
			var program = new NativeAbiProgram (span, NativeAbiVersion.FP64_V6, functions);
			NativeAbiVerifier.verify (program);
			assert (signature.physical_parameter_count == 1 && signature.result.abi_type.same_type (type));
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-cap/nabi/concrete-instance-existing-channel-universe", concrete);
	return Test.run ();
}
}
