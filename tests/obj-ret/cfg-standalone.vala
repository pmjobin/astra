// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.ObjectResultCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("result", "c"), 0, 1);
	var c = new CfgClass (span, span, "C", new ClassType ("C"));
	var d = new CfgClass (span, span, "D", new ClassType ("D"), 1);
	var cleanup = new CfgCleanupContract.for_object (c, 0);
	var cleanups = new GenericArray<CfgCleanupContract> ();
	cleanups.add (cleanup);
	var ctor_block = new CfgBlock.reserve (span, 0);
	var ctor_blocks = new GenericArray<CfgBlock> ();
	ctor_blocks.add (ctor_block);
	ctor_block.complete (span, new CfgFunctionEnd (span));
	var ctor = new CfgConstructor (span, span, c, new CfgReceiver (span, new ReceiverType (c.semantic_type, ReceiverMode.INITIALIZING)), 0, t.void_type, 1, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), ctor_blocks, ctor_block);
	c.constructor = ctor;
	var block = new CfgBlock.reserve (span, 0);
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var f = new CfgFunction (span, span, "make", c.semantic_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, block, variant == 7 ? null : cleanup);
	var input = new CfgResultObjectStorage (span, variant == 3 ? d : c);
	if (variant != 1) {
		f.result_storage = input;
	}
	if (variant != 4 && variant < 20) {
		block.instructions.add (new CfgResultConstructionInstruction (span, ctor, input, new GenericArray<CfgValue> ()));
	}
	if (variant == 5) {
		block.instructions.add (new CfgResultConstructionInstruction (span, ctor, input, new GenericArray<CfgValue> ()));
	}
	CfgValue? producer = variant == 20 || variant == 6 ? null : input;
	if (variant == 22) {
		var value = new CfgCallResultValue (span, c.semantic_type);
		var call = new CfgCallInstruction (span, f, new GenericArray<CfgValue> (), value);
		call.result_storage = input;
		block.instructions.add (call);
		producer = value;
	}
	var capture = new CfgOwnedReturnValue (span, c.semantic_type, cleanup, null, producer, variant == 22 ? ObjectResultProvenance.FORWARDED_OWNED_RESULT : variant == 20 || variant == 6 ? ObjectResultProvenance.NULL : variant == 2 ? ObjectResultProvenance.CALLEE_LOCAL_STORAGE : ObjectResultProvenance.RESULT_STORAGE);
	block.instructions.add (new CfgOwnershipReturnInstruction (span, capture));
	block.complete (span, new CfgOwnershipReturn (span, capture));
	var functions = new GenericArray<CfgFunction> ();
	functions.add (f);
	functions.add (ctor);
	var p = new CfgProgram (span, functions, null, null, null, cleanups);
	p.classes.add (c);
	p.classes.add (d);
	return p;
}
private void valid() {
	try {
		foreach (int mode in new int[] { 0, 20, 22 }) {
			CfgProgram? p = sample (mode);
			CfgVerifier.verify (p);
			assert (p.functions[0].object_storage.length == 0);
			var witness = WeakRef (p.functions[0].result_storage);
			p = null;
			assert (witness.get () == null);
		}
	} catch (CfgError e) {
		GLib.error ("%s", e.message);
	}
}
private void malformed() {
	for (int v = 1; v <= 7; v++) {
		try {
			CfgVerifier.verify (sample (v));
		} catch (CfgError e) {
			Test.message ("%d: %s", v, e.message);
			continue;
		}
		GLib.error ("accepted malformed Cfg result %d", v);
	}
}
private CfgProgram acquisitions(bool shared) throws CfgError {
	var p = sample ();
	var span = p.span;
	var c = p.classes[0];
	var block = new CfgBlock.reserve (span, 0);
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var locals = new GenericArray<CfgLocalPlace> ();
	var caller = new CfgFunction (span, span, "caller", p.functions[1].return_type, 2, new GenericArray<CfgParameter> (), locals, blocks, block);
	for (int i = 0; i < 2; i++) {
		if (i == 0 || !shared) {
			var slot = new CfgObjectStorage (span, c, i, 0);
			slot.result_candidate = true;
			caller.object_storage.add (slot);
		}
		var owner = new CfgLocalPlace (span, span, "owner%d".printf (i), c.semantic_type, i, false, p.cleanups[0]);
		locals.add (owner);
		var value = new CfgCallResultValue (span, c.semantic_type);
		var call = new CfgCallInstruction (span, p.functions[0], new GenericArray<CfgValue> (), value);
		call.candidate_storage = caller.object_storage[shared ? 0 : i];
		block.instructions.add (call);
		block.instructions.add (new CfgInitialize (span, owner, value, owner));
	}
	for (int i = 1; i >= 0; i--) {
		block.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, locals[i]), p.cleanups[0]));
	}
	block.complete (span, new CfgReturn (span, null));
	p.functions.add (caller);
	return p;
}
private void candidate_identity() {
	try {
		CfgVerifier.verify (acquisitions (false));
	} catch (CfgError e) {
		GLib.error ("distinct candidates: %s", e.message);
	}
	try {
		CfgVerifier.verify (acquisitions (true));
	} catch (CfgError e) {
		Test.message ("%s", e.message);
		return;
	}
	GLib.error ("accepted two live acquisitions sharing one candidate");
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/cfg/fresh-null-and-input-lifetime-without-upstream", valid);
	Test.add_func ("/obj-ret/cfg/reject-storage-provenance-and-lifecycle-corruption", malformed);
	Test.add_func ("/obj-ret/cfg/candidate-storage-identity", candidate_identity);
	return Test.run ();
}
}
