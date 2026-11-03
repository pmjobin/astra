// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.EnumSsa {
private SsaProgram model(int mutation) throws SsaError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("enum-ssa-independent", "x"), 0, 1);
	var definition = EnumShape.definition (t, s);
	var variant = definition.variant (0);
	var slot = new SsaEnumSlot (s, definition, 0);
	var one = new SsaIntegerConstant.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 1));
	var two = new SsaIntegerConstant.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 2));
	var fields = new GenericArray<SsaEnumFieldInput> ();
	var left = new GenericArray<SsaValue> ();
	left.add (one);
	var right = new GenericArray<SsaValue> ();
	right.add (two);
	fields.add (new SsaEnumFieldInput (s, variant.field (0), left));
	fields.add (new SsaEnumFieldInput (s, variant.field (1), right));
	var entry = new SsaBlock (s, 0, 0);
	entry.instructions.add (new SsaEnumConstruct (s, slot, variant, fields));
	var data = new SsaBlock (s, 1, 1);
	var empty = new SsaBlock (s, 2, 2);
	empty.complete (new SsaReturn (s, two));
	var invalid = new SsaBlock (s, 3, 3);
	invalid.complete (new SsaEnumInvalidTag (s));
	var read = new SsaEnumRead (s, slot, variant.field (0), 0, new EnumBindingIdentity (variant.field (0).identity, 0, slot.instance));
	data.instructions.add (read);
	data.complete (new SsaReturn (s, read.result));
	var cases = new GenericArray<SsaEnumCase> ();
	cases.add (new SsaEnumCase (variant, new SsaEdge (data, new GenericArray<SsaValue> ())));
	cases.add (new SsaEnumCase (definition.variant (1), new SsaEdge (empty, new GenericArray<SsaValue> ())));
	entry.complete (new SsaEnumDispatch (s, slot, cases, new SsaEdge (invalid, new GenericArray<SsaValue> ())));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (entry);
	blocks.add (data);
	blocks.add (empty);
	blocks.add (invalid);
	var function = new SsaFunction (s, s, "probe", t.int_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, entry);
	function.enum_slots.add (slot);
	function.enum_projections.add (new SsaEnumProjectionContract (read));
	if (mutation == 1) {
		fields.remove_index (1);
	}
	if (mutation == 2) {
		left[0] = two;
		right[0] = one;
	}
	if (mutation == 3) {
		var wrong = new SsaEnumRead (s, slot, variant.field (1), 0, read.binding);
		function.enum_projections[0].instruction = wrong;
		data.instructions[0] = wrong;
	}
	if (mutation == 4) {
		cases.remove_index (1);
	}
	if (mutation == 5) {
		cases[0] = new SsaEnumCase (definition.variant (1), cases[0].edge);
	}
	if (mutation == 6) {
		cases[0] = new SsaEnumCase (variant, cases[1].edge);
		cases[1] = new SsaEnumCase (definition.variant (1), new SsaEdge (data, new GenericArray<SsaValue> ()));
	}
	if (mutation == 7) {
		entry.instructions.remove_index (0);
	}
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	var program = new SsaProgram (s, functions);
	program.enums.add (definition);
	return program;
}

private void positive() {
	try {
		SsaProgram? program = model (0);
		SsaVerifier.verify (program);
		SsaDump.format (program);
		var function = WeakRef (program.functions[0]);
		program = null;
		assert (function.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int mutation = 1; mutation <= 8; mutation++) {
		try {
			var program = model (0);
			var function = program.functions[0];
			var entry = function.entry;
			var construction = (SsaEnumConstruct) entry.instructions[0];
			var fields = construction.fields;
			var left = fields[0];
			var right = fields[1];
			var left_value = left.leaves[0];
			var right_value = right.leaves[0];
			var dispatch = (SsaEnumDispatch) entry.terminator;
			var cases = dispatch.cases;
			var a = cases[0];
			var b = cases[1];
			var data = function.blocks[1];
			var read = (SsaEnumRead) data.instructions[0];
			if (mutation == 1) {
				fields.remove_index (1);
			}
			if (mutation == 2) {
				left.leaves[0] = right_value;
				right.leaves[0] = left_value;
			}
			if (mutation == 3) {
				var wrong = new SsaEnumRead (read.span, read.source, read.source.definition.variant (0).field (1), read.result.ordinal, read.binding);
				function.enum_projections[0].instruction = wrong;
				data.instructions[0] = wrong;
			}
			if (mutation == 4) {
				cases.remove_index (1);
			}
			if (mutation == 5) {
				cases[0] = new SsaEnumCase (b.variant, a.edge);
			}
			if (mutation == 6) {
				cases[0] = new SsaEnumCase (a.variant, b.edge);
				cases[1] = new SsaEnumCase (b.variant, a.edge);
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
				SsaVerifier.verify (program);
			} catch (SsaError error) {
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
			data.instructions[0] = read;
			function.enum_projections[0].instruction = read;
			SsaVerifier.verify (program);
			Test.message ("restored Ssa mutation %d", mutation);
		} catch (SsaError error) {
			GLib.error ("%s", error.message);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum/ssa/independent-model-lifetime", positive);
	Test.add_func ("/enum/ssa/correspondence-coverage-initialization", malformed);
	return Test.run ();
}

}
