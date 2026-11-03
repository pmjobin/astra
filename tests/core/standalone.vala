// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
private CoreProgram sample() {
	var file = new SourceFile.from_text ("standalone.astra", "007");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	assert (types.resolve ("int") == types.int_type && types.resolve ("void") == types.void_type);
	var parameters = new GenericArray<CoreParameter> ();
	var parameter = new CoreParameter (span, span, "x", types.int_type, 0);
	parameters.add (parameter);
	var locals = new GenericArray<CoreLocalPlace> ();
	var local = new CoreLocalPlace (span, span, "y", types.int_type, 0);
	locals.add (local);
	var sum = new CoreBinaryValue (span, types.int_type, BinaryOperator.ADD, new CoreParameterValue (span, parameter), new CoreIntegerValue (span, types.int_type, AstraIntValue.from_int64 (7)));
	var value = new CorePrefixValue (span, types.int_type, PrefixOperator.NEGATIVE, sum);
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreInitialize (span, local, value));
	statements.add (new CoreStore (span, local, new CoreLoadValue (span, local)));
	statements.add (new CoreReturn (span, new CoreLoadValue (span, local)));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", types.int_type, parameters, locals, new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void independent_model() {
	try {
		var program = sample ();
		CoreVerifier.verify (program);
		string dump = CoreDump.format (program);
		assert (dump.contains ("(parameter #0 : int)") && dump.contains ("(integer 7 : int)"));
		assert (dump.contains ("(prefix - : int") && dump.contains ("(binary + : int"));
		assert (dump.contains ("(local-place #0 \"y\" : int)") && dump.contains ("(load : int"));
		assert (dump.contains ("(initialize") && dump.contains ("(store") && dump.contains ("(return"));
	} catch (CoreError error) {
		GLib.error ("Unexpected standalone Core failure: %s", error.message);
	}
}

private void foreign_place() {
	var program = sample ();
	var function = program.functions[0];
	var original = function.locals[0];
	var foreign = new CoreLocalPlace (original.span, original.name_span, original.name, original.semantic_type, original.ordinal);
	function.body.statements[2] = new CoreReturn (function.span, new CoreLoadValue (function.span, foreign));
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		assert (error is CoreError.INVALID_IR);
		assert (error.message == "internal Core verification error at function #0/statement #2/value/source: local place is not owned by the containing function");
		return;
	}
	GLib.error ("Standalone Core accepted a foreign place");
}

int main(string[] args) {
	Test.init (ref args);
	register_owned_tests ();
	register_call_tests ();
	register_struct_tests ();
	register_tptr_tests ();
	register_shortcircuit_tests ();
	register_loop_tests ();
	register_loop_control_tests ();
	Test.add_func ("/core-standalone/conditional-model", conditional_model);
	Test.add_func ("/core-standalone/model", independent_model);
	Test.add_func ("/core-standalone/verifier/foreign-place", foreign_place);
	return Test.run ();
}

}
