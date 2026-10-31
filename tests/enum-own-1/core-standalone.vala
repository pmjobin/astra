// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.OwningCore {
private CoreProgram model(BuiltinTypes? supplied = null) {
	var t = supplied ?? new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("independent-owning-core", "x"), 0, 1);
	var definition = OwningShape.definition (t, s);
	var variant = definition.variant (0);
	var slice = (SliceType) variant.field (0).semantic_type;
	var cleanup = new CoreCleanupContract.for_buffer (new BufferValueShape (slice, t.raw_pointer_type, t.i32_type), s, 0);
	var fields = new GenericArray<CoreEnumFieldValue> ();
	for (uint f = 0; f < 2; f++) {
		var count = new CoreIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, f + 1));
		var allocation = new CoreOwnedBufferAllocate (s, slice, count, cleanup);
		fields.add (new CoreEnumFieldValue (s, variant.field (f), new CoreEnumBufferValue (s, cleanup, null, allocation), null, null));
	}
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (new CoreLocalPlace (s, s, "owner", definition.semantic_type, 0));
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreEnumStore (s, locals[0], new CoreEnumConstruct (s, definition, variant, fields), true));
	body.statements.add (new CoreReturn (s, new CoreIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 0))));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (s, s, "probe", t.int_type, new GenericArray<CoreParameter> (), locals, body));
	var program = new CoreProgram (s, functions);
	program.enums.add (definition);
	program.cleanups.add (cleanup);
	return program;
}
private void contracts() {
	try {
		CoreProgram? program = model ();
		CoreVerifier.verify (program);
		var function = program.functions[0];
		var store = (CoreEnumStore) function.body.statements[0];
		var construction = (CoreEnumConstruct) store.producer;
		var a = construction.fields[0];
		var b = construction.fields[1];
		for (int mutation = 0; mutation < 4; mutation++) {
			if (mutation == 0) {
				construction.fields.remove_index (1);
			}
			if (mutation == 1) {
				construction.fields[0] = new CoreEnumFieldValue (a.span, a.field, b.scalar, null, null);
				construction.fields[1] = new CoreEnumFieldValue (b.span, b.field, a.scalar, null, null);
			}
			if (mutation == 2) {
				function.body.statements[0] = new CoreEnumStore (store.span, store.destination, new CoreEnumSnapshot (store.span, store.producer.definition, store.destination), true);
			}
			if (mutation == 3) {
				function.body.statements[0] = new CoreEnumStore (store.span, store.destination, new CoreEnumConstruct (store.span, OwningShape.definition (new BuiltinTypes (), store.span), construction.variant, construction.fields), true);
			}
			bool rejected = false;
			try {
				CoreVerifier.verify (program);
			} catch (CoreError error) {
				Test.message ("owning Core mutation %d: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			if (construction.fields.length == 1) {
				construction.fields.add (b);
			}
			construction.fields[0] = a;
			construction.fields[1] = b;
			function.body.statements[0] = store;
			CoreVerifier.verify (program);
		}
		var weak = WeakRef (function);
		function = null;
		store = null;
		construction = null;
		a = null;
		b = null;
		program = null;
		assert (weak.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}
private void nonnull_field_authority() {
	try {
		var types = new BuiltinTypes ();
		var program = model (types);
		var span = program.span;
		var record = new CoreStruct (span, span, "Copied", new StructType ("Copied"));
		var field = new CoreStructField (span, span, "value", record, types.int_type, 0);
		record.fields.add (field);
		program.structs.add (record);
		CoreVerifier.verify (program);
		field.mark_nonnull ();
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum-own/core/independent-mutations-restoration-lifetime", contracts);
	Test.add_func ("/enum-own/core/reject-forged-nonnull-field", nonnull_field_authority);
	return Test.run ();
}
}
