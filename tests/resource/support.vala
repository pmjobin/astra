// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Resource {
private const string TYPES = "[CCode(destroy_function = \"destroy\", cheader_filename = \"missing/resource.h\")] handle Resource; [CCode(destroy_function = \"destroy\")] handle Other; [CCode(destroy_function = \"device_destroy\")] handle Device;";
private const string API = "owned Resource create(int id); owned Resource again(int id); owned Other other(); owned Device device(); Resource raw(); Other raw_other(); void* raw_pointer(); int inspect(borrowed Resource r); int other_inspect(borrowed Other r); int unmanaged(Resource r); int pointer(void* p);";
private const string BASIC = "int f() { owned Resource r = create(1); inspect(r); owned Resource next = move r; r = again(0); release r; r = create(2); return inspect(next); }";
private string[] fixture_names() {
	return {
			   "basic", "unmanaged", "borrow", "move", "move-null", "release", "rearm", "mixed", "order", "null", "phi", "loop", "two-types", "extern"
	};
}
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
	FileUtils.get_contents ("tests/resource/fixtures/resource-" + name, out text);
	return text;
}
private SemanticResult analyze(string text, string declarations = TYPES + API) {
	var parsed = Parser.parse (new SourceFile.from_text ("resource.astra", text));
	if (parsed.diagnostic != null) {
		return new SemanticResult (null, parsed.diagnostic);
	}
	var vapi = VapiParser.parse (new SourceFile.from_text ("resource.vapi", declarations));
	if (vapi.diagnostic != null) {
		return new SemanticResult (null, vapi.diagnostic);
	}
	return SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
}
private CheckedProgram check(string text, string declarations = TYPES + API) {
	var result = analyze (text, declarations);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private CfgProgram cfg(string text, string declarations = TYPES + API) throws GLib.Error {
	return CfgBuilder.build (CoreBuilder.build (check (text, declarations)));
}
private SsaProgram build(string text, string declarations = TYPES + API) throws GLib.Error {
	return SsaBuilder.build (cfg (text, declarations));
}
private string fixture_declarations(string name) throws FileError {
	return read ("basic.vapi") + (name == "two-types" ? read ("two-types.vapi") : "");
}
}
