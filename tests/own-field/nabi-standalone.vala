// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.OwnedFieldNabi {
private void unchanged() {
	try {
		var s = SourceSpan (new SourceFile.from_text ("owned-field-nabi", "C"), 0, 1);
		var parameters = new GenericArray<NativeParameter> ();
		parameters.add (new NativeParameter (s, s, "resource", 0, NativeScalarType.PTR));
		var signature = new NativeSignature (NativeAbiVersion.SCALAR_PTR_V1, parameters, null, new NativeScalarAbiType (NativeScalarType.PTR));
		var constructor = new NativeFunction (s, s, "init", 0, signature, NativeLinkage.NATIVE_INTERNAL, 0, -1, true, NativeCallableKind.CONSTRUCTOR);
		var dsig = new NativeSignature (NativeAbiVersion.SCALAR_PTR_V1, new GenericArray<NativeParameter> (), null, new NativeScalarAbiType (NativeScalarType.PTR));
		var destructor = new NativeFunction (s, s, "deinit", 1, dsig, NativeLinkage.NATIVE_INTERNAL, 0, -1, true, NativeCallableKind.DESTRUCTOR);
		var functions = new GenericArray<NativeFunction> ();
		functions.add (constructor);
		functions.add (destructor);
		var program = new NativeAbiProgram (s, NativeAbiVersion.SCALAR_PTR_V1, functions);
		NativeAbiVerifier.verify (program);
		assert (signature.physical_parameter_count == 2 && dsig.physical_parameter_count == 1 && !NativeAbiDump.format (program).contains ("owned-field"));
	} catch (NativeAbiError e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/nabi/existing-pointer-channels-only", unchanged);
	return Test.run ();
}
}
