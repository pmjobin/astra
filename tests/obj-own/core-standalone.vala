// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.ObjectOwnCore {
private CoreProgram sample(int variant = 0) {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("owner", "c"), 0, 1);
	var c = new CoreClass (span, span, "C", new ClassType ("C"));
	var d = new CoreClass (span, span, "D", new ClassType ("D"), 1);
	var cleanup = new CoreCleanupContract.for_object (variant == 3 ? d : c, 0);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (cleanup);
	var parameter = new CoreParameter (span, span, "p", c.semantic_type, 0, PointerParameterContract.OWNED_TRANSFER);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (parameter);
	var sink_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var slot = new CoreLocalPlace (span, span, "p", c.semantic_type, 0, false, parameter);
	var sink_locals = new GenericArray<CoreLocalPlace> ();
	sink_locals.add (slot);
	var sink_owner = new CoreOwnedLocal (span, slot, cleanup, sink_body);
	sink_body.statements.add (new CoreAcquireParameter (span, sink_owner, parameter));
	var sink = new CoreFunction (span, span, "sink", t.void_type, parameters, sink_locals, sink_body);
	sink.owned_locals.add (sink_owner);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var local = new CoreLocalPlace (span, span, "c", c.semantic_type, 0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var storage = new CoreObjectStorage (span, c, 0, 0, body);
	storage.transferable = variant != 1;
	storage.cleanup_rank = 0;
	var owner = new CoreOwnedLocal (span, local, cleanup, body, variant == 4 ? null : storage);
	var construction = new CoreObjectConstruction (span, storage, local, new GenericArray<CoreObjectFieldInitializer> ());
	construction.acquisition = variant == 2 ? null : owner;
	body.statements.add (construction);
	if (variant == 5) {
		var alias = new CoreLocalPlace (span, span, "alias", c.semantic_type, 1);
		locals.add (alias);
		body.statements.add (new CoreInitialize (span, alias, new CoreLoadValue (span, local)));
	}
	if (variant == 6) {
		body.statements.add (new CoreStore (span, local, new CoreNullPointerValue (span, c.semantic_type)));
	}
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (span, parameter, cleanup, owner));
	body.statements.add (new CoreCallStatement (span, sink, arguments));
	var caller = new CoreFunction (span, span, "caller", t.void_type, new GenericArray<CoreParameter> (), locals, body);
	caller.object_storage.add (storage);
	if (variant != 7) {
		caller.owned_locals.add (owner);
	}
	var functions = new GenericArray<CoreFunction> ();
	functions.add (sink);
	functions.add (caller);
	var result = new CoreProgram (span, functions, null, null, null, cleanups);
	result.classes.add (c);
	result.classes.add (d);
	return result;
}
private void valid() {
	try {
		CoreProgram? p = sample ();
		CoreVerifier.verify (p);
		assert (p.cleanups[0].is_object && p.cleanups[0].destructor == null);
		assert (p.functions[1].owned_locals[0].object_storage == p.functions[1].object_storage[0]);
		assert (CoreDump.format (p).contains ("owned-transfer-argument"));
		var witness = WeakRef (p.classes[0]);
		p = null;
		assert (witness.get () == null);
	} catch (CoreError e) {
		GLib.error ("%s", e.message);
	}
}
private void malformed() {
	for (int variant = 1; variant <= 7; variant++) {
		try {
			CoreVerifier.verify (sample (variant));
		} catch (CoreError e) {
			Test.message ("variant %d: %s", variant, e.message);
			continue;
		}
		GLib.error ("accepted malformed transferable object %d", variant);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-own/core/exact-storage-responsibility-move-and-stage-lifetime", valid);
	Test.add_func ("/obj-own/core/reject-storage-contract-alias-and-rebind-corruption", malformed);
	return Test.run ();
}
}
