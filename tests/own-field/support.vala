// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.OwnedFieldPipeline {
private CheckedProgram check(string name) throws GLib.Error {
	string source;
	FileUtils.get_contents ("tests/own-field/fixtures/own-field-" + name + ".astra", out source);
	string api;
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	var parsed = Parser.parse (new SourceFile.from_text (name, source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (parsed.diagnostic == null && vapi.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private SsaProgram build(string name) throws GLib.Error {
	CheckedProgram? checked = check (name);
	var symbol = WeakRef (checked.classes[0]);
	var field = WeakRef (checked.classes[0].fields[0]);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (symbol.get () == null && field.get () == null);
	CoreVerifier.verify (core);
	core = CoreGenericMonomorphizer.build (core);
	var core_class = WeakRef (core.classes[0]);
	var core_field = WeakRef (core.classes[0].fields[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_class.get () == null && core_field.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var cfg_class = WeakRef (cfg.classes[0]);
	var cfg_field = WeakRef (cfg.classes[0].fields[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_class.get () == null && cfg_field.get () == null);
	SsaVerifier.verify (ssa);
	return ssa;
}
}
