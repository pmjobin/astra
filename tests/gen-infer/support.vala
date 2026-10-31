// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;

namespace Astra.Tests.GenInfer {
private string[] fixtures() {
	return {
			   "basic", "f32", "f64", "bool", "vector", "mask", "pointer", "multi", "capabilities", "nested", "literals", "outer", "outer-capabilities", "owned-resource", "owned-class", "outer-owned", "recursive", "method-property", "flow"
	};
}
private SemanticResult analyze(string source) {
	string api;
	try {
		FileUtils.get_contents ("tests/gen-infer/fixtures/runtime.vapi", out api);
	} catch (FileError error) {
		GLib.error ("%s", error.message);
	}
	var foreign = VapiParser.parse (new SourceFile.from_text ("runtime.vapi", api));
	assert (foreign.diagnostic == null);
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("gen-infer.astra", source));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var syntax = WeakRef (parsed.unit);
	var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (foreign.file), VapiNormalizer.normalize_handles (foreign.file));
	parsed = null;
	assert (syntax.get () == null);
	return result;
}
private CheckedProgram check(string source) {
	var result = analyze (source);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private CheckedProgram fixture(string name, bool inferred = true) {
	string source;
	try {
		FileUtils.get_contents ("tests/gen-infer/fixtures/" + (inferred ? "gen-infer-" : "explicit-") + name + ".astra", out source);
	} catch (FileError error) {
		GLib.error ("%s", error.message);
	}
	return check (source);
}
}
