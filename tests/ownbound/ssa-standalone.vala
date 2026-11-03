// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.OwnboundSsa {
private SsaProgram model(int variant = -1) throws GLib.Error {
	var file = new SourceFile.from_text ("boundary-model", "Resource");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var type = new HandleType ("Resource");
	assert (new BuiltinTypes ().resolve ("Resource") == null);
	var cleanup = new SsaCleanupContract ("destroy", span, 0);
	var wrong = new SsaCleanupContract ("wrong", span, 1);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var handles = new GenericArray<SsaHandle> ();
	handles.add (new SsaHandle (span, span, type, cleanup, null, 0));
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "r", variant == 0 ? (SemanticType) types.raw_pointer_type : type, 0, PointerParameterContract.OWNED_TRANSFER));
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var function = new SsaFunction (span, span, "recursive", type, 0, parameters, blocks, block, variant == 1 ? wrong : cleanup);
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (parameters[0]);
	var call = new SsaCallInstruction (span, type, 1, function, arguments);
	call.owned_result_use = variant == 2 ? SsaOwnedResultUse.NONE : SsaOwnedResultUse.ACQUIRE;
	if (variant != 3) {
		call.owned_arguments.add (new SsaOwnedArgument (span, parameters[0], parameters[0], variant == 4 ? wrong : cleanup, 0, variant == 5 ? null : new SsaNullPointerConstant (span, type)));
	}
	block.instructions.add (call);
	block.instructions.add (new SsaCleanupInstruction (span, new SsaNullPointerConstant (span, type), cleanup));
	if (variant == 6) {
		block.complete (new SsaReturn (span, call.result));
	} else {
		block.complete (new SsaOwnershipReturn (span, call.result));
	}
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	return new SsaProgram (span, functions, null, null, null, cleanups, handles);
}

private void valid() {
	try {
		var program = model ();
		SsaVerifier.verify (program);
		assert (SsaDump.format (program).contains ("owned-call-commit"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void invalid() {
	for (int variant = 0; variant < 7; variant++) {
		try {
			SsaVerifier.verify (model (variant));
		} catch (GLib.Error error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed SSA boundary %d accepted", variant);
	}
}

private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ownbound/ssa/standalone", valid);
	Test.add_func ("/ownbound/ssa/malformed", invalid);
	return Test.run ();
}

}
