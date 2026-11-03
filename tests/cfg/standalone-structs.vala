// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private CfgProgram struct_program() {
	var file = new SourceFile.from_text ("standalone-struct", "Pair x ready handle p");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var structure = new CfgStruct (span, SourceSpan (file, 0, 4), "Pair", new StructType ("Pair"));
	structure.fields.add (new CfgStructField (span, SourceSpan (file, 5, 6), "x", structure, types.int_type, 0));
	structure.fields.add (new CfgStructField (span, SourceSpan (file, 7, 12), "ready", structure, types.bool_type, 1));
	structure.fields.add (new CfgStructField (span, SourceSpan (file, 13, 19), "handle", structure, types.raw_pointer_type, 2));
	var local = new CfgLocalPlace (span, SourceSpan (file, 20, 21), "p", structure.semantic_type, 0);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (local);
	var places = new GenericArray<CfgFieldPlace> ();
	foreach (var field in structure.fields) {
		places.add (new CfgFieldPlace (span, local, field));
	}
	var statements = new GenericArray<CfgInstruction> ();
	statements.add (new CfgInitialize (span, places[2], new CfgNullPointerValue (span, types.raw_pointer_type)));
	statements.add (new CfgInitialize (span, places[0], new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (1))));
	statements.add (new CfgInitialize (span, places[1], new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE)));
	statements.add (new CfgStore (span, places[0], new CfgLoadValue (span, places[0])));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (new CfgBlock (span, 0, statements, new CfgReturn (span, new CfgLoadValue (span, places[0]))));
	var function = new CfgFunction (span, span, "f", types.int_type, 0, new GenericArray<CfgParameter> (), locals, blocks, blocks[0]);
	foreach (var place in places) {
		function.field_places.add (place);
	}
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	var structs = new GenericArray<CfgStruct> ();
	structs.add (structure);
	return new CfgProgram (span, functions, null, null, structs);
}

private void struct_model() {
	try {
		CfgProgram? program = struct_program ();
		CfgVerifier.verify (program);
		string dump = CfgDump.format (program);
		assert (dump.contains ("(struct \"Pair\"") && dump.contains ("(struct-local-place #0 \"p\" : Pair)"));
		assert (dump.contains ("(field-place (base struct-local-place #0 : Pair) (field #2 \"handle\") : void*)"));
		assert (dump.contains ("(initialize") && dump.contains ("(store") && dump.contains ("(load"));
		var descriptor_ref = WeakRef (program.structs[0]);
		var type_ref = WeakRef (program.structs[0].semantic_type);
		var field_ref = WeakRef (program.structs[0].fields[0]);
		var base_ref = WeakRef (program.functions[0].locals[0]);
		var projection_ref = WeakRef (program.functions[0].field_places[0]);
		program = null;
		assert (descriptor_ref.get () == null && type_ref.get () == null && field_ref.get () == null);
		assert (base_ref.get () == null && projection_ref.get () == null);
		program = struct_program ();
		CfgFieldPlace? detached = program.functions[0].field_places[0];
		var detached_base_ref = WeakRef (detached.aggregate);
		program = null;
		assert (detached.field.containing_struct == null && detached_base_ref.get () != null);
		detached = null;
		assert (detached_base_ref.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void struct_invalid() {
	for (int variant = 0; variant < 21; variant++) {
		var program = struct_program ();
		var function = program.functions[0];
		var structure = program.structs[0];
		var place = function.field_places[0];
		var span = place.span;
		var statements = function.entry.instructions;
		var int_value = new CfgIntegerValue (span, structure.fields[0].semantic_type, AstraIntValue.from_int64 (1));
		string expected;
		switch (variant) {
		case 0:
			program.structs.remove_index (0);
			expected = "program-owned struct descriptor";
			break;
		case 1:
			program.structs.add (structure);
			expected = "unique declared type identity";
			break;
		case 2:
			structure.fields.remove_range (0, 3);
			expected = "at least one scalar field";
			break;
		case 3:
			structure.fields[1] = structure.fields[0];
			expected = "exact struct owner, unique name and declaration ordinal";
			break;
		case 4:
			structure.fields[0] = new CfgStructField (span, span, "x", structure, ((RawPointerType) structure.fields[2].semantic_type).pointee, 0);
			expected = "found 'void'";
			break;
		case 5:
			structure.fields[0] = new CfgStructField (span, span, "x", structure, structure.semantic_type, 0);
			expected = "recursive by-value struct layout";
			break;
		case 6:
			function.field_places.remove_index (2);
			expected = "missing canonical field projection";
			break;
		case 7:
			function.field_places.add (place);
			expected = "unexpected or duplicate field projection";
			break;
		case 8:
			function.field_places[0] = new CfgFieldPlace (span, new CfgLocalPlace (span, span, "scalar", int_value.semantic_type, 0), place.field);
			expected = "match its exact aggregate base and declared field";
			break;
		case 9:
			function.field_places[0] = new CfgFieldPlace (span, new CfgLocalPlace (span, span, "other", structure.semantic_type, 0), place.field);
			expected = "match its exact aggregate base and declared field";
			break;
		case 10:
			function.field_places[0] = new CfgFieldPlace (span, place.aggregate, new CfgStructField (span, span, "x", structure, int_value.semantic_type, 0));
			expected = "match its exact aggregate base and declared field";
			break;
		case 11:
			statements[1] = new CfgInitialize (span, new CfgFieldPlace (span, place.aggregate, place.field), int_value);
			expected = "place is not owned by the containing function";
			break;
		case 12:
			statements[2] = statements[1];
			expected = "exactly one initialization";
			break;
		case 13:
			statements.remove_index (2);
			expected = "field must have exactly one initialization";
			break;
		case 14:
			statements[0] = new CfgInitialize (span, place.aggregate, int_value);
			expected = "unsupported semantic type";
			break;
		case 15:
			statements[3] = new CfgStore (span, place.aggregate, int_value);
			expected = "unsupported semantic type";
			break;
		case 16:
			var replacement = new CfgBlock (span, 0, statements, new CfgReturn (span, new CfgLoadValue (span, place.aggregate)));
			function.blocks[0] = replacement;
			var replacement_function = new CfgFunction (span, span, "f", int_value.semantic_type, 0, function.parameters, function.locals, function.blocks, replacement);
			foreach (var projection in function.field_places) {
				replacement_function.field_places.add (projection);
			}
			program.functions[0] = replacement_function;
			expected = "unsupported semantic type";
			break;
		case 17:
			statements[3] = new CfgStore (span, place, new CfgBooleanValue (span, structure.fields[1].semantic_type, BooleanLiteral.TRUE));
			expected = "stored value type does not match";
			break;
		case 18:
			statements[1] = new CfgInitialize (span, place, new CfgBooleanValue (span, structure.fields[1].semantic_type, BooleanLiteral.TRUE));
			expected = "initializer value type does not match";
			break;
		case 19:
			structure.fields[0] = new CfgStructField (span, span, "x", new CfgStruct (span, span, "Expired", new StructType ("Expired")), int_value.semantic_type, 0);
			expected = "exact struct owner";
			break;
		case 20:
			function.field_places[1] = function.field_places[0];
			expected = "canonical, function-owned";
			break;

		default:
			assert_not_reached ();
		}
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			if (!error.message.contains (expected)) {
				GLib.error ("variant %d expected %s; got %s", variant, expected, error.message);
			}
			continue;
		}
		GLib.error ("invalid standalone struct variant %d accepted", variant);
	}
}

private void register_struct_tests() {
	Test.add_func ("/cfg-standalone/structs/model-lifetime", struct_model);
	Test.add_func ("/cfg-standalone/structs/malformed", struct_invalid);
}

}
