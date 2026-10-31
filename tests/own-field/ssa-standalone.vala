// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.OwnedFieldSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("owned-field-ssa", "C"), 0, 1);
	var r = new HandleType ("R");
	var cleanup = new SsaCleanupContract ("release", s, 0);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	var handles = new GenericArray<SsaHandle> ();
	handles.add (new SsaHandle (s, s, r, cleanup, null, 0));
	var c = new SsaClass (s, s, "C", new ClassType ("C"));
	for (int i = 0; i < 3; i++) {
		c.fields.add (new SsaStructField (s, s, "r%d".printf (i), c, r, i));
	}
	var receiver = new SsaReceiver (s, new ReceiverType (c.semantic_type, ReceiverMode.INITIALIZING), 0);
	var body = new SsaBlock (s, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (body);
	foreach (var field in c.fields) {
		body.instructions.add (new SsaInitializeInstruction (s, new SsaIndirectFieldPlace (s, receiver, field), new SsaNullPointerConstant (s, r)));
	}
	body.complete (new SsaFunctionEnd (s));
	var ctor = new SsaConstructor (s, s, c, receiver, 3, t.void_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, body);
	c.constructor = ctor;
	var live = new SsaReceiver (s, new ReceiverType (c.semantic_type), 0);
	var dbody = new SsaBlock (s, 0, 0);
	var dblocks = new GenericArray<SsaBlock> ();
	dblocks.add (dbody);
	for (int i = 2; i >= 0; i--) {
		if (variant == 1 && i == 0) {
			continue;
		}
		var load = new SsaLoadInstruction (s, new SsaIndirectFieldPlace (s, live, c.fields[variant == 2 ? 2 - i : i]), 3 - i);
		dbody.instructions.add (load);
		dbody.instructions.add (new SsaCleanupInstruction (s, load.result, cleanup));
	}
	dbody.complete (new SsaFunctionEnd (s));
	var dtor = new SsaDestructor (s, s, c, live, 4, t.void_type, 1, new GenericArray<SsaFunctionParameter> (), dblocks, dbody);
	c.destructor = dtor;
	var functions = new GenericArray<SsaFunction> ();
	functions.add (ctor);
	functions.add (dtor);
	var program = new SsaProgram (s, functions, null, null, null, cleanups, handles);
	program.classes.add (c);
	return program;
}
private void valid() {
	try {
		SsaProgram? program = sample ();
		SsaVerifier.verify (program);
		assert (!SsaDump.format (program).contains ("owned-field"));
		var field = WeakRef (program.classes[0].fields[0]);
		program = null;
		assert (field.get () == null);
	} catch (SsaError e) {
		GLib.error ("%s", e.message);
	}
}
private void invalid() {
	for (int variant = 1; variant <= 2; variant++) {
		try {
			SsaVerifier.verify (sample (variant));
		} catch (SsaError e) {
			continue;
		}
		GLib.error ("accepted missing or reordered destructor cleanup %d", variant);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/ssa/standalone-concrete-handles-memory-and-direct-cleanup", valid);
	Test.add_func ("/own-field/ssa/missing-or-reordered-concrete-cleanup", invalid);
	return Test.run ();
}
}
