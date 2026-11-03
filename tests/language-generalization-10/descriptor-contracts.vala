// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Driver;

namespace Astra.Tests.Descriptors {
private CheckedProgram check(string? metadata = null) throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	foreach (string path in new string[] {"lib/astra/base/errors.astra", "tests/language-generalization-10/descriptor-model.astra"}) {
		string source;
		FileUtils.get_contents (path, out source);
		files.add (new SourceFile.from_text (path, source));
	}
	if (metadata != null) {
		files.add (new SourceFile.from_text ("generated.astra", metadata));
	}
	var parsed = SyntaxProgram.parse (new SourceSet (files));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze_program (parsed.program);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void independent_snapshot() {
	try {
		CheckedProgram? original = check ();
		var old_class = WeakRef (original.classes[0]);
		var old_record = WeakRef (original.structs[0]);
		string metadata = NativeDescriptors.generate (original, "Witness", {"MetaReading", "MetaPoint", "MetaTransform"});
		original = null;
		assert (old_class.get () == null && old_record.get () == null);
		// Recheck the plain source snapshot with newly built nominal symbols.
		var fresh = check (metadata);
		bool reader = false;
		foreach (var function in fresh.functions) {
			if (function.symbol.name == "NativeMetadata_Witness.read_MetaReading_int") {
				reader = true;
			}
		}
		assert (reader);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/descriptors/snapshot-releases-predecessor", independent_snapshot);
	return Test.run ();
}

}
