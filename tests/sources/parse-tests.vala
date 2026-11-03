// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.SourcesParser {
private void composition() {
	try {
		var units = new GenericArray<CompilationUnitSyntax> ();
		var b = Parser.parse (new SourceFile.from_text ("sub/b.astra", "\nint b() { return a(); }"));
		var a = Parser.parse (new SourceFile.from_text ("./a.astra", "int a() { return 42; }"));
		assert (a.diagnostic == null && b.diagnostic == null);
		units.add (b.unit);
		units.add (a.unit);
		var program = new SyntaxProgram (units);
		assert (program.units[0] == a.unit && program.units[1] == b.unit);
		assert (program.functions[0] == a.unit.functions[0] && program.functions[1] == b.unit.functions[0]);
		assert (program.functions[1].span.file == b.unit.span.file && program.functions[1].span.start == 1);
		int line;
		int column;
		b.unit.span.file.locate (1, out line, out column);
		assert (line == 2 && column == 1);
		string dump = SyntaxDump.format_program (program);
		assert (dump.has_prefix ("(program\n\t(source \"a.astra\"") && dump.contains ("(source \"sub/b.astra\""));
		units.remove_index (0);
		var single = new SyntaxProgram (units);
		assert (SyntaxDump.format_program (single) == SyntaxDump.format (a.unit));
	} catch (SourceSetError error) {
		GLib.error ("%s", error.message);
	}
}

private void independent_errors() {
	try {
		var files = new GenericArray<SourceFile> ();
		files.add (new SourceFile.from_text ("b.astra", "int n) { return n; }"));
		files.add (new SourceFile.from_text ("a.astra", "int f("));
		var result = SyntaxProgram.parse (new SourceSet (files));
		assert (result.program == null && result.diagnostic.span.file == files[1]);
		assert (result.diagnostic.span.start == 6);
	} catch (SourceSetError error) {
		GLib.error ("%s", error.message);
	}
}

private void paths() {
	assert (SourceFile.normalize_path ("./sub//./file.astra") == "sub/file.astra");
	assert (SourceFile.normalize_path ("sub/../file.astra") == "sub/../file.astra");
	try {
		SourceSet.canonical_paths ({"foo.astra", "./foo.astra"});
	} catch (SourceSetError error) {
		assert (error.message == "source file 'foo.astra' was supplied more than once");
		return;
	}
	GLib.error ("accepted duplicate source input");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/parser/independent-units-and-byte-spans", composition);
	Test.add_func ("/sources/parser/no-token-stream-concatenation", independent_errors);
	Test.add_func ("/sources/parser/normalized-duplicate-input", paths);
	return Test.run ();
}

}
