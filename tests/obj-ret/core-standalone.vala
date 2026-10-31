// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.ObjectResultCore {
private CoreProgram sample(int variant = 0) {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("result", "c"), 0, 1);
	var c = new CoreClass (span, span, "C", new ClassType ("C"));
	var d = new CoreClass (span, span, "D", new ClassType ("D"), 1);
	var cleanup = new CoreCleanupContract.for_object (c, 0);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (cleanup);
	var ctor = new CoreConstructor (span, span, c, new CoreReceiver (span, new ReceiverType (c.semantic_type, ReceiverMode.INITIALIZING)), 0, t.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), new CoreBlock (span, new GenericArray<CoreStatement> ()));
	c.constructor = ctor;
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var parameters = new GenericArray<CoreParameter> ();
	var locals = new GenericArray<CoreLocalPlace> ();
	var f = new CoreFunction (span, span, "make", c.semantic_type, parameters, locals, body, variant == 7 ? null : cleanup);
	var input = new CoreResultObjectStorage (span, variant == 3 ? d : c);
	if (variant != 1) {
		f.result_storage = input;
	}
	var fresh = new CoreOwnedObjectResultConstruction (span, variant == 4 ? new CoreResultObjectStorage (span, c) : input, ctor, new GenericArray<CoreValue> ());
	CoreOwnedLocal? source = null;
	if (variant == 6 || variant == 21) {
		var parameter = new CoreParameter (span, span, "c", c.semantic_type, 0, PointerParameterContract.OWNED_TRANSFER);
		parameters.add (parameter);
		var slot = new CoreLocalPlace (span, span, "c", c.semantic_type, 0, false, parameter);
		locals.add (slot);
		source = new CoreOwnedLocal (span, slot, cleanup, body);
		f.owned_locals.add (source);
		body.statements.add (new CoreAcquireParameter (span, source, parameter));
	}
	CoreValue? producer = variant >= 20 || variant == 6 ? null : fresh;
	if (variant == 22) {
		var call = new CoreCallValue (span, c.semantic_type, f, new GenericArray<CoreValue> ());
		call.result_storage = input;
		producer = call;
	}
	var provenance = variant == 2 ? ObjectResultProvenance.CALLEE_LOCAL_STORAGE : variant == 6 ? ObjectResultProvenance.BORROWED_STORAGE : variant == 20 ? ObjectResultProvenance.NULL : variant == 21 ? ObjectResultProvenance.OWNED_PARAMETER_STORAGE : variant == 22 ? ObjectResultProvenance.FORWARDED_OWNED_RESULT : ObjectResultProvenance.RESULT_STORAGE;
	if (variant == 5) {
		body.statements.add (new CoreReturn (span, new CoreNullPointerValue (span, c.semantic_type)));
	} else {
		body.statements.add (new CoreOwnershipReturn (span, c.semantic_type, cleanup, source, producer, provenance));
	}
	var functions = new GenericArray<CoreFunction> ();
	functions.add (f);
	functions.add (ctor);
	var p = new CoreProgram (span, functions, null, null, null, cleanups);
	p.classes.add (c);
	p.classes.add (d);
	return p;
}
private void valid() {
	try {
		foreach (int mode in new int[] { 0, 20, 21, 22 }) {
			CoreProgram? p = sample (mode);
			CoreVerifier.verify (p);
			assert (p.functions[0].object_storage.length == 0 && p.functions[0].result_contract == ResultOwnershipContract.OWNED_TRANSFER);
			var witness = WeakRef (p.functions[0].result_storage);
			p = null;
			assert (witness.get () == null);
		}
	} catch (CoreError e) {
		GLib.error ("%s", e.message);
	}
}
private void malformed() {
	for (int v = 1; v <= 7; v++) {
		try {
			CoreVerifier.verify (sample (v));
		} catch (CoreError e) {
			Test.message ("%d: %s", v, e.message);
			continue;
		}
		GLib.error ("accepted malformed Core result %d", v);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/core/fresh-null-and-parameter-without-upstream", valid);
	Test.add_func ("/obj-ret/core/reject-contract-provenance-constructor-and-storage-corruption", malformed);
	return Test.run ();
}
}
