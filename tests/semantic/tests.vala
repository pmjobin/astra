// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Semantics {
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

// Keep the PARSE-1 plain-callback convention for strict C pointer checking.
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
		GLib.error ("Unexpected parse diagnostic: %s", result.diagnostic.format ());
	}
	assert (result.unit != null);
	return result.unit;
}

private CheckedProgram check_ok(string text) {
	var result = SemanticAnalyzer.analyze (parse_ok (text));
	if (result.diagnostic != null) {
		GLib.error ("Unexpected semantic diagnostic: %s", result.diagnostic.format ());
	}
	assert (result.program != null);
	return result.program;
}

private CheckedExpression returned_expression(CheckedFunction function, int index = 0) {
	assert (function.body.statements[index] is CheckedReturnStatement);
	var statement = (CheckedReturnStatement) function.body.statements[index];
	assert (statement.expression != null);
	return statement.expression;
}

private CheckedExpression check_expression(string text) {
	var program = check_ok ("int f(int a, int b) { return " + text + "; }");
	return returned_expression (program.functions[0]);
}

private void register_program(string name, string text, int function_count) {
	add_case ("/semantic/program/" + name, () => {
			var program = check_ok (text);
			assert (program.functions.length == function_count);
			assert (program.span.start == 0 && program.span.end == text.length);
			assert (program.span.text () == text);
		});
}

private void canonical_types() {
	var program = check_ok ("int first(int a, int b) { return a + b; } void noop() { return; } int last(int x) { return 0; }");
	var first = program.functions[0];
	var last = program.functions[2];
	assert (program.types.int_type != program.types.void_type);
	assert (program.types.int_type.kind == TypeKind.INT);
	assert (program.types.void_type.kind == TypeKind.VOID);
	assert (program.types.int_type.display_name () == "int");
	assert (program.types.void_type.display_name () == "void");
	assert (first.symbol.return_type == program.types.int_type);
	assert (program.functions[1].symbol.return_type == program.types.void_type);
	assert (last.symbol.return_type == first.symbol.return_type);
	assert (first.symbol.parameters[0].semantic_type == program.types.int_type);
	assert (first.symbol.parameters[1].semantic_type == program.types.int_type);
	assert (last.symbol.parameters[0].semantic_type == program.types.int_type);
	assert (returned_expression (first).semantic_type == program.types.int_type);
	assert (returned_expression (last).semantic_type == program.types.int_type);
}

private void type_names_are_identifiers() {
	var lexer = new Lexer (new SourceFile.from_text ("names.astra", "int void"));
	assert (lexer.next_token ().kind == TokenKind.IDENTIFIER);
	assert (lexer.next_token ().kind == TokenKind.IDENTIFIER);
	var program = check_ok ("int int(int void, int int) { return void + int; } void void() { return; }");
	var function = program.functions[0];
	assert (function.symbol.name == "int");
	assert (function.symbol.return_type == program.types.int_type);
	var binary = (CheckedBinaryExpression) returned_expression (function);
	assert (((CheckedParameterReferenceExpression) binary.left).parameter == function.symbol.parameters[0]);
	assert (((CheckedParameterReferenceExpression) binary.right).parameter == function.symbol.parameters[1]);
	assert (program.functions[1].symbol.name == "void");
	assert (program.functions[1].symbol.return_type == program.types.void_type);
}

private void parameter_binding() {
	var program = check_ok ("int combine(int a, int b) { return a + b; return a; }");
	var function = program.functions[0];
	var binary = (CheckedBinaryExpression) returned_expression (function);
	var left = (CheckedParameterReferenceExpression) binary.left;
	var right = (CheckedParameterReferenceExpression) binary.right;
	var repeated = (CheckedParameterReferenceExpression) returned_expression (function, 1);
	assert (left.parameter == function.symbol.parameters[0]);
	assert (right.parameter == function.symbol.parameters[1]);
	assert (left.parameter != right.parameter);
	assert (repeated.parameter == left.parameter);
	assert (left.parameter.ordinal == 0 && right.parameter.ordinal == 1);
	assert (left.semantic_type == left.parameter.semantic_type);
	assert (right.semantic_type == right.parameter.semantic_type);
}

private void function_local_bindings() {
	var program = check_ok ("int later(int x) { return x; } int earlier(int x) { return x; }");
	var first = program.functions[0];
	var second = program.functions[1];
	assert (first.symbol != second.symbol);
	assert (first.symbol.name == "later" && second.symbol.name == "earlier");
	var first_reference = (CheckedParameterReferenceExpression) returned_expression (first);
	var second_reference = (CheckedParameterReferenceExpression) returned_expression (second);
	assert (first_reference.parameter == first.symbol.parameters[0]);
	assert (second_reference.parameter == second.symbol.parameters[0]);
	assert (first_reference.parameter != second_reference.parameter);
	assert (first_reference.parameter.ordinal == 0 && second_reference.parameter.ordinal == 0);
	var reversed = check_ok ("int earlier(int x) { return x; } int later(int x) { return x; }");
	assert (reversed.functions[0].symbol.name == "earlier");
	assert (reversed.functions[1].symbol.name == "later");
	assert (((CheckedParameterReferenceExpression) returned_expression (reversed.functions[0])).parameter == reversed.functions[0].symbol.parameters[0]);
}

private void provenance() {
	string text = "int f(int x) { return -(x + 007) * x; }";
	var program = check_ok (text);
	var function = program.functions[0];
	assert (function.span.text () == text);
	assert (function.symbol.span.text () == text);
	assert (function.symbol.name_span.text () == "f");
	assert (function.symbol.parameters[0].span.text () == "int x");
	assert (function.symbol.parameters[0].name_span.text () == "x");
	assert (function.body.span.text () == "{ return -(x + 007) * x; }");
	assert (function.body.statements[0].span.text () == "return -(x + 007) * x;");
	var binary = (CheckedBinaryExpression) returned_expression (function);
	assert (binary.span.text () == "-(x + 007) * x");
	var prefix = (CheckedPrefixExpression) binary.left;
	assert (prefix.span.text () == "-(x + 007)");
	var addition = (CheckedBinaryExpression) prefix.operand;
	assert (addition.span.text () == "x + 007");
	var literal = (CheckedIntegerExpression) addition.right;
	assert (literal.span.text () == "007");
	assert (literal.span.start == 28 && literal.span.end == 31);
	assert (literal.span.file == program.span.file);
}

private void retained_parameter() {
	// check_expression releases the analyzer, syntax, program, and function.
	var reference = (CheckedParameterReferenceExpression) check_expression ("a");
	assert (reference.parameter.name == "a");
	assert (reference.parameter.ordinal == 0);
	assert (reference.parameter.span.text () == "int a");
	assert (reference.semantic_type.kind == TypeKind.INT);
	assert (reference.span.text () == "a");
	assert (reference.span.file.path == "test.astra");
}

private void syntax_is_unchanged() {
	var unit = parse_ok ("int f(int x) { return ((x)); }");
	string before = SyntaxDump.format (unit);
	var first = SemanticAnalyzer.analyze (unit);
	var second = SemanticAnalyzer.analyze (unit);
	assert (first.diagnostic == null && second.diagnostic == null);
	assert (SyntaxDump.format (unit) == before);
	assert (((ReturnStatementSyntax) unit.functions[0].body.statements[0]).expression is ParenthesizedExpressionSyntax);
	assert (returned_expression (first.program.functions[0]) is CheckedParameterReferenceExpression);
	assert (returned_expression (first.program.functions[0]).span.text () == "x");
	assert (first.program.functions[0].symbol != second.program.functions[0].symbol);
	assert (SemanticDump.format (first.program) == SemanticDump.format (second.program));
}

private void integer_literal() {
	var program = check_ok ("int main() { return 00042; }");
	var expression = returned_expression (program.functions[0]);
	assert (expression is CheckedIntegerExpression);
	assert (expression.semantic_type == program.types.int_type);
	assert (((CheckedIntegerExpression) expression).span.text () == "00042");
}

private void oversized_literal() {
	string digits = "000" + string.nfill (1000, '9');
	var parsed = Parser.parse (new SourceFile.from_text ("huge.astra", "int huge() { return ((" + digits + ")); }"));
	assert (parsed.diagnostic == null && SyntaxDump.format (parsed.unit).contains (digits));
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.program == null && result.diagnostic.message == "integer literal is out of range for 'int'");
	assert (result.diagnostic.span.text () == digits && result.diagnostic.span.end - result.diagnostic.span.start == 1003);
}

private void register_prefix(string name, string spelling, PrefixOperator operator_kind) {
	add_case ("/semantic/expression/" + name, () => {
			var program = check_ok ("int f(int x) { return " + spelling + "x; }");
			var prefix = (CheckedPrefixExpression) returned_expression (program.functions[0]);
			assert (prefix.operator_kind == operator_kind);
			assert (prefix.semantic_type == program.types.int_type);
			assert (prefix.operand.semantic_type == program.types.int_type);
			assert (((CheckedParameterReferenceExpression) prefix.operand).parameter == program.functions[0].symbol.parameters[0]);
		});
}

private void register_binary(string name, string spelling, BinaryOperator operator_kind) {
	add_case ("/semantic/expression/" + name, () => {
			var program = check_ok ("int f(int a, int b) { return a " + spelling + " b; }");
			var binary = (CheckedBinaryExpression) returned_expression (program.functions[0]);
			assert (binary.operator_kind == operator_kind);
			assert (binary.semantic_type == program.types.int_type);
			assert (binary.left.semantic_type == program.types.int_type);
			assert (binary.right.semantic_type == program.types.int_type);
			assert (((CheckedParameterReferenceExpression) binary.left).parameter == program.functions[0].symbol.parameters[0]);
			assert (((CheckedParameterReferenceExpression) binary.right).parameter == program.functions[0].symbol.parameters[1]);
		});
}

private void precedence() {
	var addition = (CheckedBinaryExpression) check_expression ("1 + 2 * 3");
	assert (addition.operator_kind == BinaryOperator.ADD);
	assert (addition.left is CheckedIntegerExpression);
	assert (((CheckedBinaryExpression) addition.right).operator_kind == BinaryOperator.MULTIPLY);
	var product = (CheckedBinaryExpression) check_expression ("(1 + 2) * 3");
	assert (product.operator_kind == BinaryOperator.MULTIPLY);
	assert (((CheckedBinaryExpression) product.left).operator_kind == BinaryOperator.ADD);
	var remainder = (CheckedBinaryExpression) check_expression ("-(a + 2) * b % 3");
	assert (remainder.operator_kind == BinaryOperator.REMAINDER);
	var multiplied = (CheckedBinaryExpression) remainder.left;
	assert (multiplied.operator_kind == BinaryOperator.MULTIPLY);
	var prefix = (CheckedPrefixExpression) multiplied.left;
	assert (prefix.operator_kind == PrefixOperator.NEGATIVE);
	assert (((CheckedBinaryExpression) prefix.operand).operator_kind == BinaryOperator.ADD);
	assert (multiplied.right is CheckedParameterReferenceExpression);
}

private void associativity() {
	var addition = (CheckedBinaryExpression) check_expression ("8 - 3 + 1");
	assert (addition.operator_kind == BinaryOperator.ADD);
	assert (((CheckedBinaryExpression) addition.left).operator_kind == BinaryOperator.SUBTRACT);
	var remainder = (CheckedBinaryExpression) check_expression ("8 / 2 * 3 % 5");
	assert (remainder.operator_kind == BinaryOperator.REMAINDER);
	var product = (CheckedBinaryExpression) remainder.left;
	assert (product.operator_kind == BinaryOperator.MULTIPLY);
	assert (((CheckedBinaryExpression) product.left).operator_kind == BinaryOperator.DIVIDE);
	var prefix = (CheckedPrefixExpression) check_expression ("+-a");
	assert (prefix.operator_kind == PrefixOperator.POSITIVE);
	assert (((CheckedPrefixExpression) prefix.operand).operator_kind == PrefixOperator.NEGATIVE);
}

private void no_constant_evaluation() {
	var sum = (CheckedBinaryExpression) check_expression ("1 + 2");
	assert (sum.operator_kind == BinaryOperator.ADD);
	assert (((CheckedIntegerExpression) sum.left).span.text () == "1");
	assert (((CheckedIntegerExpression) sum.right).span.text () == "2");
	// Direct sign is literal formation; an outer sign remains an operation.
	var negation = (CheckedPrefixExpression) check_expression ("-(-0007)");
	assert (negation.operator_kind == PrefixOperator.NEGATIVE);
	assert (((CheckedIntegerExpression) negation.operand).value.signed_value == -7);
	assert (negation.operand.span.text () == "-0007");
	assert (((CheckedBinaryExpression) check_expression ("1 / 0")).operator_kind == BinaryOperator.DIVIDE);
	assert (((CheckedBinaryExpression) check_expression ("1 % 0")).operator_kind == BinaryOperator.REMAINDER);
}

private void return_structure() {
	var program = check_ok ("void noop() { return; return; } int f() { return 1; return 2; } int empty() {}");
	var noop = program.functions[0];
	assert (noop.body.statements.length == 2);
	assert (((CheckedReturnStatement) noop.body.statements[0]).expression == null);
	assert (((CheckedReturnStatement) noop.body.statements[1]).expression == null);
	var function = program.functions[1];
	assert (function.body.statements.length == 2);
	assert (((CheckedIntegerExpression) returned_expression (function)).span.text () == "1");
	assert (((CheckedIntegerExpression) returned_expression (function, 1)).span.text () == "2");
	assert (program.functions[2].body.statements.length == 0);
}

private void register_error(string name, string text, int offset, int length, string message) {
	add_case ("/semantic/errors/" + name, () => {
			var unit = parse_ok (text);
			string before = SyntaxDump.format (unit);
			for (int i = 0; i < 2; i++) {
				var result = SemanticAnalyzer.analyze (unit);
				assert (result.program == null && result.diagnostic != null);
				if (result.diagnostic.message != message || result.diagnostic.span.start != offset) {
					GLib.error ("For %s, expected offset %d: %s; got %s", text, offset, message, result.diagnostic.format ());
				}
				assert (result.diagnostic.span.end == offset + length);
				assert (result.diagnostic.span.file == unit.span.file);
				assert (result.diagnostic.format () == "test.astra:1:%d: error: %s".printf (offset + 1, message));
			}
			assert (SyntaxDump.format (unit) == before);
		});
}

private void signature_before_body() {
	var unit = parse_ok ("int first() { return missing; }\nMystery second() { return 0; }");
	var result = SemanticAnalyzer.analyze (unit);
	assert (result.program == null && result.diagnostic != null);
	assert (result.diagnostic.format () == "test.astra:2:1: error: unknown type 'Mystery'");
	var duplicate = SemanticAnalyzer.analyze (parse_ok ("int f() { return missing; }\nint f(int x) { return x; }"));
	assert (duplicate.program == null && duplicate.diagnostic != null);
	assert (duplicate.diagnostic.format () == "test.astra:2:5: error: duplicate function 'f'; overloading is not implemented");
}

private void multiline_diagnostic() {
	var result = SemanticAnalyzer.analyze (parse_ok ("int f(int x) {\r\n\treturn /*é🙂*/ missing;\r\n}"));
	assert (result.program == null && result.diagnostic != null);
	assert (result.diagnostic.format () == "test.astra:2:16: error: unknown name 'missing'");
	assert (result.diagnostic.span.text () == "missing");
}

private void deterministic_dump() {
	string text = "int identity(int x) { return (x); }";
	string expected = "(program\n\t(function \"identity\" -> int\n\t\t(parameters\n\t\t\t(parameter #0 \"x\" : int)\n\t\t)\n\t\t(block\n\t\t\t(return (parameter-ref #0 \"x\" : int))\n\t\t)\n\t)\n)\n";
	var program = check_ok (text);
	assert (SemanticDump.format (program) == expected);
	assert (SemanticDump.format (program) == expected);
	assert (SemanticDump.format (check_ok (text)) == expected);
	assert (SemanticDump.format (check_ok ("")) == "(program)\n");
	assert (!expected.contains ("LLVM") && !expected.contains ("i32") && !expected.contains ("GObject"));
}

private void depth_boundary() {
	var prefix = check_expression (string.nfill (255, '-') + "1");
	int count = 0;
	var expression = prefix;
	while (expression is CheckedPrefixExpression) {
		assert (expression.semantic_type == prefix.semantic_type);
		expression = ((CheckedPrefixExpression) expression).operand;
		count++;
	}
	assert (count == 254 && expression is CheckedIntegerExpression);
	assert (SemanticDump.format_expression (prefix).has_prefix ("(prefix - : int"));
	var chain = new StringBuilder ("1");
	for (int i = 0; i < 255; i++) {
		chain.append ("+1");
	}
	var binary = check_expression (chain.str);
	assert (SemanticDump.format_expression (binary).has_prefix ("(binary + : int"));
	var parenthesized = check_expression (string.nfill (255, '(') + "1" + string.nfill (255, ')'));
	assert (parenthesized is CheckedIntegerExpression);
}

private void flat_lists() {
	var text = new StringBuilder ("int f(");
	for (int i = 0; i < 1000; i++) {
		text.append_printf ("%sint x%d", i == 0 ? "" : ", ", i);
	}
	text.append (") {");
	for (int i = 0; i < 1000; i++) {
		text.append_printf ("return x%d;", i);
	}
	text.append ("}");
	for (int i = 0; i < 1000; i++) {
		text.append_printf ("void f%d() {}", i);
	}
	var program = check_ok (text.str);
	assert (program.functions.length == 1001);
	var function = program.functions[0];
	assert (function.symbol.parameters.length == 1000);
	assert (function.body.statements.length == 1000);
	for (int i = 0; i < 1000; i++) {
		var reference = (CheckedParameterReferenceExpression) returned_expression (function, i);
		assert (reference.parameter == function.symbol.parameters[i]);
		assert (reference.parameter.ordinal == i);
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, TestCase> (str_hash, str_equal);
	register_branch_semantic_tests ();
	register_local_semantic_tests ();
	register_call_semantic_tests ();
	register_program ("empty-unit", "", 0);
	register_program ("comment-only", "/* empty */", 0);
	register_program ("main", "int main() { return 0; }", 1);
	register_program ("noop", "void noop() { return; }", 1);
	register_program ("identity", "int identity(int x) { return x; }", 1);
	register_program ("arithmetic", "int arithmetic(int a, int b) { return -(a + 2) * b % 3; }", 1);
	register_program ("empty-for-now", "int empty_for_now() {}", 1);
	register_program ("empty-void", "void empty() {}", 1);
	Test.add_func ("/semantic/types/canonical", canonical_types);
	Test.add_func ("/semantic/types/identifiers-and-namespaces", type_names_are_identifiers);
	Test.add_func ("/semantic/symbols/parameter-binding", parameter_binding);
	Test.add_func ("/semantic/symbols/function-local", function_local_bindings);
	Test.add_func ("/semantic/source/provenance", provenance);
	Test.add_func ("/semantic/source/retained-parameter", retained_parameter);
	Test.add_func ("/semantic/source/syntax-unchanged", syntax_is_unchanged);
	Test.add_func ("/semantic/expression/integer", integer_literal);
	Test.add_func ("/semantic/expression/oversized-literal", oversized_literal);
	register_prefix ("positive", "+", PrefixOperator.POSITIVE);
	register_prefix ("negative", "-", PrefixOperator.NEGATIVE);
	register_binary ("addition", "+", BinaryOperator.ADD);
	register_binary ("subtraction", "-", BinaryOperator.SUBTRACT);
	register_binary ("multiplication", "*", BinaryOperator.MULTIPLY);
	register_binary ("division", "/", BinaryOperator.DIVIDE);
	register_binary ("remainder", "%", BinaryOperator.REMAINDER);
	Test.add_func ("/semantic/expression/precedence", precedence);
	Test.add_func ("/semantic/expression/associativity", associativity);
	Test.add_func ("/semantic/expression/no-constant-evaluation", no_constant_evaluation);
	Test.add_func ("/semantic/return/structure-and-no-flow-analysis", return_structure);
	register_error ("unknown-return-type", "Mystery f() { return 0; }", 0, 7, "unknown type 'Mystery'");
	register_error ("unknown-parameter-type", "int f(Mystery x) { return x; }", 6, 7, "unknown type 'Mystery'");
	register_error ("void-parameter", "int f(void x) { return 0; }", 6, 4, "parameter type cannot be 'void'");
	register_error ("duplicate-parameter", "int f(int x, int x) { return x; }", 17, 1, "duplicate parameter 'x'");
	register_error ("duplicate-function", "int f() {} int f() {}", 15, 1, "duplicate function 'f'; overloading is not implemented");
	register_error ("duplicate-different-signature", "int f() {} int f(int x) { return x; }", 15, 1, "duplicate function 'f'; overloading is not implemented");
	register_error ("duplicate-different-return", "int f() {} void f() { return; }", 16, 1, "duplicate function 'f'; overloading is not implemented");
	register_error ("unknown-name", "int f() { return missing; }", 17, 7, "unknown name 'missing'");
	register_error ("unknown-prefix-name", "int f() { return -missing; }", 18, 7, "unknown name 'missing'");
	register_error ("unknown-right-name", "int f(int x) { return x + missing; }", 26, 7, "unknown name 'missing'");
	register_error ("unknown-left-name-first", "int f() { return left + right; }", 17, 4, "unknown name 'left'");
	register_error ("type-is-not-a-value", "int f() { return int; }", 17, 3, "unknown name 'int'");
	register_error ("function-is-not-a-parameter", "int f() { return f; }", 17, 1, "unknown name 'f'");
	register_error ("parameter-scope-does-not-leak", "int f(int x) {} int g() { return x; }", 33, 1, "unknown name 'x'");
	register_error ("bare-int-return", "int f() { return; }", 10, 6, "return requires a value of type 'int'");
	register_error ("void-value-return", "void f() { return 0; }", 18, 1, "cannot return a value from a 'void' function");
	register_error ("return-shape-before-expression", "void f() { return missing; }", 18, 7, "cannot return a value from a 'void' function");
	register_error ("check-after-return", "int f() { return 0; return missing; }", 27, 7, "unknown name 'missing'");
	register_error ("type-name-case-sensitive", "Int f() {}", 0, 3, "unknown type 'Int'");
	register_error ("value-name-case-sensitive", "int f(int x) { return X; }", 22, 1, "unknown name 'X'");
	Test.add_func ("/semantic/order/signatures-before-bodies", signature_before_body);
	Test.add_func ("/semantic/errors/multiline", multiline_diagnostic);
	Test.add_func ("/semantic/dump/deterministic", deterministic_dump);
	Test.add_func ("/semantic/limits/depth", depth_boundary);
	Test.add_func ("/semantic/limits/flat-lists", flat_lists);
	int result = Test.run ();
	cases.remove_all ();
	cases = null;
	return result;
}
}
