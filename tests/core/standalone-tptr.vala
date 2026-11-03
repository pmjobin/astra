// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
private CoreProgram tptr_program(int variant = -1) {
	var file = new SourceFile.from_text ("standalone-tptr", "Pair Other x y p");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var structure = new CoreStruct (span, span, "Pair", new StructType ("Pair"));
	var other = new CoreStruct (span, span, "Other", new StructType ("Other"));
	structure.fields.add (new CoreStructField (span, span, "x", structure, types.int_type, 0));
	structure.fields.add (new CoreStructField (span, span, "y", structure, types.int_type, 1));
	other.fields.add (new CoreStructField (span, span, "x", other, types.int_type, 0));
	var pointer_type = types.pointer_to (structure.semantic_type);
	var parameter = new CoreParameter (span, span, "ptr", pointer_type, 0);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (parameter);
	var local = new CoreLocalPlace (span, span, "p", variant == 8 ? types.int_type : structure.semantic_type, 0, variant != 0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var x = new CoreFieldPlace (span, local, structure.fields[0]);
	var y = new CoreFieldPlace (span, local, structure.fields[1]);
	var address = new CoreAddressOfValue (span, variant == 1 ? (SemanticType) types.raw_pointer_type : pointer_type, variant == 2 ? new CoreLocalPlace (span, span, "p", structure.semantic_type, 0, true) : local);
	CoreValue pointer = variant == 5 ? (CoreValue) new CoreNullPointerValue (span, types.raw_pointer_type) : new CoreParameterValue (span, parameter);
	var field = variant == 3 ? other.fields[0] : variant == 4 ? new CoreStructField (span, span, "x", structure, types.int_type, 0) : structure.fields[0];
	var indirect = new CoreIndirectFieldPlace (span, pointer, field);
	var one = new CoreIntegerValue (span, types.int_type, AstraIntValue.from_int64 (1));
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var function = new CoreFunction (span, span, "f", variant == 7 ? (SemanticType) pointer_type : types.int_type, parameters, locals, body);
	body.statements.add (new CoreInitialize (span, x, one));
	body.statements.add (new CoreInitialize (span, y, one));
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (address);
	body.statements.add (new CoreCallStatement (span, function, arguments));
	body.statements.add (variant == 6 ? (CoreStatement) new CoreInitialize (span, indirect, one) : new CoreStore (span, indirect, variant == 9 ? (CoreValue) new CoreBooleanValue (span, types.bool_type, BooleanLiteral.TRUE) : one));
	body.statements.add (new CoreReturn (span, new CoreLoadValue (span, indirect)));
	if (variant == 10) {
		body.statements[0] = new CoreInitialize (span, x, new CoreLoadValue (span, y));
	}
	if (variant == 11) {
		body.statements[1] = new CoreCallStatement (span, function, arguments);
	}
	function.field_places.add (x);
	function.field_places.add (y);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	var structs = new GenericArray<CoreStruct> ();
	structs.add (structure);
	structs.add (other);
	return new CoreProgram (span, functions, null, null, structs);
}

private void tptr_model() {
	try {
		CoreProgram? program = tptr_program ();
		CoreVerifier.verify (program);
		assert (!program.functions[0].locals[0].is_promotable ());
		assert (!program.functions[0].field_places[0].is_promotable ());
		string dump = CoreDump.format (program);
		assert (dump.contains ("address-taken") && dump.contains ("address-of") && dump.contains ("indirect-field-place"));
		var structure = WeakRef (program.structs[0]);
		var storage = WeakRef (program.functions[0].locals[0]);
		var pointer = WeakRef (program.functions[0].parameters[0].semantic_type);
		program = null;
		assert (structure.get () == null && storage.get () == null && pointer.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void tptr_invalid() {
	for (int variant = 0; variant < 12; variant++) {
		try {
			CoreVerifier.verify (tptr_program (variant));
		} catch (CoreError error) {
			Test.message ("malformed typed place %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("invalid standalone typed place %d accepted", variant);
	}
}

private void register_tptr_tests() {
	Test.add_func ("/core-standalone/tptr/model-lifetime", tptr_model);
	Test.add_func ("/core-standalone/tptr/malformed", tptr_invalid);
}

}
