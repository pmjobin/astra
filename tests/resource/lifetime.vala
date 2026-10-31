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

namespace Astra.Tests.Resource {
private void stages() throws GLib.Error {
	VapiParseResult? parsed = VapiParser.parse (new SourceFile.from_text ("resource.vapi", TYPES + API));
	var syntax_ref = WeakRef (parsed.file.handles[0]);
	GenericArray<ForeignHandleInput>? handles = VapiNormalizer.normalize_handles (parsed.file);
	GenericArray<ForeignDeclarationInput>? functions = VapiNormalizer.normalize (parsed.file);
	var input_cleanup = WeakRef (handles[0].cleanup);
	parsed = null;
	assert (syntax_ref.get () == null);
	CheckedProgram? checked = SemanticAnalyzer.analyze (Parser.parse (new SourceFile.from_text ("resource.astra", BASIC)).unit, functions, handles).program;
	handles = null;
	functions = null;
	assert (input_cleanup.get () == null);
	var semantic_handle = WeakRef (checked.handles[0]);
	var semantic_cleanup = WeakRef (checked.handles[0].cleanup);
	var type_ref = WeakRef (checked.handles[0].semantic_type);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (semantic_handle.get () == null && semantic_cleanup.get () == null);
	CoreVerifier.verify (core);
	var core_handle = WeakRef (core.handles[0]);
	var core_cleanup = WeakRef (core.handles[0].cleanup);
	CfgProgram? control = CfgBuilder.build (core);
	core = null;
	assert (core_handle.get () == null && core_cleanup.get () == null);
	CfgVerifier.verify (control);
	var cfg_handle = WeakRef (control.handles[0]);
	var cfg_cleanup = WeakRef (control.handles[0].cleanup);
	SsaProgram? ssa = SsaBuilder.build (control);
	control = null;
	assert (cfg_handle.get () == null && cfg_cleanup.get () == null);
	SsaVerifier.verify (ssa);
	var ssa_handle = WeakRef (ssa.handles[0]);
	var ssa_cleanup = WeakRef (ssa.handles[0].cleanup);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (ssa_handle.get () == null && ssa_cleanup.get () == null && type_ref.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
}
private void register_lifetime() {
	add ("/resource/lifetime/all-stages", stages);
}
}
