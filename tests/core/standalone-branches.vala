// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
private void conditional_model() {
	try {
		var file = new SourceFile.from_text ("conditional-standalone.astra", "007");
		var span = SourceSpan (file, 0, file.length);
		var types = new BuiltinTypes ();
		var parameters = new GenericArray<CoreParameter> ();
		var parameter = new CoreParameter (span, span, "a", types.int_type, 0);
		parameters.add (parameter);
		var locals = new GenericArray<CoreLocalPlace> ();
		var local = new CoreLocalPlace (span, span, "y", types.bool_type, 0);
		locals.add (local);
		var comparison = new CoreBinaryValue (span, types.bool_type, BinaryOperator.LESS, new CoreParameterValue (span, parameter), new CoreIntegerValue (span, types.int_type, AstraIntValue.from_int64 (7)));
		var condition = new CorePrefixValue (span, types.bool_type, PrefixOperator.NOT, comparison);
		var yes = new CoreBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
		var no = new CoreBooleanValue (span, types.bool_type, BooleanLiteral.FALSE);
		var then_statements = new GenericArray<CoreStatement> ();
		then_statements.add (new CoreStore (span, local, yes));
		var else_statements = new GenericArray<CoreStatement> ();
		else_statements.add (new CoreStore (span, local, no));
		var statements = new GenericArray<CoreStatement> ();
		statements.add (new CoreInitialize (span, local, no));
		statements.add (new CoreIf (span, condition, new CoreBlock (span, then_statements), new CoreBlock (span, else_statements)));
		statements.add (new CoreReturn (span, new CoreLoadValue (span, local)));
		var functions = new GenericArray<CoreFunction> ();
		functions.add (new CoreFunction (span, span, "f", types.bool_type, parameters, locals, new CoreBlock (span, statements)));
		var program = new CoreProgram (span, functions);
		CoreVerifier.verify (program);
		string dump = CoreDump.format (program);
		assert (dump.contains ("(if") && dump.contains ("(then") && dump.contains ("(else"));
		assert (dump.contains ("(bool true : bool)") && dump.contains ("(bool false : bool)"));
		assert (dump.contains ("(prefix ! : bool") && dump.contains ("(binary < : bool"));
		assert (dump.contains ("(load : bool") && !dump.contains ("LLVM"));
	} catch (CoreError error) {
		GLib.error ("Unexpected standalone conditional failure: %s", error.message);
	}
}
}
