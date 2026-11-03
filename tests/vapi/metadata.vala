// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Vapi {
private void assert_retained_metadata(CForeignMetadata metadata) {
	assert (metadata.external_symbol == "c_one_impl" && metadata.external_symbol_span.text () == "\"c_one_impl\"");
	assert (metadata.header_count == 1 && metadata.header_at (0).name == "missing.h");
	assert (metadata.header_at (0).span.text () == "\"missing.h\"" && metadata.header_at (0).span.file.path == "lifetime.vapi");
}

private void metadata_defaults() throws GLib.Error {
	var source = check ("extern(C) int physical(int x);", {});
	var vapi = check ("", {"int physical(int x);"});
	assert (SemanticDump.format (source) == SemanticDump.format (vapi));
	foreach (var program in new CheckedProgram[] {source, vapi}) {
		var function = program.c_functions[0];
		assert (function.name == "physical" && function.metadata.external_symbol == "physical");
		assert (function.metadata.header_count == 0 && function.metadata.external_symbol_span == null);
	}
	var normalized = inputs ({fixture ("header-only.vapi")});
	assert (normalized[0].name_span.text () == "c_value" && normalized[0].metadata.external_symbol == "c_value");
	assert (normalized[0].metadata.external_symbol_span == null && normalized[0].metadata.header_count == 1);
	assert (normalized[0].metadata.header_at (0).name == "this/header/does/not/exist.h");
	assert (normalized[0].metadata.header_at (0).span.text () == "\"this/header/does/not/exist.h\"");
	// Header strings are one opaque entry, including commas, punctuation and UTF-8.
	var opaque = inputs ({"[CCode (cname = \"physical.$é\", cheader_filename = \"../é,other; $(false)\")] int local();"})[0];
	assert (opaque.metadata.external_symbol == "physical.$é" && opaque.metadata.external_symbol_span.text () == "\"physical.$é\"");
	assert (opaque.metadata.header_count == 1 && opaque.metadata.header_at (0).name == "../é,other; $(false)");
}

private void metadata_identity() throws GLib.Error {
	var program = check ("int main() { return add(20, 22); }", {fixture ("aliases.vapi")});
	var imported = program.c_functions[0];
	assert (imported.name == "add" && imported.external_symbol == "astra_test_add_impl");
	assert (imported.name_span.text () == "add" && imported.span.text ().has_prefix ("[CCode"));
	assert (imported.metadata.external_symbol_span.text () == "\"astra_test_add_impl\"");
	var call = (CheckedCallExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
	assert (call.target == imported);
	string dump = SemanticDump.format (program);
	assert (dump.contains ("(extern-function \"add\" (abi C) (symbol \"astra_test_add_impl\")"));
	assert (dump.contains ("(headers\n\t\t\t\"helper/test_api.h\"\n\t\t)"));
	assert (!dump.contains ("CCode") && !dump.contains ("cname") && !dump.contains ("cheader_filename"));
	var syntax = Astra.Syntax.Parser.parse (new SourceFile.from_text ("lookup.astra", "int main() { return astra_test_add_impl(1, 2); }"));
	var result = SemanticAnalyzer.analyze (syntax.unit, inputs ({fixture ("aliases.vapi")}));
	assert (result.program == null && result.diagnostic.format () == "lookup.astra:1:21: error: unknown function 'astra_test_add_impl'");
	var independent = check ("int astra_test_add_impl(int a, int b) { return a + b; } int main() { return astra_test_add_impl(1, 2) + add(3, 4); }", {fixture ("aliases.vapi")});
	assert (independent.functions[0].symbol.name == "astra_test_add_impl" && independent.c_functions[0].name == "add");
}

private void metadata_local_duplicates() throws GLib.Error {
	foreach (string source in new string[] {"extern(C) int alpha();", "int alpha() { return 1; }", "export(C) int alpha() { return 1; }", ""}) {
		var syntax = Astra.Syntax.Parser.parse (new SourceFile.from_text ("program.astra", source));
		string[] declarations = {
			"[CCode (cname = \"first\")] int alpha();"
		};
		if (source == "") {
			declarations += "[CCode (cname = \"second\")] int alpha();";
		}
		var result = SemanticAnalyzer.analyze (syntax.unit, inputs (declarations));
		assert (result.program == null && result.diagnostic.format () == (source == "" ? "input1.vapi:1:32" : "input0.vapi:1:31") + ": error: duplicate function 'alpha'; overloading is not implemented");
	}
}

private void metadata_physical_duplicates() throws GLib.Error {
	for (int mode = 0; mode < 4; mode++) {
		string source = mode == 2 ? "extern(C) int same_symbol();" : mode == 3 ? "export(C) int same_symbol() { return 1; }" : "";
		string first = "[CCode (cname = \"same_symbol\")] int alpha();";
		string second = "[CCode (cname = \"same_symbol\")] int beta();";
		string[] declarations = mode == 0 ? new string[] {
			first + "\n" + second
		} : mode == 1 ? new string[] {
			first, second
		} : new string[] {
			first
		};
		// Distinct local names are semantically valid all the way through SSA/NABI.
		var ssa = build (source, declarations);
		var nabi = NativeAbiBuilder.build (ssa);
		string location = mode == 0 ? "input0.vapi:2:17" : mode == 1 ? "input1.vapi:1:17" : mode == 2 ? "input0.vapi:1:17" : "program.astra:1:15";
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				CAbiBuilder.build (ssa, nabi);
				assert_not_reached ();
			} catch (CAbiError.DUPLICATE_SYMBOL error) {
				assert (error.message == location + ": error: C external symbol 'same_symbol' is declared more than once");
			}
		}
	}
}

private void metadata_ordering() throws GLib.Error {
	for (int reverse = 0; reverse < 2; reverse++) {
		string[] declarations = {
			fixture (reverse == 0 ? "aliases.vapi" : "state-aliases.vapi"), fixture (reverse == 0 ? "state-aliases.vapi" : "aliases.vapi")
		};
		var ssa = build ("extern(C) int first(); int main() { return add(1, 2); }", declarations);
		var cabi = CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa));
		string[] names = reverse == 0 ? new string[] {
			"first", "add", "echo", "reset", "record", "state"
		} : new string[] {
			"first", "record", "state", "add", "echo", "reset"
		};
		for (int i = 0; i < names.length; i++) {
			assert (cabi.functions[i].ordinal == i && cabi.functions[i].name == names[i]);
		}
		assert (cabi.functions[reverse == 0 ? 1 : 3].external_symbol == "astra_test_add_impl");
		assert (cabi.functions[reverse == 0 ? 3 : 5].metadata.header_at (0).name == "helper/test_api.h");
	}
}

private void register_metadata() {
	add ("/vapi/metadata/defaults-and-opaque-values", metadata_defaults);
	add ("/vapi/metadata/local-identity-and-dump", metadata_identity);
	add ("/vapi/metadata/local-duplicates", metadata_local_duplicates);
	add ("/vapi/metadata/physical-duplicates-cabi-boundary", metadata_physical_duplicates);
	add ("/vapi/metadata/import-order", metadata_ordering);
}

}
