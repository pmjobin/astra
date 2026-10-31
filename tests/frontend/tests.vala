// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.Frontend {
private delegate void TestAction();

private class TestCase : Object {
	private TestAction action;

	public TestCase (owned TestAction action) {
		this.action = (owned) action;
	}

	public void run() {
		action ();
	}
}

private HashTable<string, TestCase> cases;

// Vala's bound GTestDataFunc callback loses gconstpointer. Register an
// ordinary no-argument GLib test and keep the Vala closure on our side.
private void add_case(string path, owned TestAction action) {
	cases.insert (path, new TestCase ((owned) action));
	Test.add_func (path, run_case);
}

private void run_case() {
	cases.lookup (Test.get_path ()).run ();
}

private CompilationUnitSyntax parse_ok(string text) {
	var result = Parser.parse (new SourceFile.from_text ("test.astra", text));
	if (result.diagnostic != null) {
		GLib.error ("Unexpected diagnostic: %s", result.diagnostic.format ());
	}
	assert (result.unit != null);
	return result.unit;
}

private void check_span(SourceSpan span, int start, int end, string text) {
	assert (span.start == start);
	assert (span.end == end);
	assert (span.text () == text);
}

private void check_location(SourceFile source, int offset, int expected_line, int expected_column) {
	int line;
	int column;
	source.locate (offset, out line, out column);
	assert (line == expected_line);
	assert (column == expected_column);
}

private void source_locations() {
	var source = new SourceFile.from_text ("test.astra", "a\r\n\téx\nz\rq");
	assert (source.validate_encoding () == null);
	assert (source.length == 11);
	check_location (source, 0, 1, 1);
	check_location (source, 1, 1, 2);
	check_location (source, 2, 1, 2);
	check_location (source, 3, 2, 1);
	check_location (source, 4, 2, 2);
	check_location (source, 6, 2, 3);
	check_location (source, 7, 2, 4);
	check_location (source, 8, 3, 1);
	check_location (source, 10, 4, 1);
	check_location (source, 11, 4, 2);
	check_span (SourceSpan (source, 4, 6), 4, 6, "é");
	check_location (new SourceFile.from_text ("empty", ""), 0, 1, 1);
	check_location (new SourceFile.from_text ("lf", "\n"), 1, 2, 1);
	check_location (new SourceFile.from_text ("crlf", "\r\n"), 2, 2, 1);
}

private Token retained_token() {
	var lexer = new Lexer (new SourceFile.from_text ("retained.astra", "original"));
	var token = lexer.next_token ();
	assert (token != null);
	return token;
}

private void source_lifetime() {
	var token = retained_token ();
	assert (token.spelling () == "original");
	assert (token.span.file.path == "retained.astra");
	var unit = parse_ok ("Unknown f() { return 00042; }");
	var returned = (ReturnStatementSyntax) unit.functions[0].body.statements[0];
	var literal = (IntegerLiteralExpressionSyntax) returned.expression;
	assert (literal.literal.spelling () == "00042");
	assert (unit.span.file == literal.span.file);
}

private void register_lexer(string name, string text, owned TokenKind[]? kinds, owned string[]? spellings) {
	add_case ("/lexer/" + name, () => {
			var source = new SourceFile.from_text ("test.astra", text);
			var lexer = new Lexer (source);
			assert (kinds.length == spellings.length);
			int previous_end = 0;
			for (int i = 0; i < kinds.length; i++) {
				var token = lexer.next_token ();
				assert (token != null);
				assert (token.kind == kinds[i]);
				assert (token.spelling () == spellings[i]);
				assert (token.span.file == source);
				assert (token.span.start >= previous_end);
				assert (token.span.end - token.span.start == spellings[i].length);
				previous_end = token.span.end;
			}
			var eof = lexer.next_token ();
			assert (eof != null && eof.kind == TokenKind.EOF);
			check_span (eof.span, source.length, source.length, "");
			assert (lexer.next_token ().kind == TokenKind.EOF);
			assert (lexer.diagnostic == null);
		});
}

private void lexer_spans() {
	var lexer = new Lexer (new SourceFile.from_text ("test.astra", " \r\nfoo 007+bar"));
	check_span (lexer.next_token ().span, 3, 6, "foo");
	check_span (lexer.next_token ().span, 7, 10, "007");
	check_span (lexer.next_token ().span, 10, 11, "+");
	check_span (lexer.next_token ().span, 11, 14, "bar");
	check_span (lexer.next_token ().span, 14, 14, "");
}

private void register_lex_error(string name, string text, int start, int end, string message) {
	add_case ("/lexer/" + name, () => {
			var lexer = new Lexer (new SourceFile.from_text ("test.astra", text));
			Token? token = null;
			do {
				token = lexer.next_token ();
				assert (token == null || token.kind != TokenKind.EOF);
			} while (token != null);
			assert (lexer.diagnostic != null);
			assert (lexer.diagnostic.message == message);
			assert (lexer.diagnostic.span.start == start);
			assert (lexer.diagnostic.span.end == end);
			assert (lexer.next_token () == null);
		});
}

private void register_encoding_error(string name, owned uint8[] bytes, int offset, string message = "invalid UTF-8 encoding") {
	add_case ("/encoding/" + name, () => {
			var source = new SourceFile ("bytes.astra", bytes.copy ());
			var lexer = new Lexer (source);
			assert (lexer.next_token () == null);
			var result = Parser.parse (source);
			assert (result.unit == null && result.diagnostic != null);
			assert (result.diagnostic.message == message);
			assert (result.diagnostic.span.start == offset);
			assert (result.diagnostic.span.end == offset + 1);
			assert (result.diagnostic.format () == "bytes.astra:1:%d: error: %s".printf (offset + 1, message));
		});
}

private void register_program(string name, string text, int function_count) {
	add_case ("/parser/" + name, () => {
			var unit = parse_ok (text);
			assert (unit.functions.length == function_count);
			check_span (unit.span, 0, text.length, text);
			check_span (unit.end_of_file.span, text.length, text.length, "");
		});
}

private ExpressionSyntax parse_expression(string text) {
	var unit = parse_ok ("number f() { return " + text + "; }");
	var returned = (ReturnStatementSyntax) unit.functions[0].body.statements[0];
	assert (returned.expression != null);
	return returned.expression;
}

private void register_expression(string name, string text, string expected) {
	add_case ("/expression/" + name, () => {
			string actual = SyntaxDump.format_expression (parse_expression (text));
			if (actual != expected) {
				GLib.error ("For %s, expected %s, got %s", text, expected, actual);
			}
		});
}

private void syntax_spans() {
	var unit = parse_ok ("int f(int x) { return -(x + 007) * x; }");
	var function = unit.functions[0];
	check_span (function.span, 0, 39, "int f(int x) { return -(x + 007) * x; }");
	check_span (function.return_type.span, 0, 3, "int");
	check_span (function.name.span, 4, 5, "f");
	check_span (function.open_paren.span, 5, 6, "(");
	check_span (function.parameters[0].span, 6, 11, "int x");
	check_span (function.parameters[0].type_name.span, 6, 9, "int");
	check_span (function.parameters[0].name.span, 10, 11, "x");
	check_span (function.close_paren.span, 11, 12, ")");
	check_span (function.body.span, 13, 39, "{ return -(x + 007) * x; }");
	var returned = (ReturnStatementSyntax) function.body.statements[0];
	check_span (returned.span, 15, 37, "return -(x + 007) * x;");
	check_span (returned.keyword.span, 15, 21, "return");
	check_span (returned.semicolon.span, 36, 37, ";");
	var binary = (BinaryExpressionSyntax) returned.expression;
	check_span (binary.span, 22, 36, "-(x + 007) * x");
	check_span (binary.operator_token.span, 33, 34, "*");
	check_span (binary.right.span, 35, 36, "x");
	var prefix = (PrefixExpressionSyntax) binary.left;
	check_span (prefix.span, 22, 32, "-(x + 007)");
	check_span (prefix.operator_token.span, 22, 23, "-");
	var parenthesized = (ParenthesizedExpressionSyntax) prefix.operand;
	check_span (parenthesized.span, 23, 32, "(x + 007)");
	check_span (parenthesized.open_paren.span, 23, 24, "(");
	check_span (parenthesized.close_paren.span, 31, 32, ")");
	var addition = (BinaryExpressionSyntax) parenthesized.expression;
	check_span (addition.span, 24, 31, "x + 007");
	check_span (addition.left.span, 24, 25, "x");
	check_span (addition.operator_token.span, 26, 27, "+");
	check_span (addition.right.span, 28, 31, "007");
}

private void parameter_and_return_structure() {
	var unit = parse_ok ("int add(int a, int b) { return a + b; return; }");
	var function = unit.functions[0];
	assert (function.parameters.length == 2);
	assert (function.commas.length == 1);
	assert (function.commas[0].spelling () == ",");
	assert (function.parameters[0].name.spelling () == "a");
	assert (function.parameters[1].name.spelling () == "b");
	assert (function.body.statements.length == 2);
	assert (((ReturnStatementSyntax) function.body.statements[1]).expression == null);
	assert (function.body.open_brace.spelling () == "{");
	assert (function.body.close_brace.spelling () == "}");
}

private void precedence_structure() {
	var addition = (BinaryExpressionSyntax) parse_expression ("1 + 2 * 3");
	assert (addition.operator_token.kind == TokenKind.PLUS);
	assert (addition.left is IntegerLiteralExpressionSyntax);
	assert (((BinaryExpressionSyntax) addition.right).operator_token.kind == TokenKind.STAR);
	var product = (BinaryExpressionSyntax) parse_expression ("(1 + 2) * 3");
	assert (product.operator_token.kind == TokenKind.STAR);
	assert (product.left is ParenthesizedExpressionSyntax);
	var parenthesized = (ParenthesizedExpressionSyntax) product.left;
	assert (((BinaryExpressionSyntax) parenthesized.expression).operator_token.kind == TokenKind.PLUS);
}

private void register_error(string name, string text, int offset, int length, string message) {
	add_case ("/errors/" + name, () => {
			var result = Parser.parse (new SourceFile.from_text ("test.astra", text));
			assert (result.unit == null && result.diagnostic != null);
			if (result.diagnostic.message != message || result.diagnostic.span.start != offset) {
				GLib.error ("For %s, expected offset %d: %s; got %s", text, offset, message, result.diagnostic.format ());
			}
			assert (result.diagnostic.span.end == offset + length);
			assert (result.diagnostic.format () == "test.astra:1:%d: error: %s".printf (offset + 1, message));
		});
}

private void multiline_diagnostics() {
	string[] inputs = {
		"int f() {\n\treturn 0\n}\n", "int f() {\r\n\treturn 0\r\n}\r\n"
	};
	foreach (string text in inputs) {
		var result = Parser.parse (new SourceFile.from_text ("test.astra", text));
		assert (result.diagnostic.format () == "test.astra:3:1: error: expected ';' after return statement");
	}
	var unicode = Parser.parse (new SourceFile.from_text ("test.astra", "/*é🙂*/ @"));
	assert (unicode.diagnostic.format () == "test.astra:1:8: error: unexpected character '@'");
	assert (unicode.diagnostic.span.start == 11);
}

private void arbitrary_literal() {
	string digits = "000" + string.nfill (1000, '9');
	var literal = (IntegerLiteralExpressionSyntax) parse_expression (digits);
	assert (literal.literal.spelling () == digits);
	var division = parse_expression ("1 / 0");
	assert (division is BinaryExpressionSyntax);
}

private void depth_limits() {
	string[] expressions = {
		string.nfill (10000, '-'), string.nfill (10000, '('), string.nfill (257, '-') + "1"
	};
	foreach (string expression in expressions) {
		var result = Parser.parse (new SourceFile.from_text ("deep.astra", "int f(){return " + expression + ";}"));
		assert (result.unit == null && result.diagnostic != null);
		assert (result.diagnostic.message == "expression nesting limit of 256 exceeded");
	}
	var chain = new StringBuilder ("int f(){return 1");
	for (int i = 0; i < 10000; i++) {
		chain.append ("+1");
	}
	chain.append (";}");
	var result = Parser.parse (new SourceFile.from_text ("chain.astra", chain.str));
	assert (result.diagnostic.message == "expression nesting limit of 256 exceeded");
	var limit = parse_expression (string.nfill (255, '-') + "1");
	assert (limit.tree_depth == 256);
	assert (SyntaxDump.format_expression (limit).has_prefix ("(prefix"));
}

private void flat_lists() {
	var text = new StringBuilder ("int f(");
	for (int i = 0; i < 1000; i++) {
		text.append (i == 0 ? "T x" : ", T x");
	}
	text.append (") {");
	for (int i = 0; i < 1000; i++) {
		text.append ("return;");
	}
	text.append ("}");
	var unit = parse_ok (text.str);
	assert (unit.functions[0].parameters.length == 1000);
	assert (unit.functions[0].body.statements.length == 1000);
}

private void truncated_and_arbitrary_input() {
	string program = "/*comment*/ number f(number a, number b) { return -(a + 2) * b; return; }";
	for (int i = 0; i <= program.length; i++) {
		var result = Parser.parse (new SourceFile.from_text ("prefix.astra", program.substring (0, i)));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
	for (int i = 0; i <= 255; i++) {
		uint8[] bytes = {
			(uint8) i
		};
		var result = Parser.parse (new SourceFile ("byte.astra", (owned) bytes));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
	string[] pieces = {
		"int", "x", "0", "return", "(", ")", "{", "}", ";", ",", "+", "-", "*", "/", "%"
	};
	uint state = 12345;
	for (int i = 0; i < 500; i++) {
		var text = new StringBuilder ("int f(){return ");
		for (int j = 0; j < 20; j++) {
			state = state * 1664525U + 1013904223U;
			text.append (pieces[state % pieces.length]);
			text.append_c (' ');
		}
		var result = Parser.parse (new SourceFile.from_text ("tokens.astra", text.str));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/frontend/borrowed-parameter", () => {
			var result = Parser.parse (new SourceFile.from_text ("borrowed.astra", "int f(borrowed void* p) { return 0; }"));
			assert (result.diagnostic == null);
			var parameter = result.unit.functions[0].parameters[0];
			assert (parameter.borrowed_keyword.kind == TokenKind.BORROWED);
			assert (parameter.type_name.spelling () == "void*" && parameter.span.text () == "borrowed void* p");
		});
	cases = new HashTable<string, TestCase> (str_hash, str_equal);
	register_branch_syntax_tests ();
	register_local_syntax_tests ();
	register_call_syntax_tests ();
	Test.add_func ("/source/locations", source_locations);
	Test.add_func ("/source/lifetime", source_lifetime);
	register_lexer ("empty", "", null, null);
	register_lexer ("whitespace", " \t\v\f\r\n", null, null);
	register_lexer ("lf", "a\nb\n", { TokenKind.IDENTIFIER, TokenKind.IDENTIFIER }, { "a", "b" });
	register_lexer ("crlf", "a\r\nb\r\n", { TokenKind.IDENTIFIER, TokenKind.IDENTIFIER }, { "a", "b" });
	register_lexer ("identifiers", "int uint float Foo Whatever _a9 Return returner", { TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER, TokenKind.IDENTIFIER }, { "int", "uint", "float", "Foo", "Whatever", "_a9", "Return", "returner" });
	register_lexer ("integers", "0 007 999999999999999999999999999999", { TokenKind.INTEGER, TokenKind.INTEGER, TokenKind.INTEGER }, { "0", "007", "999999999999999999999999999999" });
	register_lexer ("keyword", "return", { TokenKind.RETURN }, { "return" });
	register_lexer ("punctuation", "(){} ,;+-*/%", { TokenKind.OPEN_PAREN, TokenKind.CLOSE_PAREN, TokenKind.OPEN_BRACE, TokenKind.CLOSE_BRACE, TokenKind.COMMA, TokenKind.SEMICOLON, TokenKind.PLUS, TokenKind.MINUS, TokenKind.STAR, TokenKind.SLASH, TokenKind.PERCENT }, { "(", ")", "{", "}", ",", ";", "+", "-", "*", "/", "%" });
	register_lexer ("line-comment", "// é comment\r\nreturn // eof", { TokenKind.RETURN }, { "return" });
	register_lexer ("block-comment", "/*é\n🙂*/return/**/0;", { TokenKind.RETURN, TokenKind.INTEGER, TokenKind.SEMICOLON }, { "return", "0", ";" });
	register_lexer ("comment-boundary", "a/**/b", { TokenKind.IDENTIFIER, TokenKind.IDENTIFIER }, { "a", "b" });
	register_lexer ("non-nesting-comments", "/* outer /* inner */x", { TokenKind.IDENTIFIER }, { "x" });
	register_lexer ("slash-at-eof", "/", { TokenKind.SLASH }, { "/" });
	register_lexer ("literal-boundary", "123abc", { TokenKind.INTEGER, TokenKind.IDENTIFIER }, { "123", "abc" });
	Test.add_func ("/lexer/spans", lexer_spans);
	register_lex_error ("unterminated-comment", " \n/* unfinished", 2, 4, "unterminated block comment");
	register_lex_error ("empty-unterminated-comment", "/*", 0, 2, "unterminated block comment");
	register_lex_error ("trailing-star-comment", "/**", 0, 2, "unterminated block comment");
	register_lex_error ("unexpected-character", " @", 1, 2, "unexpected character '@'");
	register_lex_error ("non-ascii", "é", 0, 2, "non-ASCII character is not supported outside comments");
	register_lex_error ("non-bmp", "🙂", 0, 4, "non-ASCII character is not supported outside comments");
	register_lex_error ("unicode-space", " ", 0, 2, "non-ASCII character is not supported outside comments");
	register_encoding_error ("invalid-byte", { 0xff }, 0);
	register_encoding_error ("continuation", { 0x80 }, 0);
	register_encoding_error ("truncated", { 0x61, 0xc3 }, 1);
	register_encoding_error ("overlong", { 0xc0, 0xaf }, 0);
	register_encoding_error ("surrogate", { 0xed, 0xa0, 0x80 }, 0);
	register_encoding_error ("out-of-range", { 0xf4, 0x90, 0x80, 0x80 }, 0);
	register_encoding_error ("invalid-comment", { '/', '*', 0xff, '*', '/' }, 2);
	register_encoding_error ("nul", { 0 }, 0, "unexpected NUL byte");
	register_encoding_error ("embedded-nul", { 'a', 0, 'b' }, 1, "unexpected NUL byte");
	register_program ("empty-unit", "", 0);
	register_program ("comment-only", "// empty\n/* unit */", 0);
	register_program ("minimal", "int main() { return 0; }", 1);
	register_program ("parameters", "int add(int a, int b) { return a + b; }", 1);
	register_program ("nested-example", "number f(number x) { return -(x + 2) * 3; }", 1);
	register_program ("bare-return", "void noop() { return; }", 1);
	register_program ("empty-block", "int f() {}", 1);
	register_program ("multiple-functions", "T first() {} U second() { return x; }", 2);
	register_program ("unknown-names", "UnknownType f() { return mystery; }", 1);
	register_program ("duplicate-names", "T f() {} U f() { return; }", 2);
	register_expression ("integer", "0007", "(integer \"0007\")");
	register_expression ("name", "mystery", "(name \"mystery\")");
	register_expression ("prefix-plus", "+x", "(prefix \"+\" (name \"x\"))");
	register_expression ("prefix-minus", "-1", "(prefix \"-\" (integer \"1\"))");
	register_expression ("nested-prefix", "+-x", "(prefix \"+\" (prefix \"-\" (name \"x\")))");
	register_expression ("product-precedence", "1 + 2 * 3", "(binary \"+\" (integer \"1\") (binary \"*\" (integer \"2\") (integer \"3\")))");
	register_expression ("division-precedence", "1 + 8 / 2", "(binary \"+\" (integer \"1\") (binary \"/\" (integer \"8\") (integer \"2\")))");
	register_expression ("modulo-precedence", "8 % 3 - 1", "(binary \"-\" (binary \"%\" (integer \"8\") (integer \"3\")) (integer \"1\"))");
	register_expression ("additive-left-associativity", "8 - 3 + 1", "(binary \"+\" (binary \"-\" (integer \"8\") (integer \"3\")) (integer \"1\"))");
	register_expression ("multiplicative-left-associativity", "8 / 2 * 3 % 5", "(binary \"%\" (binary \"*\" (binary \"/\" (integer \"8\") (integer \"2\")) (integer \"3\")) (integer \"5\"))");
	register_expression ("parenthesized", "(1 + 2) * 3", "(binary \"*\" (parenthesized (binary \"+\" (integer \"1\") (integer \"2\"))) (integer \"3\"))");
	register_expression ("nested-parentheses", "((x))", "(parenthesized (parenthesized (name \"x\")))");
	register_expression ("prefix-precedence", "-x * +2", "(binary \"*\" (prefix \"-\" (name \"x\")) (prefix \"+\" (integer \"2\")))");
	Test.add_func ("/parser/spans", syntax_spans);
	Test.add_func ("/parser/structure", parameter_and_return_structure);
	Test.add_func ("/parser/precedence-structure", precedence_structure);
	Test.add_func ("/parser/arbitrary-literal", arbitrary_literal);
	register_error ("missing-type", "(){}", 0, 1, "expected function return type name");
	register_error ("missing-function-name", "int () {}", 4, 1, "expected function name");
	register_error ("missing-open-paren", "int f {}", 6, 1, "expected '(' after function name");
	register_error ("missing-close-paren", "int f(int x {}", 12, 1, "expected ')' after parameters");
	register_error ("missing-parameter-name", "int f(int) {}", 9, 1, "expected parameter name");
	register_error ("missing-parameter-type", "int f(,){}", 6, 1, "expected parameter type name");
	register_error ("trailing-comma", "int f(int x,) {}", 12, 1, "expected parameter type name");
	register_error ("double-comma", "int f(int x,,int y){}", 12, 1, "expected parameter type name");
	register_error ("missing-comma", "int f(int x int y){}", 12, 3, "expected ')' after parameters");
	register_error ("missing-block", "int f()", 7, 0, "expected '{' before function body");
	register_error ("missing-open-brace", "int f() return;", 8, 6, "expected '{' before function body");
	register_error ("missing-semicolon", "int f(){return 0}", 16, 1, "expected ';' after return statement");
	register_error ("missing-prefix-operand", "int f(){return -;}", 16, 1, "expected expression");
	register_error ("missing-binary-operand", "int f(){return 1 +;}", 18, 1, "expected expression");
	register_error ("empty-parentheses", "int f(){return ();}", 16, 1, "expected expression");
	register_error ("unclosed-parentheses", "int f(){return (1;}", 17, 1, "expected ')' after expression");
	register_error ("unterminated-block", "int f(){return;", 15, 0, "expected '}' after function body");
	register_error ("unmatched-close", "}", 0, 1, "expected function return type name");
	register_error ("unexpected-statement", "int f(){x;}", 9, 1, "expected '=' after assignment target");
	add_case ("/structure/nested-block", () => {
			var unit = parse_ok ("int f(){{return 1;}}");
			var body = unit.functions[0].body;
			assert (body.statements.length == 1 && body.statements[0] is BlockStatementSyntax);
			var nested = (BlockStatementSyntax) body.statements[0];
			assert (nested.statements.length == 1 && nested.statements[0] is ReturnStatementSyntax);
		});
	register_error ("prototype-not-supported", "int f();", 7, 1, "expected '{' before function body");
	register_error ("keyword-not-an-expression", "int f(){return return;}", 15, 6, "expected expression");
	Test.add_func ("/errors/multiline", multiline_diagnostics);
	Test.add_func ("/limits/depth", depth_limits);
	Test.add_func ("/limits/flat-lists", flat_lists);
	Test.add_func ("/robustness/truncated-and-arbitrary-input", truncated_and_arbitrary_input);
	int result = Test.run ();
	cases.remove_all ();
	cases = null;
	return result;
}
}
