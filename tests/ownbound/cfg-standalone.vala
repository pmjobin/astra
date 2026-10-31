// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.OwnboundCfg {
private CfgProgram model(int variant = -1) throws GLib.Error {
	var file = new SourceFile.from_text ("boundary-model", "Resource");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var type = new HandleType ("Resource");
	assert (new BuiltinTypes ().resolve ("Resource") == null);
	var cleanup = new CfgCleanupContract ("destroy", span, 0);
	var wrong = new CfgCleanupContract ("wrong", span, 1);
	var cleanups = new GenericArray<CfgCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var handles = new GenericArray<CfgHandle> ();
	handles.add (new CfgHandle (span, span, type, cleanup, null, 0));
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "r", variant == 0 ? (SemanticType) types.raw_pointer_type : type, 0, PointerParameterContract.OWNED_TRANSFER));
	var locals = new GenericArray<CfgLocalPlace> ();
	var owner = new CfgLocalPlace (span, span, "r", type, 0, false, cleanup, parameters[0]);
	var local = new CfgLocalPlace (span, span, "next", type, 1, false, cleanup);
	locals.add (owner);
	locals.add (local);
	var block = new CfgBlock.reserve (span, 0);
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var function = new CfgFunction (span, span, "pass", type, 0, parameters, locals, blocks, block, variant == 1 ? wrong : cleanup);
	if (variant != 2) {
		block.instructions.add (new CfgAcquireParameter (span, owner, parameters[0]));
	}
	if (variant == 20) {
		block.instructions.add (new CfgOwnershipReleaseInstruction (span, owner, cleanup));
	}
	var pending = new CfgPendingOwnedArgument (span, parameters[0], variant == 8 ? wrong : cleanup, owner);
	block.instructions.add (new CfgOwnedArgumentCapture (span, pending));
	if (variant == 6) {
		block.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, owner), cleanup));
	}
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (variant == 5 ? (CfgValue) new CfgNullPointerValue (span, type) : pending);
	var result = new CfgCallResultValue (span, type);
	var call = new CfgCallInstruction (span, function, arguments, result);
	var transfers = new GenericArray<CfgPendingOwnedArgument> ();
	transfers.add (pending);
	if (variant == 9) {
		transfers.add (pending);
	}
	if (variant != 3) {
		block.instructions.add (new CfgOwnedCallTransferCommit (span, call, transfers));
	}
	if (variant == 4) {
		block.instructions.add (new CfgEvaluateInstruction (span, new CfgNullPointerValue (span, type), new CfgEvaluatedValue (span, type)));
	}
	block.instructions.add (call);
	block.instructions.add (new CfgInitialize (span, local, result, variant == 7 ? null : local));
	var returned = new CfgOwnedReturnValue (span, type, variant == 10 ? wrong : cleanup, variant == 21 ? owner : local);
	block.instructions.add (new CfgOwnershipReturnInstruction (span, returned));
	block.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, local), cleanup));
	block.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, owner), cleanup));
	if (variant == 11) {
		block.complete (span, new CfgReturn (span, new CfgNullPointerValue (span, type)));
	} else {
		block.complete (span, new CfgOwnershipReturn (span, returned));
	}
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	return new CfgProgram (span, functions, null, null, null, cleanups, handles);
}
private void valid() {
	try {
		var program = model ();
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		assert (CfgDump.format (program).contains ("owned-call-transfer-commit"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void invalid() {
	for (int variant = 0; variant < 12; variant++) {
		try {
			CfgVerifier.verify (model (variant));
		} catch (GLib.Error error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed CFG boundary %d accepted", variant);
	}
}
private void flow() {
	try {
		assert (CfgFlowChecker.check (model (20)).diagnostic.message == "use of released owned value 'r'");
		assert (CfgFlowChecker.check (model (21)).diagnostic.message == "use of moved owned value 'r'");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cyclic() {
	try {
		var program = model ();
		var original = program.functions[0];
		var span = original.span;
		var owner = original.locals[0];
		var entry = new CfgBlock.reserve (span, 0);
		var loop = new CfgBlock.reserve (span, 1);
		var body = new CfgBlock.reserve (span, 2);
		var exit = new CfgBlock.reserve (span, 3);
		entry.instructions.add (new CfgAcquireParameter (span, owner, original.parameters[0]));
		entry.complete (span, new CfgBranch (span, loop));
		loop.complete (span, new CfgConditionalBranch (span, new CfgBooleanValue (span, new BuiltinTypes ().bool_type, BooleanLiteral.TRUE), body, exit));
		body.instructions.add (new CfgOwnershipReleaseInstruction (span, owner, owner.cleanup));
		body.complete (span, new CfgBranch (span, loop));
		exit.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, owner), owner.cleanup));
		exit.complete (span, new CfgReturn (span, null));
		var blocks = new GenericArray<CfgBlock> ();
		blocks.add (entry);
		blocks.add (loop);
		blocks.add (body);
		blocks.add (exit);
		var locals = new GenericArray<CfgLocalPlace> ();
		locals.add (owner);
		var function = new CfgFunction (span, span, "cyclic", new BuiltinTypes ().void_type, 0, original.parameters, locals, blocks, entry);
		program.functions.remove_index (0);
		program.functions.add (function);
		CfgVerifier.verify (program);
		var flow = OwnershipFlow.analyze (function);
		assert (flow.entry_state (body, owner) == OwnershipState.join (OwnershipState.OWNED, OwnershipState.RELEASED));
		assert (flow.diagnostic.message.contains ("may no longer own"));
		assert (flow.iterations > 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ownbound/cfg/standalone", valid);
	Test.add_func ("/ownbound/cfg/malformed", invalid);
	Test.add_func ("/ownbound/flow/parameter-call-return", flow);
	Test.add_func ("/ownbound/flow/cyclic-parameter", cyclic);
	return Test.run ();
}
}
