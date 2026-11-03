// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.BitSemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("bit.astra", text));
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.program == null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string message, bool parsing = false) {
	var syntax = Parser.parse (new SourceFile.from_text ("bit.astra", text));
	if (parsing) {
		assert (syntax.unit == null);
		return;
	}
	assert (syntax.unit != null);
	string before = SyntaxDump.format (syntax.unit);
	for (int i = 0; i < 2; i++) {
		var result = SemanticAnalyzer.analyze (syntax.unit);
		if (result.program != null || !result.diagnostic.message.contains (message)) {
			GLib.error ("Expected %s for %s; got %s", message, text, result.diagnostic == null ? "success" : result.diagnostic.message);
		}
	}
	assert (SyntaxDump.format (syntax.unit) == before);
}

private CheckedExpression returned(CheckedProgram p) {
	return ((CheckedReturnStatement) p.functions[0].body.statements[0]).expression;
}

private void types() {
	var t = new BuiltinTypes ();
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32", "bool"}) {
		foreach (int lanes in new int[] {1, 2, 4, 8, 16}) {
			if (lanes != 1 && t.vector_of (t.resolve (name), lanes) == null) {
				continue;
			}
			string type = name + (lanes == 1 ? "" : "<%d>".printf (lanes));
			foreach (string op in new string[] {"&", "|", "^"}) {
				check ("%s f(%s a,%s b){return a%s b;}".printf (type, type, type, op));
			}
			if (name == "bool") {
				check ("%s f(%s a){return !a;}".printf (type, type));
				reject ("%s f(%s a){return ~a;}".printf (type, type), "requires an integer");
				continue;
			}
			check ("%s f(%s a){return ~a;}".printf (type, type));
			foreach (string count in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32"}) {
				foreach (string op in new string[] {"<<", ">>"}) {
					var p = check ("%s f(%s a,%s c){return a%s c;}".printf (type, type, count, op));
					var shift = (CheckedIntegerShiftExpression) returned (p);
					assert (shift.count.semantic_type == p.types.resolve (count) && shift.semantic_type == shift.operand.semantic_type);
				}
			}
		}
	}
}

private void literals() {
	foreach (string op in new string[] {"&", "|", "^"}) {
		foreach (string expr in new string[] {"a" + op + "15", "15" + op + "a", "1" + op + "2", "(1" + op + "2)" + op + "a"}) {
			var p = check ("u8 f(u8 a){return " + expr + ";}");
			var b = (CheckedBinaryExpression) returned (p);
			assert (b.left.semantic_type == p.types.u8_type && b.right.semantic_type == p.types.u8_type);
		}
	}
	var plain = check ("int f(){return 1|2;}");
	assert (returned (plain).semantic_type == plain.types.int_type);
	check ("u8 f(){u8 x=1|2;return ~x;} u8 g(){return ~0;}");
	var shift = (CheckedIntegerShiftExpression) returned (check ("u8 f(){return 1<<2;}"));
	assert (shift.semantic_type.kind == TypeKind.U8 && shift.count.semantic_type.kind == TypeKind.INT);
	// A count type never contextualizes a value, including lookahead from
	// an enclosing same-domain operator.
	reject ("u8 f(u8 c){int x=1<<c;return x;}", "return");
	reject ("u8 f(){return 256 & 1;}", "out of range");
}

private void precedence() {
	var lexer = new Lexer (new SourceFile.from_text ("tokens", "& && | || ^ ~ << >> < <= > >="));
	foreach (var kind in new TokenKind[] {TokenKind.AMPERSAND, TokenKind.AMPERSAND_AMPERSAND, TokenKind.PIPE, TokenKind.PIPE_PIPE, TokenKind.CARET, TokenKind.TILDE, TokenKind.SHIFT_LEFT, TokenKind.SHIFT_RIGHT, TokenKind.LESS, TokenKind.LESS_EQUAL, TokenKind.GREATER, TokenKind.GREATER_EQUAL, TokenKind.EOF}) {
		assert (lexer.next_token ().kind == kind);
	}
	var p = check ("bool f(int a,int b,int c,int d){return a>b & c>d;}");
	var root = (CheckedBinaryExpression) returned (p);
	assert (root.operator_kind == BinaryOperator.BIT_AND && ((CheckedBinaryExpression) root.left).operator_kind == BinaryOperator.GREATER && ((CheckedBinaryExpression) root.right).operator_kind == BinaryOperator.GREATER);
	check ("struct S{int x;} int f(S* p){return p->x;} int main(){S s={x=1};return f(&s)&3;}");
	root = (CheckedBinaryExpression) returned (check ("int f(int a,int b,int c,int d){return a|b^c&d;}"));
	assert (root.operator_kind == BinaryOperator.BIT_OR && ((CheckedBinaryExpression) root.right).operator_kind == BinaryOperator.BIT_XOR && ((CheckedBinaryExpression) ((CheckedBinaryExpression) root.right).right).operator_kind == BinaryOperator.BIT_AND);
	var shift = (CheckedIntegerShiftExpression) returned (check ("int f(int a,int b,int c){return a<<b+c*2;}"));
	assert (((CheckedBinaryExpression) shift.count).operator_kind == BinaryOperator.ADD && ((CheckedBinaryExpression) ((CheckedBinaryExpression) shift.count).right).operator_kind == BinaryOperator.MULTIPLY);
	var lazy = (CheckedShortCircuitExpression) returned (check ("bool f(bool a,bool b,bool c,bool d){return a|b && c || d;}"));
	assert (lazy.operator_kind == ShortCircuitOperator.OR && ((CheckedShortCircuitExpression) lazy.left).operator_kind == ShortCircuitOperator.AND && ((CheckedShortCircuitExpression) lazy.left).left is CheckedBinaryExpression);
	root = (CheckedBinaryExpression) returned (check ("bool f(int a,int b,int c){return a<<b<c == true;}"));
	assert (root.operator_kind == BinaryOperator.EQUAL && ((CheckedBinaryExpression) root.left).left is CheckedIntegerShiftExpression);
	shift = (CheckedIntegerShiftExpression) returned (check ("int f(int a){return ~a<<1>>2;}"));
	assert (shift.shift_kind == IntegerShiftKind.RIGHT && ((CheckedIntegerShiftExpression) shift.operand).operand is CheckedPrefixExpression);
}

private void diagnostics() {
	foreach (string pair in new string[] {"i8,u8", "i8,i16", "int,u32", "u16,i16", "i8<4>,u8<4>", "i8<4>,i8<8>", "bool,bool<4>"}) {
		var names = pair.split (",");
		foreach (string op in new string[] {"&", "|", "^"}) {
			reject ("%s f(%s a,%s b){return a%s b;}".printf (names[0], names[0], names[1], op), "matching");
		}
	}
	foreach (string type in new string[] {"f32", "f32<4>", "void*", "S*"}) {
		foreach (string op in new string[] {"&", "|", "^"}) {
			reject ("struct S{int x;} void f(%s a,%s b){%s x=a%s b;}".printf (type, type, type, op), "matching");
		}
		reject ("struct S{int x;} void f(%s a){%s x=~a;}".printf (type, type), "requires an integer");
	}
	foreach (string op in new string[] {"<<", ">>"}) {
		foreach (string type in new string[] {"bool", "bool<4>", "f32", "f32<4>", "void*"}) {
			reject ("%s f(%s a){return a%s 1;}".printf (type, type, op), "shift requires");
			reject ("int f(int a,%s c){return a%s c;}".printf (type, op), "shift requires");
		}
		reject ("i8<4> f(i8<4> a,int<4> c){return a" + op + "c;}", "scalar integer count");
		foreach (string type in new string[] {"u8", "i8<16>", "u16", "i16<8>", "u32", "i32<4>"}) {
			int width = type.contains ("8") && !type.has_prefix ("i16") ? 8 : type.contains ("16") || type.has_prefix ("u16") ? 16 : 32;
			foreach (string count in new string[] {"-1", width.to_string (), (width + 1).to_string ()}) {
				reject ("%s f(%s a){return a%s %s;}".printf (type, type, op, count), "shift count must be");
			}
		}
	}
	foreach (string op in new string[] {"&&", "||"}) {
		reject ("bool<4> f(bool<4> a,bool<4> b){return a" + op + "b;}", "bool");
	}
	foreach (string op in new string[] {"&=", "|=", "^=", "<<=", ">>=", ">>>"}) {
		reject ("int f(int a){int b=1;b" + op + "a;return b;}", "", true);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/bit/semantic/type-and-count-matrix", types);
	Test.add_func ("/bit/semantic/literal-context", literals);
	Test.add_func ("/bit/parser/maximal-munch-precedence-address-of", precedence);
	Test.add_func ("/bit/semantic/diagnostics", diagnostics);
	return Test.run ();
}

}
