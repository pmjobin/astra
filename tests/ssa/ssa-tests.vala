// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Ssa {
private const string CHOOSE = "int choose(bool condition,int a,int b){int x = 0;if(condition){x = a;}else{x = b;}return x;}";

private SsaProgram promote(CfgProgram cfg) {
	try {
		return SsaBuilder.build (cfg);
	} catch (SsaError error) {
		GLib.error ("Unexpected SSA construction failure: %s", error.message);
	}
}

private SsaProgram ssa_ok(string text) {
	return promote (cfg_ok (text));
}

private string dump_ok(SsaProgram program) {
	try {
		return SsaDump.format (program);
	} catch (SsaError error) {
		GLib.error ("Unexpected SSA dump failure: %s", error.message);
	}
}

private SsaValue returned(SsaBlock block) {
	assert (block.terminator is SsaReturn && ((SsaReturn) block.terminator).value != null);
	return ((SsaReturn) block.terminator).value;
}

private void integer(SsaValue value, string spelling) {
	assert (value is SsaIntegerConstant && value.semantic_type.kind == TypeKind.INT);
	assert (((SsaIntegerConstant) value).value.to_string () == spelling);
}

private void no_storage(SsaProgram program) {
	string dump = dump_ok (program);
	foreach (string forbidden in new string[] {"place", "(load", "(store", "(initialize", "phi", "alloca", "LLVM"}) {
		assert (!dump.contains (forbidden));
	}
}

private void straight() {
	var program = ssa_ok ("int f(){int x = 1;return x;} int g(){int x = 1;x = 2;x = x + 0;x = 3;return x;}");
	var f = program.functions[0];
	assert (f.blocks.length == 1 && f.entry.parameters.length == 0 && f.entry.instructions.length == 0);
	integer (returned (f.entry), "1");
	var g = program.functions[1];
	assert (g.entry.instructions.length == 1);
	var add = (SsaBinaryInstruction) g.entry.instructions[0];
	assert (add.operator_kind == BinaryOperator.ADD && add.result.ordinal == 0);
	integer (add.left, "2");
	integer (add.right, "0");
	integer (returned (g.entry), "3");
	no_storage (program);
}

private void choose() {
	var cfg = cfg_ok (CHOOSE);
	var program = promote (cfg);
	var function = program.functions[0];
	assert (function.name == "choose" && function.ordinal == 0 && function.blocks.length == 4);
	assert (function.parameters.length == 3 && function.parameters[0].ordinal == 0 && function.parameters[2].ordinal == 2);
	assert ((Object) function.parameters[0] != (Object) cfg.functions[0].parameters[0]);
	var conditional = (SsaConditionalBranch) function.entry.terminator;
	assert (conditional.condition == function.parameters[0]);
	assert (conditional.true_edge.target == function.blocks[1] && conditional.false_edge.target == function.blocks[2]);
	assert (conditional.true_edge.arguments.length == 0 && conditional.false_edge.arguments.length == 0);
	var join = function.blocks[3];
	assert (join.parameters.length == 1 && returned (join) == join.parameters[0]);
	var parameter = join.parameters[0];
	assert (parameter.ordinal == 3 && parameter.name == "x" && parameter.source_local_ordinal == 0);
	assert (parameter.name_span.text () == "x" && parameter.span.text () == "int x = 0;");
	for (int b = 0; b < 4; b++) {
		assert (function.blocks[b].instructions.length == 0 && function.blocks[b].source_ordinal == b);
	}
	for (int b = 1; b < 3; b++) {
		var edge = ((SsaBranch) function.blocks[b].terminator).edge;
		assert (edge.target == join && edge.arguments.length == 1 && edge.arguments[0] == function.parameters[b]);
	}
	assert (dump_ok (program) == dump_ok (ssa_ok (CHOOSE)));
	no_storage (program);
}

private void one_arm() {
	var program = ssa_ok ("int maybe(bool c){int x = 0;if(c){x = 1;}return x;}");
	var f = program.functions[0];
	assert (f.blocks.length == 3 && f.blocks[2].parameters.length == 1);
	var conditional = (SsaConditionalBranch) f.entry.terminator;
	assert (conditional.true_edge.arguments.length == 0 && conditional.false_edge.arguments.length == 1);
	integer (conditional.false_edge.arguments[0], "0");
	integer (((SsaBranch) f.blocks[1].terminator).edge.arguments[0], "1");
	assert (returned (f.blocks[2]) == f.blocks[2].parameters[0]);
	no_storage (program);
}

private void multiple() {
	var program = ssa_ok ("int multiple(bool c,int a,int b){int x = 0;int y = 10;if(c){y = b;x = a;}else{x = b;y = a;}return x + y;}");
	var f = program.functions[0];
	var join = f.blocks[3];
	assert (join.parameters.length == 2);
	assert (join.parameters[0].name == "x" && join.parameters[0].source_local_ordinal == 0 && join.parameters[0].ordinal == 3);
	assert (join.parameters[1].name == "y" && join.parameters[1].source_local_ordinal == 1 && join.parameters[1].ordinal == 4);
	var left = ((SsaBranch) f.blocks[1].terminator).edge.arguments;
	var right = ((SsaBranch) f.blocks[2].terminator).edge.arguments;
	assert (left[0] == f.parameters[1] && left[1] == f.parameters[2]);
	assert (right[0] == f.parameters[2] && right[1] == f.parameters[1]);
	var sum = (SsaBinaryInstruction) join.instructions[0];
	assert (sum.left == join.parameters[0] && sum.right == join.parameters[1] && sum.result.ordinal == 5);
	assert (returned (join) == sum.result);
	no_storage (program);
}

private void nested() {
	var program = ssa_ok ("int nested(bool a,bool b){int x = 0;if(a){if(b){x = 1;}else{x = 2;}}else{x = 3;}return x;}");
	var f = program.functions[0];
	assert (f.blocks.length == 7 && f.blocks[3].parameters.length == 1 && f.blocks[6].parameters.length == 1);
	assert (f.blocks[3].parameters[0].ordinal == 2 && f.blocks[6].parameters[0].ordinal == 3);
	integer (((SsaBranch) f.blocks[4].terminator).edge.arguments[0], "1");
	integer (((SsaBranch) f.blocks[5].terminator).edge.arguments[0], "2");
	integer (((SsaBranch) f.blocks[2].terminator).edge.arguments[0], "3");
	var edge = ((SsaBranch) f.blocks[6].terminator).edge;
	assert (edge.target == f.blocks[3] && edge.arguments[0] == f.blocks[6].parameters[0]);
	assert (returned (f.blocks[3]) == f.blocks[3].parameters[0]);
	no_storage (program);
}

private void siblings() {
	var program = ssa_ok ("int f(bool c){if(c){int x = 1;x = x + 2;return x;}else{int x = 3;x = x + 4;return x;}}");
	var f = program.functions[0];
	assert (f.blocks.length == 3);
	for (int b = 1; b < 3; b++) {
		assert (f.blocks[b].parameters.length == 0);
		var sum = (SsaBinaryInstruction) f.blocks[b].instructions[0];
		integer (sum.left, b == 1 ? "1" : "3");
		integer (sum.right, b == 1 ? "2" : "4");
		assert (returned (f.blocks[b]) == sum.result);
	}
	no_storage (program);
	var scoped = ssa_ok ("void f(bool a,bool b){if(a){int x = 1;if(b){x = 2;}x = x + 3;}else{int x = 4;x = x + 5;}return;}").functions[0];
	assert (scoped.blocks[3].parameters.length == 0 && scoped.blocks[5].parameters.length == 1);
	assert (scoped.blocks[5].parameters[0].source_local_ordinal == 0);
	integer (((SsaBinaryInstruction) scoped.blocks[2].instructions[0]).left, "4");
	assert (((SsaBinaryInstruction) scoped.blocks[5].instructions[0]).left == scoped.blocks[5].parameters[0]);
}

private void iterated_frontier() {
	var f = ssa_ok ("int f(bool a,bool b){int x = 0;if(a){if(b){x = 1;}}return x;}").functions[0];
	// Only the innermost arm stores. The outer merge must be discovered
	// from the inner merge's frontier, not from another outer-arm store.
	assert (f.blocks.length == 5 && f.blocks[2].parameters.length == 1 && f.blocks[4].parameters.length == 1);
	assert (((SsaBranch) f.blocks[4].terminator).edge.arguments[0] == f.blocks[4].parameters[0]);
	assert (((SsaBranch) f.blocks[4].terminator).edge.target == f.blocks[2]);
	integer (((SsaConditionalBranch) f.entry.terminator).false_edge.arguments[0], "0");
	integer (((SsaConditionalBranch) f.blocks[1].terminator).false_edge.arguments[0], "0");
	integer (((SsaBranch) f.blocks[3].terminator).edge.arguments[0], "1");
	assert (returned (f.blocks[2]) == f.blocks[2].parameters[0]);
}

private void boolean() {
	var program = ssa_ok ("bool f(bool input){bool x = false;if(input){x = true;}return x;}");
	var f = program.functions[0];
	var join = f.blocks[2];
	assert (join.parameters[0].semantic_type.kind == TypeKind.BOOL && returned (join) == join.parameters[0]);
	var old = (SsaBooleanConstant) ((SsaConditionalBranch) f.entry.terminator).false_edge.arguments[0];
	var next = (SsaBooleanConstant) ((SsaBranch) f.blocks[1].terminator).edge.arguments[0];
	assert (old.literal == BooleanLiteral.FALSE && next.literal == BooleanLiteral.TRUE);
	assert (old.semantic_type == join.parameters[0].semantic_type && next.semantic_type == old.semantic_type);
	no_storage (program);
}

private void arithmetic() {
	var program = ssa_ok ("int arithmetic(int a,int b){return -(a + 2) * b % 3;}");
	var f = program.functions[0];
	var instructions = f.entry.instructions;
	assert (instructions.length == 4);
	var add = (SsaBinaryInstruction) instructions[0];
	var neg = (SsaPrefixInstruction) instructions[1];
	var mul = (SsaBinaryInstruction) instructions[2];
	var mod = (SsaBinaryInstruction) instructions[3];
	assert (add.operator_kind == BinaryOperator.ADD && add.left == f.parameters[0]);
	integer (add.right, "2");
	assert (neg.operator_kind == PrefixOperator.NEGATIVE && neg.operand == add.result);
	assert (mul.operator_kind == BinaryOperator.MULTIPLY && mul.left == neg.result && mul.right == f.parameters[1]);
	assert (mod.operator_kind == BinaryOperator.REMAINDER && mod.left == mul.result);
	integer (mod.right, "3");
	for (int i = 0; i < 4; i++) {
		assert (instructions[i].result.ordinal == i + 2 && instructions[i].result.semantic_type == f.return_type);
		assert (instructions[i].span.text () == instructions[i].result.span.text ());
	}
	assert (returned (f.entry) == mod.result);
	no_storage (program);
}

private void comparisons() {
	var f = ssa_ok ("bool test(int a,int b){return !(a < b == true);}").functions[0];
	var less = (SsaBinaryInstruction) f.entry.instructions[0];
	var equal = (SsaBinaryInstruction) f.entry.instructions[1];
	var neg = (SsaPrefixInstruction) f.entry.instructions[2];
	assert (less.operator_kind == BinaryOperator.LESS && less.result.semantic_type == f.return_type);
	assert (equal.operator_kind == BinaryOperator.EQUAL && equal.left == less.result && equal.right.semantic_type == f.return_type);
	assert (neg.operator_kind == PrefixOperator.NOT && neg.operand == equal.result && returned (f.entry) == neg.result);
}

private void computation_order_and_dominance() {
	var f = ssa_ok ("int f(bool c,int a,int b){int x = (a + 1) * (b + 2);if(c){return x;}else{return x;}}").functions[0];
	assert (f.entry.instructions.length == 3 && f.blocks.length == 3);
	var left = (SsaBinaryInstruction) f.entry.instructions[0];
	var right = (SsaBinaryInstruction) f.entry.instructions[1];
	var product = (SsaBinaryInstruction) f.entry.instructions[2];
	assert (left.left == f.parameters[1] && left.result.ordinal == 3);
	assert (right.left == f.parameters[2] && right.result.ordinal == 4);
	assert (product.left == left.result && product.right == right.result && product.result.ordinal == 5);
	assert (returned (f.blocks[1]) == product.result && returned (f.blocks[2]) == product.result);
}

private void all_operators() {
	foreach (string op in new string[] {"+", "-", "*", "/", "%", "<", "<=", ">", ">=", "==", "!="}) {
		bool arithmetic = op == "+" || op == "-" || op == "*" || op == "/" || op == "%";
		var f = ssa_ok ((arithmetic ? "int" : "bool") + " f(int a,int b){return a " + op + " b;}").functions[0];
		var instruction = (SsaBinaryInstruction) f.entry.instructions[0];
		assert (instruction.operator_kind.spelling () == op && instruction.result.semantic_type == f.return_type);
		assert (instruction.left == f.parameters[0] && instruction.right == f.parameters[1] && returned (f.entry) == instruction.result);
	}
	foreach (string op in new string[] {"+", "-", "!"}) {
		string type = op == "!" ? "bool" : "int";
		var f = ssa_ok (type + " f(" + type + " a){return " + op + "a;}").functions[0];
		var instruction = (SsaPrefixInstruction) f.entry.instructions[0];
		assert (instruction.operator_kind.spelling () == op && instruction.operand == f.parameters[0] && instruction.result.semantic_type == f.return_type);
	}
}

private void no_optimization() {
	var program = ssa_ok ("void f(bool c,int a){int x = a + 0;int y = a + 0;if(c){x = 1;}else{x = 2;}return;}");
	var f = program.functions[0];
	assert (f.entry.instructions.length == 2 && f.entry.instructions[0].result != f.entry.instructions[1].result);
	assert (f.blocks[3].parameters.length == 1 && f.blocks[3].parameters[0].name == "x");
	assert (((SsaReturn) f.blocks[3].terminator).value == null);
	no_storage (program);
}

private void projection() {
	var cfg = cfg_ok ("int f(){int x = 1;return x;x = 2;return x;}");
	var program = promote (cfg);
	assert (cfg.functions[0].blocks.length == 2 && program.functions[0].blocks.length == 1);
	integer (returned (program.functions[0].entry), "1");
	try {
		assert (CfgDump.format (cfg).contains ("(block #1 unreachable"));
	} catch (CfgError error) {
		GLib.error ("Unexpected CFG dump failure: %s", error.message);
	}
	assert (!dump_ok (program).contains ("(block #1"));
	var full = ssa_ok ("int f(bool c){if(c){return 1;}else{return 2;}}").functions[0];
	assert (full.blocks.length == 3 && full.blocks[1].terminator is SsaReturn && full.blocks[2].terminator is SsaReturn);
	// A removed inner join leaves a hole in original CFG ordinals; SSA
	// receives dense, independent identities while copying debug ordinals.
	var gap = ssa_ok ("void f(bool a,bool b){if(a){if(b){return;}else{return;}}else{if(b){}else{}}return;}").functions[0];
	assert (gap.blocks.length == 9 && gap.blocks[6].ordinal == 6 && gap.blocks[6].source_ordinal == 7);
	assert (((SsaConditionalBranch) gap.blocks[2].terminator).true_edge.target == gap.blocks[6]);
}

private void constant_conditions() {
	foreach (string literal in new string[] {"true", "false"}) {
		var f = ssa_ok ("int f(){int x = 0;if(" + literal + "){x = 1;}else{x = 2;}return x;}").functions[0];
		assert (f.blocks.length == 4 && f.blocks[3].parameters.length == 1);
		var condition = (SsaBooleanConstant) ((SsaConditionalBranch) f.entry.terminator).condition;
		assert (condition.literal.spelling () == literal);
		integer (((SsaBranch) f.blocks[1].terminator).edge.arguments[0], "1");
		integer (((SsaBranch) f.blocks[2].terminator).edge.arguments[0], "2");
	}
}

private void malformed_cfg() {
	var cfg = cfg_ok ("int f(){int x = 1;return x;}");
	var f = cfg.functions[0];
	// Keep the one required initialization but make its value load itself.
	// CFG structural verification intentionally does not infer assignment.
	f.entry.instructions[0] = new CfgInitialize (f.span, f.locals[0], new CfgLoadValue (f.span, f.locals[0]));
	for (int i = 0; i < 2; i++) {
		try {
			assert (CfgFlowChecker.check (cfg).diagnostic == null);
			SsaBuilder.build (cfg);
		} catch (SsaError error) {
			assert (error is SsaError.INVALID_CFG && error.message == "internal SSA construction error at function #0/block #0: local #0 has no reaching definition");
			continue;
		} catch (CfgError error) {
			GLib.error ("Malformed CFG did not reach the intended invariant: %s", error.message);
		}
		GLib.error ("SSA fabricated a value for a reachable load");
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ssa/promotion/straight", straight);
	Test.add_func ("/ssa/promotion/choose", choose);
	Test.add_func ("/ssa/promotion/one-arm", one_arm);
	Test.add_func ("/ssa/promotion/multiple", multiple);
	Test.add_func ("/ssa/promotion/nested", nested);
	Test.add_func ("/ssa/promotion/iterated-frontier", iterated_frontier);
	Test.add_func ("/ssa/promotion/siblings-and-scoped", siblings);
	Test.add_func ("/ssa/promotion/bool", boolean);
	Test.add_func ("/ssa/values/arithmetic", arithmetic);
	Test.add_func ("/ssa/values/comparisons", comparisons);
	Test.add_func ("/ssa/values/order-and-dominance", computation_order_and_dominance);
	Test.add_func ("/ssa/values/all-operators", all_operators);
	Test.add_func ("/ssa/no-optimization", no_optimization);
	Test.add_func ("/ssa/projection/unreachable", projection);
	Test.add_func ("/ssa/projection/constant-conditions", constant_conditions);
	Test.add_func ("/ssa/builder/missing-definition", malformed_cfg);
	Test.add_func ("/ssa/lifetime-and-scalar-value", lifetime);
	return Test.run ();
}

}
