// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Core;
namespace Astra.Tests.CAbiFpCore {
private CoreProgram sample(bool wide, int bad = 0) throws GLib.Error {
	var types = new BuiltinTypes ();
	SemanticType type = wide ? (SemanticType) types.f64_type : types.f32_type;
	SemanticType other = wide ? (SemanticType) types.f32_type : types.f64_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "foreign"), 0, 7);
	var parameter_types = new GenericArray<SemanticType> ();
	parameter_types.add (bad == 3 ? new SemanticType (type.kind) : type);
	var imported = new CoreCFunction (span, span, "echo", new CForeignMetadata ("c_echo"), ForeignAbi.C, type, parameter_types, 0);
	var imports = new GenericArray<CoreCFunction> ();
	imports.add (imported);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (span, span, "value", bad == 1 ? other : type, 0));
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreParameterValue (span, parameters[0]));
	var functions = new GenericArray<CoreFunction> ();
	var result_type = bad == 2 ? other : type;

	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreReturn (span, new CoreCCallValue (span, result_type, imported, arguments)));
	functions.add (new CoreFunction (span, span, "bridge", type, parameters, new GenericArray<CoreLocalPlace> (), new CoreBlock (span, statements)));

	var exports = new GenericArray<CoreCExport> ();
	exports.add (new CoreCExport (span, span, functions[0], "bridge", ForeignAbi.C, 0));
	return new CoreProgram (span, functions, imports, exports);
}

private void boundary() {
	try {
		for (int width = 0; width < 2; width++) {
			CoreProgram? program = sample (width == 1);
			CoreVerifier.verify (program);
			string dump = CoreDump.format (program);
			assert (dump.contains (width == 1 ? "f64" : "f32") && dump.contains ("c-call"));
			var reference = WeakRef (program.c_functions[0]);
			program = null;
			assert (reference.get () == null);
			for (int bad = 1; bad <= 3; bad++) {
				bool rejected = false;
				try {
					CoreVerifier.verify (sample (width == 1, bad));
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
	Test.add_func ("/cabi-fp/core/independent-import-export-exact-width-lifetime", boundary);
	return Test.run ();
}

}
