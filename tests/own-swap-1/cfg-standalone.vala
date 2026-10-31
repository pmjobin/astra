// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.OwnSwapCfg {
private CfgProgram model(int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("independent-exchange-cfg", "x"), 0, 1);
	var shape = new BufferValueShape (t.slice_of (t.f64_type), t.raw_pointer_type, t.i32_type);
	var cleanup = new CfgCleanupContract.for_buffer (shape, s, 0);
	var cleanups = new GenericArray<CfgCleanupContract> ();
	cleanups.add (cleanup);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (new CfgLocalPlace (s, s, "a", shape.slice_type, 0, false, cleanup));
	locals.add (new CfgLocalPlace (s, s, "b", shape.slice_type, 1, false, cleanup));
	var body = new CfgBlock.reserve (s, 0);
	var count = new CfgIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, variant == -1 ? 0 : 3));
	foreach (var slot in locals) {
		var allocation = new CfgBufferAllocate (s, count, cleanup);
		body.instructions.add (allocation);
		body.instructions.add (new CfgInitialize (s, slot, allocation.results.owner, slot));
	}
	var left = new CfgBufferSlotCapture (s, variant == 5 ? new CfgLocalPlace (s, s, "stale", shape.slice_type, 0, false, cleanup) : locals[0], cleanup);
	var right = new CfgBufferSlotCapture (s, locals[variant == -2 ? 0 : 1], variant == 4 ? new CfgCleanupContract.for_buffer (shape, s, 0) : cleanup);
	if (variant == 6) {
		body.instructions.add (new CfgOwnershipReleaseInstruction (s, locals[0], cleanup));
	}
	if (variant == 2) {
		body.instructions.add (right);
	}
	if (variant != 1) {
		body.instructions.add (left);
	}
	if (variant == 7) {
		body.instructions.add (new CfgOwnershipReleaseInstruction (s, locals[0], cleanup));
	}
	if (variant != 2) {
		body.instructions.add (right);
	}
	var exchange = new CfgBufferExchange (s, left, variant == 3 ? left : right);
	body.instructions.add (exchange);
	if (variant == 8) {
		body.instructions.add (new CfgBufferSlotCapture (s, locals[0], cleanup));
	}
	if (variant == 9) {
		body.instructions.add (new CfgBufferExchange (s, left, right));
	}
	for (int i = 1; i >= 0; i--) {
		body.instructions.add (new CfgCleanupInstruction (s, new CfgLoadValue (s, locals[i]), cleanup));
	}
	body.complete (s, new CfgFunctionEnd (s));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (body);
	var function = new CfgFunction (s, s, "exchange", t.void_type, 0, new GenericArray<CfgParameter> (), locals, blocks, body);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	return new CfgProgram (s, functions, null, null, null, cleanups);
}
private void verify(CfgProgram program) throws CfgError {
	CfgVerifier.verify (program);
	var flow = CfgFlowChecker.check (program);
	if (flow.diagnostic != null) {
		throw new CfgError.INVALID_CFG ("%s", flow.diagnostic.message);
	}
}
private void positive() {
	try {
		for (int variant = -2; variant <= 0; variant++) {
			CfgProgram? program = model (variant);
			verify (program);
			var function = WeakRef (program.functions[0]);
			program = null;
			assert (function.get () == null);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}
private void negative() {
	string[] reasons = {
		"each slot capture", "precede and dominate", "precede and dominate", "program-owned buffer cleanup", "function", "released", "invalidated before exchange", "orphan", "one exchange operand"
	};
	for (int variant = 1; variant <= reasons.length; variant++) {
		try {
			verify (model (variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			assert (error.message.contains (reasons[variant - 1]));
			continue;
		}
		GLib.error ("accepted malformed exchange CFG variant %d", variant);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-swap/cfg/independent-live-empty-self", positive);
	Test.add_func ("/own-swap/cfg/capture-membership-order-cleanup-liveness", negative);
	return Test.run ();
}
}
