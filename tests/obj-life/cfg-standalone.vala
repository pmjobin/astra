// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.LifecycleCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("lifecycle", "C"), 0, 1);
	var c = new CfgClass (s, s, "C", new ClassType ("C"));
	var field = new CfgStructField (s, s, "x", c, t.int_type, 0);
	c.fields.add (field);
	var receiver = new CfgReceiver (s, new ReceiverType (c.semantic_type, variant == 1 ? ReceiverMode.LIVE : ReceiverMode.INITIALIZING));
	var cb = new CfgBlock.reserve (s, 0);
	var cblocks = new GenericArray<CfgBlock> ();
	cblocks.add (cb);
	var field_place = new CfgIndirectFieldPlace (s, new CfgReceiverValue (s, receiver), field);
	if (variant == 11) {
		field_place = new CfgIndirectFieldPlace (s, new CfgReceiverValue (s, receiver), new CfgStructField (s, s, "forged", c, t.int_type, 77));
	}
	if (variant == 4 || variant == 11) {
		var loaded = new CfgEvaluatedValue (s, t.int_type);
		cb.instructions.add (new CfgEvaluateInstruction (s, new CfgLoadValue (s, field_place), loaded));
	}
	if (variant != 2) {
		cb.instructions.add (new CfgInitialize (s, field_place, new CfgIntegerValue (s, t.int_type, AstraIntValue.from_int64 (42))));
	}
	if (variant == 3) {
		cb.instructions.add (new CfgInitialize (s, new CfgIndirectFieldPlace (s, new CfgReceiverValue (s, receiver), field), new CfgIntegerValue (s, t.int_type, AstraIntValue.from_int64 (42))));
	}
	if (variant == 13) {
		var expired = new CfgBlock.reserve (s, 77);
		cb.complete (s, new CfgConditionalBranch (s, new CfgBooleanValue (s, t.bool_type, BooleanLiteral.TRUE), expired, cb));
	} else {
		cb.complete (s, variant == 10 ? (CfgTerminator) new CfgReturn (s, null) : new CfgFunctionEnd (s));
	}
	var ctor = new CfgConstructor (s, s, c, receiver, 1, t.void_type, 1, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), cblocks, cb);
	c.constructor = ctor;
	var live = new CfgReceiver (s, new ReceiverType (c.semantic_type));
	var db = new CfgBlock.reserve (s, 0);
	db.complete (s, new CfgFunctionEnd (s));
	var dblocks = new GenericArray<CfgBlock> ();
	dblocks.add (db);
	var dtor = new CfgDestructor (s, s, c, live, 2, t.void_type, 2, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), dblocks, db);
	c.destructor = dtor;
	var mb = new CfgBlock.reserve (s, 0);
	var mblocks = new GenericArray<CfgBlock> ();
	mblocks.add (mb);
	var storage = new CfgObjectStorage (s, c, 0, 0);
	storage.cleanup_rank = variant == 12 ? -1 : 0;
	var reference = new CfgEvaluatedValue (s, c.semantic_type);
	var publication = new CfgEvaluateInstruction (s, new CfgObjectReferenceValue (s, storage), reference);
	if (variant == 5) {
		mb.instructions.add (new CfgLifecycleCallInstruction (s, dtor, storage, new GenericArray<CfgValue> ()));
	}
	if (variant == 8) {
		mb.instructions.add (publication);
	}
	var call = new CfgLifecycleCallInstruction (s, ctor, storage, new GenericArray<CfgValue> ());
	mb.instructions.add (call);
	if (variant == 9) {
		mb.instructions.add (new CfgLifecycleCallInstruction (s, ctor, storage, new GenericArray<CfgValue> ()));
	}
	if (variant != 8) {
		mb.instructions.add (publication);
	}
	if (variant != 6) {
		mb.instructions.add (new CfgLifecycleCallInstruction (s, dtor, storage, new GenericArray<CfgValue> ()));
	}
	if (variant == 7) {
		mb.instructions.add (new CfgLifecycleCallInstruction (s, dtor, storage, new GenericArray<CfgValue> ()));
	}
	mb.complete (s, new CfgReturn (s, new CfgIntegerValue (s, t.int_type, AstraIntValue.from_int64 (42))));
	var main = new CfgFunction (s, s, "main", t.int_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), mblocks, mb);
	main.object_storage.add (storage);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (main);
	functions.add (ctor);
	functions.add (dtor);
	var program = new CfgProgram (s, functions);
	program.classes.add (c);
	return program;
}

private void valid() {
	try {
		CfgProgram? p = sample ();
		CfgVerifier.verify (p);
		assert (p.functions[1] is CfgConstructor && p.functions[2] is CfgDestructor && p.classes[0].methods.length == 0);
		assert (CfgDump.format (p).contains ("object-deinit"));
		var witness = WeakRef (p.functions[1]);
		var storage = WeakRef (p.functions[0].object_storage[0]);
		p = null;
		assert (witness.get () == null && storage.get () == null);
	} catch (CfgError e) {
		GLib.error ("%s", e.message);
	}
}

private void invalid() {
	for (int i = 1; i <= 13; i++) {
		try {
			CfgVerifier.verify (sample (i));
		} catch (CfgError e) {
			Test.message ("variant %d: %s", i, e.message);
			continue;
		}
		GLib.error ("accepted malformed lifecycle Cfg %d", i);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/cfg/independent-lifecycle-initialization-and-cleanup", valid);
	Test.add_func ("/obj-life/cfg/reject-uninitialized-double-premature-and-missing-cleanup", invalid);
	return Test.run ();
}

}
