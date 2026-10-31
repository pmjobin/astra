// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Lifecycle {
private CheckedProgram check(string text) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("lifecycle", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	string api;
	FileUtils.get_contents ("tests/obj-life/fixtures/lifecycle.vapi", out api);
	var vapi = VapiParser.parse (new SourceFile.from_text ("lifecycle.vapi", api));
	assert (vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private string read(string name) throws GLib.Error {
	string text;
	FileUtils.get_contents ("tests/obj-life/fixtures/obj-life-" + name + ".astra", out text);
	return text;
}
private SsaProgram build(string text) throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check (text))));
}
}
