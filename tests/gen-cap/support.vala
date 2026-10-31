// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
namespace Astra.Tests.Generics {
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
private string read(string name) throws FileError {
	string text;
	FileUtils.get_contents ("tests/gen-cap/fixtures/gen-cap-" + name + ".astra", out text);
	return text;
}
private CheckedProgram check(string text) throws FileError {
	var parsed = Parser.parse (new SourceFile.from_text ("generic.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	string bindings;
	FileUtils.get_contents ("tests/obj-life/fixtures/lifecycle.vapi", out bindings);
	var vapi = VapiParser.parse (new SourceFile.from_text ("lifecycle.vapi", bindings));
	var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private SsaProgram unresolved_ssa() throws SsaError {
	var span = SourceSpan (new SourceFile.from_text ("unresolved", "T"), 0, 1);
	var type = new TypeParameterType ("T", new GenericCapabilitySet (new GenericCapabilityIdentity[] {GenericCapabilityIdentity.EQ}));
	var parameter = new SsaFunctionParameter (span, span, "x", type, 0);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (parameter);
	var block = new SsaBlock (span, 0, 0);
	block.complete (new SsaReturn (span, parameter));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "bad", type, 0, parameters, blocks, block));
	return new SsaProgram (span, functions);
}
private CoreProgram core(string text) throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (check (text)));
}
private SsaProgram build(string text) throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (core (text)));
}
}
