// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Vapi;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Vapi {
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
	FileUtils.get_contents ("tests/vapi/fixtures/" + name, out text);
	return text;
}

private GenericArray<ForeignDeclarationInput> inputs(string[] declarations) {
	var inputs = new GenericArray<ForeignDeclarationInput> ();
	for (int i = 0; i < declarations.length; i++) {
		var parsed = VapiParser.parse (new SourceFile.from_text ("input%d.vapi".printf (i), declarations[i]));
		assert (parsed.diagnostic == null);
		foreach (var input in VapiNormalizer.normalize (parsed.file)) {
			inputs.add (input);
		}
	}
	return inputs;
}

private CheckedProgram check(string text, string[] declarations, bool vapi = true) {
	string source = text;
	var normalized = inputs (declarations);
	if (!vapi) {
		foreach (var input in normalized) {
			source += "\nextern(C) " + input.span.text ();
		}
	}
	var parsed = Astra.Syntax.Parser.parse (new SourceFile.from_text ("program.astra", source));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit, vapi ? normalized : null);
	if (result.diagnostic != null) {
		GLib.error ("Unexpected diagnostic: %s", result.diagnostic.format ());
	}
	return result.program;
}

private SsaProgram build(string text, string[] declarations, bool vapi = true) throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check (text, declarations, vapi)));
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	return SsaBuilder.build (cfg);
}

}
