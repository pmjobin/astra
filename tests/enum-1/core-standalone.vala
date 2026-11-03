// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.EnumCore {
private CoreProgram model(int mutation) {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("enum-core-independent", "x"), 0, 1);
	var definition = EnumShape.definition (t, s);
	var variant = definition.variant (0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (new CoreLocalPlace (s, s, "value", definition.semantic_type, 0));
	locals.add (new CoreLocalPlace (s, s, "a", t.int_type, 1));
	locals.add (new CoreLocalPlace (s, s, "b", t.int_type, 2));
	var one = new CoreIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 1));
	var two = new CoreIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 2));
	var fields = new GenericArray<CoreEnumFieldValue> ();
	fields.add (new CoreEnumFieldValue (s, variant.field (0), one, null, null));
	fields.add (new CoreEnumFieldValue (s, variant.field (1), two, null, null));
	var construct = new CoreEnumConstruct (s, definition, variant, fields);
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreEnumStore (s, locals[0], construct, true));
	var snapshot = new CoreEnumSnapshot (s, definition, locals[0]);
	var bindings = new GenericArray<CoreEnumBinding> ();
	bindings.add (new CoreEnumBinding (s, variant.field (0), locals[1], new EnumBindingIdentity (variant.field (0).identity, 1, snapshot.instance)));
	bindings.add (new CoreEnumBinding (s, variant.field (1), locals[2], new EnumBindingIdentity (variant.field (1).identity, 2, snapshot.instance)));
	var data = new CoreBlock (s, new GenericArray<CoreStatement> ());
	data.statements.add (new CoreReturn (s, one));
	var empty = new CoreBlock (s, new GenericArray<CoreStatement> ());
	empty.statements.add (new CoreReturn (s, two));
	var arms = new GenericArray<CoreEnumArm> ();
	arms.add (new CoreEnumArm (s, variant, bindings, data));
	arms.add (new CoreEnumArm (s, definition.variant (1), new GenericArray<CoreEnumBinding> (), empty));
	body.statements.add (new CoreEnumMatch (s, snapshot, arms));
	if (mutation == 1) {
		fields.remove_index (1);
	}
	if (mutation == 2) {
		fields[0] = new CoreEnumFieldValue (s, variant.field (0), two, null, null);
		fields[1] = new CoreEnumFieldValue (s, variant.field (1), one, null, null);
	}
	if (mutation == 3) {
		bindings[0] = new CoreEnumBinding (s, variant.field (0), locals[2], bindings[0].contract);
		bindings[1] = new CoreEnumBinding (s, variant.field (1), locals[1], bindings[1].contract);
	}
	if (mutation == 4) {
		arms.remove_index (1);
	}
	if (mutation == 5) {
		arms.add (arms[0]);
	}
	if (mutation == 6) {
		arms[1] = new CoreEnumArm (s, null, new GenericArray<CoreEnumBinding> (), empty);
		arms.add (new CoreEnumArm (s, definition.variant (1), new GenericArray<CoreEnumBinding> (), empty));
	}
	if (mutation == 7) {
		body.statements[0] = new CoreEnumStore (s, locals[0], new CoreEnumConstruct (s, EnumShape.definition (t, s), variant, fields), true);
	}
	var function = new CoreFunction (s, s, "probe", t.int_type, new GenericArray<CoreParameter> (), locals, body);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	var program = new CoreProgram (s, functions);
	program.enums.add (definition);
	return program;
}

private void positive() {
	try {
		CoreProgram? program = model (0);
		CoreVerifier.verify (program);
		CoreDump.format (program);
		var function = WeakRef (program.functions[0]);
		program = null;
		assert (function.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int mutation = 1; mutation <= 7; mutation++) {
		try {
			var program = model (0);
			var function = program.functions[0];
			var store = (CoreEnumStore) function.body.statements[0];
			var construction = (CoreEnumConstruct) store.producer;
			var match = (CoreEnumMatch) function.body.statements[1];
			var fields = construction.fields;
			var left = fields[0];
			var right = fields[1];
			var arms = match.arms;
			var empty = arms[1];
			var bindings = arms[0].bindings;
			var a = bindings[0];
			var b = bindings[1];
			if (mutation == 1) {
				fields.remove_index (1);
			}
			if (mutation == 2) {
				fields[0] = new CoreEnumFieldValue (left.span, left.field, right.scalar, null, null);
				fields[1] = new CoreEnumFieldValue (right.span, right.field, left.scalar, null, null);
			}
			if (mutation == 3) {
				bindings[0] = new CoreEnumBinding (a.span, a.field, b.destination, a.contract);
				bindings[1] = new CoreEnumBinding (b.span, b.field, a.destination, b.contract);
			}
			if (mutation == 4) {
				arms.remove_index (1);
			}
			if (mutation == 5) {
				arms.add (arms[0]);
			}
			if (mutation == 6) {
				arms[1] = new CoreEnumArm (empty.span, null, empty.bindings, empty.body);
				arms.add (empty);
			}
			if (mutation == 7) {
				function.body.statements[0] = new CoreEnumStore (store.span, store.destination, new CoreEnumConstruct (construction.span, EnumShape.definition (new BuiltinTypes (), construction.span), construction.variant, fields), true);
			}
			bool rejected = false;
			try {
				CoreVerifier.verify (program);
			} catch (CoreError error) {
				Test.message ("mutation %d: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			if (fields.length < 2) {
				fields.add (right);
			}
			fields[0] = left;
			fields[1] = right;
			bindings[0] = a;
			bindings[1] = b;
			while (arms.length > 2) {
				arms.remove_index (arms.length - 1);
			}
			if (arms.length < 2) {
				arms.add (empty);
			}
			arms[1] = empty;
			function.body.statements[0] = store;
			CoreVerifier.verify (program);
			Test.message ("restored Core mutation %d", mutation);
		} catch (CoreError error) {
			GLib.error ("%s", error.message);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum/core/independent-model-lifetime", positive);
	Test.add_func ("/enum/core/correspondence-coverage-nominal", malformed);
	return Test.run ();
}

}
