// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Core;

namespace Astra.Tests.OwnedFieldCore {
private CoreProgram sample(int variant = 0) {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("owned-field-core", "C"), 0, 1);
	var r = new HandleType ("R");
	var cleanup = new CoreCleanupContract ("release", s, 0);
	var wrong = new CoreCleanupContract ("wrong", s, 1);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var handles = new GenericArray<CoreHandle> ();
	handles.add (new CoreHandle (s, s, r, cleanup, null, 0));
	var c = new CoreClass (s, s, "C", new ClassType ("C"));
	for (int i = 0; i < 3; i++) {
		var field = new CoreStructField (s, s, "r%d".printf (i), c, variant == 1 && i == 0 ? t.int_type : (SemanticType) r, i);
		field.owned_cleanup = variant == 2 && i == 0 ? wrong : cleanup;
		c.fields.add (field);
	}
	var producer = new CoreCFunction (s, s, "make", new CForeignMetadata ("make"), ForeignAbi.C, r, new GenericArray<SemanticType> (), 0, cleanup);
	var imports = new GenericArray<CoreCFunction> ();
	imports.add (producer);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (s, s, "r", r, 0, PointerParameterContract.BORROWED_NOESCAPE));
	var parameter_types = new GenericArray<SemanticType> ();
	parameter_types.add (r);
	var use = new CoreCFunction (s, s, "use", new CForeignMetadata ("use"), ForeignAbi.C, t.void_type, parameter_types, 1, null, parameters);
	imports.add (use);
	var receiver = new CoreReceiver (s, new ReceiverType (c.semantic_type, ReceiverMode.INITIALIZING));
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var ctor = new CoreConstructor (s, s, c, receiver, 3, t.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body);
	c.constructor = ctor;
	for (int i = 0; i < 3; i++) {
		if (variant == 3 && i == 0) {
			continue;
		}
		var destination = new CoreIndirectFieldPlace (s, new CoreReceiverValue (s, receiver), c.fields[i]);
		var value = new CoreCCallValue (s, r, producer, new GenericArray<CoreValue> ());
		if (variant == 12 && i == 0) {
			var arguments = new GenericArray<CoreValue> ();
			arguments.add (new CoreOwnedFieldBorrow (s, destination, parameters[0]));
			body.statements.add (new CoreCCallStatement (s, use, arguments));
		}
		if (variant == 8 && i == 0) {
			body.statements.add (new CoreFieldInitialize (s, destination, value));
			continue;
		}
		body.statements.add (new CoreOwnedFieldTransfer (s, destination, cleanup, null, variant == 7 ? (CoreValue) new CoreNullPointerValue (s, r) : value, variant != 6));
		if (variant == 4 && i == 0) {
			body.statements.add (new CoreOwnedFieldTransfer (s, destination, cleanup, null, value, true));
		}
	}
	var live = new CoreReceiver (s, new ReceiverType (c.semantic_type));
	var dbody = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var dtor = new CoreDestructor (s, s, c, live, 4, t.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), dbody);
	c.destructor = dtor;
	for (int i = 2; i >= 0; i--) {
		if (variant == 5 && i == 0) {
			continue;
		}
		dtor.field_cleanups.add (new CoreOwnedFieldCleanup (s, c.fields[variant == 9 ? 2 - i : i], variant == 10 ? wrong : cleanup));
	}
	if (variant == 11) {
		var destination = new CoreIndirectFieldPlace (s, new CoreReceiverValue (s, live), c.fields[0]);
		dbody.statements.add (new CoreStore (s, destination, new CoreNullPointerValue (s, r)));
	}
	if (variant == 13) {
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (new CoreLoadValue (s, new CoreIndirectFieldPlace (s, new CoreReceiverValue (s, live), c.fields[0])));
		dbody.statements.add (new CoreCCallStatement (s, use, arguments));
	}
	var functions = new GenericArray<CoreFunction> ();
	functions.add (ctor);
	functions.add (dtor);
	var program = new CoreProgram (s, functions, imports, null, null, cleanups, handles);
	program.classes.add (c);
	return program;
}
private void valid() {
	try {
		CoreProgram? program = sample ();
		CoreVerifier.verify (program);
		assert (CoreDump.format (program).contains ("owned-field-cleanup"));
		var field = WeakRef (program.classes[0].fields[0]);
		program = null;
		assert (field.get () == null);
	} catch (CoreError e) {
		GLib.error ("%s", e.message);
	}
}
private void invalid() {
	for (int variant = 1; variant <= 13; variant++) {
		try {
			CoreVerifier.verify (sample (variant));
		} catch (CoreError e) {
			Test.message ("variant %d: %s", variant, e.message);
			continue;
		}
		GLib.error ("accepted malformed owned field Core %d", variant);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/core/independent-contract-and-cleanup-lifetime", valid);
	Test.add_func ("/own-field/core/malformed-type-init-source-order-cleanup", invalid);
	return Test.run ();
}
}
