// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;

namespace Astra.Tests.Sources {
private class Witness : Object {
	private WeakRef reference;
	public Witness (Object object) {
		reference = WeakRef (object);
	}

	public new Object? get() {
		return reference.get ();
	}

}
private string[] fixtures() {
	return {
			   "simple", "recursion", "structs", "objects", "generics", "ownership", "cad", "foreign", "partition"
	};
}

private CheckedProgram fixture(string name, out GenericArray<Witness> source_refs) throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	var directory = Dir.open ("tests/sources/fixtures/" + name);
	string? file;
	while ((file = directory.read_name ()) != null) {
		if (!file.has_suffix (".astra")) {
			continue;
		}
		string path = "tests/sources/fixtures/" + name + "/" + file;
		string text;
		FileUtils.get_contents (path, out text);
		files.add (new SourceFile.from_text (path, text));
	}
	SyntaxProgramResult? parsed = SyntaxProgram.parse (new SourceSet (files));
	files = null;
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var syntax_refs = new GenericArray<Witness> ();
	var file_refs = new GenericArray<Witness> ();
	foreach (var unit in parsed.program.units) {
		syntax_refs.add (new Witness (unit));
		file_refs.add (new Witness (unit.span.file));
	}
	source_refs = file_refs;
	var syntax_program = WeakRef (parsed.program);
	var source_set = WeakRef (parsed.program.sources);
	GenericArray<ForeignDeclarationInput>? declarations = null;
	GenericArray<ForeignHandleInput>? handles = null;
	if (name == "objects" || name == "ownership" || name == "partition") {
		string api;
		FileUtils.get_contents ("tests/param-borrow/fixtures/runtime.vapi", out api);
		var foreign = VapiParser.parse (new SourceFile.from_text ("runtime.vapi", api));
		assert (foreign.diagnostic == null);
		declarations = VapiNormalizer.normalize (foreign.file);
		handles = VapiNormalizer.normalize_handles (foreign.file);
	}
	var result = SemanticAnalyzer.analyze_program (parsed.program, declarations, handles);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	parsed = null;
	assert (syntax_program.get () == null && source_set.get () == null);
	foreach (var syntax in syntax_refs) {
		assert (syntax.get () == null);
	}
	foreach (var source in source_refs) {
		assert (source.get () != null);
	}
	return result.program;
}

}
