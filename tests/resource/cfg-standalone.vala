// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Cfg;

namespace Astra.Tests.ResourceCfg {
private CfgProgram model(int variant = -1) throws GLib.Error {
	var file = new SourceFile.from_text ("resource-model", "ResourceA ResourceB");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	assert (types.resolve ("ResourceA") == null);
	var a = new HandleType ("ResourceA");
	var b = new HandleType (variant == 3 ? "ResourceA" : "ResourceB");
	assert (a != b && !a.is_void_pointer ());
	var cleanup = new CfgCleanupContract ("destroy", span, 0);
	var wrong = new CfgCleanupContract ("other_destroy", span, 1);
	var cleanups = new GenericArray<CfgCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (wrong);
	var handles = new GenericArray<CfgHandle> ();
	handles.add (new CfgHandle (span, span, a, cleanup, new CForeignHeader ("missing.h"), 0));
	handles.add (new CfgHandle (span, span, b, cleanup, null, 1));
	var imports = new GenericArray<CfgCFunction> ();
	imports.add (new CfgCFunction (span, span, "create", new CForeignMetadata ("create"), ForeignAbi.C, a, new GenericArray<SemanticType> (), 0, variant == 1 ? wrong : cleanup));
	var imported_parameters = new GenericArray<CfgParameter> ();
	imported_parameters.add (new CfgParameter (span, span, "r", a, 0, PointerParameterContract.BORROWED_NOESCAPE));
	var parameter_types = new GenericArray<SemanticType> ();
	parameter_types.add (a);
	imports.add (new CfgCFunction (span, span, "inspect", new CForeignMetadata ("inspect"), ForeignAbi.C, types.void_type, parameter_types, 1, null, imported_parameters));
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "r", variant == 5 ? b : a, 0, PointerParameterContract.BORROWED_NOESCAPE));
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (new CfgParameterValue (span, parameters[0]));
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
	var functions = new GenericArray<CfgFunction> ();
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (new CfgCCallInstruction (span, imports[1], arguments, null));
	block.complete (span, new CfgReturn (span, new CfgNullPointerValue (span, returned_type)));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	functions.add (new CfgFunction (span, span, "f", a, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions, imports, null, null, cleanups, handles);
}

private void valid() {
	try {
		var program = model ();
		CfgVerifier.verify (program);
		assert (program.handles[0].cleanup == program.handles[1].cleanup);
		assert (CfgDump.format (program).contains ("ResourceB"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void invalid() {
	for (int variant = 0; variant < 6; variant++) {
		try {
			CfgVerifier.verify (model (variant));
		} catch (GLib.Error error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed nominal handle model %d accepted", variant);
	}
}

private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/resource/cfg/standalone-valid", valid);
	Test.add_func ("/resource/cfg/standalone-reject-nominal-contract", invalid);
	return Test.run ();
}

}
