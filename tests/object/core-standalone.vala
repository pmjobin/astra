// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.ObjectCore {
private CoreProgram sample(int variant = 0) {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("object", "C"), 0, 1);
	var type = new ClassType ("C");
	var c = new CoreClass (span, span, "C", type);
	var other = new CoreClass (span, span, "D", new ClassType ("D"), 1);
	var field = new CoreStructField (span, span, "x", c, t.int_type, 0);
	c.fields.add (field);
	var other_field = new CoreStructField (span, span, "x", other, t.int_type, 0);
	other.fields.add (other_field);
	var contract = new ReceiverType (variant == 8 ? other.semantic_type : type);
	var receiver = new CoreReceiver (span, contract);
	var method_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var parameters = new GenericArray<CoreParameter> ();
	if (variant == 9) {
		parameters.add (new CoreParameter (span, span, "p", type, 0));
	}
	var method = new CoreMethod (span, span, "get", variant == 7 ? other : c, receiver, 0, 1, variant == 10 ? (SemanticType) type : t.int_type, parameters, new GenericArray<CoreLocalPlace> (), method_body);
	method_body.statements.add (new CoreReturn (span, new CoreLoadValue (span, new CoreIndirectFieldPlace (span, new CoreReceiverValue (span, receiver), field))));
	c.methods.add (method);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var locals = new GenericArray<CoreLocalPlace> ();
	var local = new CoreLocalPlace (span, span, "reference", variant == 4 ? other.semantic_type : type, 0, variant == 11);
	locals.add (local);
	var storage = new CoreObjectStorage (span, c, variant == 12 ? 1 : 0, variant == 13 ? -1 : 0, variant == 14 ? method_body : body);
	var initializers = new GenericArray<CoreObjectFieldInitializer> ();
	var initializer = new CoreObjectFieldInitializer (span, variant == 3 ? other_field : field, variant == 5 ? (CoreValue) new CoreNullPointerValue (span, type) : variant == 6 ? (CoreValue) new CoreLoadValue (span, local) : new CoreIntegerValue (span, t.int_type, AstraIntValue.from_int64 (42)));
	if (variant != 1) {
		initializers.add (initializer);
	}
	if (variant == 2) {
		initializers.add (initializer);
	}
	body.statements.add (new CoreObjectConstruction (span, storage, local, initializers));
	var validated = new CoreObjectReceiverValue (span, new CoreLoadValue (span, local), contract);
	body.statements.add (new CoreReturn (span, new CoreCallValue (span, t.int_type, method, new GenericArray<CoreValue> (), validated)));
	var main = new CoreFunction (span, span, "main", t.int_type, new GenericArray<CoreParameter> (), locals, body);
	if (variant != 15) {
		main.object_storage.add (storage);
	}
	if (variant == 16) {
		main.object_storage.add (storage);
	}
	var functions = new GenericArray<CoreFunction> ();
	functions.add (main);
	functions.add (method);
	var program = new CoreProgram (span, functions);
	program.classes.add (c);
	program.classes.add (other);
	if (variant == 17) {
		program.classes.add (new CoreClass (span, span, "C", type, 2));
	}
	if (variant == 18) {
		program.classes.add (new CoreClass (span, span, "Empty", new ClassType ("Empty"), -1));
	}
	if (variant == 19) {
		main.object_storage.add (new CoreObjectStorage (span, c, 1, 0, body));
	}
	return program;
}

private void valid() {
	try {
		CoreProgram? p = sample ();
		CoreVerifier.verify (p);
		assert (p.classes[0].methods[0] == p.functions[1] && p.functions[0].locals[0].is_promotable ());
		assert ((Object) p.functions[0].object_storage[0] != (Object) p.functions[0].locals[0]);
		assert (CoreDump.format (p).contains ("object-construct"));
		var storage = WeakRef (p.functions[0].object_storage[0]);
		var method = WeakRef (p.functions[1]);
		var declaration = WeakRef (p.classes[0]);
		p = null;
		assert (storage.get () == null && method.get () == null && declaration.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 19; variant++) {
		try {
			CoreVerifier.verify (sample (variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed object Core variant %d", variant);
	}
}

private void identity() {
	foreach (var op in new BinaryOperator[] { BinaryOperator.EQUAL, BinaryOperator.NOT_EQUAL }) {
		for (int variant = 0; variant < 2; variant++) {
			try {
				var p = sample ();
				var t = new BuiltinTypes ();
				var span = p.span;
				var type = p.classes[0].semantic_type;
				var left = new CoreNullPointerValue (span, type);
				var right = new CoreNullPointerValue (span, variant == 1 ? new ClassType ("C") : type);
				var comparison = new CoreBinaryValue (span, t.bool_type, op, left, right);
				var statements = new GenericArray<CoreStatement> ();
				statements.add (new CoreReturn (span, comparison));
				p.functions.add (new CoreFunction (span, span, "equal", t.bool_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), new CoreBlock (span, statements)));
				CoreVerifier.verify (p);
				assert (variant == 0);
			} catch (CoreError error) {
				if (variant == 0) {
					GLib.error ("%s", error.message);
				}
			}
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/object/core/independent-storage-reference-fields-methods-lifetime", valid);
	Test.add_func ("/object/core/malformed-identities-construction-types-and-boundaries", malformed);
	Test.add_func ("/object/core/exact-class-null-identity-comparison", identity);
	return Test.run ();
}

}
