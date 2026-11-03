// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.StructElementsPipeline {
private CheckedProgram check(string source) {
	ParseResult? syntax = Parser.parse (new SourceFile.from_text ("record.astra", source));
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var body = WeakRef (syntax.unit);
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	// Checked source metadata can retain immutable spans, never the syntax graph.
	syntax = null;
	assert (body.get () == null);
	return result.program;
}

private SsaProgram build(string name) throws GLib.Error {
	string source;
	FileUtils.get_contents ("tests/struct-elem-1/fixtures/" + name + ".astra", out source);
	CheckedProgram? checked = check (source);
	var checked_function = WeakRef (checked.functions[0]);
	var universe = WeakRef (checked.types);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_function.get () == null && universe.get () == null);
	CoreVerifier.verify (core);
	core = CoreGenericMonomorphizer.build (core);
	CoreVerifier.verify_concrete (core);
	var core_function = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_function.get () == null);
	CfgVerifier.verify (cfg);
	var flow = CfgFlowChecker.check (cfg);
	if (flow.diagnostic != null) {
		GLib.error ("%s", flow.diagnostic.format ());
	}
	var cfg_function = WeakRef (cfg.functions[0]);
	var ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_function.get () == null);
	SsaVerifier.verify (ssa);
	return ssa;
}

}
