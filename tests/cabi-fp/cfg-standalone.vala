// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Cfg;
namespace Astra.Tests.CAbiFpCfg {
private CfgProgram sample(bool wide, int bad = 0) throws GLib.Error {
	var types = new BuiltinTypes ();
	SemanticType type = wide ? (SemanticType) types.f64_type : types.f32_type;
	SemanticType other = wide ? (SemanticType) types.f32_type : types.f64_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "foreign"), 0, 7);
	var parameter_types = new GenericArray<SemanticType> ();
	parameter_types.add (bad == 3 ? new SemanticType (type.kind) : type);
	var imported = new CfgCFunction (span, span, "echo", new CForeignMetadata ("c_echo"), ForeignAbi.C, type, parameter_types, 0);
	var imports = new GenericArray<CfgCFunction> ();
	imports.add (imported);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "value", bad == 1 ? other : type, 0));
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (new CfgParameterValue (span, parameters[0]));
	var functions = new GenericArray<CfgFunction> ();
	var result_type = bad == 2 ? other : type;

	var result = new CfgCallResultValue (span, result_type);
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (new CfgCCallInstruction (span, imported, arguments, result));
	block.complete (span, new CfgReturn (span, result));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	functions.add (new CfgFunction (span, span, "bridge", type, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));

	var exports = new GenericArray<CfgCExport> ();
	exports.add (new CfgCExport (span, span, functions[0], "bridge", ForeignAbi.C, 0));
	return new CfgProgram (span, functions, imports, exports);
}
private void boundary() {
	try {
		for (int width = 0; width < 2; width++) {
			CfgProgram? program = sample (width == 1);
			CfgVerifier.verify (program);
			string dump = CfgDump.format (program);
			assert (dump.contains (width == 1 ? "f64" : "f32") && dump.contains ("c-call"));
			var reference = WeakRef (program.c_functions[0]);
			program = null;
			assert (reference.get () == null);
			for (int bad = 1; bad <= 3; bad++) {
				bool rejected = false;
				try {
					CfgVerifier.verify (sample (width == 1, bad));
				} catch (GLib.Error error) {
					rejected = true;
				}
				assert (rejected);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/cabi-fp/cfg/independent-import-export-exact-width-lifetime", boundary);
	return Test.run ();
}
}
