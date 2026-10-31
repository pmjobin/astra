// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.LoopControl {
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
	FileUtils.get_contents ("tests/loopctrl/fixtures/" + name + ".astra", out text);
	return text;
}

private CompilationUnitSyntax parse(string text) {
	var result = Parser.parse (new SourceFile.from_text ("loop-control.astra", text));
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

private void syntax() {
	var lexer = new Lexer (new SourceFile.from_text ("tokens.astra", "break continue breaker continue_"));
	TokenKind[] kinds = {
		TokenKind.BREAK, TokenKind.CONTINUE, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.EOF
	};
	foreach (var kind in kinds) {
		assert (lexer.next_token ().kind == kind);
	}
	string text = "void f(){while(true){if(false){break;}continue;}}";
	var unit = parse (text);
	var loop = (WhileStatementSyntax) unit.functions[0].body.statements[0];
	var stopped = (BreakStatementSyntax) ((IfStatementSyntax) loop.body.statements[0]).then_body.statements[0];
	var resumed = (ContinueStatementSyntax) loop.body.statements[1];
	assert (stopped.keyword.kind == TokenKind.BREAK && stopped.keyword.span.text () == "break" && stopped.semicolon.spelling () == ";" && stopped.span.text () == "break;");
	assert (resumed.keyword.kind == TokenKind.CONTINUE && resumed.keyword.span.text () == "continue" && resumed.semicolon.spelling () == ";" && resumed.span.text () == "continue;");
	assert (SyntaxDump.format (unit).contains ("(break)") && SyntaxDump.format (unit).contains ("(continue)"));
	for (int i = 0; i <= text.length; i++) {
		var result = Parser.parse (new SourceFile.from_text ("truncated.astra", text.substring (0, i)));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
}

private void outside(string keyword) {
	foreach (string text in new string[] {"int f(){" + keyword + ";return 0;}", "void f(){while(true){break;}" + keyword + ";}", "void f(){while(true){continue;}}void g(){" + keyword + ";}", "void f(){if(true){" + keyword + ";}}"}) {
		var result = SemanticAnalyzer.analyze (parse (text));
		assert (result.program == null && result.diagnostic.message == "'%s' is only valid inside a loop".printf (keyword));
		assert (result.diagnostic.span.text () == keyword && result.diagnostic.span.start == text.last_index_of (keyword));
	}
}

private void rejected(string text, string message) {
	var result = Parser.parse (new SourceFile.from_text ("invalid.astra", text));
	assert (result.unit == null && result.diagnostic.message == message);
}

private void boundaries() {
	foreach (string keyword in new string[] {"break", "continue"}) {
		foreach (string tail in new string[] {"", " 1;", " label;", " (1);"}) {
			rejected ("void f(){while(true){" + keyword + tail + "}}", "expected ';' after '%s'".printf (keyword));
		}
		rejected ("int f(){return " + keyword + ";}", "expected expression");
		rejected ("int f(){int x = 0;x = " + keyword + ";return x;}", "expected expression");
	}
	rejected ("void f(){label:while(true){break;}}", "unexpected character ':'");
	rejected ("void f(){for(;){}}", "expected expression");
	rejected ("void f(){do{}while(true);}", "expected '=' after assignment target");
	assert (Parser.parse (new SourceFile.from_text ("eager-and", "void f(){while(true & false){}}")).unit != null);
	assert (Parser.parse (new SourceFile.from_text ("eager-or", "void f(){while(true | false){}}")).unit != null);
}

private void identities() throws GLib.Error {
	var checked_program = check (fixture ("nested-loop-control"));
	var outer = (CheckedWhile) checked_program.functions[0].body.statements[2];
	var inner = (CheckedWhile) outer.body.statements[1];
	var inner_continue = (CheckedContinue) ((CheckedIf) inner.body.statements[1]).then_body.statements[0];
	var inner_break = (CheckedBreak) ((CheckedIf) inner.body.statements[2]).then_body.statements[0];
	var outer_continue = (CheckedContinue) ((CheckedIf) outer.body.statements[3]).then_body.statements[0];
	var outer_break = (CheckedBreak) ((CheckedIf) outer.body.statements[4]).then_body.statements[0];
	assert (outer.target != inner.target && outer.target.ordinal == 0 && inner.target.ordinal == 1);
	assert (outer.target.span.text () == "while" && inner.target.span.text () == "while");
	assert (inner_continue.target == inner.target && inner_break.target == inner.target);
	assert (outer_continue.target == outer.target && outer_break.target == outer.target);
	assert (inner_break.target != outer_break.target && inner_continue.target != outer_continue.target);
	var core = CoreBuilder.build (checked_program);
	CoreVerifier.verify (core);
	var co = (CoreWhile) core.functions[0].body.statements[2];
	var ci = (CoreWhile) co.body.statements[1];
	assert (co.target != ci.target && co.target.ordinal == outer.target.ordinal && ci.target.ordinal == inner.target.ordinal);
	assert (co.target.span.start == outer.target.span.start && ci.target.span.start == inner.target.span.start);
	assert (((CoreContinue) ((CoreIf) ci.body.statements[1]).then_block.statements[0]).target == ci.target);
	assert (((CoreBreak) ((CoreIf) ci.body.statements[2]).then_block.statements[0]).target == ci.target);
	assert (((CoreContinue) ((CoreIf) co.body.statements[3]).then_block.statements[0]).target == co.target);
	assert (((CoreBreak) ((CoreIf) co.body.statements[4]).then_block.statements[0]).target == co.target);
	foreach (string dump in new string[] {SemanticDump.format (checked_program), CoreDump.format (core)}) {
		foreach (string expected in new string[] {"(while #0", "(while #1", "(break #0)", "(break #1)", "(continue #0)", "(continue #1)"}) {
			assert (dump.contains (expected));
		}
	}
}

private void ordinals() throws GLib.Error {
	string text = "void f(){while(true){while(false){continue;}while(true){break;}continue;}while(false){break;}}void g(){while(true){break;}}";
	var program = check (text);
	var outer = (CheckedWhile) program.functions[0].body.statements[0];
	assert (outer.target.ordinal == 0);
	assert (((CheckedWhile) outer.body.statements[0]).target.ordinal == 1);
	assert (((CheckedWhile) outer.body.statements[1]).target.ordinal == 2);
	assert (((CheckedContinue) outer.body.statements[2]).target == outer.target);
	assert (((CheckedWhile) program.functions[0].body.statements[1]).target.ordinal == 3);
	var next_function = (CheckedWhile) program.functions[1].body.statements[0];
	assert (next_function.target.ordinal == 0 && next_function.target != outer.target);
	assert (SemanticDump.format (program) == SemanticDump.format (check (text)));
	assert (CoreDump.format (CoreBuilder.build (program)) == CoreDump.format (CoreBuilder.build (check (text))));
}

private void invalid_checked_targets() throws GLib.Error {
	for (int kind = 0; kind < 3; kind++) {
		var program = check ("void f(){while(true){break;continue;}}void g(){while(true){break;}}");
		var loop = (CheckedWhile) program.functions[0].body.statements[0];
		CheckedLoopTarget? target = kind == 2 ? ((CheckedWhile) program.functions[1].body.statements[0]).target : new CheckedLoopTarget (loop.target.span, 0);
		loop.body.statements[0] = new CheckedBreak (loop.span, target);
		loop.body.statements[1] = new CheckedContinue (loop.span, target);
		if (kind == 0) {
			target = null;
			assert (((CheckedBreak) loop.body.statements[0]).target == null && ((CheckedContinue) loop.body.statements[1]).target == null);
			assert (SemanticDump.format (program).contains ("(break <expired>)"));
		}
		for (int repeat = 0; repeat < 2; repeat++) {
			try {
				CoreBuilder.build (program);
				GLib.error ("Invalid checked loop target accepted");
			} catch (CoreError error) {
				assert (error.code == CoreError.INVALID_CHECKED_MODEL && error.message.contains ("expired or has no mapping"));
			}
		}
	}
}

private void graph_merges() throws GLib.Error {
	var f = cfg ("continue-merge").functions[0];
	var b = f.blocks;
	assert (b.length == 6);
	assert (((CfgBranch) b[4].terminator).target == b[1] && ((CfgBranch) b[5].terminator).target == b[1]);
	var p = CfgPredecessors.analyze (f);
	block_list (p.predecessors (b[1]), {b[0], b[4], b[5]});
	block_list (p.predecessors (b[5]), {b[2]});
	var d = CfgDominance.analyze (f);
	assert (d.immediate_dominator (b[4]) == b[2] && d.immediate_dominator (b[5]) == b[2]);
	assert (d.immediate_dominator (b[3]) == b[1] && !d.dominates (b[4], b[5]));
	block_list (d.dominance_frontier (b[4]), {b[1]});
	block_list (d.dominance_frontier (b[5]), {b[1]});
	f = cfg ("break-merge").functions[0];
	b = f.blocks;
	assert (((CfgBranch) b[4].terminator).target == b[3]);
	p = CfgPredecessors.analyze (f);
	block_list (p.predecessors (b[3]), {b[1], b[4]});
	block_list (p.predecessors (b[5]), {b[2]});
	d = CfgDominance.analyze (f);
	assert (d.immediate_dominator (b[3]) == b[1] && !d.dominates (b[2], b[3]));
	block_list (d.dominance_frontier (b[4]), {b[3]});
	block_list (d.dominance_frontier (b[2]), {b[1], b[3]});
	Test.message ("continue preds(header)=[b0,b4,b5], DF(b4)=DF(b5)={header}; break preds(exit)=[b1,b4], DF(b4)={exit}");
}

private void multiple_graphs() throws GLib.Error {
	var program = cfg ("multiple-sites");
	var b = program.functions[0].blocks;
	var p = CfgPredecessors.analyze (program.functions[0]);
	block_list (p.predecessors (b[1]), {b[0], b[4], b[6], b[7]});
	var d = CfgDominance.analyze (program.functions[0]);
	foreach (int site in new int[] {4, 6, 7}) {
		assert (((CfgBranch) b[site].terminator).target == b[1]);
		block_list (d.dominance_frontier (b[site]), {b[1]});
	}
	b = program.functions[1].blocks;
	p = CfgPredecessors.analyze (program.functions[1]);
	block_list (p.predecessors (b[3]), {b[1], b[4], b[6]});
	d = CfgDominance.analyze (program.functions[1]);
	foreach (int site in new int[] {4, 6}) {
		assert (((CfgBranch) b[site].terminator).target == b[3]);
		block_list (d.dominance_frontier (b[site]), {b[3]});
	}
	assert (d.immediate_dominator (b[3]) == b[1]);
}

private void merge_values() throws GLib.Error {
	var f = ssa ("continue-merge").functions[0];
	var b = f.blocks;
	assert (b[1].parameters.length == 2 && b[1].parameters[0].name == "i" && b[1].parameters[1].name == "x");
	var next = b[2].instructions[0].result;
	for (int i = 0; i < 2; i++) {
		integer (((SsaBranch) b[0].terminator).edge.arguments[i], "0");
		var edge = ((SsaBranch) b[4 + i].terminator).edge;
		assert (edge.target == b[1] && edge.arguments[0] == next);
		integer (edge.arguments[1], i == 0 ? "10" : "20");
	}
	assert (((SsaReturn) b[3].terminator).value == b[1].parameters[1]);
	f = ssa ("break-merge").functions[0];
	b = f.blocks;
	assert (b[1].parameters.length == 1 && b[3].parameters.length == 1);
	assert (((SsaConditionalBranch) b[1].terminator).false_edge.arguments[0] == b[1].parameters[0]);
	integer (((SsaBranch) b[4].terminator).edge.arguments[0], "1");
	integer (((SsaBranch) b[5].terminator).edge.arguments[0], "2");
	assert (((SsaReturn) b[3].terminator).value == b[3].parameters[0]);
}

private void edge_values() throws GLib.Error {
	var program = ssa ("edge-state");
	var b = program.functions[0].blocks;
	assert (b[1].parameters.length == 0 && b[3].parameters.length == 1);
	integer (((SsaConditionalBranch) b[1].terminator).false_edge.arguments[0], "5");
	integer (((SsaBranch) b[2].terminator).edge.arguments[0], "10");
	b = program.functions[1].blocks;
	assert (((SsaBranch) b[4].terminator).edge.arguments[1] == b[1].parameters[1]);
	assert (((SsaBranch) b[5].terminator).edge.arguments[1] == b[5].instructions[0].result);
	b = program.functions[2].blocks;
	assert (((SsaBranch) b[2].terminator).edge.arguments[1] == b[2].instructions[1].result);
	b = program.functions[3].blocks;
	assert (((SsaBranch) b[2].terminator).edge.arguments[0] == b[2].instructions[0].result);
	b = program.functions[4].blocks;
	for (int i = 0; i < b.length; i++) {
		for (int p = 0; p < b[i].parameters.length; p++) {
			assert (b[i].parameters[p].name != "temp" && b[i].parameters[p].source_local_ordinal != 2);
		}
	}
	assert (((SsaBranch) b[4].terminator).edge.arguments[1] == b[1].parameters[1]);
	assert (((SsaReturn) b[3].terminator).value == b[1].parameters[1]);
	var sites = ssa ("multiple-sites");
	b = sites.functions[0].blocks;
	foreach (int site in new int[] {4, 6, 7}) {
		assert (((SsaBranch) b[site].terminator).edge.arguments[1] == b[site].instructions[0].result);
	}
	b = sites.functions[1].blocks;
	assert (b[3].parameters.length == 2 && b[3].parameters[1].name == "x");
	integer (((SsaBranch) b[4].terminator).edge.arguments[1], "10");
	integer (((SsaBranch) b[6].terminator).edge.arguments[1], "20");
}

private void nested_graph() throws GLib.Error {
	var cf = cfg ("nested-loop-control").functions[0];
	var b = cf.blocks;
	assert (b.length == 15);
	assert (((CfgBranch) b[7].terminator).target == b[4] && ((CfgBranch) b[9].terminator).target == b[6]);
	assert (((CfgBranch) b[11].terminator).target == b[1] && ((CfgBranch) b[13].terminator).target == b[3]);
	var p = CfgPredecessors.analyze (cf);
	block_list (p.predecessors (b[1]), {b[0], b[11], b[14]});
	block_list (p.predecessors (b[4]), {b[2], b[7], b[10]});
	block_list (p.predecessors (b[6]), {b[4], b[9]});
	var d = CfgDominance.analyze (cf);
	assert (d.immediate_dominator (b[6]) == b[4] && d.immediate_dominator (b[3]) == b[1]);
	block_list (d.dominance_frontier (b[7]), {b[4]});
	block_list (d.dominance_frontier (b[9]), {b[6]});
	var f = ssa ("nested-loop-control").functions[0];
	assert (f.blocks[1].parameters.length == 2 && f.blocks[4].parameters.length == 2);
	assert (f.blocks[1].parameters[0].name == "outer" && f.blocks[1].parameters[1].name == "total");
	assert (f.blocks[4].parameters[0].name == "total" && f.blocks[4].parameters[1].name == "inner");
	assert (((SsaBranch) f.blocks[7].terminator).edge.target == f.blocks[4] && ((SsaBranch) f.blocks[9].terminator).edge.target == f.blocks[6]);
	assert (((SsaBranch) f.blocks[7].terminator).edge.arguments[0] == f.blocks[4].parameters[0]);
	assert (((SsaBranch) f.blocks[10].terminator).edge.arguments[0] == f.blocks[10].instructions[0].result);
	assert (((SsaBranch) f.blocks[11].terminator).edge.arguments[1] == f.blocks[4].parameters[0]);
}

private void unreachable() throws GLib.Error {
	var program = cfg ("unreachable");
	var values = ssa ("unreachable");
	for (int i = 1; i <= 2; i++) {
		var f = program.functions[i];
		var b = f.blocks;
		assert (b.length == 5 && !CfgReachability.analyze (f).is_reachable (b[4]));
		assert (b[2].instructions[0] is CfgCallInstruction && b[2].instructions[2] is CfgCallInstruction);
		assert (((CfgBranch) b[2].terminator).target == b[i == 1 ? 3 : 1]);
		assert (b[4].instructions[0] is CfgStore && b[4].instructions[1] is CfgCallInstruction);
		assert (((CfgBranch) b[4].terminator).target == b[1]);
		assert (values.functions[i].blocks.length == 4);
		assert (values.functions[i].blocks[2].instructions.length == 2);
		assert (values.functions[i].blocks[2].instructions[0] is SsaCallInstruction && values.functions[i].blocks[2].instructions[1] is SsaCallInstruction);
		assert (!SsaDump.format (values).contains ("integer 99"));
	}
	var b = program.functions[3].blocks;
	assert (b[4].terminator is CfgReturn && b[4].terminator.successors ().length == 0);
	assert (((CfgBranch) b[6].terminator).target == b[3] && ((CfgBranch) b[7].terminator).target == b[1]);
}

private void flow() throws GLib.Error {
	foreach (string condition in new string[] {"c", "true", "false"}) {
		var core = CoreBuilder.build (check ("int f(bool c){while(" + condition + "){break;}}"));
		CoreVerifier.verify (core);
		var graph = CfgBuilder.build (core);
		assert (CfgFlowChecker.check (graph).diagnostic != null);
		assert (CfgReachability.analyze (graph.functions[0]).is_reachable (graph.functions[0].blocks[3]));
	}
}

private class Probe : Object {
	private WeakRef reference;
	internal Probe (Object target) {
		reference = WeakRef (target);
	}
	internal void gone() {
		assert (reference.get () == null);
	}
}

private void lifetime() throws GLib.Error {
	CheckedProgram? checked_program = check (fixture ("nested-loop-control"));
	var checked_refs = new GenericArray<Probe> ();
	checked_refs.add (new Probe (checked_program));
	var detached_checked = new GenericArray<CheckedStatement> ();
	{
		var outer = (CheckedWhile) checked_program.functions[0].body.statements[2];
		var inner = (CheckedWhile) outer.body.statements[1];
		checked_refs.add (new Probe (outer.target));
		checked_refs.add (new Probe (inner.target));
		checked_refs.add (new Probe (outer));
		checked_refs.add (new Probe (inner));
		detached_checked.add (((CheckedIf) outer.body.statements[3]).then_body.statements[0]);
		detached_checked.add (((CheckedIf) outer.body.statements[4]).then_body.statements[0]);
		detached_checked.add (((CheckedIf) inner.body.statements[1]).then_body.statements[0]);
		detached_checked.add (((CheckedIf) inner.body.statements[2]).then_body.statements[0]);
	}
	CoreProgram? core = CoreBuilder.build (checked_program);
	checked_program = null;
	for (int i = 0; i < checked_refs.length; i++) {
		checked_refs[i].gone ();
	}
	for (int i = 0; i < detached_checked.length; i++) {
		var target = (detached_checked[i] is CheckedBreak) ? ((CheckedBreak) detached_checked[i]).target : ((CheckedContinue) detached_checked[i]).target;
		assert (target == null);
	}
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("(continue #1)"));
	var core_refs = new GenericArray<Probe> ();
	core_refs.add (new Probe (core));
	var detached_core = new GenericArray<CoreStatement> ();
	{
		var outer = (CoreWhile) core.functions[0].body.statements[2];
		var inner = (CoreWhile) outer.body.statements[1];
		core_refs.add (new Probe (outer.target));
		core_refs.add (new Probe (inner.target));
		core_refs.add (new Probe (outer));
		core_refs.add (new Probe (inner));
		detached_core.add (((CoreIf) outer.body.statements[3]).then_block.statements[0]);
		detached_core.add (((CoreIf) outer.body.statements[4]).then_block.statements[0]);
		detached_core.add (((CoreIf) inner.body.statements[1]).then_block.statements[0]);
		detached_core.add (((CoreIf) inner.body.statements[2]).then_block.statements[0]);
	}
	CfgProgram? graph = CfgBuilder.build (core);
	core = null;
	for (int i = 0; i < core_refs.length; i++) {
		core_refs[i].gone ();
	}
	for (int i = 0; i < detached_core.length; i++) {
		var target = (detached_core[i] is CoreBreak) ? ((CoreBreak) detached_core[i]).target : ((CoreContinue) detached_core[i]).target;
		assert (target == null);
	}
	CfgVerifier.verify (graph);
	assert (CfgDump.format (graph).contains ("(branch #4)"));
	var graph_refs = new GenericArray<Probe> ();
	graph_refs.add (new Probe (graph.functions[0]));
	for (int i = 0; i < graph.functions[0].blocks.length; i++) {
		graph_refs.add (new Probe (graph.functions[0].blocks[i]));
	}
	var detached_branch = (CfgBranch) graph.functions[0].blocks[7].terminator;
	SsaProgram? values = SsaBuilder.build (graph);
	graph = null;
	for (int i = 0; i < graph_refs.length; i++) {
		graph_refs[i].gone ();
	}
	assert (detached_branch.target == null && detached_branch.successors ().length == 0);
	SsaVerifier.verify (values);
	assert (SsaDump.format (values).contains ("(arguments"));
	var value_refs = new GenericArray<Probe> ();
	value_refs.add (new Probe (values.functions[0]));
	for (int i = 0; i < values.functions[0].blocks.length; i++) {
		value_refs.add (new Probe (values.functions[0].blocks[i]));
	}
	var detached_edge = ((SsaBranch) values.functions[0].blocks[7].terminator).edge;
	values = null;
	for (int i = 0; i < value_refs.length; i++) {
		value_refs[i].gone ();
	}
	assert (detached_edge.target == null);
}

private void checked_function_ownership() throws GLib.Error {
	for (int kind = 0; kind < 3; kind++) {
		var program = check ("void f(){while(true){break;continue;}}void g(){while(true){break;continue;}}");
		var first = (CheckedWhile) program.functions[0].body.statements[0];
		var second = (CheckedWhile) program.functions[1].body.statements[0];
		if (kind == 0) {
			second.body.statements[0] = new CheckedBreak (second.span, first.target);
		} else if (kind == 1) {
			second.body.statements[1] = new CheckedContinue (second.span, first.target);
		} else {
			program.functions[1].body.statements[0] = new CheckedWhile (second.span, first.target, second.condition, second.body);
		}
		try {
			CoreBuilder.build (program);
			GLib.error ("Cross-function checked target accepted");
		} catch (CoreError error) {
			assert (error.message.contains (kind == 2 ? "repeated loop-target identity" : "expired or has no mapping"));
		}
	}
}

private void terminated_diamonds() throws GLib.Error {
	foreach (string transfer in new string[] {"break;", "continue;", "return 1;"}) {
		var core = CoreBuilder.build (check ("int f(bool c,bool a){while(c){if(a){" + transfer + "}else{break;}while(c){continue;}int dead = 99;}return 2;}"));
		var graph = CfgBuilder.build (core);
		CfgVerifier.verify (graph);
		var f = graph.functions[0];
		var reachability = CfgReachability.analyze (f);
		for (int b = 6; b < f.blocks.length; b++) {
			assert (!reachability.is_reachable (f.blocks[b]));
		}
		assert (CfgDump.format (graph).contains ("unreachable"));
		var values = SsaBuilder.build (graph);
		SsaVerifier.verify (values);
		assert (values.functions[0].blocks.length == 6);
		assert (!SsaDump.format (values).contains ("integer 99"));
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/loopctrl/parser/structure-tokens", () => syntax ());
	add ("/loopctrl/parser/boundaries", () => boundaries ());
	add ("/loopctrl/semantics/outside-break", () => outside ("break"));
	add ("/loopctrl/semantics/outside-continue", () => outside ("continue"));
	add ("/loopctrl/semantics/core-exact-identities", identities);
	add ("/loopctrl/semantics/function-local-ordinals", ordinals);
	add ("/loopctrl/core/invalid-checked-targets", invalid_checked_targets);
	add ("/loopctrl/core/checked-function-ownership", checked_function_ownership);
	add ("/loopctrl/cfg/terminated-diamonds", terminated_diamonds);
	add ("/loopctrl/cfg/edges-dominance-frontiers", graph_merges);
	add ("/loopctrl/cfg/multiple-predecessors", multiple_graphs);
	add ("/loopctrl/ssa/merge-values", merge_values);
	add ("/loopctrl/ssa/current-edge-values-availability", edge_values);
	add ("/loopctrl/ssa/nested-targets", nested_graph);
	add ("/loopctrl/cfg/unreachable-call-order-return", unreachable);
	add ("/loopctrl/cfg/conservative-flow", flow);
	add ("/loopctrl/lifetime/stage-independence-expiry", lifetime);
	return Test.run ();
}
}
