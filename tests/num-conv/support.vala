// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.NumericPipeline {
private string[] fixtures() {
	return {
			   "int-f32", "int-f64", "f32-int", "f64-int", "signed", "unsigned", "literals", "order", "trap", "cad"
	};
}

private SsaProgram build(string name) throws GLib.Error {
	string text;
	FileUtils.get_contents ("tests/num-conv/fixtures/num-conv-" + name + ".astra", out text);
	ParseResult? syntax = Parser.parse (new SourceFile.from_text ("fixture.astra", text));
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var syntax_unit = WeakRef (syntax.unit);
	SemanticResult? result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	syntax = null;
	assert (syntax_unit.get () == null);
	var checked_function = WeakRef (result.program.functions[0]);
	CoreProgram? core = CoreBuilder.build (result.program);
	result = null;
	assert (checked_function.get () == null);
	CoreVerifier.verify (core);
	core = CoreGenericMonomorphizer.build (core);
	var core_function = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_function.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var cfg_function = WeakRef (cfg.functions[0]);
	var ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_function.get () == null);
	SsaVerifier.verify (ssa);
	return ssa;
}
}
