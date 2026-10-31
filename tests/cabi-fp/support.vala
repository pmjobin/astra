// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
namespace Astra.Tests.CAbiFp {
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
	Test.add_func (path, () => { try {
									 cases.lookup (Test.get_path ()).body ();
								 } catch (GLib.Error error) {
									 GLib.error ("%s: %s", Test.get_path (), error.message);
								 }
	});
}
private string fixture(string name) throws FileError {
	string text;
	FileUtils.get_contents ("tests/cabi-fp/fixtures/" + name + ".astra", out text);
	return text;
}
private CheckedProgram check(string text, string declarations = "") {
	var parsed = Parser.parse (new SourceFile.from_text ("cabi-f64.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var vapi = VapiParser.parse (new SourceFile.from_text ("double.vapi", declarations));
	assert (vapi.file != null);
	var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
}
