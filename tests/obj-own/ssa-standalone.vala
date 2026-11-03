// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.ObjectOwnSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("owner", "c"), 0, 1);
	var c = new SsaClass (span, span, "C", new ClassType ("C"));
	var d = new SsaClass (span, span, "D", new ClassType ("D"), 1);
	var cleanup = new SsaCleanupContract.for_object (c, 0);
	var wrong = new SsaCleanupContract.for_object (d, 1);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var parameter = new SsaFunctionParameter (span, span, "c", c.semantic_type, 0, PointerParameterContract.OWNED_TRANSFER);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (parameter);
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var f = new SsaFunction (span, span, "forward", t.void_type, 0, parameters, blocks, block);
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (parameter);
	var call = new SsaCallInstruction (span, null, -1, f, arguments);
	if (variant != 1) {
		call.owned_arguments.add (new SsaOwnedArgument (span, parameter, parameter, variant == 2 ? wrong : cleanup, 0, variant == 3 ? null : new SsaNullPointerConstant (span, c.semantic_type)));
	}
	block.instructions.add (call);
	block.instructions.add (new SsaCleanupInstruction (span, new SsaNullPointerConstant (span, c.semantic_type), variant == 4 ? wrong : cleanup));
	block.complete (new SsaReturn (span, null));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (f);
	var p = new SsaProgram (span, functions, null, null, null, cleanups);
	p.classes.add (c);
	p.classes.add (d);
	return p;
}

private void valid() {
	try {
		SsaProgram? p = sample ();
		SsaVerifier.verify (p);
		assert (p.functions[0].object_storage.length == 0 && p.functions[0].storage.length == 0);
		assert (SsaDump.format (p).contains ("owned-call-commit"));
		var witness = WeakRef (p.classes[0]);
		p = null;
		assert (witness.get () == null);
	} catch (SsaError e) {
		GLib.error ("%s", e.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 4; variant++) {
		try {
			SsaVerifier.verify (sample (variant));
		} catch (SsaError e) {
			Test.message ("variant %d: %s", variant, e.message);
			continue;
		}
		GLib.error ("accepted malformed object SSA %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-own/ssa/one-pointer-exact-contract-and-source-null", valid);
	Test.add_func ("/obj-own/ssa/reject-missing-commit-and-wrong-class-cleanup", malformed);
	return Test.run ();
}

}
