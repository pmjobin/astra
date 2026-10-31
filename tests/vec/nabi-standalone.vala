// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.VectorNative {
private NativeAbiProgram sample(NativeAbiVersion version, NativeAbiType type) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("native", "signature"), 0, 9);
	var parameters = new GenericArray<NativeParameter> ();
	foreach (var scalar in new NativeScalarType[] {NativeScalarType.I32, NativeScalarType.B1, NativeScalarType.PTR, NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.U32, NativeScalarType.F32}) {
		parameters.add (new NativeParameter (span, span, "p", parameters.length, scalar));
	}
	parameters.add (new NativeParameter.typed (span, span, "v", parameters.length, type));
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "f", 0, new NativeSignature (version, parameters, new NativeResult.typed (type)), NativeLinkage.NATIVE_INTERNAL));
	return new NativeAbiProgram (span, version, functions);
}

private void channels() {
	try {
		int count = 0;
		foreach (var element in new NativeScalarType[] {NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.F32, NativeScalarType.B1}) {
			foreach (int lanes in new int[] {2, 4, 8, 16}) {
				bool supported = element == NativeScalarType.B1 || element == NativeScalarType.I8 || element == NativeScalarType.U8 || ((element == NativeScalarType.I16 || element == NativeScalarType.U16) ? lanes <= 8 : lanes <= 4);
				var type = new NativeVectorType (element, lanes);
				assert (type.same_type (new NativeVectorType (element, lanes)) && !type.same_type (new NativeScalarAbiType (element)) && !type.same_type (new NativeVectorType (element, lanes + 1)));
				NativeAbiProgram? program = sample (NativeAbiVersion.VECTOR_V4, type);
				bool accepted = true;
				try {
					NativeAbiVerifier.verify (program);
				} catch (NativeAbiError error) {
					accepted = false;
				}
				assert (accepted == supported);
				if (!accepted) {
					continue;
				}
				count++;
				string dump = NativeAbiDump.format (program);
				assert (dump.contains ("vector-v4") && dump.contains ("(parameter #9 " + type.spelling () + ")") && dump.contains ("(result " + type.spelling () + ")"));
				var function = WeakRef (program.functions[0]);
				program = null;
				assert (function.get () == null);
			}
		}
		assert (count == 24);
		assert (!new NativeVectorType (NativeScalarType.I8, 16).same_type (new NativeVectorType (NativeScalarType.U8, 16)));
		foreach (var type in new NativeVectorType[] {new NativeVectorType (NativeScalarType.PTR, 4), new NativeVectorType ((NativeScalarType) 99, 4), new NativeVectorType (NativeScalarType.B1, 0), new NativeVectorType (NativeScalarType.I8, 3), new NativeVectorType (NativeScalarType.I32, 8)}) {
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (sample (NativeAbiVersion.VECTOR_V4, type));
			} catch (NativeAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
		foreach (var version in new NativeAbiVersion[] {NativeAbiVersion.SCALAR_V0, NativeAbiVersion.SCALAR_PTR_V1, NativeAbiVersion.SCALAR_INT_V2, NativeAbiVersion.SCALAR_FP_V3}) {
			var span = SourceSpan (new SourceFile.from_text ("native", "x"), 0, 1);
			var parameters = new GenericArray<NativeParameter> ();
			var functions = new GenericArray<NativeFunction> ();
			functions.add (new NativeFunction (span, span, "f", 0, new NativeSignature (version, parameters, new NativeResult.typed (new NativeVectorType (NativeScalarType.I8, 4))), NativeLinkage.NATIVE_INTERNAL));
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (new NativeAbiProgram (span, version, functions));
			} catch (NativeAbiError error) {
				rejected = error.message.contains ("vector-v4");
			}
			assert (rejected);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec/nabi/standalone-24-shapes-signedness-mixed-profiles", channels);
	return Test.run ();
}
}
