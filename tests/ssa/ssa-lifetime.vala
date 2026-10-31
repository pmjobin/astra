// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Ssa {
private void lifetime() {
	string digits = string.nfill (993, '0') + "2147483647";
	string prefix = "int f(bool c,int a){int x = ";
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("ssa-lifetime.astra", prefix + digits + ";if(c){x = x + a;}return x;}"));
	assert (parsed.diagnostic == null);
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var syntax_ref = WeakRef (parsed.unit);
	var token_ref = WeakRef (parsed.unit.functions[0].name);
	var checked_ref = WeakRef (checked_result.program);
	var function_symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
	var parameter_symbol_ref = WeakRef (checked_result.program.functions[0].symbol.parameters[0]);
	var local_symbol_ref = WeakRef (checked_result.program.functions[0].locals[0]);
	var universe_ref = WeakRef (checked_result.program.types);
	var int_ref = WeakRef (checked_result.program.types.int_type);
	var bool_ref = WeakRef (checked_result.program.types.bool_type);
	var source_ref = WeakRef (parsed.unit.span.file);
	try {
		CoreProgram? core = CoreBuilder.build (checked_result.program);
		var core_ref = WeakRef (core);
		var core_function_ref = WeakRef (core.functions[0]);
		var core_parameter_ref = WeakRef (core.functions[0].parameters[0]);
		var core_local_ref = WeakRef (core.functions[0].locals[0]);
		var core_value_ref = WeakRef (((CoreInitialize) core.functions[0].body.statements[0]).value);
		CfgProgram? cfg = CfgBuilder.build (core);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var cfg_ref = WeakRef (cfg);
		var cfg_function_ref = WeakRef (cfg.functions[0]);
		var cfg_parameter_ref = WeakRef (cfg.functions[0].parameters[0]);
		var cfg_local_ref = WeakRef (cfg.functions[0].locals[0]);
		var cfg_block_ref = WeakRef (cfg.functions[0].entry);
		var cfg_join_ref = WeakRef (cfg.functions[0].blocks[2]);
		var cfg_instruction_ref = WeakRef (cfg.functions[0].entry.instructions[0]);
		var cfg_value_ref = WeakRef (((CfgInitialize) cfg.functions[0].entry.instructions[0]).value);
		var cfg_terminator_ref = WeakRef (cfg.functions[0].entry.terminator);
		var cfg_load_ref = WeakRef (((CfgReturn) cfg.functions[0].blocks[2].terminator).value);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		parsed = null;
		checked_result = null;
		core = null;
		cfg = null;
		assert (syntax_ref.get () == null && token_ref.get () == null && checked_ref.get () == null);
		assert (function_symbol_ref.get () == null && parameter_symbol_ref.get () == null && local_symbol_ref.get () == null && universe_ref.get () == null);
		assert (core_ref.get () == null && core_function_ref.get () == null && core_parameter_ref.get () == null && core_local_ref.get () == null && core_value_ref.get () == null);
		assert (cfg_ref.get () == null && cfg_function_ref.get () == null && cfg_parameter_ref.get () == null && cfg_local_ref.get () == null);
		assert (cfg_block_ref.get () == null && cfg_join_ref.get () == null && cfg_instruction_ref.get () == null && cfg_value_ref.get () == null && cfg_terminator_ref.get () == null && cfg_load_ref.get () == null);
		SsaVerifier.verify (ssa);
		string dump = SsaDump.format (ssa);
		assert (dump.contains ("(integer 2147483647 : int)") && dump == SsaDump.format (ssa));
		assert (source_ref.get () != null && int_ref.get () != null && bool_ref.get () != null);
		var ssa_block_ref = WeakRef (ssa.functions[0].entry);
		var ssa_join_ref = WeakRef (ssa.functions[0].blocks[2]);
		{
			var f = ssa.functions[0];
			assert (f.ordinal == 0 && f.name == "f" && f.name_span.text () == "f");
			assert (f.parameters[0].ordinal == 0 && f.parameters[0].name == "c" && f.parameters[0].semantic_type == bool_ref.get ());
			var branch = (SsaConditionalBranch) f.entry.terminator;
			var constant = (SsaIntegerConstant) branch.false_edge.arguments[0];
			assert (constant.span.text () == digits && constant.span.text ().length == 1003 && constant.semantic_type == int_ref.get ());
			assert (constant.value.signed_value == AstraIntValue.MAX);
			assert (constant.span.start == prefix.length && constant.span.end - constant.span.start == 1003);
			assert (constant.span.file.path == "ssa-lifetime.astra");
			int line;
			int column;
			constant.span.file.locate (constant.span.start, out line, out column);
			assert (line == 1 && column == prefix.length + 1);
			var join = f.blocks[2];
			var parameter = join.parameters[0];
			assert (join.ordinal == 2 && join.source_ordinal == 2 && join.span.file == constant.span.file);
			assert (parameter.ordinal == 2 && parameter.name == "x" && parameter.source_local_ordinal == 0 && parameter.name_span.text () == "x");
			assert (parameter.span.text () == "int x = " + digits + ";" && parameter.semantic_type == constant.semantic_type);
			var sum = (SsaBinaryInstruction) f.blocks[1].instructions[0];
			assert (sum.left == constant && sum.right == f.parameters[1] && sum.result.ordinal == 3);
			assert (sum.span.text () == "x + a" && sum.result.span.text () == "x + a");
			var true_exit = (SsaBranch) f.blocks[1].terminator;
			assert (true_exit.edge.target == join && true_exit.edge.arguments[0] == sum.result);
			assert (branch.true_edge.target == f.blocks[1] && branch.false_edge.target == join);
			assert (branch.span.text () == "if(c){x = x + a;}" && returned (join) == parameter);
		}
		ssa = null;
		assert (ssa_block_ref.get () == null && ssa_join_ref.get () == null);
		assert (source_ref.get () == null && int_ref.get () == null && bool_ref.get () == null);
	} catch (GLib.Error error) {
		GLib.error ("SSA lifetime regression failed: %s", error.message);
	}
}
}
