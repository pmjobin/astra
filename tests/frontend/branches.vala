// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.Frontend {
private void branch_syntax() {
	string text = "int f(bool c) { if (c) { return 1; } else { if (!c) {} } return 0; }";
	var unit = parse_ok (text);
	var conditional = (IfStatementSyntax) unit.functions[0].body.statements[0];
	assert (conditional.keyword.kind == TokenKind.IF && conditional.keyword.span.text () == "if");
	assert (conditional.open_paren.spelling () == "(" && conditional.close_paren.spelling () == ")");
	assert (conditional.condition.span.text () == "c" && conditional.then_body.span.text () == "{ return 1; }");
	assert (conditional.else_keyword.kind == TokenKind.ELSE && conditional.else_body.span.text () == "{ if (!c) {} }");
	var nested = (IfStatementSyntax) conditional.else_body.statements[0];
	assert (nested.else_keyword == null && nested.else_body == null && nested.then_body.statements.length == 0);
	assert (((PrefixExpressionSyntax) nested.condition).operator_token.kind == TokenKind.BANG);
	assert (conditional.span.text () == "if (c) { return 1; } else { if (!c) {} }");
	string dump = SyntaxDump.format (unit);
	assert (dump.contains ("(if") && dump.contains ("(else") && dump == SyntaxDump.format (parse_ok (text)));
	for (int i = 0; i <= text.length; i++) {
		var result = Parser.parse (new SourceFile.from_text ("truncated.astra", text.substring (0, i)));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
}

private void branch_depth() {
	var text = new StringBuilder ("void f(){");
	for (int i = 0; i < 255; i++) {
		text.append ("if(true){");
	}
	string valid = text.str + string.nfill (256, '}');
	assert (SyntaxDump.format (parse_ok (valid)).contains ("(bool true)"));
	var result = Parser.parse (new SourceFile.from_text ("deep.astra", text.str + "if(true){}" + string.nfill (256, '}')));
	assert (result.unit == null && result.diagnostic.message == "block nesting limit of 256 exceeded");
}

private void branch_parse_error(string name, string text, string message, string marker) {
	add_case ("/parser/branch/error/" + name, () => {
			var result = Parser.parse (new SourceFile.from_text ("branch.astra", text));
			assert (result.unit == null && result.diagnostic != null);
			assert (result.diagnostic.message == message && result.diagnostic.span.text () == marker);
		});
}

private void register_branch_syntax_tests() {
	Test.add_func ("/parser/branch/structure-spans-truncation", branch_syntax);
	Test.add_func ("/parser/branch/depth", branch_depth);
	register_lexer ("branch-keywords", "bool int void true false if else trueish false_ iffy elsewhere", { TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.TRUE, TokenKind.FALSE, TokenKind.IF, TokenKind.ELSE, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER }, { "bool", "int", "void", "true", "false", "if", "else", "trueish", "false_", "iffy", "elsewhere" });
	register_lexer ("branch-maximal-match", "===!!=<<=>>=", { TokenKind.EQUAL_EQUAL, TokenKind.EQUAL, TokenKind.BANG, TokenKind.BANG_EQUAL, TokenKind.SHIFT_LEFT, TokenKind.EQUAL, TokenKind.SHIFT_RIGHT, TokenKind.EQUAL }, { "==", "=", "!", "!=", "<<", "=", ">>", "=" });
	register_expression ("true", "true", "(bool true)");
	register_expression ("false", "false", "(bool false)");
	register_expression ("not-prefix", "!!true", "(prefix \"!\" (prefix \"!\" (bool true)))");
	register_expression ("relational-precedence", "a + 1 < b * 2", "(binary \"<\" (binary \"+\" (name \"a\") (integer \"1\")) (binary \"*\" (name \"b\") (integer \"2\")))");
	register_expression ("equality-precedence", "a < b == true", "(binary \"==\" (binary \"<\" (name \"a\") (name \"b\")) (bool true))");
	register_expression ("equality-left-associative", "a == b != false", "(binary \"!=\" (binary \"==\" (name \"a\") (name \"b\")) (bool false))");
	register_expression ("relational-comparison-chain", "a < b <= c > d >= e", "(comparison-chain (name \"a\") < (name \"b\") <= (name \"c\") > (name \"d\") >= (name \"e\"))");
	register_program ("bool-as-identifier", "bool bool(bool bool) { return bool; }", 1);
	register_program ("equality-assignment-rhs", "bool f(){bool x = true; x = 1 == 2; return x;}", 1);
	branch_parse_error ("empty-condition", "void f(){if() {}}", "expected expression", ")");
	branch_parse_error ("malformed-condition", "void f(){if(true ==) {}}", "expected expression", ")");
	branch_parse_error ("missing-open-paren", "void f(){if true {}}", "expected '(' after 'if'", "true");
	branch_parse_error ("missing-close-paren", "void f(){if(true {}}", "expected ')' after if condition", "{");
	branch_parse_error ("assignment-condition", "void f(){if(x = true) {}}", "expected ')' after if condition", "=");
	branch_parse_error ("unbraced-then", "void f(){if(true) return;}", "expected '{' before if body", "return");
	branch_parse_error ("missing-then-close", "void f(){if(true){", "expected '}' after if body", "");
	branch_parse_error ("unbraced-else", "void f(){if(true){}else return;}", "expected '{' before else body", "return");
	branch_parse_error ("else-if", "void f(){if(true){}else if(false){}}", "expected '{' before else body", "if");
	branch_parse_error ("missing-else", "void f(){if(true){}else", "expected '{' before else body", "");
	branch_parse_error ("missing-else-close", "void f(){if(true){}else{", "expected '}' after else body", "");
	branch_parse_error ("equality-is-not-assignment", "void f(){x == true;}", "expected '=' after assignment target", "==");
	register_expression ("eager-and", "true & false", "(binary \"&\" (bool true) (bool false))");
	register_expression ("eager-or", "true | false", "(binary \"|\" (bool true) (bool false))");
}

}
