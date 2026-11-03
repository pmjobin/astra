// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;

namespace Astra.Tests.ParamBorrow {
private string[] fixtures() {
	return {
			   "resource", "class", "slice", "method", "constructor", "mutation", "reborrow", "owned-control", "values", "var", "after-call", "order", "null"
	};
}

private CheckedProgram check(string source) {
	string api;
	try {
		FileUtils.get_contents ("tests/param-borrow/fixtures/runtime.vapi", out api);
	} catch (FileError error) {
		GLib.error ("%s", error.message);
	}
	var foreign = VapiParser.parse (new SourceFile.from_text ("runtime.vapi", api));
	assert (foreign.diagnostic == null);
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("parameter.astra", source));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var syntax = WeakRef (parsed.unit);
	var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (foreign.file), VapiNormalizer.normalize_handles (foreign.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	parsed = null;
	assert (syntax.get () == null);
	return result.program;
}

private CheckedProgram fixture(string name, bool implicit = true) {
	string source;
	try {
		FileUtils.get_contents ("tests/param-borrow/fixtures/" + (implicit ? "param-borrow-" : "explicit-") + name + ".astra", out source);
	} catch (FileError error) {
		GLib.error ("%s", error.message);
	}
	return check (source);
}

}
