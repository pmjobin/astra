// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
private CoreProgram short_program(int variant = -1) {
	var file = new SourceFile.from_text ("core-short", "a && (b || c)");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var type = variant == 2 ? types.int_type : types.bool_type;
	CoreValue left = variant == 0 ? (CoreValue) new CoreIntegerValue (span, types.int_type, AstraIntValue.from_int64 (1)) : new CoreBooleanValue (span, types.bool_type, BooleanLiteral.FALSE);
	CoreValue right = variant == 1 ? (CoreValue) new CoreIntegerValue (span, types.int_type, AstraIntValue.from_int64 (1)) : new CoreShortCircuitValue (span, types.bool_type, ShortCircuitOperator.OR, new CoreBooleanValue (span, types.bool_type, BooleanLiteral.TRUE), new CoreBooleanValue (span, types.bool_type, BooleanLiteral.FALSE));
	var value = new CoreShortCircuitValue (span, type, variant == 3 ? (ShortCircuitOperator) 99 : ShortCircuitOperator.AND, left, right);
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreReturn (span, value));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void short_model() {
	try {
		CoreProgram? program = short_program ();
		var value_ref = WeakRef (((CoreReturn) program.functions[0].body.statements[0]).value);
		CoreVerifier.verify (program);
		string dump = CoreDump.format (program);
		assert (dump.contains ("short-circuit && : bool") && dump.contains ("short-circuit || : bool"));
		assert (!dump.contains ("binary") && !dump.contains ("block #"));
		program = null;
		assert (value_ref.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void short_invalid() {
	for (int i = 0; i < 4; i++) {
		try {
			CoreVerifier.verify (short_program (i));
		} catch (CoreError error) {
			assert (error.message.has_suffix ("invalid operator, operands or result type for short-circuit value"));
			continue;
		}
		GLib.error ("Invalid short-circuit Core accepted: %d", i);
	}
}

private void register_shortcircuit_tests() {
	Test.add_func ("/core-standalone/shortcircuit/structure-lifetime", short_model);
	Test.add_func ("/core-standalone/shortcircuit/invalid-types-operator", short_invalid);
}

}
