// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Sources {
private void composition() {
	try {
		foreach (string name in fixtures ()) {
			GenericArray<Witness> sources;
			CheckedProgram? program = fixture (name, out sources);
			assert (program.functions.length > 1);
			if (name == "objects") {
				foreach (var function in program.functions) {
					if (function.symbol.name == "inspect") {
						assert (function.symbol.parameters[0].semantic_type == program.classes[0].semantic_type);
						assert (function.symbol.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
					}
				}
			}
			program = null;
			foreach (var source in sources) {
				assert (source.get () == null);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void duplicates() {
	try {
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (Parser.parse (new SourceFile.from_text ("b.astra", "\nint helper() { return 2; }")).unit);
		units.add (Parser.parse (new SourceFile.from_text ("a.astra", "int helper() { return 1; }")).unit);
		var result = SemanticAnalyzer.analyze_program (new SyntaxProgram (units));
		assert (result.diagnostic.format () == "b.astra:2:5: error: duplicate function 'helper'; overloading is not implemented\nprevious declaration: a.astra:1:5");
	} catch (SourceSetError error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/semantic/global-universe-exact-contracts-syntax-destruction", composition);
	Test.add_func ("/sources/semantic/duplicate-declarations-both-source-locations", duplicates);
	return Test.run ();
}

}
