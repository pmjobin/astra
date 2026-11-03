// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.BufferPipeline {
private CheckedProgram check(string name) throws GLib.Error {
	string source;
	FileUtils.get_contents("tests/buffer/fixtures/buffer-" + name + ".astra", out source);
	string api;
	FileUtils.get_contents("tests/buffer/fixtures/runtime.vapi", out api);
	var parsed = Parser.parse(new SourceFile.from_text(name, source));
	var foreign = VapiParser.parse(new SourceFile.from_text("runtime.vapi", api));
	if (parsed.diagnostic != null) {
		GLib.error("%s", parsed.diagnostic.format());
	}
	assert(foreign.diagnostic == null);
	var result = SemanticAnalyzer.analyze(parsed.unit, VapiNormalizer.normalize(foreign.file), VapiNormalizer.normalize_handles(foreign.file));
	if (result.diagnostic != null) {
		GLib.error("%s", result.diagnostic.format());
	}
	return result.program;
}

private SsaProgram build(string name) throws GLib.Error {
	CheckedProgram? checked = check(name);
	var checked_function = WeakRef(checked.functions[0]);
	CoreProgram? core = CoreBuilder.build(checked);
	checked = null;
	assert(checked_function.get() == null);
	CoreVerifier.verify(core);
	core = CoreGenericMonomorphizer.build(core);
	var core_function = WeakRef(core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build(core);
	core = null;
	assert(core_function.get() == null);
	CfgVerifier.verify(cfg);
	assert(CfgFlowChecker.check(cfg).diagnostic == null);
	var cfg_function = WeakRef(cfg.functions[0]);
	var ssa = SsaBuilder.build(cfg);
	cfg = null;
	assert(cfg_function.get() == null);
	SsaVerifier.verify(ssa);
	return ssa;
}

}
