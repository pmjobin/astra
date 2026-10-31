// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Ssa;
namespace Astra.Tests.CAbiFpSsa {
private SsaProgram sample(bool wide, int bad = 0) throws GLib.Error {
	var types = new BuiltinTypes ();
	SemanticType type = wide ? (SemanticType) types.f64_type : types.f32_type;
	SemanticType other = wide ? (SemanticType) types.f32_type : types.f64_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "foreign"), 0, 7);
	var parameter_types = new GenericArray<SemanticType> ();
	parameter_types.add (bad == 3 ? new SemanticType (type.kind) : type);
	var imported = new SsaCFunction (span, span, "echo", new CForeignMetadata ("c_echo"), ForeignAbi.C, type, parameter_types, 0);
	var imports = new GenericArray<SsaCFunction> ();
	imports.add (imported);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "value", bad == 1 ? other : type, 0));
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (parameters[0]);
	var functions = new GenericArray<SsaFunction> ();
	var result_type = bad == 2 ? other : type;

	var call = new SsaCCallInstruction (span, result_type, 1, imported, arguments);
	var block = new SsaBlock (span, 0, 0);
	block.instructions.add (call);
	block.complete (new SsaReturn (span, call.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	functions.add (new SsaFunction (span, span, "bridge", type, 0, parameters, blocks, block));

	var exports = new GenericArray<SsaCExport> ();
	exports.add (new SsaCExport (span, span, functions[0], "bridge", ForeignAbi.C, 0));
	return new SsaProgram (span, functions, imports, exports);
}
private void boundary() {
	try {
		for (int width = 0; width < 2; width++) {
			SsaProgram? program = sample (width == 1);
			SsaVerifier.verify (program);
			string dump = SsaDump.format (program);
			assert (dump.contains (width == 1 ? "f64" : "f32") && dump.contains ("c-call"));
			var reference = WeakRef (program.c_functions[0]);
			program = null;
			assert (reference.get () == null);
			for (int bad = 1; bad <= 3; bad++) {
				bool rejected = false;
				try {
					SsaVerifier.verify (sample (width == 1, bad));
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
	Test.add_func ("/cabi-fp/ssa/independent-import-export-exact-width-lifetime", boundary);
	return Test.run ();
}
}
