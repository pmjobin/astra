// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private CfgProgram tptr_program(int variant = -1) {
	var file = new SourceFile.from_text ("standalone-tptr", "Pair Other x y p");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var structure = new CfgStruct (span, span, "Pair", new StructType ("Pair"));
	var other = new CfgStruct (span, span, "Other", new StructType ("Other"));
	structure.fields.add (new CfgStructField (span, span, "x", structure, types.int_type, 0));
	structure.fields.add (new CfgStructField (span, span, "y", structure, types.int_type, 1));
	other.fields.add (new CfgStructField (span, span, "x", other, types.int_type, 0));
	var pointer_type = types.pointer_to (structure.semantic_type);
	var parameter = new CfgParameter (span, span, "ptr", pointer_type, 0);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (parameter);
	var local = new CfgLocalPlace (span, span, "p", variant == 8 ? types.int_type : structure.semantic_type, 0, variant != 0);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (local);
	var x = new CfgFieldPlace (span, local, structure.fields[0]);
	var y = new CfgFieldPlace (span, local, structure.fields[1]);
	var address = new CfgAddressOfValue (span, variant == 1 ? (SemanticType) types.raw_pointer_type : pointer_type, variant == 2 ? new CfgLocalPlace (span, span, "p", structure.semantic_type, 0, true) : local);
	CfgValue pointer = variant == 5 ? (CfgValue) new CfgNullPointerValue (span, types.raw_pointer_type) : new CfgParameterValue (span, parameter);
	var field = variant == 3 ? other.fields[0] : variant == 4 ? new CfgStructField (span, span, "x", structure, types.int_type, 0) : structure.fields[0];
	var indirect = new CfgIndirectFieldPlace (span, pointer, field);
	var one = new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (1));
	var instructions = new GenericArray<CfgInstruction> ();
	instructions.add (new CfgInitialize (span, x, one));
	instructions.add (new CfgInitialize (span, y, one));
	instructions.add (variant == 6 ? (CfgInstruction) new CfgInitialize (span, indirect, one) : new CfgStore (span, indirect, variant == 9 ? (CfgValue) new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE) : one));
	var block = new CfgBlock (span, 0, instructions, new CfgReturn (span, new CfgLoadValue (span, indirect)));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var function = new CfgFunction (span, span, "f", variant == 7 ? (SemanticType) pointer_type : types.int_type, 0, parameters, locals, blocks, block);
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (address);
	instructions.add (new CfgCallInstruction (span, function, arguments, new CfgCallResultValue (span, types.int_type)));
	function.field_places.add (x);
	function.field_places.add (y);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	var structs = new GenericArray<CfgStruct> ();
	structs.add (structure);
	structs.add (other);
	return new CfgProgram (span, functions, null, null, structs);
}

private void tptr_model() {
	try {
		CfgProgram? program = tptr_program ();
		CfgVerifier.verify (program);
		assert (!program.functions[0].locals[0].is_promotable ());
		assert (!program.functions[0].field_places[0].is_promotable ());
		string dump = CfgDump.format (program);
		assert (dump.contains ("address-taken") && dump.contains ("address-of") && dump.contains ("indirect-field-place"));
		var structure = WeakRef (program.structs[0]);
		var storage = WeakRef (program.functions[0].locals[0]);
		var pointer = WeakRef (program.functions[0].parameters[0].semantic_type);
		program = null;
		assert (structure.get () == null && storage.get () == null && pointer.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void tptr_invalid() {
	for (int variant = 0; variant < 10; variant++) {
		try {
			CfgVerifier.verify (tptr_program (variant));
		} catch (CfgError error) {
			Test.message ("malformed typed place %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("invalid standalone typed place %d accepted", variant);
	}
}

private void register_tptr_tests() {
	Test.add_func ("/cfg-standalone/tptr/model-lifetime", tptr_model);
	Test.add_func ("/cfg-standalone/tptr/malformed", tptr_invalid);
}

}
