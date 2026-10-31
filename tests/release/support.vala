// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Release {
private const string THREE_WAY = "void f(bool enter, bool release_path) { owned void* a = create(1); while (enter) { if (release_path) { release a; break; } else { owned void* b = move a; break; } } }";
private string[] fixture_names() {
	return {
			   "basic", "null", "move", "borrow", "loop", "move-loop", "break", "continue", "order", "lifo", "others", "multiple", "contracts", "shortcircuit", "branch", "memory", "unreachable", "conditional", "both-arms", "terminating-arm", "loop-break", "loop-return", "null-conditional", "return", "three-way", "trap"
	};
}
private string fixture_declarations() throws FileError {
	string declarations;
	FileUtils.get_contents ("tests/own/fixtures/owned-resource.vapi", out declarations);
	string other;
	FileUtils.get_contents ("tests/move/fixtures/move-resource.vapi", out other);
	string borrowed;
	FileUtils.get_contents ("tests/oborrow/fixtures/borrowed-resource.vapi", out borrowed);
	return declarations + other + borrowed;
}

private const string VAPI = "[CCode(cname = \"resource_create_impl\", destroy_function = \"resource_destroy_impl\", cheader_filename = \"missing/resource.h\")] void* create(int id); void* raw(); void use(void* p); int effect(); int inspect(borrowed void* p);";
private const string BASIC = "int f() { owned void* a = create(1); release a; return 7; }";
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
	FileUtils.get_contents ("tests/release/fixtures/" + name, out text);
	return text;
}
private SemanticResult analyze(string text, string declarations = VAPI) {
	var parsed = Parser.parse (new SourceFile.from_text ("release.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var vapi = VapiParser.parse (new SourceFile.from_text ("owned.vapi", declarations));
	if (vapi.diagnostic != null) {
		GLib.error ("%s", vapi.diagnostic.format ());
	}
	return SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file));
}
private CheckedProgram check(string text, string declarations = VAPI) {
	var result = analyze (text, declarations);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private CfgProgram cfg(string text, string declarations = VAPI) throws GLib.Error {
	return CfgBuilder.build (CoreBuilder.build (check (text, declarations)));
}
private SsaProgram build(string text, string declarations = VAPI) throws GLib.Error {
	return SsaBuilder.build (cfg (text, declarations));
}
}
