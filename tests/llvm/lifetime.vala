// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private void lifetime(string path) throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text (path, fixture (path)));
	assert (parsed.diagnostic == null);
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var source_ref = WeakRef (parsed.unit.span.file);
	var syntax_ref = WeakRef (parsed.unit);
	var syntax_function_ref = WeakRef (parsed.unit.functions[0]);
	var checked_ref = WeakRef (checked_result.program);
	var symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
	var types_ref = WeakRef (checked_result.program.types);
	var int_ref = WeakRef (checked_result.program.types.int_type);
	var bool_ref = WeakRef (checked_result.program.types.bool_type);
	var void_ref = WeakRef (checked_result.program.types.void_type);
	CoreProgram? core = CoreBuilder.build (checked_result.program);
	var core_ref = WeakRef (core);
	var core_function_ref = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var cfg_ref = WeakRef (cfg);
	var cfg_function_ref = WeakRef (cfg.functions[0]);
	var cfg_block_ref = WeakRef (cfg.functions[0].entry);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	var ssa_ref = WeakRef (ssa);
	var ssa_function_ref = WeakRef (ssa.functions[0]);
	var ssa_last_ref = WeakRef (ssa.functions[ssa.functions.length - 1]);
	var ssa_block_ref = WeakRef (ssa.functions[0].entry);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	var nabi_ref = WeakRef (nabi);
	var native_function_ref = WeakRef (nabi.functions[0]);
	var signature_ref = WeakRef (nabi.functions[0].signature);
	Astra.CAbi.CAbiProgram? cabi = Astra.CAbi.CAbiBuilder.build (ssa, nabi);
	LlvmModuleArtifact? artifact = LlvmLowering.lower (ssa, nabi, cabi);
	cabi = null;
	string expected = artifact.dump ();
	parsed = null;
	checked_result = null;
	core = null;
	cfg = null;
	ssa = null;
	nabi = null;
	assert (source_ref.get () == null && syntax_ref.get () == null && syntax_function_ref.get () == null);
	assert (checked_ref.get () == null && symbol_ref.get () == null && types_ref.get () == null);
	assert (int_ref.get () == null && bool_ref.get () == null && void_ref.get () == null);
	assert (core_ref.get () == null && core_function_ref.get () == null);
	assert (cfg_ref.get () == null && cfg_function_ref.get () == null && cfg_block_ref.get () == null);
	assert (ssa_ref.get () == null && ssa_function_ref.get () == null && ssa_last_ref.get () == null && ssa_block_ref.get () == null);
	assert (nabi_ref.get () == null && native_function_ref.get () == null && signature_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump () == expected && functions (artifact).length > 0);
	var artifact_ref = WeakRef (artifact);
	artifact = null;
	assert (artifact_ref.get () == null);
	// LLVM's non-GObject resources are checked by the Valgrind run.
}

private void register_lifetime_tests() {
	add ("/llvm/lifetime/type-layout-contexts", type_layout_contexts);
	add ("/llvm/lifetime/arithmetic", () => lifetime ("tests/llvm/fixtures/wrapping.astra"));
	add ("/llvm/lifetime/choose", () => lifetime ("tests/branch/fixtures/choose.astra"));
	add ("/llvm/lifetime/recursive", () => lifetime ("tests/call/fixtures/recursion.astra"));
	add ("/llvm/lifetime/mutual", () => lifetime ("tests/call/fixtures/mutual-recursion.astra"));
	add ("/llvm/lifetime/division", () => lifetime ("tests/scalar/fixtures/division.astra"));
	add ("/llvm/lifetime/nested-calls", () => lifetime ("tests/call/fixtures/nested-calls.astra"));
	add ("/llvm/lifetime/bool-void", () => lifetime ("tests/nabi/fixtures/bool-transport.astra"));
}

private void type_layout_contexts() throws GLib.Error {
	var target = new LlvmTargetMachineArtifact ();
	var equivalent = new LlvmTargetMachineArtifact (2);
	LlvmModuleArtifact? first = new LlvmModuleArtifact ();
	var second = new LlvmModuleArtifact ();
	var first_data = target.enum_target_data (first);
	var second_data = target.enum_target_data (second);
	assert ((void*) first_data != (void*) second_data);
	assert ((void*) first_data == (void*) equivalent.enum_target_data (first));
	var cache_ref = WeakRef (first.type_layouts.lookup (target.data_layout));
	CApi.TypeRef[] narrow = {
		CApi.int_type_in_context (first.context, 8)
	};
	CApi.TypeRef[] wide = {
		CApi.int_type_in_context (second.context, 8), CApi.int_type_in_context (second.context, 64), CApi.int_type_in_context (second.context, 8)
	};
	var a = CApi.struct_type_in_context (first.context, narrow, narrow.length, 0);
	var b = CApi.struct_type_in_context (second.context, wide, wide.length, 0);
	assert (CApi.abi_size_of_type (first_data, a) == 1 && CApi.abi_alignment_of_type (first_data, a) == 1);
	assert (CApi.abi_size_of_type (second_data, b) == 24 && CApi.abi_alignment_of_type (second_data, b) == 8);
	assert (CApi.offset_of_element (second_data, b, 1) == 8 && CApi.offset_of_element (second_data, b, 2) == 16);
	first = null;
	assert (cache_ref.get () == null);
	assert (CApi.abi_size_of_type (second_data, b) == 24);
	// The target survives both queried contexts; it owns no cached Type*.
}

}
