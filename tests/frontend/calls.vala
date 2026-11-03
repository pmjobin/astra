// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.Frontend {
private void call_structure() {
	var unit = parse_ok ("int f(){ping(); int x = outer(inner(1), 2); x = -left() + right(); if(pred(x)){ping();} return x;}");
	var statements = unit.functions[0].body.statements;
	var statement = (CallStatementSyntax) statements[0];
	assert (statement.span.text () == "ping();" && statement.semicolon.spelling () == ";");
	assert (statement.call.identifier.spelling () == "ping" && statement.call.arguments.length == 0);
	assert (statement.call.open_paren.spelling () == "(" && statement.call.close_paren.spelling () == ")");
	var outer = (CallExpressionSyntax) ((LocalDeclarationSyntax) statements[1]).initializer;
	assert (outer.span.text () == "outer(inner(1), 2)" && outer.arguments.length == 2);
	assert (outer.commas.length == 1 && outer.commas[0].spelling () == ",");
	assert (((CallExpressionSyntax) outer.arguments[0]).arguments[0].span.text () == "1");
	assert (outer.arguments[1].span.text () == "2");
	var sum = (BinaryExpressionSyntax) ((AssignmentStatementSyntax) statements[2]).expression;
	assert (((PrefixExpressionSyntax) sum.left).operand is CallExpressionSyntax);
	assert (sum.right is CallExpressionSyntax);
	assert (((IfStatementSyntax) statements[3]).condition is CallExpressionSyntax);
	string text = unit.span.text ();
	assert (SyntaxDump.format (unit) == SyntaxDump.format (parse_ok (text)));
	for (int i = 0; i <= text.length; i++) {
		var result = Parser.parse (new SourceFile.from_text ("truncated.astra", text.substring (0, i)));
		assert ((result.unit == null) != (result.diagnostic == null));
	}
}

private void call_limits() {
	var expression = new StringBuilder ("1");
	for (int i = 0; i < 255; i++) {
		expression.prepend ("f(");
		expression.append (")");
	}
	parse_ok ("int f(){return " + expression.str + ";}");
	var result = Parser.parse (new SourceFile.from_text ("deep.astra", "int f(){return f(" + expression.str + ");}"));
	assert (result.diagnostic.message == "expression nesting limit of 256 exceeded");
	var arguments = new StringBuilder ("0");
	for (int i = 0; i < 2000; i++) {
		arguments.append (",0");
	}
	var unit = parse_ok ("int f(){g(" + arguments.str + ");}");
	assert (((CallStatementSyntax) unit.functions[0].body.statements[0]).call.arguments.length == 2001);
}

private void call_error(string name, string expression, string marker, string message) {
	string text = "int f(){" + expression + "}";
	register_error ("call-" + name, text, text.index_of (marker, 8), marker.length, message);
}

private void register_call_syntax_tests() {
	Test.add_func ("/parser/call-structure-and-spans", call_structure);
	Test.add_func ("/limits/call-depth-and-flat-arguments", call_limits);
	register_program ("call-in-return", "int f(){return g();}", 1);
	register_program ("call-no-args", "void f(){ping();}", 1);
	register_program ("call-multiple-args", "void f(){foo(1, 2, true);}", 1);
	call_error ("missing-argument", "f(,);", ",", "expected expression");
	register_error ("call-trailing-comma", "int f(){g(1,);}", 12, 1, "expected expression");
	register_error ("call-double-comma", "int f(){g(1,,2);}", 12, 1, "expected expression");
	call_error ("missing-comma", "g(1 2);", "2", "expected ')' after call arguments");
	call_error ("missing-close", "g(1;", ";", "expected ')' after call arguments");
	call_error ("missing-semicolon", "g()", "}", "expected ';' after call statement");
	call_error ("expression-statement", "g() + 1;", "+", "expected ';' after call statement");
	register_error ("call-parenthesized-callee", "int f(){return (g)();}", 18, 1, "expected ';' after return statement");
	register_error ("call-returned-callee", "int f(){return g()();}", 18, 1, "expected ';' after return statement");
	call_error ("literal-statement", "1 + 2;", "1", "expected return, if, while, break, continue, local declaration, assignment, or call statement");
	call_error ("bool-statement", "true;", "true", "expected return, if, while, break, continue, local declaration, assignment, or call statement");
	call_error ("value-statement", "x;", ";", "expected '=' after assignment target");
	// METHOD-1 adds member-call syntax; receiver validity is checked semantically.
	register_program ("call-member-callee", "int f(){object.method();}", 1);
}

}
