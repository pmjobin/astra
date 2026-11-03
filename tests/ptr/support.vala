// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Vapi;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Pointers {
private delegate void TestBody() throws GLib.Error;

private class Case : Object {
	internal TestBody body;
	internal Case (owned TestBody body) {
		this.body = (owned) body;
	}

}

private HashTable<string, Case> cases;

private void add(string path, owned TestBody body) {
	cases.insert (path, new Case ((owned) body));
	Test.add_func (path, () => {
			try {
				cases.lookup (Test.get_path ()).body ();
			} catch (GLib.Error error) {
				GLib.error ("%s failed: %s", Test.get_path (), error.message);
			}
		});
}

private string fixture(string name) throws FileError {
	string text;
	FileUtils.get_contents ("tests/ptr/fixtures/" + name, out text);
	return text;
}

private CheckedProgram check(string text, string declarations = "", bool source_extern = false) {
	var vapi = VapiParser.parse (new SourceFile.from_text ("pointer.vapi", declarations));
	assert (vapi.diagnostic == null);
	var normalized = VapiNormalizer.normalize (vapi.file);
	string source = text;
	if (source_extern) {
		foreach (var declaration in normalized) {
			source += "\nextern(C) " + declaration.span.text ();
		}
	}
	var syntax = Parser.parse (new SourceFile.from_text ("pointer.astra", source));
	assert (syntax.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit, source_extern ? null : normalized);
	if (result.diagnostic != null) {
		GLib.error ("Unexpected diagnostic: %s", result.diagnostic.format ());
	}
	return result.program;
}

private SsaProgram build(string text, string declarations = "", bool source_extern = false) throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check (text, declarations, source_extern)));
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	return SsaBuilder.build (cfg);
}

private string declarations(string name) throws FileError {
	return fixture ("pointer-alias.vapi") + (name == "ptr-cexport" || name == "ptr-roundtrip" ? fixture ("pointer-roundtrip.vapi") : "");
}

}
