// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.OwnSwapCore {
private CoreProgram model(int variant = 0) {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("independent-exchange-core", "x"), 0, 1);
	var shape = new BufferValueShape (t.slice_of (t.f64_type), t.raw_pointer_type, t.i32_type);
	var cleanup = new CoreCleanupContract.for_buffer (shape, s, 0);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (cleanup);
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (new CoreLocalPlace (s, s, "a", shape.slice_type, 0));
	locals.add (new CoreLocalPlace (s, s, "b", shape.slice_type, 1));
	var a = new CoreOwnedLocal (s, locals[0], cleanup, body);
	var b = new CoreOwnedLocal (s, locals[1], cleanup, body);
	var count = new CoreIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, variant == -1 ? 0 : 3));
	body.statements.add (new CoreInitialize (s, a.place, new CoreOwnedBufferAllocate (s, shape.slice_type, count, cleanup), a));
	if (variant != 5) {
		body.statements.add (new CoreInitialize (s, b.place, new CoreOwnedBufferAllocate (s, shape.slice_type, count, cleanup), b));
	}
	if (variant == 6 || variant == 7) {
		body.statements.add (new CoreOwnershipRelease (s, variant == 6 ? a : b, cleanup));
	}
	var foreign = new BuiltinTypes ();
	var stale = new CoreLocalPlace (s, s, "stale", variant == 2 ? foreign.slice_of (foreign.f64_type) : shape.slice_type, 0);
	var left = new CoreBufferOwnerSlot (s, variant == 1 || variant == 2 ? stale : a.place, variant == 3 ? new CoreOwnedLocal (s, a.place, cleanup, body) : a, variant == 4 ? new CoreCleanupContract.for_buffer (shape, s, 0) : cleanup);
	var right = new CoreBufferOwnerSlot (s, variant == -2 ? a.place : b.place, variant == -2 ? a : b, cleanup);
	body.statements.add (new CoreOwnedBufferExchange (s, left, right));
	var function = new CoreFunction (s, s, "exchange", t.void_type, new GenericArray<CoreParameter> (), locals, body);
	function.owned_locals.add (a);
	function.owned_locals.add (b);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	return new CoreProgram (s, functions, null, null, null, cleanups);
}
private void positive() {
	try {
		for (int variant = -2; variant <= 0; variant++) {
			CoreProgram? program = model (variant);
			CoreVerifier.verify (program);
			var function = WeakRef (program.functions[0]);
			program = null;
			assert (function.get () == null);
		}
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}
private void negative() {
	string[] reasons = {
		"identity mismatch", "cleanup authority", "identity mismatch", "cleanup authority", "initializ", "RELEASED", "RELEASED"
	};
	for (int variant = 1; variant <= reasons.length; variant++) {
		try {
			CoreVerifier.verify (model (variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			assert (error.message.contains (reasons[variant - 1]));
			continue;
		}
		GLib.error ("accepted malformed exchange Core variant %d", variant);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-swap/core/independent-live-empty-self", positive);
	Test.add_func ("/own-swap/core/stale-universe-owner-cleanup-dead", negative);
	return Test.run ();
}
}
