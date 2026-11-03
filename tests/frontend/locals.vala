// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.Frontend {
private void local_syntax() {
	var unit = parse_ok ("int f(int x) { int y = x + 007; y = y * 2; return y; }");
	var statements = unit.functions[0].body.statements;
	assert (statements.length == 3);
	var declaration = (LocalDeclarationSyntax) statements[0];
	assert (declaration.span.text () == "int y = x + 007;");
	assert (declaration.type_name.span.text () == "int" && declaration.name.spelling () == "y");
	assert (declaration.equals_token.kind == TokenKind.EQUAL && declaration.equals_token.span.text () == "=");
	assert (declaration.initializer.span.text () == "x + 007" && declaration.semicolon.spelling () == ";");
	var assignment = (AssignmentStatementSyntax) statements[1];
	assert (assignment.span.text () == "y = y * 2;");
	assert (assignment.name.spelling () == "y" && assignment.equals_token.kind == TokenKind.EQUAL);
	assert (assignment.expression.span.text () == "y * 2" && assignment.semicolon.spelling () == ";");
	assert (((NameExpressionSyntax) ((ReturnStatementSyntax) statements[2]).expression).identifier.spelling () == "y");
	assert (SyntaxDump.format (unit).contains ("(assign (name \"y\") (binary \"*\""));
	string text = unit.span.text ();
	for (int i = 0; i <= text.length; i++) {
		var result = Parser.parse (new SourceFile.from_text ("truncated.astra", text.substring (0, i)));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
}

private void register_local_syntax_tests() {
	Test.add_func ("/parser/local-structure-and-spans", local_syntax);
	register_lexer ("equals", "x=007;", { TokenKind.IDENTIFIER, TokenKind.EQUAL, TokenKind.INTEGER, TokenKind.SEMICOLON }, { "x", "=", "007", ";" });
	register_program ("initialized-local", "int f() { int x = 1; return x; }", 1);
	register_program ("local-assignment", "void f() { int x = 1; x = 2; return; }", 1);
	register_program ("local-unknown-type-is-syntax", "int f() { Mystery x = 1; return x; }", 1);
	register_error ("local-missing-initializer", "int f(){int x;}", 13, 1, "expected '=' and initializer after local name");
	register_error ("local-missing-initializer-value", "int f(){int x =;}", 15, 1, "expected expression");
	register_error ("assignment-missing-rhs", "int f(){x =;}", 11, 1, "expected expression");
	register_error ("local-missing-semicolon", "int f(){int x = 1}", 17, 1, "expected ';' after local declaration");
	register_error ("assignment-missing-semicolon", "int f(){x = 1}", 13, 1, "expected ';' after assignment statement");
	register_error ("assignment-is-not-expression", "int f(){return x = 3;}", 17, 1, "expected ';' after return statement");
	register_error ("assignment-no-chaining", "int f(){a = b = 4;}", 14, 1, "expected ';' after assignment statement");
	register_error ("assignment-in-initializer", "int f(){int a = b = 4;}", 18, 1, "expected ';' after local declaration");
	register_error ("parenthesized-assignment", "int f(){return (x = 3);}", 18, 1, "expected ')' after expression");
	register_error ("assignment-in-call", "int f(){f(x = 4);}", 12, 1, "expected ')' after call arguments");
	register_error ("assignment-literal-target", "int f(){1 = 2;}", 8, 1, "expected return, if, while, break, continue, local declaration, assignment, or call statement");
	register_error ("assignment-expression-target", "int f(){x + y = 2;}", 10, 1, "expected '=' after assignment target");
	register_error ("compound-assignment", "int f(){x += 1;}", 10, 1, "expected '=' after assignment target");
}

}
