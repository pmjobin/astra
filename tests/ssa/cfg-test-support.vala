// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.Ssa {
private CfgProgram cfg_ok(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("ssa.astra", text));
	assert (parsed.diagnostic == null);
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (checked_result.program));
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		return cfg;
	} catch (GLib.Error error) {
		GLib.error ("Unexpected CFG test setup failure: %s", error.message);
	}
}
}
