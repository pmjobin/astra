// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.F32Core {
private CoreProgram sample(BuiltinTypes types, uint32 bits, SemanticType? wrong = null) {
	var type = types.f32_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "not a decimal"), 0, 13);
	var parameter = new CoreParameter (span, span, "p", type, 0);
	var local = new CoreLocalPlace (span, span, "x", type, 0);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (parameter);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var statements = new GenericArray<CoreStatement> ();
	var constant = new CoreFloatValue (span, wrong ?? type, new AstraF32Value.from_bits (bits));
	statements.add (new CoreInitialize (span, local, constant));
	var comparison = new CoreLocalPlace (span, span, "same", types.bool_type, 1);
	locals.add (comparison);
	statements.add (new CoreInitialize (span, comparison, new CoreBinaryValue (span, types.bool_type, BinaryOperator.NOT_EQUAL, new CoreLoadValue (span, local), constant)));
	statements.add (new CoreStore (span, local, new CoreBinaryValue (span, type, BinaryOperator.ADD, new CoreLoadValue (span, local), new CoreParameterValue (span, parameter))));
	statements.add (new CoreReturn (span, new CoreLoadValue (span, local)));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", type, parameters, locals, new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void constants_places() {
	try {
		var types = new BuiltinTypes ();
		foreach (uint32 bits in new uint32[] {0, 0x80000000U, 1, 0x00800000U, 0x7f7fffffU, 0x7f800000U, 0xffc00001U}) {
			var program = sample (types, bits);
			CoreVerifier.verify (program);
			string dump = CoreDump.format (program);
			assert (dump.contains ("(f32 0x%08x : f32)".printf (bits)) && dump.contains ("binary !="));
		}
		foreach (var wrong in new SemanticType[] {types.i32_type, new BuiltinTypes ().f32_type, new SemanticType (TypeKind.F32)}) {
			bool rejected = false;
			try {
				CoreVerifier.verify (sample (types, 1, wrong));
			} catch (CoreError error) {
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
	Test.add_func ("/f32/core/standalone-constants-places-exactness", constants_places);
	return Test.run ();
}

}
