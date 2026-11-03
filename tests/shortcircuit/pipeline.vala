// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.ShortCircuit {
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
				GLib.error ("%s: %s", Test.get_path (), error.message);
			}
		});
}

private string fixture(string name) throws FileError {
	string text;
	FileUtils.get_contents ("tests/shortcircuit/fixtures/" + name + ".astra", out text);
	return text;
}

private CompilationUnitSyntax parse(string text) {
	var result = Parser.parse (new SourceFile.from_text ("short.astra", text));
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

private CfgProgram graph(string text) throws GLib.Error {
	var result = CfgBuilder.build (CoreBuilder.build (check (text)));
	assert (CfgFlowChecker.check (result).diagnostic == null);
	assert (CfgDump.format (result) == CfgDump.format (result));
	return result;
}

private SsaProgram promote(CfgProgram cfg) throws GLib.Error {
	var result = SsaBuilder.build (cfg);
	SsaVerifier.verify (result);
	string dump = SsaDump.format (result);
	assert (dump == SsaDump.format (result));
	foreach (string forbidden in new string[] {"temporary-place", "local-place", "(load", "(store", "(initialize", "short-circuit", "undef", "poison"}) {
		assert (!dump.contains (forbidden));
	}
	return result;
}

private ExpressionSyntax expression(string text) {
	return ((ReturnStatementSyntax) parse ("bool f(){return " + text + ";}").functions[0].body.statements[0]).expression;
}

private void tokens() {
	var lexer = new Lexer (new SourceFile.from_text ("tokens", "&&||!!= &&&"));
	foreach (var kind in new TokenKind[] {TokenKind.AMPERSAND_AMPERSAND, TokenKind.PIPE_PIPE, TokenKind.BANG, TokenKind.BANG_EQUAL, TokenKind.AMPERSAND_AMPERSAND}) {
		assert (lexer.next_token ().kind == kind);
	}
	assert (lexer.next_token ().kind == TokenKind.AMPERSAND);
	assert (lexer.next_token ().kind == TokenKind.EOF && lexer.diagnostic == null);
	assert (expression ("true & false") is BinaryExpressionSyntax && expression ("true | false") is BinaryExpressionSyntax);
	foreach (string text in new string[] {"|||", "&&=", "||="}) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", "bool f(){return true " + text + " false;}")).diagnostic != null);
	}
}

private void precedence() {
	var root = (ShortCircuitExpressionSyntax) expression ("a || b && c");
	assert (root.operator_token.kind == TokenKind.PIPE_PIPE && root.left is NameExpressionSyntax);
	assert (((ShortCircuitExpressionSyntax) root.right).operator_token.kind == TokenKind.AMPERSAND_AMPERSAND);
	root = (ShortCircuitExpressionSyntax) expression ("a == b && c != d || e");
	assert (root.operator_token.kind == TokenKind.PIPE_PIPE && root.right is NameExpressionSyntax);
	var left = (ShortCircuitExpressionSyntax) root.left;
	assert (left.operator_token.kind == TokenKind.AMPERSAND_AMPERSAND);
	assert (((BinaryExpressionSyntax) left.left).operator_token.kind == TokenKind.EQUAL_EQUAL);
	assert (((BinaryExpressionSyntax) left.right).operator_token.kind == TokenKind.BANG_EQUAL);
	foreach (string op in new string[] {"&&", "||"}) {
		root = (ShortCircuitExpressionSyntax) expression ("a " + op + " b " + op + " c");
		assert (root.left is ShortCircuitExpressionSyntax && root.right is NameExpressionSyntax);
		assert (root.operator_token.spelling () == op && ((ShortCircuitExpressionSyntax) root.left).operator_token.spelling () == op);
	}
	root = (ShortCircuitExpressionSyntax) expression ("!a || -b + c * d < e == f && g");
	assert (root.left is PrefixExpressionSyntax);
	var equality = (BinaryExpressionSyntax) ((ShortCircuitExpressionSyntax) root.right).left;
	var relational = (BinaryExpressionSyntax) equality.left;
	var additive = (BinaryExpressionSyntax) relational.left;
	assert (additive.left is PrefixExpressionSyntax && ((BinaryExpressionSyntax) additive.right).operator_token.kind == TokenKind.STAR);
	string text = "bool f(){return a && (b || !c);}";
	for (int i = 0; i <= text.length; i++) {
		var result = Parser.parse (new SourceFile.from_text ("truncated", text.substring (0, i)));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
}

private void semantics() {
	foreach (string op in new string[] {"&&", "||"}) {
		var program = check ("bool f(bool a,bool b){return a " + op + " b;}");
		var value = (CheckedShortCircuitExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
		assert (value.semantic_type == program.types.bool_type && value.left.semantic_type == value.semantic_type && value.right.semantic_type == value.semantic_type);
		assert (value.operator_kind.spelling () == op && value.span.text () == "a " + op + " b");
		assert (SemanticDump.format (program).contains ("(short-circuit " + op + " : bool"));
		foreach (string operands in new string[] {"1 " + op + " true", "false " + op + " 1", "1 " + op + " 2"}) {
			var result = SemanticAnalyzer.analyze (parse ("bool f(){return " + operands + ";}"));
			assert (result.program == null && result.diagnostic.message.contains ("requires a 'bool' operand"));
		}
	}
}

private void static_rhs() {
	foreach (string text in new string[] {"false && missing()", "true || missing()", "false && (2147483648 == 0)", "true || (2147483648 == 0)"}) {
		var result = SemanticAnalyzer.analyze (parse ("bool f(){return " + text + ";}"));
		assert (result.program == null && result.diagnostic != null);
		assert (result.diagnostic.message.contains (text.contains ("missing") ? "unknown function 'missing'" : "integer literal is out of range"));
	}
	check ("bool f(){return false && ((1 / 0) == 0);}");
}

private void simple(bool is_and) throws GLib.Error {
	string name = is_and ? "logical-and" : "logical-or";
	var checked_program = check (fixture (name));
	var core = CoreBuilder.build (checked_program);
	CoreVerifier.verify (core);
	var structured = (CoreShortCircuitValue) ((CoreReturn) core.functions[0].body.statements[0]).value;
	assert (structured.operator_kind == (is_and ? ShortCircuitOperator.AND : ShortCircuitOperator.OR));
	assert (CoreDump.format (core).contains ("(short-circuit"));
	var cfg = graph (fixture (name));
	var f = cfg.functions[0];
	var b = f.blocks;
	assert (b.length == 4 && f.locals.length == 0 && f.temporaries.length == 1);
	var t = f.temporaries[0];
	assert (t.ordinal == 0 && t.semantic_type.kind == TypeKind.BOOL && t.span.text () == "a " + (is_and ? "&&" : "||") + " b");
	assert (b[0].instructions.length == 0 && ((CfgBranch) b[0].terminator).target == b[1]);
	var initial = (CfgInitialize) b[1].instructions[0];
	assert (b[1].instructions.length == 1 && initial.target == t);
	assert (((CfgBooleanValue) initial.value).literal == (is_and ? BooleanLiteral.FALSE : BooleanLiteral.TRUE));
	var conditional = (CfgConditionalBranch) b[1].terminator;
	assert (((CfgParameterValue) conditional.condition).parameter == f.parameters[0]);
	assert (conditional.true_target == b[is_and ? 2 : 3] && conditional.false_target == b[is_and ? 3 : 2]);
	var store = (CfgStore) b[2].instructions[0];
	assert (store.target == t && ((CfgParameterValue) store.value).parameter == f.parameters[1]);
	assert (((CfgBranch) b[2].terminator).target == b[3]);
	assert (((CfgLoadValue) ((CfgReturn) b[3].terminator).value).source == t);
	var sf = promote (cfg).functions[0];
	assert (sf.blocks.length == 4 && sf.blocks[3].parameters.length == 1);
	var result = sf.blocks[3].parameters[0];
	assert (result.origin_kind == SsaPromotionOrigin.TEMPORARY && result.origin_ordinal == 0 && result.source_local_ordinal == -1 && result.name == "");
	var decision = (SsaConditionalBranch) sf.blocks[1].terminator;
	var short_edge = is_and ? decision.false_edge : decision.true_edge;
	assert (short_edge.target == sf.blocks[3] && short_edge.arguments.length == 1);
	assert (((SsaBooleanConstant) short_edge.arguments[0]).literal == (is_and ? BooleanLiteral.FALSE : BooleanLiteral.TRUE));
	assert (((SsaBranch) sf.blocks[2].terminator).edge.arguments[0] == sf.parameters[1]);
	assert (((SsaReturn) sf.blocks[3].terminator).value == result);
	for (int i = 0; i < sf.blocks.length; i++) {
		assert (sf.blocks[i].instructions.length == 0);
	}
}

private void nested() throws GLib.Error {
	var cfg = graph (fixture ("nested-short"));
	var ssa = promote (cfg);
	for (int i = 0; i < cfg.functions.length; i++) {
		var f = cfg.functions[i];
		assert (f.temporaries.length == 2 && f.temporaries[0] != f.temporaries[1]);
		assert (f.temporaries[0].ordinal == 0 && f.temporaries[1].ordinal == 1);
		var found = new bool[2];
		for (int b = 0; b < ssa.functions[i].blocks.length; b++) {
			var parameters = ssa.functions[i].blocks[b].parameters;
			for (int p = 0; p < parameters.length; p++) {
				assert (parameters[p].origin_kind == SsaPromotionOrigin.TEMPORARY);
				found[parameters[p].origin_ordinal] = true;
			}
		}
		assert (found[0] && found[1]);
	}
	var core = CoreBuilder.build (check (fixture ("nested-short")));
	var chain = (CoreShortCircuitValue) ((CoreReturn) core.functions[0].body.statements[0]).value;
	assert (chain.left is CoreShortCircuitValue && chain.right is CoreParameterValue);
	var inner = (CoreShortCircuitValue) ((CoreReturn) core.functions[2].body.statements[0]).value;
	assert (inner.left is CoreParameterValue && ((CoreShortCircuitValue) inner.right).operator_kind == ShortCircuitOperator.OR);
}

private void calls() throws GLib.Error {
	var cfg = graph (fixture ("call-short"));
	for (int i = 3; i <= 4; i++) {
		var f = cfg.functions[i];
		assert (f.blocks[0].instructions.length == 0);
		assert (((CfgCallInstruction) f.blocks[1].instructions[0]).target == cfg.functions[0]);
		var decision = (CfgConditionalBranch) f.blocks[1].terminator;
		var rhs = i == 3 ? decision.true_target : decision.false_target;
		assert (((CfgCallInstruction) rhs.instructions[0]).target == cfg.functions[1]);
	}
	var args = cfg.functions[5].blocks;
	assert (((CfgBranch) args[3].terminator).target == args[4]);
	assert (((CfgCallInstruction) args[4].instructions[0]).target == cfg.functions[0]);
	assert (((CfgCallInstruction) args[6].instructions[0]).target == cfg.functions[2]);
	var earlier = cfg.functions[6].blocks;
	assert (earlier[0].instructions[0] is CfgCallInstruction && earlier[3].instructions[0] is CfgCallInstruction);
	assert (((CfgCallInstruction) earlier[3].instructions[0]).arguments[0] == ((CfgCallInstruction) earlier[0].instructions[0]).result);
	var trapping = cfg.functions[7].blocks;
	assert (trapping[0].instructions[0] is CfgEvaluateInstruction);
	assert (((CfgCallInstruction) trapping[3].instructions[0]).arguments[0] == ((CfgEvaluateInstruction) trapping[0].instructions[0]).result);
	promote (cfg);
}

private void loops() throws GLib.Error {
	var cfg = graph (fixture ("loop-short"));
	var ssa = promote (cfg);
	foreach (int i in new int[] {0, 2, 3}) {
		var f = cfg.functions[i];
		var b = f.blocks;
		assert (((CfgBranch) b[0].terminator).target == b[1]);
		assert (((CfgBranch) b[1].terminator).target == b[4]);
		assert (b[4].instructions[0] is CfgInitialize);
		var d = CfgDominance.analyze (f);
		assert (d.dominates (b[1], b[4]) && !d.dominates (b[4], b[1]) && d.dominates (b[4], b[6]));
		assert (ssa.functions[i].blocks[1].parameters.length == 1);
		assert (ssa.functions[i].blocks[1].parameters[0].origin_kind == SsaPromotionOrigin.SOURCE_LOCAL);
		assert (ssa.functions[i].blocks[1].parameters[0].name == "i");
		assert (ssa.functions[i].blocks[6].parameters.length == 1 && ssa.functions[i].blocks[6].parameters[0].origin_kind == SsaPromotionOrigin.TEMPORARY);
		assert (((CfgConditionalBranch) b[6].terminator).true_target == b[2] && ((CfgConditionalBranch) b[6].terminator).false_target == b[3]);
		if (i != 0) {
			assert (((CfgCallInstruction) b[5].instructions[0]).target == cfg.functions[1]);
		}
		if (i != 3) {
			assert (((CfgBranch) b[2].terminator).target == b[1]);
		}
	}
	var broken = cfg.functions[3].blocks;
	assert (((CfgBranch) broken[7].terminator).target == broken[3]);
	assert (((CfgBranch) broken[8].terminator).target == broken[1]);
	var exit = ssa.functions[3].blocks[3];
	assert (exit.parameters.length == 1 && exit.parameters[0].origin_kind == SsaPromotionOrigin.SOURCE_LOCAL);
	assert (((SsaReturn) exit.terminator).value == exit.parameters[0]);
}

private void contexts() throws GLib.Error {
	var cfg = graph (fixture ("contexts-short"));
	var f = cfg.functions[1];
	assert (f.locals.length == 1 && f.locals[0].ordinal == 0 && f.temporaries.length == 9);
	assert (f.temporaries[0].ordinal == 0 && (CfgPlace) f.temporaries[0] != (CfgPlace) f.locals[0]);
	assert (((CfgInitialize) f.blocks[3].instructions[0]).target == f.locals[0]);
	assert (((CfgLoadValue) ((CfgInitialize) f.blocks[3].instructions[0]).value).source == f.temporaries[0]);
	assert (((CfgStore) f.blocks[6].instructions[0]).target == f.locals[0]);
	var ssa = promote (cfg);
	assert (SsaDump.format (ssa).contains ("\"x\" : bool") && SsaDump.format (ssa).contains ("(temporary #0)"));
	// Disconnected tails still preserve and verify expression control flow.
	promote (graph ("bool p(){return true;}bool f(bool a){return a;bool x = p() == (a && p());while(a || p()){continue;}return x;}"));
}

private void unavailable_temporary() throws GLib.Error {
	var cfg = graph (fixture ("loop-short"));
	var f = cfg.functions[0];
	// Deliberately violate the lowering contract: initializing at the
	// re-entry header would demand a nonexistent preheader definition.
	f.blocks[1].instructions.add (f.blocks[4].instructions[0]);
	f.blocks[4].instructions.remove_index (0);
	CfgVerifier.verify (cfg);
	try {
		SsaBuilder.build (cfg);
	} catch (SsaError error) {
		assert (error.message.contains ("block #0: temporary #0 has no reaching definition"));
		return;
	}
	GLib.error ("SSA fabricated an incoming temporary value");
}

private void promotion_identity() throws GLib.Error {
	var cfg = graph (fixture ("logical-and"));
	var f = cfg.functions[0];
	var t = f.temporaries[0];
	// Same span, type, and ordinal across the two distinct storage kinds.
	var local = new CfgLocalPlace (t.span, t.span, "temporary", t.semantic_type, 0);
	f.locals.add (local);
	f.blocks[1].instructions.add (new CfgInitialize (t.span, local, new CfgBooleanValue (t.span, t.semantic_type, BooleanLiteral.TRUE)));
	f.blocks[2].instructions.add (new CfgStore (t.span, local, new CfgParameterValue (t.span, f.parameters[0])));
	var second = new CfgTemporaryPlace (t.span, t.semantic_type, 1);
	f.temporaries.add (second);
	f.blocks[1].instructions.add (new CfgInitialize (t.span, second, new CfgBooleanValue (t.span, t.semantic_type, BooleanLiteral.TRUE)));
	f.blocks[2].instructions.add (new CfgStore (t.span, second, new CfgParameterValue (t.span, f.parameters[0])));
	var ssa = promote (cfg).functions[0];
	var ps = ssa.blocks[3].parameters;
	assert (ps.length == 3 && ps[0].origin_kind == SsaPromotionOrigin.SOURCE_LOCAL && ps[0].source_local_ordinal == 0);
	assert (ps[1].origin_kind == SsaPromotionOrigin.TEMPORARY && ps[1].origin_ordinal == 0);
	assert (ps[2].origin_kind == SsaPromotionOrigin.TEMPORARY && ps[2].origin_ordinal == 1);
	var short_args = ((SsaConditionalBranch) ssa.blocks[1].terminator).false_edge.arguments;
	assert (((SsaBooleanConstant) short_args[0]).literal == BooleanLiteral.TRUE);
	assert (((SsaBooleanConstant) short_args[1]).literal == BooleanLiteral.FALSE);
	assert (((SsaBooleanConstant) short_args[2]).literal == BooleanLiteral.TRUE);
	var right_args = ((SsaBranch) ssa.blocks[2].terminator).edge.arguments;
	assert (right_args[0] == ssa.parameters[0] && right_args[1] == ssa.parameters[1] && right_args[2] == ssa.parameters[0]);
	assert (((SsaReturn) ssa.blocks[3].terminator).value == ps[1]);
}

private class Probe : Object {
	private WeakRef reference;
	internal Probe (Object value) {
		reference = WeakRef (value);
	}

	internal void gone() {
		assert (reference.get () == null);
	}

}
private void lifetime() throws GLib.Error {
	CompilationUnitSyntax? syntax = parse (fixture ("loop-short"));
	var syntax_ref = new Probe (syntax);
	CheckedProgram? checked_program = SemanticAnalyzer.analyze (syntax).program;
	var checked_ref = new Probe (((CheckedWhile) checked_program.functions[0].body.statements[1]).condition);
	CoreProgram? core = CoreBuilder.build (checked_program);
	syntax = null;
	checked_program = null;
	syntax_ref.gone ();
	checked_ref.gone ();
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("short-circuit"));
	var core_ref = new Probe (((CoreWhile) core.functions[0].body.statements[1]).condition);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	core_ref.gone ();
	CfgVerifier.verify (cfg);
	assert (CfgDump.format (cfg).contains ("temporary-place"));
	var graph_refs = new GenericArray<Probe> ();
	for (int f = 0; f < cfg.functions.length; f++) {
		graph_refs.add (new Probe (cfg.functions[f]));
		for (int b = 0; b < cfg.functions[f].blocks.length; b++) {
			graph_refs.add (new Probe (cfg.functions[f].blocks[b]));
		}
		for (int t = 0; t < cfg.functions[f].temporaries.length; t++) {
			graph_refs.add (new Probe (cfg.functions[f].temporaries[t]));
		}
	}
	var detached = (CfgBranch) cfg.functions[2].blocks[2].terminator;
	SsaProgram? ssa = promote (cfg);
	cfg = null;
	for (int i = 0; i < graph_refs.length; i++) {
		graph_refs[i].gone ();
	}
	assert (detached.target == null);
	SsaVerifier.verify (ssa);
	assert (SsaDump.format (ssa).contains ("temporary #0"));
	var ssa_refs = new GenericArray<Probe> ();
	for (int f = 0; f < ssa.functions.length; f++) {
		ssa_refs.add (new Probe (ssa.functions[f]));
		for (int b = 0; b < ssa.functions[f].blocks.length; b++) {
			ssa_refs.add (new Probe (ssa.functions[f].blocks[b]));
			for (int p = 0; p < ssa.functions[f].blocks[b].parameters.length; p++) {
				ssa_refs.add (new Probe (ssa.functions[f].blocks[b].parameters[p]));
			}
		}
	}
	var edge = ((SsaBranch) ssa.functions[2].blocks[2].terminator).edge;
	ssa = null;
	for (int i = 0; i < ssa_refs.length; i++) {
		ssa_refs[i].gone ();
	}
	assert (edge.target == null);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/shortcircuit/tokens-maximal-boundaries", () => tokens ());
	add ("/shortcircuit/precedence-associativity", () => precedence ());
	add ("/shortcircuit/exact-bool-semantics", () => semantics ());
	add ("/shortcircuit/static-rhs", () => static_rhs ());
	add ("/shortcircuit/and-core-cfg-ssa", () => simple (true));
	add ("/shortcircuit/or-core-cfg-ssa", () => simple (false));
	add ("/shortcircuit/nested-distinct-temporaries", nested);
	add ("/shortcircuit/calls-arguments-trap-order", calls);
	add ("/shortcircuit/loop-header-continue-break", loops);
	add ("/shortcircuit/initializer-store-if-call-return", contexts);
	add ("/shortcircuit/exact-place-identity-parameter-order", promotion_identity);
	add ("/shortcircuit/no-fabricated-header-temporary", unavailable_temporary);
	add ("/shortcircuit/cyclic-stage-lifetime", lifetime);
	return Test.run ();
}

}
