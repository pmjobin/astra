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

namespace Astra.Tests.Rearm {
private void foreign_lifetime() throws GLib.Error {
	VapiParseResult? vapi = VapiParser.parse (new SourceFile.from_text ("owned.vapi", VAPI));
	var syntax_ref = WeakRef (vapi.file.functions[0].metadata.entries[1]);
	GenericArray<ForeignDeclarationInput>? inputs = VapiNormalizer.normalize (vapi.file);
	var input_cleanup_ref = WeakRef (inputs[0].metadata.owned_result.cleanup);
	vapi = null;
	assert (syntax_ref.get () == null);
	var parsed = Parser.parse (new SourceFile.from_text ("own.astra", BASIC));
	SemanticResult? result = SemanticAnalyzer.analyze (parsed.unit, inputs);
	inputs = null;
	assert (input_cleanup_ref.get () == null && result.diagnostic == null);
	assert (result.program.c_functions[0].metadata.owned_result.cleanup.external_symbol == "resource_destroy_impl");
}

private void stages() throws GLib.Error {
	CheckedProgram? checked = check (BASIC);
	var checked_ref = WeakRef (checked);
	var checked_rearm = WeakRef (checked.functions[0].body.statements[2]);
	var semantic_cleanup = WeakRef (checked.c_functions[0].metadata.owned_result.cleanup);
	var metadata_ref = WeakRef (checked.c_functions[0].metadata);
	var local_ref = WeakRef (checked.functions[0].locals[0]);
	var region_ref = WeakRef (checked.functions[0].body.region);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_ref.get () == null && semantic_cleanup.get () == null && metadata_ref.get () == null && local_ref.get () == null && region_ref.get () == null);
	assert (checked_rearm.get () == null);
	CoreVerifier.verify (core);
	var core_rearm = WeakRef (core.functions[0].body.statements[2]);
	var core_cleanup = WeakRef (core.cleanups[0]);
	var owner_ref = WeakRef (core.functions[0].owned_locals[0]);
	var scope_ref = WeakRef (core.functions[0].body);
	CfgProgram? control = CfgBuilder.build (core);
	core = null;
	assert (core_cleanup.get () == null && owner_ref.get () == null && scope_ref.get () == null);
	assert (core_rearm.get () == null);
	CfgVerifier.verify (control);
	OwnershipFlowResult? flow = OwnershipFlow.analyze (control.functions[0]);
	var flow_ref = WeakRef (flow);
	var cfg_rearm = WeakRef (control.functions[0].entry.instructions[4]);
	var cfg_cleanup = WeakRef (control.cleanups[0]);
	var cfg_place = WeakRef (control.functions[0].locals[0]);
	SsaProgram? ssa = SsaBuilder.build (control);
	flow = null;
	assert (flow_ref.get () == null);
	control = null;
	assert (cfg_rearm.get () == null);
	assert (cfg_cleanup.get () == null && cfg_place.get () == null);
	SsaVerifier.verify (ssa);
	var ssa_cleanup = WeakRef (ssa.cleanups[0]);
	var instruction_ref = WeakRef (ssa.functions[0].entry.instructions[1]);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (ssa_cleanup.get () == null && instruction_ref.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	var physical_ref = WeakRef (cabi.cleanups[0]);
	var source_ref = WeakRef (cabi.cleanups[0].symbol_span.file);
	nabi = null;
	cabi = null;
	assert (physical_ref.get () == null && source_ref.get () == null);
}

private void register_lifetime() {
	add ("/rearm/lifetime/foreign", foreign_lifetime);
	add ("/rearm/lifetime/stages", stages);
}

}
