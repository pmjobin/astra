// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.TypedPointers {
private void lifetime() throws GLib.Error {
	ParseResult? syntax = Parser.parse (new SourceFile.from_text ("lifetime", SIMPLE));
	SemanticResult? checked_result = SemanticAnalyzer.analyze (syntax.unit);
	var syntax_ref = WeakRef (syntax.unit);
	var semantic_ref = WeakRef (checked_result.program);
	var symbol_ref = WeakRef (checked_result.program.structs[0]);
	var field_ref = WeakRef (checked_result.program.structs[0].fields[0]);
	var local_ref = WeakRef (checked_result.program.functions[1].locals[0]);
	var borrow_ref = WeakRef (((CheckedCallStatement) checked_result.program.functions[1].body.statements[2]).arguments[0]);
	var pointer_ref = WeakRef (checked_result.program.functions[0].symbol.parameters[0].semantic_type);
	var pointee_ref = WeakRef (checked_result.program.structs[0].semantic_type);
	var source_ref = WeakRef (syntax.unit.span.file);
	CoreProgram? core = CoreBuilder.build (checked_result.program);
	syntax = null;
	checked_result = null;
	assert (syntax_ref.get () == null && semantic_ref.get () == null && symbol_ref.get () == null && field_ref.get () == null);
	assert (local_ref.get () == null && borrow_ref.get () == null && pointer_ref.get () != null);
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("address-taken"));
	var core_struct_ref = WeakRef (core.structs[0]);
	var core_place_ref = WeakRef (core.functions[1].locals[0]);
	var core_indirect_ref = WeakRef (((CoreStore) core.functions[0].body.statements[0]).target);
	var core_address_ref = WeakRef (((CoreCallStatement) core.functions[1].body.statements[3]).arguments[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_struct_ref.get () == null && core_place_ref.get () == null && core_indirect_ref.get () == null && core_address_ref.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgDump.format (cfg).contains ("indirect-field-place"));
	var cfg_struct_ref = WeakRef (cfg.structs[0]);
	var cfg_place_ref = WeakRef (cfg.functions[1].locals[0]);
	var cfg_indirect_ref = WeakRef (((CfgStore) cfg.functions[0].entry.instructions[0]).target);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_struct_ref.get () == null && cfg_place_ref.get () == null && cfg_indirect_ref.get () == null);
	assert (pointer_ref.get () != null && pointee_ref.get () != null);
	SsaVerifier.verify (ssa);
	assert (SsaDump.format (ssa).contains ("address-of (storage #0)"));
	var ssa_struct_ref = WeakRef (ssa.structs[0]);
	var storage_ref = WeakRef (ssa.functions[1].storage[0]);
	var ssa_field_ref = WeakRef (ssa.structs[0].fields[0]);
	var indirect_ref = WeakRef (((SsaStoreInstruction) ssa.functions[0].entry.instructions[0]).target);
	var direct_ref = WeakRef (((SsaInitializeInstruction) ssa.functions[1].entry.instructions[0]).target);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (ssa_struct_ref.get () == null && storage_ref.get () == null && ssa_field_ref.get () == null);
	assert (indirect_ref.get () == null && direct_ref.get () == null && pointer_ref.get () == null && pointee_ref.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	nabi = null;
	cabi = null;
	assert (source_ref.get () == null);
}

private void register_lifetime() {
	add ("/tptr/stage-lifetime", lifetime);
}

}
