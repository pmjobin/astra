// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.Cfg {
private void mutable_join() {
	string text = "int choose(bool condition,int a,int b){int x = 0;if(condition){x = a;}else{x = b;}return x;}";
	var core = build_core (check_ok (text));
	var program = build_from_core (core);
	var function = program.functions[0];
	assert (function.locals.length == 1 && function.blocks.length == 4 && function.entry == function.blocks[0]);
	var local = function.locals[0];
	assert ((Object) local != (Object) core.functions[0].locals[0]);
	assert (((CfgInitialize) function.entry.instructions[0]).target == local);
	var conditional = (CfgConditionalBranch) function.entry.terminator;
	assert (((CfgParameterValue) conditional.condition).parameter == function.parameters[0]);
	assert (conditional.condition.semantic_type.kind == TypeKind.BOOL);
	assert (conditional.true_target == function.blocks[1] && conditional.false_target == function.blocks[2]);
	assert (conditional.successors ().length == 2 && conditional.successors ()[0] == function.blocks[1] && conditional.successors ()[1] == function.blocks[2]);
	var reachability = CfgReachability.analyze (function);
	for (int i = 0; i < 4; i++) {
		assert (function.blocks[i].ordinal == i && function.blocks[i].is_complete && reachability.is_reachable (function.blocks[i]));
	}
	for (int i = 1; i < 3; i++) {
		var block = function.blocks[i];
		assert (block.instructions.length == 1);
		var store = (CfgStore) block.instructions[0];
		assert (store.target == local && ((CfgParameterValue) store.value).parameter == function.parameters[i]);
		assert (((CfgBranch) block.terminator).target == function.blocks[3]);
		assert (block.terminator.successors ().length == 1 && block.terminator.successors ()[0] == function.blocks[3]);
	}
	assert (((CfgLoadValue) returned_value (function, 3)).source == local);
	assert (function.blocks[3].instructions.length == 0 && function.blocks[3].terminator.successors ().length == 0);
	assert (flow_result (program).diagnostic == null && dump_ok (program) == dump_ok (build_ok (text)));
}

private void conditional_returns() {
	var program = build_ok ("int full(bool c){if(c){return 1;}else{return 2;}} int partial(bool c){if(c){return 1;}} bool missing(){if(true){return true;}} void empty(bool c){if(c){}else{}} int mixed(bool c){if(c){return 1;}else{}return 2;}");
	var full = program.functions[0];
	assert (full.blocks.length == 4 && full.blocks[1].terminator is CfgReturn && full.blocks[2].terminator is CfgReturn);
	assert (full.blocks[3].terminator is CfgFunctionEnd);
	var reachability = CfgReachability.analyze (full);
	for (int i = 0; i < 4; i++) {
		assert (reachability.is_reachable (full.blocks[i]) == (i != 3));
	}
	var partial_function = program.functions[1];
	assert (partial_function.blocks.length == 3 && partial_function.blocks[1].terminator is CfgReturn && partial_function.blocks[2].terminator is CfgFunctionEnd);
	var conditional = (CfgConditionalBranch) partial_function.entry.terminator;
	assert (conditional.true_target == partial_function.blocks[1] && conditional.false_target == partial_function.blocks[2]);
	assert (CfgReachability.analyze (partial_function).is_reachable (partial_function.blocks[2]));
	assert (flow_result (program).diagnostic.message == "not all paths in function 'partial' return a value");
	assert (flow_result (build_ok ("int f(bool c){if(c){return 1;}else{return 2;}}")).diagnostic == null);
	assert (flow_result (build_ok ("bool f(){if(true){return true;}}")).diagnostic != null);
	assert (flow_result (build_ok ("int f(){if(false){return 1;}}")).diagnostic != null);
	assert (flow_result (build_ok ("bool f(){}")).diagnostic != null);
	var empty = program.functions[3];
	assert (empty.blocks.length == 4 && empty.blocks[1].terminator is CfgBranch && empty.blocks[2].terminator is CfgBranch);
	assert (CfgReachability.analyze (empty).is_reachable (empty.blocks[3]));
	var mixed = program.functions[4];
	assert (mixed.blocks[1].terminator is CfgReturn && mixed.blocks[2].terminator is CfgBranch);
	assert (CfgReachability.analyze (mixed).is_reachable (mixed.blocks[3]) && mixed.blocks[3].terminator is CfgReturn);
}

private void nested_joins() {
	string text = "int nested(bool a,bool b){int x = 0;if(a){if(b){x = 1;}else{x = 2;}}else{x = 3;}return x;}";
	var program = build_ok (text);
	var function = program.functions[0];
	assert (function.blocks.length == 7 && function.locals.length == 1);
	var outer = (CfgConditionalBranch) function.blocks[0].terminator;
	var inner = (CfgConditionalBranch) function.blocks[1].terminator;
	assert (outer.true_target == function.blocks[1] && outer.false_target == function.blocks[2]);
	assert (inner.true_target == function.blocks[4] && inner.false_target == function.blocks[5]);
	assert (((CfgBranch) function.blocks[2].terminator).target == function.blocks[3]);
	assert (((CfgBranch) function.blocks[4].terminator).target == function.blocks[6]);
	assert (((CfgBranch) function.blocks[5].terminator).target == function.blocks[6]);
	assert (((CfgBranch) function.blocks[6].terminator).target == function.blocks[3]);
	int[] stores = {
		4, 5, 2
	};
	for (int i = 0; i < stores.length; i++) {
		var store = (CfgStore) function.blocks[stores[i]].instructions[0];
		assert (store.target == function.locals[0] && ((CfgIntegerValue) store.value).span.text () == (i + 1).to_string ());
	}
	assert (((CfgLoadValue) returned_value (function, 3)).source == function.locals[0]);
	var reachability = CfgReachability.analyze (function);
	for (int i = 0; i < 7; i++) {
		assert (reachability.is_reachable (function.blocks[i]));
	}
	assert (flow_result (program).diagnostic == null && dump_ok (program) == dump_ok (build_ok (text)));
	assert (flow_result (build_ok ("int f(bool a,bool b){if(a){if(b){return 1;}else{return 2;}}else{return 3;}}")).diagnostic == null);
}

private void sibling_and_boolean_places() {
	var program = build_ok ("bool f(bool c){bool y = false;if(c){bool x = true;y = x;}else{bool x = false;y = x;}return y;}");
	var function = program.functions[0];
	assert (function.locals.length == 3 && function.locals[1] != function.locals[2]);
	assert (function.locals[1].name == "x" && function.locals[2].name == "x");
	for (int i = 1; i < 3; i++) {
		assert (function.locals[i].ordinal == i && function.locals[i].semantic_type == function.return_type);
		var initialization = (CfgInitialize) function.blocks[i].instructions[0];
		var store = (CfgStore) function.blocks[i].instructions[1];
		assert (initialization.target == function.locals[i] && initialization.value is CfgBooleanValue);
		assert (store.target == function.locals[0] && ((CfgLoadValue) store.value).source == function.locals[i]);
	}
	assert (((CfgLoadValue) returned_value (function, 3)).source == function.locals[0]);
	var straight = build_ok ("bool f(bool x){bool y = false;y = x;return y;}").functions[0];
	assert (straight.locals[0].semantic_type.kind == TypeKind.BOOL);
	assert (((CfgInitialize) straight.entry.instructions[0]).target == straight.locals[0]);
	assert (((CfgStore) straight.entry.instructions[1]).target == straight.locals[0]);
	assert (((CfgLoadValue) returned_value (straight)).source == straight.locals[0]);
}

private void post_return_conditional() {
	var program = build_ok ("int f(bool c){return 1;if(c){return 2;}else{return 3;}}");
	var function = program.functions[0];
	assert (function.blocks.length == 5 && function.entry.terminator is CfgReturn);
	assert (function.blocks[1].terminator is CfgConditionalBranch);
	assert (function.blocks[2].terminator is CfgReturn && function.blocks[3].terminator is CfgReturn);
	assert (function.blocks[4].terminator is CfgFunctionEnd);
	var reachability = CfgReachability.analyze (function);
	for (int i = 0; i < 5; i++) {
		assert (reachability.is_reachable (function.blocks[i]) == (i == 0));
	}
	assert (flow_result (program).diagnostic == null);
	var arm = build_ok ("int f(bool c){if(c){return 1;int x = 2;}else{return 3;}}").functions[0];
	assert (arm.blocks.length == 5 && arm.blocks[1].terminator is CfgReturn);
	assert (arm.blocks[4].instructions[0] is CfgInitialize && ((CfgBranch) arm.blocks[4].terminator).target == arm.blocks[3]);
	assert (!CfgReachability.analyze (arm).is_reachable (arm.blocks[4]) && !CfgReachability.analyze (arm).is_reachable (arm.blocks[3]));
}

private void conditional_lifetime() {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("branch-lifetime.astra", "bool f(int a,bool c){bool x = false;if(a < 2 == c){bool y = !c;x = y;}else{bool y = true;x = y;}return x;}"));
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	var syntax_ref = WeakRef (parsed.unit);
	var checked_ref = WeakRef (checked_result.program);
	var symbol_ref = WeakRef (checked_result.program.functions[0].locals[1]);
	var bool_ref = WeakRef (checked_result.program.types.bool_type);
	var source_ref = WeakRef (parsed.unit.span.file);
	CoreProgram? core = build_core (checked_result.program);
	var core_ref = WeakRef (core);
	var conditional_ref = WeakRef (core.functions[0].body.statements[1]);
	var condition_ref = WeakRef (((CoreIf) core.functions[0].body.statements[1]).condition);
	var core_place_ref = WeakRef (core.functions[0].locals[1]);
	var core_sibling_ref = WeakRef (core.functions[0].locals[2]);
	CfgProgram? cfg = build_from_core (core);
	var block_ref = WeakRef (cfg.functions[0].entry);
	var join_ref = WeakRef (cfg.functions[0].blocks[3]);
	var cfg_place_ref = WeakRef (cfg.functions[0].locals[0]);
	parsed = null;
	checked_result = null;
	core = null;
	assert (syntax_ref.get () == null && checked_ref.get () == null && symbol_ref.get () == null);
	assert (core_ref.get () == null && conditional_ref.get () == null && condition_ref.get () == null);
	assert (core_place_ref.get () == null && core_sibling_ref.get () == null);
	verify_ok (cfg);
	assert (bool_ref.get () == cfg.functions[0].return_type && flow_result (cfg).diagnostic == null);
	assert (dump_ok (cfg).contains ("(binary == : bool") && dump_ok (cfg).contains ("(bool true : bool)"));
	{
		var function = cfg.functions[0];
		var conditional = (CfgConditionalBranch) function.entry.terminator;
		assert (((CfgBinaryValue) conditional.condition).operator_kind == BinaryOperator.EQUAL);
		assert (((CfgBinaryValue) ((CfgBinaryValue) conditional.condition).left).operator_kind == BinaryOperator.LESS);
		assert (((CfgInitialize) function.blocks[1].instructions[0]).target == function.locals[1]);
		assert (((CfgInitialize) function.blocks[2].instructions[0]).target == function.locals[2]);
		assert (((CfgStore) function.blocks[1].instructions[1]).target == function.locals[0]);
		assert (((CfgStore) function.blocks[2].instructions[1]).target == function.locals[0]);
		assert (((CfgLoadValue) returned_value (function, 3)).source == function.locals[0]);
		assert (conditional.span.file.path == "branch-lifetime.astra" && function.locals[1].span.text () == "bool y = !c;");
		assert (conditional.true_target == function.blocks[1] && conditional.false_target == function.blocks[2]);
	}
	cfg = null;
	assert (source_ref.get () == null && bool_ref.get () == null);
	assert (block_ref.get () == null && join_ref.get () == null && cfg_place_ref.get () == null);
}

private void register_branch_cfg_tests() {
	Test.add_func ("/cfg/branch/mutable-join", mutable_join);
	Test.add_func ("/cfg/branch/return-flow", conditional_returns);
	Test.add_func ("/cfg/branch/nested-joins", nested_joins);
	Test.add_func ("/cfg/branch/sibling-and-bool-places", sibling_and_boolean_places);
	Test.add_func ("/cfg/branch/post-return", post_return_conditional);
	Test.add_func ("/cfg/branch/lifetime", conditional_lifetime);
	register_branch_operator_tests ();
	add_case ("/cfg/branch/maximum-nesting", () => {
			var text = new StringBuilder ("void f(){");
			for (int i = 0; i < 255; i++) {
				text.append ("if(true){");
			}
			text.append (string.nfill (256, '}'));
			var program = build_ok (text.str);
			var function = program.functions[0];
			assert (function.blocks.length == 511);
			var reachability = CfgReachability.analyze (function);
			for (int i = 0; i < function.blocks.length; i++) {
				assert (reachability.is_reachable (function.blocks[i]));
			}
			assert (flow_result (program).diagnostic == null && dump_ok (program).contains ("(bool true : bool)"));
		});
	for (int i = 0; i < 2; i++) {
		int operation = i;
		add_case ("/cfg/branch/verifier/write-type-%d".printf (operation), () => {
				var program = build_ok ("void f(bool c){bool x = false;if(c){x = true;}}int g(){return 1;}");
				var function = program.functions[0];
				var value = new CfgIntegerValue (function.span, program.functions[1].return_type, AstraIntValue.from_int64 (7));
				function.blocks[operation].instructions[0] = operation == 0 ? (CfgInstruction) new CfgInitialize (function.span, function.locals[0], value) : new CfgStore (function.span, function.locals[0], value);
				string path = "function #0/block #%d/instruction #0".printf (operation);
				expect_invalid (program, path, operation == 0 ? "initializer value type does not match target place type" : "stored value type does not match target place type");
			});
	}

	for (int i = 0; i < 3; i++) {
		int edge = i;
		add_case ("/cfg/branch/verifier/foreign-target-%d".printf (edge), () => {
				var program = build_ok ("void f(bool c){return;return;}void g(){}");
				var function = program.functions[0];
				var own = function.blocks[1];
				var foreign = program.functions[1].entry;
				var condition = new CfgParameterValue (function.span, function.parameters[0]);
				CfgTerminator bad = edge == 0 ? (CfgTerminator) new CfgBranch (function.span, foreign) : new CfgConditionalBranch (function.span, condition, edge == 1 ? foreign : own, edge == 2 ? foreign : own);
				replace_terminator (program, 0, 0, bad);
				expect_invalid (program, "function #0/block #0/terminator/successor #%d".printf (edge == 2 ? 1 : 0), "successor block is not owned by the containing function");
			});
	}
	add_case ("/cfg/branch/verifier/condition", () => {
			var program = build_ok ("int f(){return 1;return 2;}");
			var function = program.functions[0];
			replace_terminator (program, 0, 0, new CfgConditionalBranch (function.span, returned_value (function), function.blocks[1], function.blocks[1]));
			expect_invalid (program, "function #0/block #0/terminator/condition", "conditional branch condition must have type 'bool'");
		});
	add_case ("/cfg/branch/verifier/incomplete", () => {
			var program = build_ok ("void f(){}");
			program.functions[0].blocks.add (new CfgBlock.reserve (program.span, 1));
			expect_invalid (program, "function #0/block #1/terminator", "block has no terminator");
		});
	add_case ("/cfg/branch/verifier/foreign-place", () => {
			var program = build_ok ("void f(bool c){int x = 1;if(c){x = 2;}}void g(){int x = 3;}");
			var instructions = program.functions[0].blocks[1].instructions;
			var store = (CfgStore) instructions[0];
			instructions[0] = new CfgStore (store.span, program.functions[1].locals[0], store.value);
			expect_invalid (program, "function #0/block #1/instruction #0/target", "local place is not owned by the containing function");
		});
	add_case ("/cfg/branch/constant-structural-successors", () => {
			var program = build_ok ("void f(){if(true){}else{}}");
			var function = program.functions[0];
			assert (((CfgBooleanValue) ((CfgConditionalBranch) function.entry.terminator).condition).literal == BooleanLiteral.TRUE);
			for (int i = 0; i < 4; i++) {
				assert (CfgReachability.analyze (function).is_reachable (function.blocks[i]));
			}
		});
}
}
