// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Loops {
private delegate void TestBody() throws GLib.Error;

private class Case : Object {
	internal TestBody body;
	internal Case (owned TestBody body) {
		this.body = (owned) body;
	}
}

private HashTable<string, Case> cases;

private void add(string path, owned TestBody body) {
	cases.insert (path, new Case ((owned) body));
	Test.add_func (path, () => {
			try {
				cases.lookup (Test.get_path ()).body ();
			} catch (GLib.Error error) {
				GLib.error ("%s failed: %s", Test.get_path (), error.message);
			}
		});
}

private string fixture(string name) throws FileError {
	string text;
	FileUtils.get_contents ("tests/loop/fixtures/" + name + ".astra", out text);
	return text;
}

private CompilationUnitSyntax parse(string text) {
	var result = Parser.parse (new SourceFile.from_text ("loop.astra", text));
	assert (result.diagnostic == null);
	return result.unit;
}

private CheckedProgram check(string text) {
	var result = SemanticAnalyzer.analyze (parse (text));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.message);
	}
	return result.program;
}

private CfgProgram cfg(string name) throws GLib.Error {
	var result = CfgBuilder.build (CoreBuilder.build (check (fixture (name))));
	assert (CfgFlowChecker.check (result).diagnostic == null);
	return result;
}

private SsaProgram ssa(string name) throws GLib.Error {
	var program = SsaBuilder.build (cfg (name));
	SsaVerifier.verify (program);
	string dump = SsaDump.format (program);
	assert (dump == SsaDump.format (program));
	foreach (string forbidden in new string[] {"local-place", "(load", "(store", "(initialize", "undef", "poison"}) {
		assert (!dump.contains (forbidden));
	}
	return program;
}

private void integer(SsaValue value, string expected) {
	assert (value is SsaIntegerConstant);
	assert (((SsaIntegerConstant) value).value.to_string () == expected);
}

private void block_list(GenericArray<CfgBlock> actual, CfgBlock[] expected) {
	assert (actual.length == expected.length);
	for (int i = 0; i < expected.length; i++) {
		assert (actual[i] == expected[i]);
	}
}

private void syntax() throws GLib.Error {
	string text = fixture ("count");
	var unit = parse (text);
	var loop = (WhileStatementSyntax) unit.functions[0].body.statements[1];
	assert (loop.keyword.kind == TokenKind.WHILE && loop.keyword.spelling () == "while");
	assert (loop.open_paren.spelling () == "(" && loop.close_paren.spelling () == ")");
	assert (loop.condition.span.text () == "i < n");
	assert (loop.body.open_brace.spelling () == "{" && loop.body.close_brace.spelling () == "}");
	assert (loop.span.text ().has_prefix ("while (i < n) {") && loop.span.end == loop.body.span.end);
	assert (SyntaxDump.format (unit) == SyntaxDump.format (parse (text)));
	var nested = (WhileStatementSyntax) parse (fixture ("nested-loop")).functions[0].body.statements[2];
	assert (nested.body.statements[1] is WhileStatementSyntax);
	assert (((WhileStatementSyntax) parse ("void f(){while(true){}}").functions[0].body.statements[0]).body.statements.length == 0);
	for (int i = 0; i <= text.length; i++) {
		var result = Parser.parse (new SourceFile.from_text ("truncated.astra", text.substring (0, i)));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
}

private void keywords() {
	var lexer = new Lexer (new SourceFile.from_text ("keywords.astra", "while whileish while_ break continue for foreach do"));
	assert (lexer.next_token ().kind == TokenKind.WHILE);
	for (int i = 0; i < 2; i++) {
		assert (lexer.next_token ().kind == TokenKind.IDENTIFIER);
	}
	assert (lexer.next_token ().kind == TokenKind.BREAK);
	assert (lexer.next_token ().kind == TokenKind.CONTINUE);
	assert (lexer.next_token ().kind == TokenKind.FOR);
	assert (lexer.next_token ().kind == TokenKind.FOREACH);
	assert (lexer.next_token ().kind == TokenKind.IDENTIFIER);
	assert (lexer.next_token ().kind == TokenKind.EOF);
	assert (parse ("void f(){for(;;){break;}}").functions.length == 1);
}

private void depth() {
	var text = new StringBuilder ("void f(){");
	for (int i = 0; i < 255; i++) {
		text.append ("while(true){");
	}
	assert (SyntaxDump.format (parse (text.str + string.nfill (256, '}'))).contains ("(while"));
	var result = Parser.parse (new SourceFile.from_text ("deep.astra", text.str + "while(true){}" + string.nfill (256, '}')));
	assert (result.unit == null && result.diagnostic.message == "block nesting limit of 256 exceeded");
}

private void parse_error(string name, string text, string message) {
	add ("/loop/parser/error/" + name, () => {
			var result = Parser.parse (new SourceFile.from_text ("bad.astra", text));
			assert (result.unit == null && result.diagnostic != null);
			assert (result.diagnostic.message == message);
		});
}

private void semantic_error(string name, string text, string message) {
	add ("/loop/semantics/error/" + name, () => {
			var result = SemanticAnalyzer.analyze (parse (text));
			assert (result.program == null && result.diagnostic != null);
			assert (result.diagnostic.message == message);
		});
}

private void identities() throws GLib.Error {
	var checked_program = check (fixture ("body-local"));
	var f = checked_program.functions[0];
	var loop = (CheckedWhile) f.body.statements[1];
	assert (loop.condition.semantic_type == checked_program.types.bool_type && f.locals.length == 2);
	assert (((CheckedLocalReferenceExpression) ((CheckedBinaryExpression) loop.condition).left).local == f.locals[0]);
	var declaration = (CheckedLocalDeclaration) loop.body.statements[0];
	assert (declaration.local == f.locals[1]);
	assert (((CheckedLocalReferenceExpression) ((CheckedBinaryExpression) declaration.initializer).left).local == f.locals[0]);
	var assignment = (CheckedAssignment) loop.body.statements[1];
	assert (assignment.target == f.locals[0] && ((CheckedLocalReferenceExpression) assignment.expression).local == f.locals[1]);
	assert (((CheckedLocalReferenceExpression) ((CheckedReturnStatement) f.body.statements[2]).expression).local == f.locals[0]);
	assert (SemanticDump.format (checked_program).contains ("(while"));
	var core = CoreBuilder.build (checked_program);
	CoreVerifier.verify (core);
	var cf = core.functions[0];
	var cl = (CoreWhile) cf.body.statements[1];
	assert (cf.locals.length == 2 && cl.span.text () == loop.span.text ());
	assert (((CoreLoadValue) ((CoreBinaryValue) cl.condition).left).source == cf.locals[0]);
	var init = (CoreInitialize) cl.body.statements[0];
	assert (init.target == cf.locals[1] && ((CoreLoadValue) ((CoreBinaryValue) init.value).left).source == cf.locals[0]);
	var store = (CoreStore) cl.body.statements[1];
	assert (store.target == cf.locals[0] && ((CoreLoadValue) store.value).source == cf.locals[1]);
	assert (((CoreLoadValue) ((CoreReturn) cf.body.statements[2]).value).source == cf.locals[0]);
	string dump = CoreDump.format (core);
	assert (dump.contains ("(while") && !dump.contains ("branch") && !dump.contains ("block #"));
}

private void scopes() {
	var program = check ("int f(bool c){int outer = 0;while(c){int x = 1;if(c){outer = x;}while(c){int y = x;outer = y;}}while(c){int x = 2;outer = x;}int x = outer;return x;}");
	var f = program.functions[0];
	assert (f.locals.length == 5);
	for (int i = 0; i < 5; i++) {
		assert (f.locals[i].ordinal == i);
	}
	assert (f.locals[1].name == "x" && f.locals[3].name == "x" && f.locals[4].name == "x");
	assert (f.locals[1] != f.locals[3] && f.locals[3] != f.locals[4]);
	var outer = (CheckedWhile) f.body.statements[1];
	var inner = (CheckedWhile) outer.body.statements[2];
	assert (((CheckedLocalReferenceExpression) ((CheckedLocalDeclaration) inner.body.statements[0]).initializer).local == f.locals[1]);
	assert (((CheckedAssignment) inner.body.statements[1]).target == f.locals[0]);
}

private void graph() throws GLib.Error {
	var program = cfg ("count");
	var f = program.functions[0];
	var bs = f.blocks;
	assert (bs.length == 4);
	assert (((CfgBranch) bs[0].terminator).target == bs[1]);
	var header = (CfgConditionalBranch) bs[1].terminator;
	assert (header.true_target == bs[2] && header.false_target == bs[3]);
	assert (((CfgBranch) bs[2].terminator).target == bs[1] && bs[3].terminator is CfgReturn);
	assert (bs[0].instructions[0] is CfgInitialize && bs[2].instructions[0] is CfgStore);
	assert (((CfgLoadValue) ((CfgBinaryValue) header.condition).left).source == f.locals[0]);
	var reachable = CfgReachability.analyze (f);
	for (int i = 0; i < 4; i++) {
		assert (bs[i].ordinal == i && reachable.is_reachable (bs[i]));
	}
	var incoming = CfgPredecessors.analyze (f);
	block_list (incoming.predecessors (bs[1]), {bs[0], bs[2]});
	block_list (incoming.predecessors (bs[2]), {bs[1]});
	block_list (incoming.predecessors (bs[3]), {bs[1]});
	var d = CfgDominance.analyze (f);
	block_list (d.dominators (bs[0]), {bs[0]});
	block_list (d.dominators (bs[1]), {bs[0], bs[1]});
	block_list (d.dominators (bs[2]), {bs[0], bs[1], bs[2]});
	block_list (d.dominators (bs[3]), {bs[0], bs[1], bs[3]});
	assert (d.immediate_dominator (bs[0]) == null && d.immediate_dominator (bs[1]) == bs[0]);
	assert (d.immediate_dominator (bs[2]) == bs[1] && d.immediate_dominator (bs[3]) == bs[1]);
	assert (!d.dominates (bs[2], bs[1]) && !d.dominates (bs[2], bs[3]));
	block_list (d.dominance_frontier (bs[0]), {});
	block_list (d.dominance_frontier (bs[1]), {bs[1]});
	block_list (d.dominance_frontier (bs[2]), {bs[1]});
	block_list (d.dominance_frontier (bs[3]), {});
	Test.message ("count: preds(b1)=[b0,b2]; idoms=[none,b0,b1,b1]; DF(b1)=DF(b2)={b1}");
}

private void carried() throws GLib.Error {
	var program = ssa ("count");
	var f = program.functions[0];
	var bs = f.blocks;
	assert (bs.length == 4 && bs[1].parameters.length == 1);
	assert (bs[0].parameters.length == 0 && bs[2].parameters.length == 0 && bs[3].parameters.length == 0);
	var current = bs[1].parameters[0];
	assert (current.name == "i" && current.source_local_ordinal == 0);
	var entry = ((SsaBranch) bs[0].terminator).edge;
	assert (entry.target == bs[1] && entry.arguments.length == 1);
	integer (entry.arguments[0], "0");
	var condition = (SsaBinaryInstruction) bs[1].instructions[0];
	assert (condition.operator_kind == BinaryOperator.LESS && condition.left == current && condition.right == f.parameters[0]);
	assert (((SsaConditionalBranch) bs[1].terminator).condition == condition.result);
	var next = (SsaBinaryInstruction) bs[2].instructions[0];
	assert (next.operator_kind == BinaryOperator.ADD && next.left == current);
	integer (next.right, "1");
	var backedge = ((SsaBranch) bs[2].terminator).edge;
	assert (backedge.target == bs[1] && backedge.arguments.length == 1 && backedge.arguments[0] == next.result);
	assert (((SsaReturn) bs[3].terminator).value == current);
}

private void multiple() throws GLib.Error {
	var f = ssa ("accumulate").functions[0];
	var h = f.blocks[1];
	assert (h.parameters.length == 2 && h.parameters[0].name == "i" && h.parameters[1].name == "sum");
	for (int i = 0; i < 2; i++) {
		assert (h.parameters[i].source_local_ordinal == i);
		integer (((SsaBranch) f.entry.terminator).edge.arguments[i], "0");
	}
	var sum = (SsaBinaryInstruction) f.blocks[2].instructions[0];
	var step = (SsaBinaryInstruction) f.blocks[2].instructions[1];
	assert (sum.left == h.parameters[1] && sum.right == h.parameters[0] && step.left == h.parameters[0]);
	var edge = ((SsaBranch) f.blocks[2].terminator).edge;
	assert (edge.arguments[0] == step.result && edge.arguments[1] == sum.result);
	assert (((SsaReturn) f.blocks[3].terminator).value == h.parameters[1]);
}

private void body_local() throws GLib.Error {
	var f = ssa ("body-local").functions[0];
	assert (f.blocks[1].parameters.length == 1 && f.blocks[1].parameters[0].source_local_ordinal == 0);
	for (int b = 0; b < f.blocks.length; b++) {
		for (int p = 0; p < f.blocks[b].parameters.length; p++) {
			assert (f.blocks[b].parameters[p].source_local_ordinal != 1);
		}
	}
	assert (f.blocks[2].instructions.length == 1);
	assert (((SsaBranch) f.blocks[2].terminator).edge.arguments[0] == f.blocks[2].instructions[0].result);
}

private void boolean() throws GLib.Error {
	var f = ssa ("bool-carried").functions[0];
	var h = f.blocks[1];
	assert (h.parameters.length == 2 && h.parameters[1].semantic_type.kind == TypeKind.BOOL);
	assert (((SsaBooleanConstant) ((SsaBranch) f.entry.terminator).edge.arguments[1]).literal == BooleanLiteral.FALSE);
	var flip = (SsaPrefixInstruction) f.blocks[2].instructions[0];
	assert (flip.operator_kind == PrefixOperator.NOT && flip.operand == h.parameters[1]);
	assert (((SsaBranch) f.blocks[2].terminator).edge.arguments[1] == flip.result);
	assert (((SsaConditionalBranch) f.blocks[3].terminator).condition == h.parameters[1]);
}

private void nested() throws GLib.Error {
	var cf = cfg ("nested-loop").functions[0];
	var bs = cf.blocks;
	assert (bs.length == 7);
	var d = CfgDominance.analyze (cf);
	int[] idoms = {
		0, 0, 1, 1, 2, 4, 4
	};
	for (int b = 1; b < 7; b++) {
		assert (d.immediate_dominator (bs[b]) == bs[idoms[b]]);
	}
	block_list (d.dominance_frontier (bs[4]), {bs[1], bs[4]});
	block_list (d.dominance_frontier (bs[5]), {bs[4]});
	block_list (d.dominance_frontier (bs[6]), {bs[1]});
	var f = ssa ("nested-loop").functions[0];
	var outer = f.blocks[1];
	var inner = f.blocks[4];
	assert (outer.parameters.length == 2 && inner.parameters.length == 2);
	assert (outer.parameters[0].name == "outer" && outer.parameters[1].name == "total");
	assert (inner.parameters[0].name == "total" && inner.parameters[1].name == "inner");
	var enter_inner = ((SsaBranch) f.blocks[2].terminator).edge;
	assert (enter_inner.arguments[0] == outer.parameters[1]);
	integer (enter_inner.arguments[1], "0");
	var back_inner = ((SsaBranch) f.blocks[5].terminator).edge;
	assert (back_inner.arguments[0] == f.blocks[5].instructions[0].result && back_inner.arguments[1] == f.blocks[5].instructions[1].result);
	var back_outer = ((SsaBranch) f.blocks[6].terminator).edge;
	assert (back_outer.target == outer && back_outer.arguments[0] == f.blocks[6].instructions[0].result && back_outer.arguments[1] == inner.parameters[0]);
	assert (((SsaReturn) f.blocks[3].terminator).value == outer.parameters[1]);
}

private void calls() throws GLib.Error {
	var cf = cfg ("call-loop").functions[2];
	assert (cf.entry.instructions.length == 1 && cf.blocks[1].instructions.length == 1);
	assert (cf.blocks[1].instructions[0] is CfgCallInstruction && cf.blocks[2].instructions[0] is CfgCallInstruction);
	var program = ssa ("call-loop");
	var f = program.functions[2];
	var current = f.blocks[1].parameters[0];
	var condition = (SsaCallInstruction) f.blocks[1].instructions[0];
	var step = (SsaCallInstruction) f.blocks[2].instructions[0];
	assert (condition.target == program.functions[0] && step.target == program.functions[1]);
	assert (condition.arguments[0] == current && step.arguments[0] == current);
	assert (((SsaConditionalBranch) f.blocks[1].terminator).condition == condition.result);
	assert (((SsaBranch) f.blocks[2].terminator).edge.arguments[0] == step.result);
	var ordered = ssa ("condition-order").functions[2];
	assert (ordered.entry.instructions.length == 0 && ordered.blocks[1].instructions.length == 4);
	assert (((SsaBinaryInstruction) ordered.blocks[1].instructions[0]).operator_kind == BinaryOperator.DIVIDE);
	assert (ordered.blocks[1].instructions[1] is SsaCallInstruction);
	assert (((SsaBinaryInstruction) ordered.blocks[1].instructions[2]).operator_kind == BinaryOperator.ADD);
	assert (ordered.blocks[1].instructions[3] is SsaCallInstruction);
}

private void returns() throws GLib.Error {
	var f = ssa ("return-loop").functions[0];
	assert (f.blocks.length == 6 && f.blocks[1].parameters.length == 1);
	assert (f.blocks[4].terminator is SsaReturn && f.blocks[4].terminator.successors ().length == 0);
	assert (((SsaReturn) f.blocks[4].terminator).value == f.blocks[1].parameters[0]);
	assert (((SsaBranch) f.blocks[5].terminator).edge.target == f.blocks[1]);
	assert (((SsaBranch) f.blocks[5].terminator).edge.arguments[0] == f.blocks[5].instructions[0].result);
}

private void unreachable() throws GLib.Error {
	var program = cfg ("post-return");
	for (int i = 0; i < 2; i++) {
		var f = program.functions[i];
		var r = CfgReachability.analyze (f);
		assert (f.blocks.length == 5 && f.entry.terminator is CfgReturn);
		for (int b = 1; b < 5; b++) {
			assert (!r.is_reachable (f.blocks[b]));
		}
		assert (ssa ("post-return").functions[i].blocks.length == 1);
	}
	var tail = cfg ("body-return-tail");
	for (int i = 0; i < 2; i++) {
		var f = tail.functions[i];
		var r = CfgReachability.analyze (f);
		var last = f.blocks[f.blocks.length - 1];
		assert (!r.is_reachable (last) && ((CfgBranch) last.terminator).target == f.blocks[1]);
		block_list (CfgPredecessors.analyze (f).predecessors (f.blocks[1]), {f.entry});
		var sf = ssa ("body-return-tail").functions[i];
		assert (sf.blocks[1].parameters.length == 0);
		integer (((SsaReturn) sf.blocks[3].terminator).value, "0");
	}
}

private void conservative_flow() throws GLib.Error {
	var program = cfg ("constant");
	for (int f = 0; f < 2; f++) {
		var function = program.functions[f];
		var r = CfgReachability.analyze (function);
		assert (function.blocks[1].terminator.successors ().length == 2);
		assert (r.is_reachable (function.blocks[2]) && r.is_reachable (function.blocks[3]));
	}
	foreach (string condition in new string[] {"c", "true", "false"}) {
		var core = CoreBuilder.build (check ("int f(bool c){while(" + condition + "){return 1;}}"));
		CoreVerifier.verify (core);
		assert (CfgFlowChecker.check (CfgBuilder.build (core)).diagnostic != null);
	}
}

// Stable object storage for GWeakRef; never relocate raw WeakRef structs.
private class Probe : Object {
	private WeakRef reference;
	internal Probe (Object target) {
		reference = WeakRef (target);
	}
	internal void gone() {
		assert (reference.get () == null);
	}
}

private void lifetime(string name) throws GLib.Error {
	CompilationUnitSyntax? syntax = parse (fixture (name));
	CheckedProgram? checked_program = SemanticAnalyzer.analyze (syntax).program;
	var syntax_ref = new Probe (syntax);
	var checked_ref = new Probe (checked_program);
	var symbol_ref = new Probe (checked_program.functions[0].locals[0]);
	var source_ref = new Probe (syntax.span.file);
	var int_ref = new Probe (checked_program.types.int_type);
	CoreProgram? core = CoreBuilder.build (checked_program);
	var core_ref = new Probe (core);
	var loop_ref = new Probe (core.functions[0].body.statements[name == "nested-loop" ? 2 : 1]);
	var place_ref = new Probe (core.functions[0].locals[0]);
	syntax = null;
	checked_program = null;
	syntax_ref.gone ();
	checked_ref.gone ();
	symbol_ref.gone ();
	CoreVerifier.verify (core);
	CfgProgram? graph = CfgBuilder.build (core);
	core = null;
	core_ref.gone ();
	loop_ref.gone ();
	place_ref.gone ();
	var graph_refs = new GenericArray<Probe> ();
	graph_refs.add (new Probe (graph.functions[0]));
	graph_refs.add (new Probe (graph.functions[0].locals[0]));
	for (int b = 0; b < graph.functions[0].blocks.length; b++) {
		graph_refs.add (new Probe (graph.functions[0].blocks[b]));
		graph_refs.add (new Probe (graph.functions[0].blocks[b].terminator));
	}
	SsaProgram? values = SsaBuilder.build (graph);
	graph = null;
	for (int i = 0; i < graph_refs.length; i++) {
		graph_refs[i].gone ();
	}
	SsaVerifier.verify (values);
	assert (SsaDump.format (values).contains ("(arguments"));
	var value_refs = new GenericArray<Probe> ();
	value_refs.add (new Probe (values.functions[0]));
	for (int b = 0; b < values.functions[0].blocks.length; b++) {
		value_refs.add (new Probe (values.functions[0].blocks[b]));
		value_refs.add (new Probe (values.functions[0].blocks[b].terminator));
		for (int p = 0; p < values.functions[0].blocks[b].parameters.length; p++) {
			value_refs.add (new Probe (values.functions[0].blocks[b].parameters[p]));
		}
		for (int i = 0; i < values.functions[0].blocks[b].instructions.length; i++) {
			value_refs.add (new Probe (values.functions[0].blocks[b].instructions[i]));
			value_refs.add (new Probe (values.functions[0].blocks[b].instructions[i].result));
		}
	}
	values = null;
	for (int i = 0; i < value_refs.length; i++) {
		value_refs[i].gone ();
	}
	source_ref.gone ();
	int_ref.gone ();
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/loop/parser/structure", syntax);
	add ("/loop/parser/keywords-boundaries", () => keywords ());
	add ("/loop/parser/depth", () => depth ());
	parse_error ("missing-condition", "void f(){while(){}}", "expected expression");
	parse_error ("malformed-condition", "void f(){while(true ==){}}", "expected expression");
	parse_error ("missing-open", "void f(){while true{}}", "expected '(' after 'while'");
	parse_error ("missing-close", "void f(){while(true{}}", "expected ')' after while condition");
	parse_error ("missing-braces", "void f(){while(true)return;}", "expected '{' before while body");
	parse_error ("missing-body-close", "void f(){while(true){", "expected '}' after while body");
	parse_error ("malformed-body", "void f(){while(true){x = ;}}", "expected expression");
	add ("/loop/parser/break", () => { assert (parse ("void f(){while(true){break;}}").functions.length == 1);
	});
	add ("/loop/parser/continue", () => { assert (parse ("void f(){while(true){continue;}}").functions.length == 1);
	});
	parse_error ("for", "void f(){for(;){}}", "expected expression");
	parse_error ("do", "void f(){do{}while(true);}", "expected '=' after assignment target");
	add ("/loop/parser/eager-and", () => { assert (parse ("void f(){while(true & false){}}").functions.length == 1);
	});
	add ("/loop/parser/eager-or", () => { assert (parse ("void f(){while(true | false){}}").functions.length == 1);
	});
	semantic_error ("int-condition", "void f(){while(1){}}", "while condition must have type 'bool', found 'int'");
	semantic_error ("escape", "int f(bool c){while(c){int x = 1;}return x;}", "unknown name 'x'");
	semantic_error ("self-initializer", "void f(bool c){while(c){int x = x + 1;}}", "unknown name 'x'");
	semantic_error ("shadow-local", "void f(bool c){int x = 0;while(c){int x = 1;}}", "duplicate local 'x'");
	semantic_error ("shadow-parameter", "void f(int x,bool c){while(c){int x = 1;}}", "local 'x' conflicts with parameter");
	semantic_error ("body-in-condition", "void f(){while(x < 1){int x = 0;}}", "unknown name 'x'");
	semantic_error ("nested-escape", "void f(bool c){while(c){while(c){int x = 1;}x = 2;}}", "unknown assignment target 'x'");
	add ("/loop/semantics/scopes", () => scopes ());
	add ("/loop/core/identities", identities);
	add ("/loop/cfg/graph-dominance-frontiers", graph);
	add ("/loop/cfg/conservative-flow", conservative_flow);
	add ("/loop/cfg/unreachable", unreachable);
	add ("/loop/ssa/count", carried);
	add ("/loop/ssa/multiple", multiple);
	add ("/loop/ssa/body-local", body_local);
	add ("/loop/ssa/bool", boolean);
	add ("/loop/ssa/nested", nested);
	add ("/loop/ssa/calls-order", calls);
	add ("/loop/ssa/returns", returns);
	add ("/loop/lifetime/count", () => lifetime ("count"));
	add ("/loop/lifetime/nested", () => lifetime ("nested-loop"));
	return Test.run ();
}
}
