// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Cfg;

namespace Astra.Tests.OwnedFieldCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("owned-field-cfg", "C"), 0, 1);
	var r = new HandleType ("R");
	var cleanup = new CfgCleanupContract ("release", s, 0);
	var cleanups = new GenericArray<CfgCleanupContract> ();
	cleanups.add (cleanup);
	var handles = new GenericArray<CfgHandle> ();
	handles.add (new CfgHandle (s, s, r, cleanup, null, 0));
	var c = new CfgClass (s, s, "C", new ClassType ("C"));
	for (int i = 0; i < 3; i++) {
		c.fields.add (new CfgStructField (s, s, "r%d".printf (i), c, r, i));
	}
	var producer = new CfgCFunction (s, s, "make", new CForeignMetadata ("make"), ForeignAbi.C, r, new GenericArray<SemanticType> (), 0, cleanup);
	var imports = new GenericArray<CfgCFunction> ();
	imports.add (producer);
	var receiver = new CfgReceiver (s, new ReceiverType (c.semantic_type, ReceiverMode.INITIALIZING));
	var body = new CfgBlock.reserve (s, 0);
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (body);
	for (int i = 0; i < 3; i++) {
		var result = new CfgCallResultValue (s, r);
		body.instructions.add (new CfgCCallInstruction (s, producer, new GenericArray<CfgValue> (), result));
		var capture = new CfgResourceCapture (s, result, null, cleanup);
		body.instructions.add (capture);
		body.instructions.add (new CfgInitialize (s, new CfgIndirectFieldPlace (s, new CfgReceiverValue (s, receiver), c.fields[i]), capture.result));
	}
	body.complete (s, new CfgFunctionEnd (s));
	var ctor = new CfgConstructor (s, s, c, receiver, 3, t.void_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, body);
	c.constructor = ctor;
	var live = new CfgReceiver (s, new ReceiverType (c.semantic_type));
	var dbody = new CfgBlock.reserve (s, 0);
	var dblocks = new GenericArray<CfgBlock> ();
	dblocks.add (dbody);
	var destination = new CfgIndirectFieldPlace (s, new CfgReceiverValue (s, live), c.fields[0]);
	var result = new CfgCallResultValue (s, r);
	var old = new CfgCleanupInstruction (s, new CfgLoadValue (s, destination), cleanup);
	if (variant == 1) {
		dbody.instructions.add (old);
	}
	dbody.instructions.add (new CfgCCallInstruction (s, producer, new GenericArray<CfgValue> (), result));
	var capture = new CfgResourceCapture (s, result, null, cleanup);
	dbody.instructions.add (capture);
	if (variant != 1 && variant != 2) {
		dbody.instructions.add (old);
	}
	dbody.instructions.add (new CfgStore (s, destination, capture.result));
	if (variant == 5) {
		dbody.instructions.add (new CfgStore (s, destination, capture.result));
	}
	for (int i = 2; i >= 0; i--) {
		if (variant == 3 && i == 0) {
			continue;
		}
		var place = new CfgIndirectFieldPlace (s, new CfgReceiverValue (s, live), c.fields[variant == 4 ? 2 - i : i]);
		dbody.instructions.add (new CfgCleanupInstruction (s, new CfgLoadValue (s, place), cleanup));
	}
	dbody.complete (s, new CfgFunctionEnd (s));
	var dtor = new CfgDestructor (s, s, c, live, 4, t.void_type, 1, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), dblocks, dbody);
	c.destructor = dtor;
	var functions = new GenericArray<CfgFunction> ();
	functions.add (ctor);
	functions.add (dtor);
	var program = new CfgProgram (s, functions, imports, null, null, cleanups, handles);
	program.classes.add (c);
	return program;
}

private void valid() {
	try {
		CfgProgram? program = sample ();
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		assert (CfgDump.format (program).contains ("resource-capture"));
		var field = WeakRef (program.classes[0].fields[0]);
		program = null;
		assert (field.get () == null);
	} catch (CfgError e) {
		GLib.error ("%s", e.message);
	}
}

private void invalid() {
	for (int variant = 1; variant <= 5; variant++) {
		try {
			CfgVerifier.verify (sample (variant));
		} catch (CfgError e) {
			Test.message ("variant %d: %s", variant, e.message);
			continue;
		}
		GLib.error ("accepted malformed Resource CFG %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/cfg/concrete-capture-cleanup-store-and-destruction", valid);
	Test.add_func ("/own-field/cfg/reject-reordered-duplicated-and-missing-actions", invalid);
	return Test.run ();
}

}
