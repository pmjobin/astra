// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenCore {
private void model() {
	try {
		var program = sample (2);
		CoreVerifier.verify (program);
		assert (program.generic_functions[0].return_type != program.generic_functions[1].return_type);
		assert (CoreDump.format (program).contains ("generic-call"));
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		var a = program.generic_functions[0];
		var b = program.generic_functions[1];
		a.body.statements.remove_index (1);
		a.body.statements.add (new CoreReturn (a.span, new CoreParameterValue (a.span, b.parameters[0])));
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		var invalid = sample ();
		var definition = invalid.generic_functions[0];
		definition.body.statements.remove_index (1);
		definition.body.statements.add (new CoreReturn (definition.span, new CoreBinaryValue (definition.span, definition.return_type, BinaryOperator.ADD, new CoreLoadValue (definition.span, definition.locals[0]), new CoreLoadValue (definition.span, definition.locals[0]))));
		rejected = false;
		try {
			CoreGenericMonomorphizer.build (invalid);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen/core/parameterized-model-exact-scope-firewall", model);
	return Test.run ();
}
}
