// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.LifecycleCore {
private CoreProgram sample(int variant = 0) {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("lifecycle", "C"), 0, 1);
	var c = new CoreClass (s, s, "C", new ClassType ("C"));
	var field = new CoreStructField (s, s, "x", c, t.int_type, 0);
	c.fields.add (field);
	var receiver = new CoreReceiver (s, new ReceiverType (c.semantic_type, variant == 1 ? ReceiverMode.LIVE : ReceiverMode.INITIALIZING));
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var place = new CoreIndirectFieldPlace (s, new CoreReceiverValue (s, receiver), field);
	if (variant == 15) {
		place = new CoreIndirectFieldPlace (s, new CoreReceiverValue (s, receiver), new CoreStructField (s, s, "forged", c, t.int_type, 77));
	}
	CoreValue value = variant == 4 || variant == 15 ? (CoreValue) new CoreLoadValue (s, place) : new CoreIntegerValue (s, t.int_type, AstraIntValue.from_int64 (42));
	if (variant != 2) {
		body.statements.add (variant == 5 ? (CoreStatement) new CoreStore (s, place, value) : new CoreFieldInitialize (s, place, value));
	}
	if (variant == 3) {
		body.statements.add (new CoreFieldInitialize (s, new CoreIndirectFieldPlace (s, new CoreReceiverValue (s, receiver), field), value));
	}
	if (variant == 6) {
		body.statements.add (new CoreReturn (s, null));
	}
	var parameters = new GenericArray<CoreParameter> ();
	if (variant == 7) {
		parameters.add (new CoreParameter (s, s, "object", c.semantic_type, 0));
	}
	var ctor = new CoreConstructor (s, s, c, receiver, 1, variant == 8 ? t.int_type : t.void_type, parameters, new GenericArray<CoreLocalPlace> (), body);
	if (variant != 13) {
		c.constructor = ctor;
	}
	var live = new CoreReceiver (s, new ReceiverType (c.semantic_type, variant == 10 ? ReceiverMode.INITIALIZING : ReceiverMode.LIVE));
	var dbody = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var dparameters = new GenericArray<CoreParameter> ();
	if (variant == 9) {
		dparameters.add (new CoreParameter (s, s, "n", t.int_type, 0));
	}
	var dtor = new CoreDestructor (s, s, c, live, 2, t.void_type, dparameters, new GenericArray<CoreLocalPlace> (), dbody);
	c.destructor = dtor;
	if (variant == 14) {
		dbody.statements.add (new CoreFieldInitialize (s, new CoreIndirectFieldPlace (s, new CoreReceiverValue (s, live), field), new CoreIntegerValue (s, t.int_type, AstraIntValue.from_int64 (1))));
	}
	var main_body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var local = new CoreLocalPlace (s, s, "reference", c.semantic_type, 0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var storage = new CoreObjectStorage (s, c, 0, 0, main_body);
	storage.cleanup_rank = variant == 16 ? -1 : 0;
	if (variant == 12) {
		var fields = new GenericArray<CoreObjectFieldInitializer> ();
		fields.add (new CoreObjectFieldInitializer (s, field, value));
		main_body.statements.add (new CoreObjectConstruction (s, storage, local, fields));
	} else {
		main_body.statements.add (new CoreConstructorObjectInitialization (s, storage, local, ctor, new GenericArray<CoreValue> ()));
	}
	if (variant == 11) {
		main_body.statements.add (new CoreCallStatement (s, ctor, new GenericArray<CoreValue> (), new CoreStorageReceiverValue (s, storage, receiver.contract)));
	}
	main_body.statements.add (new CoreStore (s, local, new CoreNullPointerValue (s, c.semantic_type)));
	main_body.statements.add (new CoreReturn (s, new CoreIntegerValue (s, t.int_type, AstraIntValue.from_int64 (42))));
	var main = new CoreFunction (s, s, "main", t.int_type, new GenericArray<CoreParameter> (), locals, main_body);
	main.object_storage.add (storage);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (main);
	functions.add (ctor);
	functions.add (dtor);
	var program = new CoreProgram (s, functions);
	program.classes.add (c);
	return program;
}

private void valid() {
	try {
		CoreProgram? p = sample ();
		CoreVerifier.verify (p);
		assert (p.functions[1] is CoreConstructor && p.functions[2] is CoreDestructor && p.classes[0].methods.length == 0);
		assert (p.functions[0].object_storage[0].destructor == p.functions[2]);
		assert (CoreDump.format (p).contains ("(construct (storage #0) (constructor class #0)"));
		var witness = WeakRef (p.functions[1]);
		var storage = WeakRef (p.functions[0].object_storage[0]);
		p = null;
		assert (witness.get () == null && storage.get () == null);
	} catch (CoreError e) {
		GLib.error ("%s", e.message);
	}
}

private void invalid() {
	for (int i = 1; i <= 16; i++) {
		try {
			CoreVerifier.verify (sample (i));
		} catch (CoreError e) {
			Test.message ("variant %d: %s", i, e.message);
			continue;
		}
		GLib.error ("accepted malformed lifecycle Core %d", i);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/core/stage-owned-lifecycle-and-storage-authority", valid);
	Test.add_func ("/obj-life/core/reject-malformed-contracts-initialization-and-calls", invalid);
	return Test.run ();
}

}
