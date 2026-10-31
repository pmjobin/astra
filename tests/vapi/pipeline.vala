// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Vapi;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Vapi {
private void semantic_diagnostics() throws GLib.Error {
	string[] declarations = {
		"bool f(int x);", "int f(bool x);", "int f(void x);", "int f(int x, int x);", "Unknown f();", "int f(Unknown x);"
	};
	string[] messages = {
		"C result type must be 'int', 'void*' or 'void'; foreign bool is unsupported", "C parameter type must be 'int' or 'void*'; foreign bool is unsupported", "parameter type cannot be 'void'", "duplicate parameter 'x'", "unknown type 'Unknown'", "unknown type 'Unknown'"
	};
	int[] columns = {
		1, 7, 7, 18, 1, 7
	};
	for (int i = 0; i < declarations.length; i++) {
		for (int attempt = 0; attempt < 2; attempt++) {
			var parsed = Astra.Syntax.Parser.parse (new SourceFile.from_text ("program.astra", "int main() { return unknown(); }"));
			var result = SemanticAnalyzer.analyze (parsed.unit, inputs ({declarations[i]}));
			assert (result.program == null && result.diagnostic != null);
			assert (result.diagnostic.format () == "input0.vapi:1:%d: error: %s".printf (columns[i], messages[i]));
		}
	}
}

private void duplicates() throws GLib.Error {
	string[] sources = {
		"extern(C) int f();", "int f() { return 1; }", "export(C) int f() { return 1; }", "", ""
	};
	for (int i = 0; i < sources.length; i++) {
		for (int attempt = 0; attempt < 2; attempt++) {
			var parsed = Astra.Syntax.Parser.parse (new SourceFile.from_text ("program.astra", sources[i] + " int main() { return unknown(); }"));
			string[] declarations = i == 3 ? new string[] {
				"int f();", "int f();"
			} : new string[] {
				i == 4 ? "int f();\nint f();" : "int f();"
			};
			var result = SemanticAnalyzer.analyze (parsed.unit, inputs (declarations));
			assert (result.program == null && result.diagnostic != null);
			string location = i == 3 ? "input1.vapi:1:5" : i == 4 ? "input0.vapi:2:5" : "input0.vapi:1:5";
			assert (result.diagnostic.format () == location + ": error: duplicate function 'f'; overloading is not implemented");
		}
	}
}

private void forward_identity() throws GLib.Error {
	var program = check ("int main() { return external_value(); } int later() { return main(); }", {"int external_value();"});
	var imported = program.c_functions[0];
	assert (imported.domain == CallableDomain.C && imported.abi == ForeignAbi.C && imported.external_symbol == "external_value");
	assert (imported.return_type == program.types.int_type && imported.parameters.length == 0);
	assert (imported.span.file.path == "input0.vapi" && imported.name_span.text () == "external_value");
	var call = (CheckedCallExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
	assert (call.target == imported);
	assert (!Astra.Syntax.SyntaxDump.format (Astra.Syntax.Parser.parse (new SourceFile.from_text ("program.astra", "int main() { return external_value(); }")).unit).contains ("extern-function"));
}

private void differential() throws GLib.Error {
	foreach (string name in new string[] {"basic", "order", "shortcircuit", "loop", "recursive-native", "roundtrip", "mixed"}) {
		string text = fixture ("vapi-" + name + ".astra");
		string[] declarations = {
			fixture ("basic.vapi"), fixture ("state.vapi")
		};
		if (name == "roundtrip") {
			declarations += fixture ("roundtrip.vapi");
		}
		var source = check (text, declarations, false);
		var vapi = check (text, declarations);
		assert (SemanticDump.format (source) == SemanticDump.format (vapi));
		assert (source.c_functions.length == vapi.c_functions.length);
		for (int i = 0; i < source.c_functions.length; i++) {
			var a = source.c_functions[i];
			var b = vapi.c_functions[i];
			assert (a.domain == b.domain && a.abi == b.abi && a.external_symbol == b.external_symbol);
			assert (a.return_type.display_name () == b.return_type.display_name ());
			assert (a.parameters.length == b.parameters.length);
			for (int j = 0; j < a.parameters.length; j++) {
				assert (a.parameters[j].name == b.parameters[j].name && a.parameters[j].ordinal == b.parameters[j].ordinal);
				assert (a.parameters[j].semantic_type.display_name () == b.parameters[j].semantic_type.display_name ());
			}
		}
		var source_core = CoreBuilder.build (source);
		var vapi_core = CoreBuilder.build (vapi);
		assert (CoreDump.format (source_core) == CoreDump.format (vapi_core));
		var source_cfg = CfgBuilder.build (source_core);
		var vapi_cfg = CfgBuilder.build (vapi_core);
		assert (CfgFlowChecker.check (source_cfg).diagnostic == null && CfgFlowChecker.check (vapi_cfg).diagnostic == null);
		assert (CfgDump.format (source_cfg) == CfgDump.format (vapi_cfg));
		var source_ssa = SsaBuilder.build (source_cfg);
		var vapi_ssa = SsaBuilder.build (vapi_cfg);
		assert (SsaDump.format (source_ssa) == SsaDump.format (vapi_ssa));
		var source_nabi = NativeAbiBuilder.build (source_ssa);
		var vapi_nabi = NativeAbiBuilder.build (vapi_ssa);
		assert (NativeAbiDump.format (source_nabi) == NativeAbiDump.format (vapi_nabi));
		assert (CAbiDump.format (CAbiBuilder.build (source_ssa, source_nabi)) == CAbiDump.format (CAbiBuilder.build (vapi_ssa, vapi_nabi)));
	}
}

private void ordering() throws GLib.Error {
	var ssa = build (fixture ("vapi-mixed.astra"), {fixture ("basic.vapi"), fixture ("state.vapi")});
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	assert (nabi.functions.length == 2 && cabi.functions.length == 6 && cabi.exports.length == 1);
	assert (!NativeAbiDump.format (nabi).contains ("astra_test_"));
	string[] names = {
		"astra_test_second", "astra_test_add", "astra_test_identity", "astra_test_reset", "astra_test_record", "astra_test_state"
	};
	for (int i = 0; i < names.length; i++) {
		assert (cabi.functions[i].external_symbol == names[i] && cabi.functions[i].ordinal == i);
	}
	assert (cabi.exports[0].ordinal == 0 && cabi.exports[0].external_symbol == "mixed");
	assert (CAbiDump.format (cabi) == fixture ("vapi-mixed.cabi"));
	var reversed = build (fixture ("vapi-mixed.astra"), {fixture ("state.vapi"), fixture ("basic.vapi")});
	var reversed_cabi = CAbiBuilder.build (reversed, NativeAbiBuilder.build (reversed));
	assert (reversed_cabi.functions[0].external_symbol == "astra_test_second");
	assert (reversed_cabi.functions[1].external_symbol == "astra_test_record" && reversed_cabi.functions[3].external_symbol == "astra_test_add");
}

private void lifetime() throws GLib.Error {
	VapiParseResult? parsed = VapiParser.parse (new SourceFile.from_text ("lifetime.vapi", "[CCode (cname = \"c_one_impl\", cheader_filename = \"missing.h\")] int c_one(int x); void c_void();"));
	var attribute_ref = WeakRef (parsed.file.functions[0].metadata);
	var entry_ref = WeakRef (parsed.file.functions[0].metadata.entries[0]);
	var value_ref = WeakRef (parsed.file.functions[0].metadata.entries[0].value);
	var file_ref = WeakRef (parsed.file);
	var function_ref = WeakRef (parsed.file.functions[0]);
	var parameter_ref = WeakRef (parsed.file.functions[0].parameters[0]);
	var type_ref = WeakRef (parsed.file.functions[0].return_type);
	var token_ref = WeakRef (parsed.file.functions[0].name);
	var source_ref = WeakRef (parsed.file.span.file);
	GenericArray<ForeignDeclarationInput>? normalized = VapiNormalizer.normalize (parsed.file);
	var input_ref = WeakRef (normalized[0]);
	var metadata_ref = WeakRef (normalized[0].metadata);
	parsed = null;
	assert (attribute_ref.get () == null && entry_ref.get () == null && value_ref.get () == null);
	assert (file_ref.get () == null && function_ref.get () == null && parameter_ref.get () == null && type_ref.get () == null && token_ref.get () == null);
	CheckedProgram? program = SemanticAnalyzer.analyze (Astra.Syntax.Parser.parse (new SourceFile.from_text ("program.astra", "int main() { c_void(); return c_one(1); }")).unit, normalized).program;
	normalized = null;
	assert (input_ref.get () == null && source_ref.get () != null);
	assert (program.c_functions[0].parameters[0].name == "x" && program.c_functions[0].parameters[0].semantic_type == program.types.int_type);
	assert_retained_metadata (program.c_functions[0].metadata);
	var checked_ref = WeakRef (program);
	var symbol_ref = WeakRef (program.c_functions[0]);
	CoreProgram? core = CoreBuilder.build (program);
	program = null;
	assert (checked_ref.get () == null && symbol_ref.get () == null);
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("c_one"));
	assert_retained_metadata (core.c_functions[0].metadata);
	var core_ref = WeakRef (core);
	var core_function_ref = WeakRef (core.c_functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_function_ref.get () == null);
	assert (CfgFlowChecker.check (cfg).diagnostic == null && CfgDump.format (cfg).contains ("c_one"));
	assert (((CfgCCallInstruction) cfg.functions[0].entry.instructions[0]).target == cfg.c_functions[1]);
	assert_retained_metadata (cfg.c_functions[0].metadata);
	var cfg_ref = WeakRef (cfg);
	var cfg_function_ref = WeakRef (cfg.c_functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_function_ref.get () == null);
	SsaVerifier.verify (ssa);
	assert (SsaDump.format (ssa).contains ("c_one"));
	assert (((SsaCCallInstruction) ssa.functions[0].entry.instructions[0]).target == ssa.c_functions[1]);
	assert_retained_metadata (ssa.c_functions[0].metadata);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	assert (nabi.functions.length == 1 && cabi.functions.length == 2);
	assert (cabi.functions[0].signature.parameters[0].scalar_type == CAbiScalarType.I32 && cabi.functions[1].signature.result == null);
	string dump = CAbiDump.format (cabi);
	var ssa_ref = WeakRef (ssa);
	var ssa_function_ref = WeakRef (ssa.c_functions[0]);
	ssa = null;
	nabi = null;
	assert (ssa_ref.get () == null && ssa_function_ref.get () == null);
	CAbiVerifier.verify (cabi);
	assert_retained_metadata (cabi.functions[0].metadata);
	assert (CAbiDump.format (cabi) == dump && cabi.functions[0].span.file.path == "lifetime.vapi");
	cabi = null;
	assert (source_ref.get () == null && metadata_ref.get () == null);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	register_metadata ();
	add ("/vapi/semantic-diagnostics", semantic_diagnostics);
	add ("/vapi/unified-namespace-duplicates", duplicates);
	add ("/vapi/forward-call-identity", forward_identity);
	add ("/vapi/source-extern-differential", differential);
	add ("/vapi/multiple-input-ordering-mixed", ordering);
	add ("/vapi/frontend-through-cabi-lifetime", lifetime);
	int status = Test.run ();
	cases = null;
	return status;
}
}
