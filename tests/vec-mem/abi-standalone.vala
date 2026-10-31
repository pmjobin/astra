// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.VectorMemoryAbi {
private void mapping() {
	try {
		var t = new BuiltinTypes ();
		var pointees = new GenericArray<SemanticType> ();
		foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
			for (int lanes = 2; lanes <= 16; lanes *= 2) {
				var vector = t.vector_of (t.resolve (name), lanes);
				if (vector != null) {
					pointees.add (vector);
				}
			}
		}
		foreach (var pointee in pointees) {
			var type = t.pointer_to (pointee);
			assert (NativeTypeMapper.map_scalar (type) == NativeScalarType.PTR);
			assert (((NativeScalarAbiType) NativeTypeMapper.map_type (type)).scalar_type == NativeScalarType.PTR);
			bool rejected = false;
			try {
				CAbiTypeMapper.map_scalar (type);
			} catch (CAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
		assert (t.pointer_to (t.int_type) == t.pointer_to (t.resolve ("i32")));
		assert (NativeTypeMapper.map_scalar (t.raw_pointer_type) == NativeScalarType.PTR);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void profiles() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("native-vecmem", "pointer"), 0, 7);
		foreach (var profile in new NativeAbiVersion[] {NativeAbiVersion.SCALAR_PTR_V1, NativeAbiVersion.SCALAR_INT_V2, NativeAbiVersion.SCALAR_FP_V3, NativeAbiVersion.VECTOR_V4}) {
			var parameters = new GenericArray<NativeParameter> ();
			parameters.add (new NativeParameter (span, span, "p", 0, NativeScalarType.PTR));
			var functions = new GenericArray<NativeFunction> ();
			functions.add (new NativeFunction (span, span, "f", 0, new NativeSignature (profile, parameters, new NativeResult (NativeScalarType.I32)), NativeLinkage.NATIVE_INTERNAL));
			NativeAbiProgram? program = new NativeAbiProgram (span, profile, functions);
			NativeAbiVerifier.verify (program);
			assert (NativeAbiDump.format (program).contains ("(parameter #0 PTR)"));
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vecmem/abi/standalone-exact-types-to-existing-ptr", mapping);
	Test.add_func ("/vecmem/abi/standalone-existing-profiles", profiles);
	return Test.run ();
}
}
