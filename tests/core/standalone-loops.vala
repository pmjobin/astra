// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
private CoreProgram loop_model(int invalid = 0) {
	var span = SourceSpan (new SourceFile.from_text ("structured-loop.astra", ""), 0, 0);
	var types = new BuiltinTypes ();
	var locals = new GenericArray<CoreLocalPlace> ();
	var outer = new CoreLocalPlace (span, span, "outer", types.int_type, 0);
	var inner = new CoreLocalPlace (span, span, "inner", types.int_type, 1);
	locals.add (outer);
	locals.add (inner);
	var zero = new CoreIntegerValue (span, types.int_type, AstraIntValue.from_int64 (0));
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreInitialize (span, inner, new CoreLoadValue (span, outer)));
	var target = invalid == 2 ? new CoreLocalPlace (span, span, "foreign", types.int_type, 0) : outer;
	body.statements.add (new CoreStore (span, target, new CoreLoadValue (span, inner)));
	var condition = new CoreBinaryValue (span, types.bool_type, BinaryOperator.LESS, new CoreLoadValue (span, invalid == 4 ? inner : outer), zero);
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreInitialize (span, outer, zero));
	statements.add (new CoreWhile (span, new CoreLoopTarget (span, 0), invalid == 1 ? (CoreValue) zero : condition, body));
	if (invalid == 5) {
		statements.add (new CoreWhile (span, new CoreLoopTarget (span, 1), condition, body));
	}
	statements.add (new CoreReturn (span, new CoreLoadValue (span, invalid == 3 ? inner : outer)));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "loop", types.int_type, new GenericArray<CoreParameter> (), locals, new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void structured_loop() {
	try {
		CoreProgram? program = loop_model ();
		var loop_ref = WeakRef (program.functions[0].body.statements[1]);
		var body_ref = WeakRef (((CoreWhile) program.functions[0].body.statements[1]).body);
		var place_ref = WeakRef (program.functions[0].locals[1]);
		CoreVerifier.verify (program);
		string dump = CoreDump.format (program);
		assert (dump.contains ("(while") && dump.contains ("(initialize") && !dump.contains ("branch") && !dump.contains ("block #"));
		program = null;
		assert (loop_ref.get () == null && body_ref.get () == null && place_ref.get () == null);
	} catch (CoreError error) {
		GLib.error ("Structured loop failed: %s", error.message);
	}
}

private void invalid_structured_loops() {
	string[] errors = {
		"while condition must have type 'bool'", "not owned by the containing function", "used before initialization", "used before initialization", "block identity occurs more than once"
	};
	for (int invalid = 1; invalid <= 5; invalid++) {
		var program = loop_model (invalid);
		try {
			CoreDump.format (program);
			GLib.error ("Invalid Core loop %d accepted", invalid);
		} catch (CoreError error) {
			assert (error.message.contains (errors[invalid - 1]));
		}
	}
}

private void register_loop_tests() {
	Test.add_func ("/core-standalone/loop/structure-lifetime", structured_loop);
	Test.add_func ("/core-standalone/loop/invalid-models", invalid_structured_loops);
}

}
