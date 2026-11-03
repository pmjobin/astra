// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.F64Core {
private CoreProgram sample(BuiltinTypes types, uint64 bits, SemanticType? wrong = null, bool wrong_format = false) {
	var type = types.f64_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "not a decimal"), 0, 13);
	var parameter = new CoreParameter (span, span, "p", type, 0);
	var local = new CoreLocalPlace (span, span, "x", type, 0);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (parameter);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var statements = new GenericArray<CoreStatement> ();
	var constant = new CoreFloatValue (span, wrong ?? type, new BinaryFloatValue.from_bits (wrong_format ? BinaryFloatFormat.BINARY32 : BinaryFloatFormat.BINARY64, bits));
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
		foreach (uint64 bits in new uint64[] {0, 0x8000000000000000UL, 1, 0x0010000000000000UL, 0x7fefffffffffffffUL, 0x7ff0000000000000UL, 0xfff8000000000001UL}) {
			var program = sample (types, bits);
			CoreVerifier.verify (program);
			string dump = CoreDump.format (program);
			assert (dump.contains ("(f64 %s : f64)".printf (new BinaryFloatValue.from_bits (BinaryFloatFormat.BINARY64, bits).to_string ())) && dump.contains ("binary !="));
		}
		bool bad_format = false;
		try {
			CoreVerifier.verify (sample (types, 1, null, true));
		} catch (CoreError error) {
			bad_format = error.message.contains ("matching binary format");
		}
		assert (bad_format);
		foreach (var wrong in new SemanticType[] {types.i32_type, new BuiltinTypes ().f64_type, new SemanticType (TypeKind.F64)}) {
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

private CoreProgram conversion(int variant) throws CoreError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("conversion", "no source parsing"), 0, 17);
	SemanticType source = variant == 2 ? (SemanticType) types.int_type : types.f32_type;
	SemanticType destination = variant == 3 ? (SemanticType) types.f32_type : types.f64_type;
	var kind = variant == 1 ? FloatConversionKind.FLOAT_NARROW : FloatConversionKind.FLOAT_WIDEN;
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (span, span, "x", source, 0));
	var value = new CoreFloatConversionValue (span, source, destination, kind, new CoreParameterValue (span, parameters[0]));
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreReturn (span, value));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "convert", destination, parameters, new GenericArray<CoreLocalPlace> (), new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void conversions() {
	try {
		var program = conversion (0);
		CoreVerifier.verify (program);
		assert (CoreDump.format (program).contains ("float-convert (from f32) (to f64) (mode widen-exact)"));
		for (int variant = 1; variant <= 3; variant++) {
			bool rejected = false;
			try {
				CoreVerifier.verify (conversion (variant));
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
	Test.add_func ("/f64/core/standalone-constants-places-exactness", constants_places);
	Test.add_func ("/f64/core/explicit-conversion-verifier", conversions);
	return Test.run ();
}

}
