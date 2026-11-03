// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Objects {
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
				GLib.error ("%s: %s", Test.get_path (), error.message);
			}
		});
}

private string read(string name) throws FileError {
	string text;
	FileUtils.get_contents ("tests/object/fixtures/object-" + name + ".astra", out text);
	return text;
}

private CheckedProgram check(string text) throws FileError {
	var parsed = Parser.parse (new SourceFile.from_text ("object.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	string api;
	string handles;
	FileUtils.get_contents ("tests/resource/fixtures/resource-api.vapi", out api);
	FileUtils.get_contents ("tests/resource/fixtures/resource-types.vapi", out handles);
	var vapi = VapiParser.parse (new SourceFile.from_text ("resource.vapi", api + handles));
	assert (vapi.file != null);
	var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private SsaProgram build(string text) throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check (text))));
}

}
