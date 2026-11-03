// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Objects {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("object.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string fragment) {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", text));
	var diagnostic = parsed.diagnostic;
	if (diagnostic == null) {
		diagnostic = SemanticAnalyzer.analyze (parsed.unit).diagnostic;
	}
	if (diagnostic == null || !diagnostic.message.contains (fragment)) {
		GLib.error ("expected '%s', found %s", fragment, diagnostic == null ? "success" : diagnostic.format ());
	}
}

}
