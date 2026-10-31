// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.Native {
private void lifetime(string path, int[] targets) {
	try {
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
		var ssa_other_ref = WeakRef (ssa.functions[ssa.functions.length - 1]);
		var ssa_block_ref = WeakRef (ssa.functions[0].entry);
		var ssa_call_ref = WeakRef (first_call (ssa.functions[0]));
		NativeAbiProgram? program = NativeAbiBuilder.build (ssa);
		{
			var map = correspondence (ssa, program);
			NativeAbiValidator.validate_ssa_calls (ssa, program, map);
			for (int f = 0; f < targets.length; f++) {
				var call = first_call (ssa.functions[f]);
				if (targets[f] < 0) {
					assert (call == null);
				} else {
					assert (call.target == ssa.functions[targets[f]]);
					assert (NativeAbiValidator.validate_call (call, program, map, "lifetime") == program.functions[targets[f]]);
				}
			}
		}
		string dump = NativeAbiDump.format (program);
		parsed = null;
		checked_result = null;
		core = null;
		cfg = null;
		ssa = null;
		assert (syntax_ref.get () == null && syntax_function_ref.get () == null && checked_ref.get () == null && symbol_ref.get () == null);
		assert (core_ref.get () == null && core_function_ref.get () == null && cfg_ref.get () == null && cfg_function_ref.get () == null && cfg_block_ref.get () == null);
		assert (ssa_ref.get () == null && ssa_function_ref.get () == null && ssa_other_ref.get () == null && ssa_block_ref.get () == null && ssa_call_ref.get () == null);
		assert (types_ref.get () == null && int_ref.get () == null && bool_ref.get () == null && void_ref.get () == null);
		NativeAbiVerifier.verify (program);
		assert (NativeAbiDump.format (program) == dump && source_ref.get () != null);
		for (int f = 0; f < program.functions.length; f++) {
			var function = program.functions[f];
			assert (function.ordinal == f && function.owner == program);
			assert (function.span.file.path == path && function.name_span.text () == function.name);
			int line;
			int column;
			function.name_span.file.locate (function.name_span.start, out line, out column);
			assert (line >= 1 && column >= 1);
			var signature = function.signature;
			assert (signature.abi_version == NativeAbiVersion.SCALAR_V0);
			for (int p = 0; p < signature.parameters.length; p++) {
				var parameter = signature.parameters[p];
				assert (parameter.ordinal == p && parameter.name_span.text () == parameter.name);
				assert (parameter.scalar_type == NativeScalarType.I32 || parameter.scalar_type == NativeScalarType.B1);
			}
			assert (signature.result == null || signature.result.scalar_type == NativeScalarType.I32 || signature.result.scalar_type == NativeScalarType.B1);
		}
		var program_ref = WeakRef (program);
		var function_ref = WeakRef (program.functions[0]);
		var other_ref = WeakRef (program.functions[program.functions.length - 1]);
		var signature_ref = WeakRef (program.functions[0].signature);
		var parameter_ref = WeakRef (program.functions[0].signature.parameters[0]);
		var result_ref = WeakRef (program.functions[0].signature.result);
		program = null;
		assert (program_ref.get () == null && function_ref.get () == null && other_ref.get () == null);
		assert (signature_ref.get () == null && parameter_ref.get () == null && result_ref.get () == null && source_ref.get () == null);
	} catch (GLib.Error error) {
		GLib.error ("NABI lifetime failed: %s", error.message);
	}
}

private void register_lifetime_tests() {
	Test.add_func ("/nabi/lifetime/forward", () => lifetime ("tests/call/fixtures/forward-call.astra", {1, -1}));
	Test.add_func ("/nabi/lifetime/self-recursion", () => lifetime ("tests/call/fixtures/recursion.astra", {0}));
	Test.add_func ("/nabi/lifetime/mutual-recursion", () => lifetime ("tests/call/fixtures/mutual-recursion.astra", {1, 0}));
	Test.add_func ("/nabi/lifetime/scalar-types", () => lifetime ("tests/nabi/fixtures/signatures.astra", {-1, -1, -1}));
	Test.add_func ("/nabi/lifetime/bool-and-void-calls", () => lifetime ("tests/nabi/fixtures/bool-transport.astra", {-1, -1, 0}));
}
}
