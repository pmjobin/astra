// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.StructCopy {
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
	FileUtils.get_contents ("tests/struct-copy/fixtures/struct-copy-" + name + ".astra", out text);
	return text;
}

private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("struct.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("Unexpected parse diagnostic: %s", parsed.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("Unexpected semantic diagnostic: %s", result.diagnostic.format ());
	}
	return result.program;
}

private SsaProgram build(string text) throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text)))));
}

}
