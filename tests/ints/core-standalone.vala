// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.IntegersCore {
private CoreProgram sample(IntegerType type, IntegerType? wrong = null) {
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "not a decimal"), 0, 13);
	var parameter = new CoreParameter (span, span, "p", type, 0);
	var local = new CoreLocalPlace (span, span, "x", type, 0);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (parameter);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var statements = new GenericArray<CoreStatement> ();
	var constant = new CoreIntegerValue.typed (span, type, AstraIntegerValue.from_bits (wrong ?? type, 255));
	statements.add (new CoreInitialize (span, local, constant));
	statements.add (new CoreStore (span, local, new CoreBinaryValue (span, type, BinaryOperator.ADD, new CoreLoadValue (span, local), new CoreParameterValue (span, parameter))));
	statements.add (new CoreReturn (span, new CoreLoadValue (span, local)));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", type, parameters, locals, new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void constants_places() {
	try {
		var types = new BuiltinTypes ();
		foreach (var type in new IntegerType[] {types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
			var program = sample (type);
			CoreVerifier.verify (program);
			assert (CoreDump.format (program).contains (" : " + type.display_name ()));
			assert (((CoreIntegerValue) ((CoreInitialize) program.functions[0].body.statements[0]).value).value.bits == 255);
		}
		try {
			CoreVerifier.verify (sample (types.i8_type, types.u8_type));
		} catch (CoreError error) {
			assert (error.message.contains ("integer value must retain its exact semantic type identity"));
			return;
		}
		GLib.error ("Mismatched integer bits/type accepted");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ints/core/standalone-constants-places-exactness", constants_places);
	return Test.run ();
}

}
