// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.ObjectOwnCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("owner", "c"), 0, 1);
	var c = new CfgClass (span, span, "C", new ClassType ("C"));
	var d = new CfgClass (span, span, "D", new ClassType ("D"), 1);
	var cleanup = new CfgCleanupContract.for_object (c, 0);
	var wrong = new CfgCleanupContract.for_object (d, 1);
	var cleanups = new GenericArray<CfgCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var parameter = new CfgParameter (span, span, "c", c.semantic_type, 0, PointerParameterContract.OWNED_TRANSFER);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (parameter);
	var owner = new CfgLocalPlace (span, span, "c", c.semantic_type, 0, false, cleanup, parameter);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (owner);
	var block = new CfgBlock.reserve (span, 0);
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var f = new CfgFunction (span, span, "forward", t.void_type, 0, parameters, locals, blocks, block);
	if (variant != 1) {
		block.instructions.add (new CfgAcquireParameter (span, owner, parameter));
	}
	var pending = new CfgPendingOwnedArgument (span, parameter, variant == 4 ? wrong : cleanup, owner);
	block.instructions.add (new CfgOwnedArgumentCapture (span, pending));
	if (variant == 20) {
		block.instructions.add (new CfgEvaluateInstruction (span, new CfgLoadValue (span, owner), new CfgEvaluatedValue (span, c.semantic_type)));
	}
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (pending);
	var call = new CfgCallInstruction (span, f, arguments, null);
	var transfers = new GenericArray<CfgPendingOwnedArgument> ();
	transfers.add (pending);
	if (variant != 2) {
		block.instructions.add (new CfgOwnedCallTransferCommit (span, call, transfers));
	}
	if (variant == 3) {
		block.instructions.add (new CfgEvaluateInstruction (span, new CfgNullPointerValue (span, c.semantic_type), new CfgEvaluatedValue (span, c.semantic_type)));
	}
	block.instructions.add (call);
	if (variant != 5) {
		block.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, owner), cleanup));
	}
	block.complete (span, new CfgReturn (span, null));
	var functions = new GenericArray<CfgFunction> ();
	functions.add (f);
	var p = new CfgProgram (span, functions, null, null, null, cleanups);
	p.classes.add (c);
	p.classes.add (d);
	return p;
}

private void valid() {
	try {
		CfgProgram? p = sample ();
		CfgVerifier.verify (p);
		assert (CfgFlowChecker.check (p).diagnostic == null);
		assert (CfgDump.format (p).contains ("semantic-move") && CfgDump.format (p).contains ("owned-call-transfer-commit"));
		var witness = WeakRef (p.classes[0]);
		p = null;
		assert (witness.get () == null);
	} catch (CfgError e) {
		GLib.error ("%s", e.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 5; variant++) {
		try {
			var p = sample (variant);
			CfgVerifier.verify (p);
			CfgFlowChecker.check (p);
		} catch (CfgError e) {
			Test.message ("variant %d: %s", variant, e.message);
			continue;
		}
		GLib.error ("accepted malformed object CFG %d", variant);
	}
}

private void flow() {
	try {
		assert (CfgFlowChecker.check (sample (20)).diagnostic.message == "use of moved owned value 'c'");
	} catch (CfgError e) {
		GLib.error ("%s", e.message);
	}
	assert (OwnershipState.OWNED.definitely_owned () && !OwnershipState.MOVED.definitely_owned ());
	assert (OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED).may_own ());
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-own/cfg/pending-commit-and-cleanup-authority", valid);
	Test.add_func ("/obj-own/cfg/reject-incomplete-or-mismatched-transfer", malformed);
	Test.add_func ("/obj-own/ownership/shared-possibility-state-and-moved-use", flow);
	return Test.run ();
}

}
