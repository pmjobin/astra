// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;

namespace Astra.Tests.Infer {
private string[] fixtures() {
	return {
			   "scalars", "literals", "conversions", "pointers", "vectors", "structs", "generic-struct", "generic-result", "resource", "object", "constructor", "generic-owner", "buffer", "move", "property-method", "foreign", "slice-loop", "cad"
	};
}

private CheckedProgram check(string source) {
	string api;
	try {
		FileUtils.get_contents ("tests/infer/fixtures/runtime.vapi", out api);
	} catch (FileError error) {
		GLib.error ("%s", error.message);
	}
	var foreign = VapiParser.parse (new SourceFile.from_text ("runtime.vapi", api));
	assert (foreign.diagnostic == null);
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("infer.astra", source));
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

private CheckedProgram fixture(string name, bool inferred = true) {
	string source;
	try {
		FileUtils.get_contents ("tests/infer/fixtures/" + (inferred ? "infer-" : "explicit-") + name + ".astra", out source);
	} catch (FileError error) {
		GLib.error ("%s", error.message);
	}
	return check (source);
}

}
