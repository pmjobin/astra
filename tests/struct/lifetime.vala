// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Structs {
private void lifetime() throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("struct.astra", "struct S { void* p; bool b; int x; } int f(bool c) { S s = { x = 1, b = false, p = null }; if (c) { s.x = 2; s.b = true; s.p = null; } return s.x; }"));
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var syntax_ref = WeakRef (parsed.unit);
	var syntax_struct_ref = WeakRef (parsed.unit.structs[0]);
	var semantic_ref = WeakRef (checked_result.program);
	var symbol_ref = WeakRef (checked_result.program.structs[0]);
	var field_ref = WeakRef (checked_result.program.structs[0].fields[0]);
	var type_ref = WeakRef (checked_result.program.structs[0].semantic_type);
	var local_ref = WeakRef (checked_result.program.functions[0].locals[0]);
	var source_ref = WeakRef (parsed.unit.span.file);
	CoreProgram? core = CoreBuilder.build (checked_result.program);
	parsed = null;
	checked_result = null;
	assert (syntax_ref.get () == null && syntax_struct_ref.get () == null && semantic_ref.get () == null);
	assert (symbol_ref.get () == null && field_ref.get () == null && local_ref.get () == null && type_ref.get () != null);
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("(field #0 \"p\") : void*)"));
	assert (core.functions[0].field_places[0].field.containing_struct == core.structs[0]);
	assert (core.functions[0].field_places[0].aggregate == core.functions[0].locals[0]);
	var core_ref = WeakRef (core);
	var core_struct_ref = WeakRef (core.structs[0]);
	var core_field_ref = WeakRef (core.structs[0].fields[0]);
	var core_place_ref = WeakRef (core.functions[0].field_places[0]);
	var core_base_ref = WeakRef (core.functions[0].locals[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_struct_ref.get () == null && core_field_ref.get () == null);
	assert (core_place_ref.get () == null && core_base_ref.get () == null && type_ref.get () != null);
	CfgVerifier.verify (cfg);
	assert (CfgDump.format (cfg).contains ("(field #0 \"p\") : void*)"));
	assert (cfg.functions[0].field_places[0].field.containing_struct == cfg.structs[0]);
	var cfg_ref = WeakRef (cfg);
	var cfg_struct_ref = WeakRef (cfg.structs[0]);
	var cfg_field_ref = WeakRef (cfg.structs[0].fields[0]);
	var cfg_place_ref = WeakRef (cfg.functions[0].field_places[0]);
	var cfg_base_ref = WeakRef (cfg.functions[0].locals[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_struct_ref.get () == null && cfg_field_ref.get () == null);
	assert (cfg_place_ref.get () == null && cfg_base_ref.get () == null && type_ref.get () == null);
	SsaVerifier.verify (ssa);
	assert (SsaDump.format (ssa).contains ("\"s.p\" (local #0 field #0) : void*"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var ssa_ref = WeakRef (ssa);
	ssa = null;
	assert (ssa_ref.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	nabi = null;
	cabi = null;
	assert (source_ref.get () == null);
}

private void register_lifetime() {
	add ("/struct/stage-lifetime", lifetime);
}
}
