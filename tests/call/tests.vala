// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Calls {
private string fixture(string name) {
	try {
		string text;
		FileUtils.get_contents (name + ".astra", out text);
		return text;
	} catch (FileError error) {
		GLib.error ("Call fixture failed: %s", error.message);
	}
}

private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("calls.astra", text));
	assert (parsed.diagnostic == null);
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	return checked_result.program;
}

private CfgProgram cfg_fixture(string name) throws GLib.Error {
	return CfgBuilder.build (CoreBuilder.build (check (fixture (name))));
}

private CheckedCallExpression? checked_call(CheckedFunction function) {
	var statement = function.body.statements[0];
	if (statement is CheckedIf) {
		statement = ((CheckedIf) statement).else_body.statements[0];
	}
	return ((CheckedReturnStatement) statement).expression as CheckedCallExpression;
}

private CoreCallValue? core_call(CoreFunction function) {
	var statement = function.body.statements[0];
	if (statement is CoreIf) {
		statement = ((CoreIf) statement).else_block.statements[0];
	}
	return ((CoreReturn) statement).value as CoreCallValue;
}

private CfgCallInstruction? cfg_call(CfgFunction function) {
	for (int b = 0; b < function.blocks.length; b++) {
		for (int i = 0; i < function.blocks[b].instructions.length; i++) {
			var call = function.blocks[b].instructions[i] as CfgCallInstruction;
			if (call != null) {
				return call;
			}
		}
	}
	return null;
}

private SsaCallInstruction? ssa_call(SsaFunction function) {
	for (int b = 0; b < function.blocks.length; b++) {
		for (int i = 0; i < function.blocks[b].instructions.length; i++) {
			var call = function.blocks[b].instructions[i] as SsaCallInstruction;
			if (call != null) {
				return call;
			}
		}
	}
	return null;
}

// At each boundary, destroy the upstream graph BEFORE verifying, dumping,
// inspecting targets, and building the next stage. Both ends of mutual
// recursion are watched; no call/body/function may keep its program alive.
private void identity_and_lifetime(string name, int[] targets) {
	try {
		ParseResult? parsed = Parser.parse (new SourceFile.from_text (name + ".astra", fixture (name)));
		SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked_result.diagnostic == null);
		int last = targets.length - 1;
		var syntax_ref = WeakRef (parsed.unit);
		var checked_ref = WeakRef (checked_result.program);
		var symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
		var other_symbol_ref = WeakRef (checked_result.program.functions[last].symbol);
		var checked_body_ref = WeakRef (checked_result.program.functions[0].body);
		var source_ref = WeakRef (parsed.unit.span.file);
		for (int i = 0; i < targets.length; i++) {
			var call = checked_call (checked_result.program.functions[i]);
			assert (targets[i] < 0 ? call == null : call.target == checked_result.program.functions[targets[i]].symbol);
		}
		string semantic_dump = SemanticDump.format (checked_result.program);
		assert (semantic_dump == SemanticDump.format (check (fixture (name))));
		CoreProgram? core = CoreBuilder.build (checked_result.program);
		parsed = null;
		checked_result = null;
		assert (syntax_ref.get () == null && checked_ref.get () == null);
		assert (symbol_ref.get () == null && other_symbol_ref.get () == null && checked_body_ref.get () == null);
		CoreVerifier.verify (core);
		assert (CoreDump.format (core) == CoreDump.format (core));
		for (int i = 0; i < targets.length; i++) {
			var call = core_call (core.functions[i]);
			assert (targets[i] < 0 ? call == null : call.target == core.functions[targets[i]]);
		}
		var core_ref = WeakRef (core);
		var core_function_ref = WeakRef (core.functions[0]);
		var core_other_ref = WeakRef (core.functions[last]);
		var core_body_ref = WeakRef (core.functions[0].body);
		var core_call_ref = WeakRef (core_call (core.functions[0]));
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_ref.get () == null && core_function_ref.get () == null && core_other_ref.get () == null);
		assert (core_body_ref.get () == null && core_call_ref.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null && CfgDump.format (cfg) == CfgDump.format (cfg));
		for (int i = 0; i < targets.length; i++) {
			var call = cfg_call (cfg.functions[i]);
			assert (targets[i] < 0 ? call == null : call.target == cfg.functions[targets[i]]);
		}
		var cfg_ref = WeakRef (cfg);
		var cfg_function_ref = WeakRef (cfg.functions[0]);
		var cfg_other_ref = WeakRef (cfg.functions[last]);
		var cfg_block_ref = WeakRef (cfg.functions[0].entry);
		var cfg_call_ref = WeakRef (cfg_call (cfg.functions[0]));
		var cfg_result_ref = WeakRef (cfg_call (cfg.functions[0]).result);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_ref.get () == null && cfg_function_ref.get () == null && cfg_other_ref.get () == null);
		assert (cfg_block_ref.get () == null && cfg_call_ref.get () == null && cfg_result_ref.get () == null);
		SsaVerifier.verify (ssa);
		string dump = SsaDump.format (ssa);
		assert (dump == SsaDump.format (ssa));
		for (int i = 0; i < targets.length; i++) {
			var call = ssa_call (ssa.functions[i]);
			assert (targets[i] < 0 ? call == null : call.target == ssa.functions[targets[i]]);
			if (call != null) {
				assert (call.span.file.path == name + ".astra" && call.result.span.text () == call.span.text ());
			}
		}
		var ssa_ref = WeakRef (ssa);
		var ssa_function_ref = WeakRef (ssa.functions[0]);
		var ssa_other_ref = WeakRef (ssa.functions[last]);
		var ssa_block_ref = WeakRef (ssa.functions[0].entry);
		var ssa_call_ref = WeakRef (ssa_call (ssa.functions[0]));
		var ssa_result_ref = WeakRef (ssa_call (ssa.functions[0]).result);
		ssa = null;
		assert (ssa_ref.get () == null && ssa_function_ref.get () == null && ssa_other_ref.get () == null);
		assert (ssa_block_ref.get () == null && ssa_call_ref.get () == null && ssa_result_ref.get () == null && source_ref.get () == null);
	} catch (GLib.Error error) {
		GLib.error ("Call identity/lifetime failed: %s", error.message);
	}
}

private void forward_lifetime() {
	identity_and_lifetime ("forward-call", {1, -1});
}

private void self_lifetime() {
	identity_and_lifetime ("recursion", {0});
}

private void mutual_lifetime() {
	identity_and_lifetime ("mutual-recursion", {1, 0});
}

private void ordered_binary() {
	try {
		var cfg = cfg_fixture ("ordered-calls");
		var block = cfg.functions[2].entry;
		assert (block.instructions.length == 2);
		var left = (CfgCallInstruction) block.instructions[0];
		var right = (CfgCallInstruction) block.instructions[1];
		assert (left.target == cfg.functions[0] && right.target == cfg.functions[1]);
		var sum = (CfgBinaryValue) ((CfgReturn) block.terminator).value;
		assert (sum.left == left.result && sum.right == right.result);
		var ssa = SsaBuilder.build (cfg);
		var instructions = ssa.functions[2].entry.instructions;
		assert (instructions.length == 3);
		assert (((SsaCallInstruction) instructions[0]).target == ssa.functions[0]);
		assert (((SsaCallInstruction) instructions[1]).target == ssa.functions[1]);
		var addition = (SsaBinaryInstruction) instructions[2];
		assert (addition.operator_kind == BinaryOperator.ADD);
		assert (addition.left == instructions[0].result && addition.right == instructions[1].result);
		assert (((SsaReturn) ssa.functions[2].entry.terminator).value == addition.result);
	} catch (GLib.Error error) {
		GLib.error ("Binary call order failed: %s", error.message);
	}
}

private void nested_order() {
	try {
		var cfg = cfg_fixture ("nested-calls");
		var instructions = cfg.functions[2].entry.instructions;
		assert (instructions.length == 3);
		var first = (CfgCallInstruction) instructions[0];
		var second = (CfgCallInstruction) instructions[1];
		var outer = (CfgCallInstruction) instructions[2];
		assert (first.target == cfg.functions[0] && second.target == cfg.functions[0] && outer.target == cfg.functions[1]);
		assert (((CfgIntegerValue) first.arguments[0]).span.text () == "1" && ((CfgIntegerValue) second.arguments[0]).span.text () == "2");
		assert (outer.arguments[0] == first.result && outer.arguments[1] == second.result);
		var ssa = SsaBuilder.build (cfg);
		var body = ssa.functions[2].entry;
		assert (body.instructions.length == 3);
		var a = (SsaCallInstruction) body.instructions[0];
		var b = (SsaCallInstruction) body.instructions[1];
		var c = (SsaCallInstruction) body.instructions[2];
		assert (a.target == ssa.functions[0] && b.target == ssa.functions[0] && c.target == ssa.functions[1]);
		assert (((SsaIntegerConstant) a.arguments[0]).span.text () == "1" && ((SsaIntegerConstant) b.arguments[0]).span.text () == "2");
		assert (c.arguments[0] == a.result && c.arguments[1] == b.result && ((SsaReturn) body.terminator).value == c.result);
		var arithmetic = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ("int id(int x){return x;} int f(){return id(1 + 2);}"))));
		var ops = arithmetic.functions[1].entry.instructions;
		assert (ops.length == 2 && ops[0] is SsaBinaryInstruction && ((SsaCallInstruction) ops[1]).arguments[0] == ops[0].result);
	} catch (GLib.Error error) {
		GLib.error ("Nested call order failed: %s", error.message);
	}
}

private void statements() {
	try {
		var cfg = cfg_fixture ("statements");
		var ssa = SsaBuilder.build (cfg);
		for (int f = 2; f < 4; f++) {
			assert (cfg.functions[f].entry.instructions.length == 2 && ssa.functions[f].entry.instructions.length == 2);
			for (int i = 0; i < 2; i++) {
				var call = (CfgCallInstruction) cfg.functions[f].entry.instructions[i];
				var lowered = (SsaCallInstruction) ssa.functions[f].entry.instructions[i];
				assert (call.target == cfg.functions[f - 2] && lowered.target == ssa.functions[f - 2]);
				assert (f == 2 ? call.result == null && lowered.result == null : call.result != null && lowered.result != null);
			}
		}
		var discarded = ssa.functions[3].entry;
		assert (discarded.instructions[0].result != discarded.instructions[1].result);
		assert (((SsaReturn) discarded.terminator).value == null);
	} catch (GLib.Error error) {
		GLib.error ("Call statements failed: %s", error.message);
	}
}

private void places_and_branches() {
	try {
		var cfg = cfg_fixture ("places-calls");
		var function = cfg.functions[1];
		var instructions = function.entry.instructions;
		assert (instructions.length == 5);
		var initialization = (CfgInitialize) instructions[1];
		var store = (CfgStore) instructions[3];
		assert (initialization.target == function.locals[0] && store.target == initialization.target);
		assert (initialization.value == ((CfgCallInstruction) instructions[0]).result);
		assert (store.value == ((CfgCallInstruction) instructions[2]).result);
		assert (((CfgBinaryValue) ((CfgReturn) function.entry.terminator).value).left == ((CfgCallInstruction) instructions[4]).result);
		assert (SsaBuilder.build (cfg).functions[1].entry.instructions.length == 4);
		var branches = cfg_fixture ("branch-calls");
		var ssa = SsaBuilder.build (branches);
		var chosen = ssa.functions[1];
		assert (chosen.blocks[1].instructions.length == 1 && chosen.blocks[2].instructions.length == 2);
		var inner = (SsaCallInstruction) chosen.blocks[2].instructions[0];
		var outer = (SsaCallInstruction) chosen.blocks[2].instructions[1];
		assert (inner.arguments[0] == chosen.parameters[1] && outer.arguments[0] == inner.result);
		assert (((SsaBranch) chosen.blocks[2].terminator).edge.arguments[0] == outer.result);
		var core = CoreBuilder.build (check (fixture ("branch-calls")));
		var branch = (CoreIf) core.functions[1].body.statements[1];
		assert (((CoreStore) branch.then_block.statements[0]).target == ((CoreStore) branch.else_block.statements[0]).target);
	} catch (GLib.Error error) {
		GLib.error ("Calls with Places failed: %s", error.message);
	}
}

private void choose_join() {
	try {
		var ssa = SsaBuilder.build (cfg_fixture ("choose-call"));
		var function = ssa.functions[1];
		var join = function.blocks[3];
		assert (join.parameters.length == 1 && join.parameters[0].name == "x");
		for (int i = 1; i < 3; i++) {
			var arm = function.blocks[i];
			assert (arm.instructions.length == 1);
			var call = (SsaCallInstruction) arm.instructions[0];
			assert (call.target == ssa.functions[0] && call.arguments[0] == function.parameters[i]);
			var edge = ((SsaBranch) arm.terminator).edge;
			assert (edge.target == join && edge.arguments.length == 1 && edge.arguments[0] == call.result);
		}
		assert (((SsaReturn) join.terminator).value == join.parameters[0]);
	} catch (GLib.Error error) {
		GLib.error ("Call SSA join failed: %s", error.message);
	}
}

private void bool_calls() {
	try {
		var cfg = cfg_fixture ("bool-calls");
		var call = (CfgCallInstruction) cfg.functions[2].entry.instructions[0];
		assert (call.result.semantic_type.kind == TypeKind.BOOL);
		assert (((CfgConditionalBranch) cfg.functions[2].entry.terminator).condition == call.result);
		var ssa = SsaBuilder.build (cfg);
		var prefix = (SsaPrefixInstruction) ssa.functions[1].entry.instructions[1];
		assert (prefix.operator_kind == PrefixOperator.NOT && prefix.operand == ssa.functions[1].entry.instructions[0].result);
		assert (((SsaConditionalBranch) ssa.functions[2].entry.terminator).condition == ssa.functions[2].entry.instructions[0].result);
	} catch (GLib.Error error) {
		GLib.error ("Bool calls failed: %s", error.message);
	}
}

private void huge_argument() {
	var parsed = Parser.parse (new SourceFile.from_text ("huge-argument.astra", fixture ("huge-argument")));
	string digits = "000" + string.nfill (1000, '9');
	assert (parsed.diagnostic == null && SyntaxDump.format (parsed.unit).contains (digits));
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.program == null && result.diagnostic.message == "integer literal is out of range for 'int'");
	assert (result.diagnostic.span.text () == digits && result.diagnostic.span.end - result.diagnostic.span.start == 1003);
}

private void unreachable_projection() {
	try {
		var cfg = cfg_fixture ("unreachable-call");
		string before = CfgDump.format (cfg);
		var function = cfg.functions[1];
		assert (function.blocks.length == 2 && function.blocks[1].instructions[0] is CfgCallInstruction);
		assert (!CfgReachability.analyze (function).is_reachable (function.blocks[1]));
		var ssa = SsaBuilder.build (cfg);
		assert (ssa.functions[1].blocks.length == 1 && ssa.functions[1].entry.instructions.length == 0);
		assert (CfgDump.format (cfg) == before && !SsaDump.format (ssa).contains ("= call"));
	} catch (GLib.Error error) {
		GLib.error ("Unreachable call projection failed: %s", error.message);
	}
}

private void invalid_checked_target(bool expired) {
	var program = check ("int f(){return 1;} int g(){return f();}");
	CheckedProgram? other = check ("int f(){return 1;}");
	var span = program.functions[1].span;
	var call = new CheckedCallExpression (span, other.functions[0].symbol, new GenericArray<CheckedExpression> ());
	program.functions[1].body.statements[0] = new CheckedReturnStatement (span, call);
	if (expired) {
		other = null;
		assert (call.target == null);
	}
	try {
		CoreBuilder.build (program);
	} catch (CoreError error) {
		assert (error is CoreError.INVALID_CHECKED_MODEL && error.message == "internal Core construction error: call target is not owned by the checked program");
		return;
	}
	GLib.error ("Same-spelled foreign checked callee was accepted");
}

private void foreign_checked_target() {
	invalid_checked_target (false);
}

private void expired_checked_target() {
	invalid_checked_target (true);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/calls/lifetime/forward", forward_lifetime);
	Test.add_func ("/calls/lifetime/self-recursion", self_lifetime);
	Test.add_func ("/calls/lifetime/mutual-recursion", mutual_lifetime);
	Test.add_func ("/calls/order/binary", ordered_binary);
	Test.add_func ("/calls/order/nested", nested_order);
	Test.add_func ("/calls/statements", statements);
	Test.add_func ("/calls/places-and-branches", places_and_branches);
	Test.add_func ("/calls/choose-join", choose_join);
	Test.add_func ("/calls/bool", bool_calls);
	Test.add_func ("/calls/huge-argument", huge_argument);
	Test.add_func ("/calls/unreachable-projection", unreachable_projection);
	Test.add_func ("/calls/foreign-checked-target", foreign_checked_target);
	Test.add_func ("/calls/expired-checked-target", expired_checked_target);
	return Test.run ();
}

}
