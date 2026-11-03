// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.ObjectResultSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("result", "c"), 0, 1);
	var c = new SsaClass (span, span, "C", new ClassType ("C"));
	var d = new SsaClass (span, span, "D", new ClassType ("D"), 1);
	var cleanup = new SsaCleanupContract.for_object (c, 0);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	var ctor_block = new SsaBlock (span, 0, 0);
	var ctor_blocks = new GenericArray<SsaBlock> ();
	ctor_blocks.add (ctor_block);
	ctor_block.complete (new SsaFunctionEnd (span));
	var ctor = new SsaConstructor (span, span, c, new SsaReceiver (span, new ReceiverType (c.semantic_type, ReceiverMode.INITIALIZING), 0), 0, t.void_type, 1, new GenericArray<SsaFunctionParameter> (), ctor_blocks, ctor_block);
	c.constructor = ctor;
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var f = new SsaFunction (span, span, "make", c.semantic_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, block, variant == 7 ? null : cleanup);
	var input = new SsaResultObjectStorage (span, variant == 3 ? d : c);
	if (variant != 1) {
		f.result_storage = input;
	}
	if (variant != 4 && variant < 20) {
		block.instructions.add (new SsaResultConstructionInstruction (span, ctor, input, new GenericArray<SsaValue> ()));
	}
	if (variant == 5) {
		block.instructions.add (new SsaResultConstructionInstruction (span, ctor, input, new GenericArray<SsaValue> ()));
	}
	var value = variant == 20 || variant == 6 ? (SsaValue) new SsaNullPointerConstant (span, c.semantic_type) : input;
	if (variant == 22) {
		var call = new SsaCallInstruction (span, c.semantic_type, 0, f, new GenericArray<SsaValue> ());
		call.result_storage = input;
		call.owned_result_use = SsaOwnedResultUse.FORWARD;
		block.instructions.add (call);
		value = call.result;
	}
	block.complete (new SsaOwnershipReturn (span, value, variant == 22 ? ObjectResultProvenance.FORWARDED_OWNED_RESULT : variant == 20 || variant == 6 ? ObjectResultProvenance.NULL : variant == 2 ? ObjectResultProvenance.CALLEE_LOCAL_STORAGE : ObjectResultProvenance.RESULT_STORAGE));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (f);
	functions.add (ctor);
	var p = new SsaProgram (span, functions, null, null, null, cleanups);
	p.classes.add (c);
	p.classes.add (d);
	return p;
}

private void valid() {
	try {
		foreach (int mode in new int[] { 0, 20, 22 }) {
			SsaProgram? p = sample (mode);
			SsaVerifier.verify (p);
			assert (p.functions[0].object_storage.length == 0);
			var witness = WeakRef (p.functions[0].result_storage);
			p = null;
			assert (witness.get () == null);
		}
	} catch (SsaError e) {
		GLib.error ("%s", e.message);
	}
}

private void malformed() {
	for (int v = 1; v <= 7; v++) {
		try {
			SsaVerifier.verify (sample (v));
		} catch (SsaError e) {
			Test.message ("%d: %s", v, e.message);
			continue;
		}
		GLib.error ("accepted malformed Ssa result %d", v);
	}
}

private SsaProgram acquisitions(bool shared) throws SsaError {
	var p = sample ();
	var span = p.span;
	var c = p.classes[0];
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var caller = new SsaFunction (span, span, "caller", p.functions[1].return_type, 2, new GenericArray<SsaFunctionParameter> (), blocks, block);
	var owners = new GenericArray<SsaValue> ();
	for (int i = 0; i < 2; i++) {
		if (i == 0 || !shared) {
			var slot = new SsaObjectStorage (span, c, i, 0);
			slot.result_candidate = true;
			caller.object_storage.add (slot);
		}
		var call = new SsaCallInstruction (span, c.semantic_type, i, p.functions[0], new GenericArray<SsaValue> ());
		call.candidate_storage = caller.object_storage[shared ? 0 : i];
		call.owned_result_use = SsaOwnedResultUse.ACQUIRE;
		block.instructions.add (call);
		owners.add (call.result);
	}
	for (int i = 1; i >= 0; i--) {
		block.instructions.add (new SsaCleanupInstruction (span, owners[i], p.cleanups[0]));
	}
	block.complete (new SsaReturn (span, null));
	p.functions.add (caller);
	return p;
}

private void candidate_identity() {
	try {
		SsaVerifier.verify (acquisitions (false));
	} catch (SsaError e) {
		GLib.error ("distinct candidates: %s", e.message);
	}
	try {
		SsaVerifier.verify (acquisitions (true));
	} catch (SsaError e) {
		Test.message ("%s", e.message);
		return;
	}
	GLib.error ("accepted two live acquisitions sharing one candidate");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/ssa/fresh-null-and-input-lifetime-without-upstream", valid);
	Test.add_func ("/obj-ret/ssa/reject-storage-provenance-and-lifecycle-corruption", malformed);
	Test.add_func ("/obj-ret/ssa/candidate-storage-identity", candidate_identity);
	return Test.run ();
}

}
