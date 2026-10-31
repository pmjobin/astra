// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.OwnboundCore {
private CoreProgram model(int variant = -1) {
	var file = new SourceFile.from_text ("boundary-model", "Resource");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var type = new HandleType ("Resource");
	assert (new BuiltinTypes ().resolve ("Resource") == null);
	var other = new HandleType ("Other");
	var cleanup = new CoreCleanupContract ("destroy", span, 0);
	var wrong = new CoreCleanupContract ("wrong", span, 1);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var handles = new GenericArray<CoreHandle> ();
	handles.add (new CoreHandle (span, span, type, cleanup, null, 0));
	handles.add (new CoreHandle (span, span, other, cleanup, null, 1));
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (span, span, "r", variant == 0 ? (SemanticType) types.raw_pointer_type : type, 0, PointerParameterContract.OWNED_TRANSFER));
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (new CoreLocalPlace (span, span, "r", type, 0, false, parameters[0]));
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var function = new CoreFunction (span, span, "pass", type, parameters, locals, body, variant == 1 ? wrong : cleanup);
	var owner = new CoreOwnedLocal (span, locals[0], cleanup, body);
	function.owned_locals.add (owner);
	if (variant != 2) {
		body.statements.add (new CoreAcquireParameter (span, owner, parameters[0]));
	}
	if (variant == 3) {
		body.statements.add (new CoreReturn (span, new CoreNullPointerValue (span, type)));
	} else {
		body.statements.add (new CoreOwnershipReturn (span, variant == 4 ? other : type, cleanup, owner));
	}
	var caller_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var caller = new CoreFunction (span, span, "caller", types.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), caller_body);
	var arguments = new GenericArray<CoreValue> ();
	if (variant == 5) {
		arguments.add (new CoreNullPointerValue (span, type));
	} else {
		arguments.add (new CoreOwnedArgumentValue (span, parameters[0], variant == 6 ? wrong : cleanup, null));
	}
	var place = new CoreLocalPlace (span, span, "result", type, 0);
	caller.locals.add (place);
	var acquired = new CoreOwnedLocal (span, place, cleanup, caller_body);
	caller.owned_locals.add (acquired);
	var call = new CoreCallValue (span, type, function, arguments);
	if (variant == 7) {
		caller_body.statements.add (new CoreCallStatement (span, function, arguments));
	}
	caller_body.statements.add (new CoreInitialize (span, place, call, acquired));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	functions.add (caller);
	return new CoreProgram (span, functions, null, null, null, cleanups, handles);
}
private void valid() {
	try {
		var program = model ();
		CoreVerifier.verify (program);
		assert (CoreDump.format (program).contains ("acquire-parameter"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void invalid() {
	for (int variant = 0; variant < 8; variant++) {
		try {
			CoreVerifier.verify (model (variant));
		} catch (GLib.Error error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed owned boundary %d accepted", variant);
	}
}
private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ownbound/core/standalone", valid);
	Test.add_func ("/ownbound/core/malformed", invalid);
	return Test.run ();
}
}
