// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Vapi;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Pointers {
private void lifetime() throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("lifetime.astra", "export(C) void* echo(void* p) { void* x = null; if (p != null) { x = foreign(p); } return x; }"));
	VapiParseResult? vapi = VapiParser.parse (new SourceFile.from_text ("lifetime.vapi", "[CCode (cname = \"physical\", cheader_filename = \"missing/pointer.h\")] void /* retained span */ * foreign(void* p);"));
	GenericArray<ForeignDeclarationInput>? normalized = VapiNormalizer.normalize (vapi.file);
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit, normalized);
	assert (checked_result.diagnostic == null);
	var syntax_ref = WeakRef (parsed.unit);
	var star_ref = WeakRef (vapi.file.functions[0].return_type.stars[0]);
	var vapi_ref = WeakRef (vapi.file);
	var input_ref = WeakRef (normalized[0]);
	var checked_ref = WeakRef (checked_result.program);
	var universe_ref = WeakRef (checked_result.program.types);
	var ptr_ref = WeakRef (checked_result.program.types.raw_pointer_type);
	var void_ref = WeakRef (checked_result.program.types.void_type);
	var null_ref = WeakRef (((CheckedLocalDeclaration) checked_result.program.functions[0].body.statements[0]).initializer);
	var source_ref = WeakRef (vapi.file.span.file);
	CoreProgram? core = CoreBuilder.build (checked_result.program);
	parsed = null;
	vapi = null;
	normalized = null;
	checked_result = null;
	assert (syntax_ref.get () == null && star_ref.get () == null && vapi_ref.get () == null && input_ref.get () == null);
	assert (checked_ref.get () == null && universe_ref.get () == null && null_ref.get () == null);
	assert (ptr_ref.get () != null && void_ref.get () != null);
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("(null : void*)"));
	assert (((CoreInitialize) core.functions[0].body.statements[0]).value.span.text () == "null");
	var core_ref = WeakRef (core);
	var core_null_ref = WeakRef (((CoreInitialize) core.functions[0].body.statements[0]).value);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_null_ref.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgFlowChecker.check (cfg).diagnostic == null && CfgDump.format (cfg).contains ("(null : void*)"));
	var cfg_ref = WeakRef (cfg);
	var cfg_null_ref = WeakRef (((CfgInitialize) cfg.functions[0].entry.instructions[0]).value);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_null_ref.get () == null);
	SsaVerifier.verify (ssa);
	assert (SsaDump.format (ssa).contains ("(null : void*)"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	string native_dump = NativeAbiDump.format (nabi);
	string c_dump = CAbiDump.format (cabi);
	var ssa_ref = WeakRef (ssa);
	ssa = null;
	assert (ssa_ref.get () == null && ptr_ref.get () == null && void_ref.get () == null);
	assert (NativeAbiDump.format (nabi) == native_dump && CAbiDump.format (cabi) == c_dump);
	nabi = null;
	assert (CAbiDump.format (cabi) == c_dump && source_ref.get () != null);
	cabi = null;
	assert (source_ref.get () == null);
}

private void register_lifetime() {
	add ("/ptr/frontend-core-cfg-ssa-abi-lifetime", lifetime);
}
}
