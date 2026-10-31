// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.LifecycleSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("lifecycle", "C"), 0, 1);
	var c = new SsaClass (s, s, "C", new ClassType ("C"));
	var field = new SsaStructField (s, s, "x", c, t.int_type, 0);
	c.fields.add (field);
	var receiver = new SsaReceiver (s, new ReceiverType (c.semantic_type, variant == 1 ? ReceiverMode.LIVE : ReceiverMode.INITIALIZING), 0);
	var cb = new SsaBlock (s, 0, 0);
	var cblocks = new GenericArray<SsaBlock> ();
	cblocks.add (cb);
	var field_place = new SsaIndirectFieldPlace (s, receiver, field);
	if (variant == 11) {
		field_place = new SsaIndirectFieldPlace (s, receiver, new SsaStructField (s, s, "forged", c, t.int_type, 77));
	}
	if (variant == 4 || variant == 11) {
		cb.instructions.add (new SsaLoadInstruction (s, field_place, 1));
	}
	if (variant != 2) {
		cb.instructions.add (new SsaInitializeInstruction (s, field_place, new SsaIntegerConstant (s, t.int_type, AstraIntValue.from_int64 (42))));
	}
	if (variant == 3) {
		cb.instructions.add (new SsaInitializeInstruction (s, new SsaIndirectFieldPlace (s, receiver, field), new SsaIntegerConstant (s, t.int_type, AstraIntValue.from_int64 (42))));
	}
	cb.complete (variant == 10 ? (SsaTerminator) new SsaReturn (s, null) : new SsaFunctionEnd (s));
	var ctor = new SsaConstructor (s, s, c, receiver, 1, t.void_type, 1, new GenericArray<SsaFunctionParameter> (), cblocks, cb);
	c.constructor = ctor;
	var live = new SsaReceiver (s, new ReceiverType (c.semantic_type), 0);
	var db = new SsaBlock (s, 0, 0);
	db.complete (new SsaFunctionEnd (s));
	var dblocks = new GenericArray<SsaBlock> ();
	dblocks.add (db);
	var dtor = new SsaDestructor (s, s, c, live, 2, t.void_type, 2, new GenericArray<SsaFunctionParameter> (), dblocks, db);
	c.destructor = dtor;
	var mb = new SsaBlock (s, 0, 0);
	var mblocks = new GenericArray<SsaBlock> ();
	mblocks.add (mb);
	var storage = new SsaObjectStorage (s, c, 0, 0);
	storage.cleanup_rank = variant == 12 ? -1 : 0;
	var ca = new SsaStorageReceiverInstruction (s, storage, receiver.contract, 0);
	mb.instructions.add (ca);
	var da = new SsaStorageReceiverInstruction (s, storage, live.contract, 1);
	mb.instructions.add (da);
	var cref = ca.result;
	var dref = da.result;
	var publication = new SsaObjectReferenceInstruction (s, storage, 2);
	if (variant == 5) {
		mb.instructions.add (new SsaLifecycleCallInstruction (s, dtor, storage, new GenericArray<SsaValue> (), dref));
	}
	if (variant == 8) {
		mb.instructions.add (publication);
	}
	var call = new SsaLifecycleCallInstruction (s, ctor, storage, new GenericArray<SsaValue> (), cref);
	mb.instructions.add (call);
	if (variant == 9) {
		mb.instructions.add (new SsaLifecycleCallInstruction (s, ctor, storage, new GenericArray<SsaValue> (), cref));
	}
	if (variant != 8) {
		mb.instructions.add (publication);
	}
	if (variant != 6) {
		mb.instructions.add (new SsaLifecycleCallInstruction (s, dtor, storage, new GenericArray<SsaValue> (), dref));
	}
	if (variant == 7) {
		mb.instructions.add (new SsaLifecycleCallInstruction (s, dtor, storage, new GenericArray<SsaValue> (), dref));
	}
	mb.complete (new SsaReturn (s, new SsaIntegerConstant (s, t.int_type, AstraIntValue.from_int64 (42))));
	var main = new SsaFunction (s, s, "main", t.int_type, 0, new GenericArray<SsaFunctionParameter> (), mblocks, mb);
	main.object_storage.add (storage);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (main);
	functions.add (ctor);
	functions.add (dtor);
	var program = new SsaProgram (s, functions);
	program.classes.add (c);
	return program;
}
private void valid() {
	try {
		SsaProgram? p = sample ();
		SsaVerifier.verify (p);
		assert (p.functions[1] is SsaConstructor && p.functions[2] is SsaDestructor && p.classes[0].methods.length == 0);
		assert (SsaDump.format (p).contains ("object-deinit"));
		var witness = WeakRef (p.functions[1]);
		var storage = WeakRef (p.functions[0].object_storage[0]);
		p = null;
		assert (witness.get () == null && storage.get () == null);
	} catch (SsaError e) {
		GLib.error ("%s", e.message);
	}
}
private void invalid() {
	for (int i = 1; i <= 12; i++) {
		try {
			SsaVerifier.verify (sample (i));
		} catch (SsaError e) {
			Test.message ("variant %d: %s", i, e.message);
			continue;
		}
		GLib.error ("accepted malformed lifecycle Ssa %d", i);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/ssa/independent-lifecycle-initialization-and-cleanup", valid);
	Test.add_func ("/obj-life/ssa/reject-uninitialized-double-premature-and-missing-cleanup", invalid);
	return Test.run ();
}
}
