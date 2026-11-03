// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Ssa;

namespace Astra.Tests.ResourceSsa {
private SsaProgram model(int variant = -1) throws GLib.Error {
	var file = new SourceFile.from_text ("resource-model", "ResourceA ResourceB");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	assert (types.resolve ("ResourceA") == null);
	var a = new HandleType ("ResourceA");
	var b = new HandleType (variant == 3 ? "ResourceA" : "ResourceB");
	assert (a != b && !a.is_void_pointer ());
	var cleanup = new SsaCleanupContract ("destroy", span, 0);
	var wrong = new SsaCleanupContract ("other_destroy", span, 1);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var handles = new GenericArray<SsaHandle> ();
	handles.add (new SsaHandle (span, span, a, cleanup, new CForeignHeader ("missing.h"), 0));
	handles.add (new SsaHandle (span, span, b, cleanup, null, 1));
	var imports = new GenericArray<SsaCFunction> ();
	imports.add (new SsaCFunction (span, span, "create", new CForeignMetadata ("create"), ForeignAbi.C, a, new GenericArray<SemanticType> (), 0, variant == 1 ? wrong : cleanup));
	var imported_parameters = new GenericArray<SsaFunctionParameter> ();
	imported_parameters.add (new SsaFunctionParameter (span, span, "r", a, 0, PointerParameterContract.BORROWED_NOESCAPE));
	var parameter_types = new GenericArray<SemanticType> ();
	parameter_types.add (a);
	imports.add (new SsaCFunction (span, span, "inspect", new CForeignMetadata ("inspect"), ForeignAbi.C, types.void_type, parameter_types, 1, null, imported_parameters));
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "r", variant == 5 ? b : a, 0, PointerParameterContract.BORROWED_NOESCAPE));
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (parameters[0]);
	SemanticType returned_type = a;
	if (variant == 0) {
		returned_type = b;
	}
	if (variant == 2) {
		returned_type = new HandleType ("ResourceA");
	}
	if (variant == 4) {
		returned_type = types.raw_pointer_type;
	}
	var functions = new GenericArray<SsaFunction> ();
	var block = new SsaBlock (span, 0, 0);
	block.instructions.add (new SsaCCallInstruction (span, null, -1, imports[1], arguments));
	if (variant == 6 || variant == 7) {
		var join = new SsaBlock (span, 1, 1);
		var parameter = new SsaBlockParameter (span, span, "q", a, 1, 0);
		join.parameters.add (parameter);
		join.complete (new SsaReturn (span, parameter));
		var incoming = new GenericArray<SsaValue> ();
		incoming.add (new SsaNullPointerConstant (span, variant == 6 ? b : a));
		block.complete (new SsaBranch (span, new SsaEdge (join, incoming)));
		var phi_blocks = new GenericArray<SsaBlock> ();
		phi_blocks.add (block);
		phi_blocks.add (join);
		functions.add (new SsaFunction (span, span, "f", a, 0, parameters, phi_blocks, block));
		return new SsaProgram (span, functions, imports, null, null, cleanups, handles);
	}
	block.complete (new SsaReturn (span, new SsaNullPointerConstant (span, returned_type)));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	functions.add (new SsaFunction (span, span, "f", a, 0, parameters, blocks, block));
	return new SsaProgram (span, functions, imports, null, null, cleanups, handles);
}

private void valid() {
	try {
		SsaVerifier.verify (model (7));
		var program = model ();
		SsaVerifier.verify (program);
		assert (program.handles[0].cleanup == program.handles[1].cleanup);
		assert (SsaDump.format (program).contains ("ResourceB"));
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
		GLib.error ("malformed nominal handle model %d accepted", variant);
	}
}

private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/resource/ssa/standalone-valid", valid);
	Test.add_func ("/resource/ssa/standalone-reject-nominal-contract", invalid);
	return Test.run ();
}

}
