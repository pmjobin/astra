// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.EnumCfg {
private CfgProgram model(int mutation) throws CfgError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("enum-cfg-independent", "x"), 0, 1);
	var definition = EnumShape.definition (t, s);
	var variant = definition.variant (0);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (new CfgLocalPlace (s, s, "a", t.int_type, 0));
	locals.add (new CfgLocalPlace (s, s, "b", t.int_type, 1));
	var slot = new CfgEnumSlot (s, definition, 0);
	var one = new CfgIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 1));
	var two = new CfgIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 2));
	var fields = new GenericArray<CfgEnumFieldInput> ();
	var left = new GenericArray<CfgValue> ();
	left.add (one);
	var right = new GenericArray<CfgValue> ();
	right.add (two);
	fields.add (new CfgEnumFieldInput (s, variant.field (0), left));
	fields.add (new CfgEnumFieldInput (s, variant.field (1), right));
	var entry = new CfgBlock.reserve (s, 0);
	entry.instructions.add (new CfgEnumConstruct (s, slot, variant, fields));
	var data = new CfgBlock.reserve (s, 1);
	var empty = new CfgBlock (s, 2, new GenericArray<CfgInstruction> (), new CfgReturn (s, two));
	var invalid = new CfgBlock (s, 3, new GenericArray<CfgInstruction> (), new CfgEnumInvalidTag (s));
	for (uint f = 0; f < 2; f++) {
		var field = variant.field (f);
		var payload = new CfgEnumPayloadValue (s, slot, field, new EnumBindingIdentity (field.identity, (int) f, slot.instance));
		var captured = new CfgEvaluatedValue (s, t.int_type);
		data.instructions.add (new CfgEvaluateInstruction (s, payload, captured));
		data.instructions.add (new CfgInitialize (s, locals[f], captured));
	}
	data.complete (s, new CfgReturn (s, one));
	var cases = new GenericArray<CfgEnumCase> ();
	cases.add (new CfgEnumCase (variant, data));
	cases.add (new CfgEnumCase (definition.variant (1), empty));
	entry.complete (s, new CfgEnumDispatch (s, slot, cases, invalid));
	if (mutation == 1) {
		fields.remove_index (1);
	}
	if (mutation == 2) {
		left[0] = two;
		right[0] = one;
	}
	if (mutation == 3) {
		var init = (CfgInitialize) data.instructions[1];
		data.instructions[1] = new CfgInitialize (s, locals[1], init.value);
	}
	if (mutation == 4) {
		cases.remove_index (1);
	}
	if (mutation == 5) {
		cases[0] = new CfgEnumCase (definition.variant (1), data);
	}
	if (mutation == 6) {
		cases[0] = new CfgEnumCase (variant, empty);
		cases[1] = new CfgEnumCase (definition.variant (1), data);
	}
	if (mutation == 7) {
		entry.instructions.remove_index (0);
	}
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (entry);
	blocks.add (data);
	blocks.add (empty);
	blocks.add (invalid);
	var function = new CfgFunction (s, s, "probe", t.int_type, 0, new GenericArray<CfgParameter> (), locals, blocks, entry);
	function.enum_slots.add (slot);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	var program = new CfgProgram (s, functions);
	program.enums.add (definition);
	return program;
}
private CfgProgram tag_model() throws CfgError {
	var original = model (0);
	var previous = original.functions[0];
	var construction = (CfgEnumConstruct) previous.entry.instructions[0];
	var slot = construction.destination;
	var span = previous.span;
	var instructions = new GenericArray<CfgInstruction> ();
	instructions.add (construction);
	var entry = new CfgBlock (span, 0, instructions, new CfgReturn (span, new CfgEnumTag (span, slot.definition.tag_type, slot)));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (entry);
	var function = new CfgFunction (span, span, "tag", previous.return_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, entry);
	function.enum_slots.add (slot);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	var program = new CfgProgram (span, functions);
	program.enums.add (slot.definition);
	return program;
}
private void returned_tag_initialization() {
	try {
		var program = tag_model ();
		CfgVerifier.verify (program);
		var instructions = program.functions[0].entry.instructions;
		var construction = instructions[0];
		instructions.remove_index (0);
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("returned tag: %s", error.message);
			rejected = true;
		}
		assert (rejected);
		instructions.add (construction);
		CfgVerifier.verify (program);
		Test.message ("restored returned tag initialization");
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}
private void positive() {
	try {
		CfgProgram? program = model (0);
		CfgVerifier.verify (program);
		CfgDump.format (program);
		var function = WeakRef (program.functions[0]);
		program = null;
		assert (function.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}
private void malformed() {
	for (int mutation = 1; mutation <= 8; mutation++) {
		try {
			var program = model (0);
			var function = program.functions[0];
			var entry = function.entry;
			var construction = (CfgEnumConstruct) entry.instructions[0];
			var fields = construction.fields;
			var left = fields[0];
			var right = fields[1];
			var left_value = left.leaves[0];
			var right_value = right.leaves[0];
			var dispatch = (CfgEnumDispatch) entry.terminator;
			var cases = dispatch.cases;
			var a = cases[0];
			var b = cases[1];
			var data = function.blocks[1];
			var init = (CfgInitialize) data.instructions[1];
			if (mutation == 1) {
				fields.remove_index (1);
			}
			if (mutation == 2) {
				left.leaves[0] = right_value;
				right.leaves[0] = left_value;
			}
			if (mutation == 3) {
				data.instructions[1] = new CfgInitialize (init.span, function.locals[1], init.value);
			}
			if (mutation == 4) {
				cases.remove_index (1);
			}
			if (mutation == 5) {
				cases[0] = new CfgEnumCase (b.variant, a.target);
			}
			if (mutation == 6) {
				cases[0] = new CfgEnumCase (a.variant, b.target);
				cases[1] = new CfgEnumCase (b.variant, a.target);
			}
			if (mutation == 7) {
				entry.instructions.remove_index (0);
			}
			if (mutation == 8) {
				program.enums.remove_index (0);
				function.enum_slots.remove_index (0);
			}
			var definition = construction.destination.definition;
			var slot = construction.destination;
			bool rejected = false;
			try {
				CfgVerifier.verify (program);
			} catch (CfgError error) {
				Test.message ("mutation %d: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			if (program.enums.length == 0) {
				program.enums.add (definition);
			}
			if (function.enum_slots.length == 0) {
				function.enum_slots.add (slot);
			}
			if (fields.length < 2) {
				fields.add (right);
			}
			fields[0] = left;
			fields[1] = right;
			left.leaves[0] = left_value;
			right.leaves[0] = right_value;
			if (cases.length < 2) {
				cases.add (b);
			}
			cases[0] = a;
			cases[1] = b;
			if (entry.instructions.length == 0) {
				entry.instructions.add (construction);
			}
			entry.instructions[0] = construction;
			data.instructions[1] = init;
			CfgVerifier.verify (program);
			Test.message ("restored Cfg mutation %d", mutation);
		} catch (CfgError error) {
			GLib.error ("%s", error.message);
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum/cfg/independent-model-lifetime", positive);
	Test.add_func ("/enum/cfg/correspondence-coverage-initialization", malformed);
	Test.add_func ("/enum/cfg/returned-tag-initialization", returned_tag_initialization);
	return Test.run ();
}
}
