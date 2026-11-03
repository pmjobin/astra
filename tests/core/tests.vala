// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.Core {
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

// Preserve the existing plain-callback convention for strict C pointers.
private void add_case(string path, owned TestAction action) {
	cases.insert (path, new TestCase ((owned) action));
	Test.add_func (path, run_case);
}

private void run_case() {
	cases.lookup (Test.get_path ()).run ();
}

private CheckedProgram check_ok(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("test.astra", text));
	assert (parsed.diagnostic == null && parsed.unit != null);
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null && checked_result.program != null);
	return checked_result.program;
}

private void verify_ok(CoreProgram program) {
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		GLib.error ("Unexpected Core verification failure: %s", error.message);
	}
}

private CoreProgram build_checked(CheckedProgram program) {
	try {
		var core = CoreBuilder.build (program);
		verify_ok (core);
		return core;
	} catch (CoreError error) {
		GLib.error ("Unexpected Core construction failure: %s", error.message);
	}
}

private CoreProgram build_ok(string text) {
	return build_checked (check_ok (text));
}

private string dump_ok(CoreProgram program) {
	try {
		return CoreDump.format (program);
	} catch (CoreError error) {
		GLib.error ("Unexpected Core dump failure: %s", error.message);
	}
}

private CoreValue returned_value(CoreFunction function, int index = 0) {
	assert (function.body.statements[index] is CoreReturn);
	var returned = (CoreReturn) function.body.statements[index];
	assert (returned.value != null);
	return returned.value;
}

private CoreValue build_value(string text) {
	return returned_value (build_ok ("int f(int a, int b) { return " + text + "; }").functions[0]);
}

private void register_program(string name, string text, int function_count) {
	add_case ("/core/program/" + name, () => {
			var program = build_ok (text);
			assert (program.functions.length == function_count);
			assert (program.span.text () == text);
		});
}

private void declarations_and_types() {
	var checked_program = check_ok ("int z(int a, int b) { return a + b; } void m() { return; } int a(int x) { return x; }");
	string before = SemanticDump.format (checked_program);
	var program = build_checked (checked_program);
	assert (program.functions.length == 3);
	assert (program.functions[0].name == "z" && program.functions[1].name == "m" && program.functions[2].name == "a");
	for (int i = 0; i < program.functions.length; i++) {
		var function = program.functions[i];
		var symbol = checked_program.functions[i].symbol;
		assert ((Object) function != (Object) symbol);
		assert ((Object) function != (Object) checked_program.functions[i]);
		assert (function.return_type == symbol.return_type);
		assert (function.parameters.length == symbol.parameters.length);
		for (int j = 0; j < function.parameters.length; j++) {
			assert ((Object) function.parameters[j] != (Object) symbol.parameters[j]);
			assert (function.parameters[j].name == symbol.parameters[j].name);
			assert (function.parameters[j].ordinal == j);
			assert (function.parameters[j].semantic_type == checked_program.types.int_type);
		}
	}
	assert (program.functions[1].return_type == checked_program.types.void_type);
	assert (returned_value (program.functions[0]).semantic_type == checked_program.types.int_type);
	var second = build_checked (checked_program);
	assert (second.functions[0] != program.functions[0]);
	assert (second.functions[0].parameters[0] != program.functions[0].parameters[0]);
	assert (dump_ok (second) == dump_ok (program));
	assert (SemanticDump.format (checked_program) == before);
}

private void parameter_identity() {
	var program = build_ok ("int f(int x, int xx) { return x + xx; return x; } int g(int x) { return x; }");
	var first = program.functions[0];
	var second = program.functions[1];
	var sum = (CoreBinaryValue) returned_value (first);
	var left = (CoreParameterValue) sum.left;
	var right = (CoreParameterValue) sum.right;
	assert (left.parameter == first.parameters[0]);
	assert (right.parameter == first.parameters[1]);
	assert (left.parameter != right.parameter);
	assert (((CoreParameterValue) returned_value (first, 1)).parameter == left.parameter);
	assert (((CoreParameterValue) returned_value (second)).parameter == second.parameters[0]);
	assert (second.parameters[0] != first.parameters[0]);
	// Reference type is derived from its exact parameter by construction.
	assert (left.semantic_type == left.parameter.semantic_type);
	assert (right.semantic_type == right.parameter.semantic_type);
}

private void semantic_binding_over_spelling() {
	var program = check_ok ("int f(int a, int b) { return b; }");
	var function = program.functions[0];
	var returned = (CheckedReturnStatement) function.body.statements[0];
	// Deliberately disagreeing provenance proves the builder trusts binding.
	var reference = new CheckedParameterReferenceExpression (returned.expression.span, function.symbol.parameters[0]);
	function.body.statements[0] = new CheckedReturnStatement (returned.span, reference);
	var core = build_checked (program);
	var value = (CoreParameterValue) returned_value (core.functions[0]);
	assert (value.span.text () == "b");
	assert (value.parameter == core.functions[0].parameters[0]);
	assert (value.parameter.name == "a");
}

private void expect_build_error(CheckedProgram program, string message) {
	for (int i = 0; i < 2; i++) {
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			assert (error is CoreError.INVALID_CHECKED_MODEL);
			assert (error.message == "internal Core construction error: " + message);
			continue;
		}
		GLib.error ("Invalid checked model was accepted");
	}
}

private void missing_symbol_mapping() {
	var program = check_ok ("int f(int x) { return x; }");
	var function = program.functions[0];
	var parameter = function.symbol.parameters[0];
	// Same spelling, type, ordinal, and spans do not establish identity.
	var impostor = new ParameterSymbol (parameter.span, parameter.name_span, parameter.semantic_type, parameter.ordinal);
	var returned = (CheckedReturnStatement) function.body.statements[0];
	function.body.statements[0] = new CheckedReturnStatement (returned.span, new CheckedParameterReferenceExpression (returned.expression.span, impostor));
	expect_build_error (program, "parameter reference has no declaration in the containing function");
}

private void checked_cross_function_reference() {
	var program = check_ok ("int f(int x) { return x; } int g(int x) { return x; }");
	var returned = (CheckedReturnStatement) program.functions[0].body.statements[0];
	program.functions[0].body.statements[0] = new CheckedReturnStatement (returned.span, new CheckedParameterReferenceExpression (returned.expression.span, program.functions[1].symbol.parameters[0]));
	expect_build_error (program, "parameter reference has no declaration in the containing function");
}

private void integer_spelling() {
	var ordinary = (CoreIntegerValue) build_value ("42");
	assert (ordinary.span.text () == "42" && ordinary.semantic_type.kind == TypeKind.INT);
	assert (((CoreIntegerValue) build_value ("00042")).span.text () == "00042");
	assert (((CoreIntegerValue) build_value ("((007))")).span.text () == "007");
}

private void huge_literal() {
	string digits = "000" + string.nfill (1000, '9');
	var parsed = Parser.parse (new SourceFile.from_text ("huge.astra", "int huge() { return ((" + digits + ")); }"));
	assert (parsed.diagnostic == null && SyntaxDump.format (parsed.unit).contains (digits));
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.program == null && result.diagnostic.message == "integer literal is out of range for 'int'");
	assert (result.diagnostic.span.text () == digits && result.diagnostic.span.end - result.diagnostic.span.start == 1003);
}

private void register_prefix(string name, string spelling, PrefixOperator operator_kind) {
	add_case ("/core/value/" + name, () => {
			var prefix = (CorePrefixValue) build_value (spelling + "a");
			assert (prefix.operator_kind == operator_kind);
			assert (prefix.semantic_type.kind == TypeKind.INT);
			assert (prefix.operand.semantic_type == prefix.semantic_type);
			assert (prefix.operand is CoreParameterValue);
		});
}

private void register_binary(string name, string spelling, BinaryOperator operator_kind) {
	add_case ("/core/value/" + name, () => {
			var binary = (CoreBinaryValue) build_value ("a " + spelling + " b");
			assert (binary.operator_kind == operator_kind);
			assert (binary.semantic_type.kind == TypeKind.INT);
			assert (binary.left.semantic_type == binary.semantic_type && binary.right.semantic_type == binary.semantic_type);
			assert (((CoreParameterValue) binary.left).parameter.ordinal == 0);
			assert (((CoreParameterValue) binary.right).parameter.ordinal == 1);
		});
}

private void arithmetic_structure() {
	var sum = (CoreBinaryValue) build_value ("1 + 2 * 3");
	assert (sum.operator_kind == BinaryOperator.ADD);
	assert (((CoreIntegerValue) sum.left).span.text () == "1");
	var product = (CoreBinaryValue) sum.right;
	assert (product.operator_kind == BinaryOperator.MULTIPLY);
	assert (((CoreIntegerValue) product.left).span.text () == "2");
	assert (((CoreIntegerValue) product.right).span.text () == "3");
	var remainder = (CoreBinaryValue) build_value ("-(a + 2) * b % 3");
	assert (remainder.operator_kind == BinaryOperator.REMAINDER);
	assert (((CoreIntegerValue) remainder.right).span.text () == "3");
	product = (CoreBinaryValue) remainder.left;
	assert (product.operator_kind == BinaryOperator.MULTIPLY);
	assert (((CoreParameterValue) product.right).parameter.ordinal == 1);
	var negative = (CorePrefixValue) product.left;
	assert (negative.operator_kind == PrefixOperator.NEGATIVE);
	assert (((CoreBinaryValue) negative.operand).operator_kind == BinaryOperator.ADD);
}

private void no_simplification() {
	assert (((CorePrefixValue) build_value ("+a")).operator_kind == PrefixOperator.POSITIVE);
	var prefix = (CorePrefixValue) build_value ("+-0007");
	assert (prefix.operator_kind == PrefixOperator.POSITIVE);
	assert (((CoreIntegerValue) prefix.operand).value.signed_value == -7);
	assert (prefix.operand.span.text () == "-0007");
	assert (((CoreBinaryValue) build_value ("a + 0")).operator_kind == BinaryOperator.ADD);
	assert (((CoreBinaryValue) build_value ("1 / 0")).operator_kind == BinaryOperator.DIVIDE);
	assert (((CoreBinaryValue) build_value ("1 % 0")).operator_kind == BinaryOperator.REMAINDER);
	var sum = (CoreBinaryValue) build_value ("8 - 3 + 1");
	assert (sum.operator_kind == BinaryOperator.ADD);
	assert (((CoreBinaryValue) sum.left).operator_kind == BinaryOperator.SUBTRACT);
	var remainder = (CoreBinaryValue) build_value ("8 / 2 * 3 % 5");
	assert (remainder.operator_kind == BinaryOperator.REMAINDER);
	assert (((CoreBinaryValue) remainder.left).operator_kind == BinaryOperator.MULTIPLY);
	assert (((CoreBinaryValue) ((CoreBinaryValue) remainder.left).left).operator_kind == BinaryOperator.DIVIDE);
}

private void return_order() {
	var program = build_ok ("void f() { return; return; } int g() { return 1; return 2; } int h() {}");
	assert (program.functions[0].body.statements.length == 2);
	assert (((CoreReturn) program.functions[0].body.statements[0]).value == null);
	assert (((CoreReturn) program.functions[0].body.statements[1]).value == null);
	assert (program.functions[1].body.statements.length == 2);
	assert (((CoreIntegerValue) returned_value (program.functions[1])).span.text () == "1");
	assert (((CoreIntegerValue) returned_value (program.functions[1], 1)).span.text () == "2");
	assert (program.functions[2].body.statements.length == 0);
}

private void provenance() {
	string text = "int f(int x) { return -(x + 007) * x; }";
	var checked_program = check_ok (text);
	var program = build_checked (checked_program);
	var function = program.functions[0];
	assert (program.span.file == checked_program.span.file);
	assert (function.span.text () == text);
	assert (function.name_span.text () == "f");
	assert (function.parameters[0].span.text () == "int x");
	assert (function.parameters[0].name_span.text () == "x");
	assert (function.body.span.text () == "{ return -(x + 007) * x; }");
	assert (function.body.statements[0].span.text () == "return -(x + 007) * x;");
	var product = (CoreBinaryValue) returned_value (function);
	assert (product.span.text () == "-(x + 007) * x");
	var prefix = (CorePrefixValue) product.left;
	assert (prefix.span.text () == "-(x + 007)");
	var sum = (CoreBinaryValue) prefix.operand;
	assert (sum.span.text () == "x + 007");
	assert (sum.left.span.text () == "x" && sum.right.span.text () == "007");
	assert (sum.right.span.start == 28 && sum.right.span.end == 31);
	assert (sum.right.span.file == checked_program.span.file);
}

private void frontend_lifetime() {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("retained.astra", "int f(int x) { return x + 007; }"));
	assert (parsed.diagnostic == null);
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var syntax_ref = WeakRef (parsed.unit);
	var token_ref = WeakRef (parsed.unit.functions[0].name);
	var program_ref = WeakRef (checked_result.program);
	var function_ref = WeakRef (checked_result.program.functions[0]);
	var symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
	var parameter_ref = WeakRef (checked_result.program.functions[0].symbol.parameters[0]);
	var value_ref = WeakRef (((CheckedReturnStatement) checked_result.program.functions[0].body.statements[0]).expression);
	var types_ref = WeakRef (checked_result.program.types);
	var type_ref = WeakRef (checked_result.program.types.int_type);
	var source_ref = WeakRef (parsed.unit.span.file);
	CoreProgram? core = build_checked (checked_result.program);
	parsed = null;
	checked_result = null;
	assert (syntax_ref.get () == null && token_ref.get () == null);
	assert (program_ref.get () == null && function_ref.get () == null);
	assert (symbol_ref.get () == null && parameter_ref.get () == null && value_ref.get () == null);
	assert (types_ref.get () == null);
	assert (type_ref.get () == core.functions[0].return_type);
	assert (source_ref.get () == core.span.file);
	verify_ok (core);
	assert (dump_ok (core).contains ("(integer 7 : int)"));
	{
		var binary = (CoreBinaryValue) returned_value (core.functions[0]);
		assert (((CoreParameterValue) binary.left).parameter == core.functions[0].parameters[0]);
		assert (((CoreIntegerValue) binary.right).span.text () == "007");
		assert (((CoreIntegerValue) binary.right).value.signed_value == 7);
		assert (binary.right.span.file.path == "retained.astra");
		int line;
		int column;
		binary.right.span.file.locate (binary.right.span.start, out line, out column);
		assert (line == 1 && column == 27);
	}
	core = null;
	assert (type_ref.get () == null && source_ref.get () == null);
}

private void expect_invalid(CoreProgram program, string path, string message) {
	string expected = "internal Core verification error at " + path + ": " + message;
	for (int i = 0; i < 2; i++) {
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			assert (error is CoreError.INVALID_IR);
			if (error.message != expected) {
				GLib.error ("Expected %s; got %s", expected, error.message);
			}
			continue;
		}
		GLib.error ("Malformed Core passed verification");
	}
	try {
		CoreDump.format (program);
	} catch (CoreError error) {
		assert (error.message == expected);
		return;
	}
	GLib.error ("Malformed Core produced a dump");
}

private void register_verifier_tests() {
	add_case ("/core/verifier/cross-function-reference", () => {
			var program = build_ok ("int f(int x) { return x; } int g(int x) { return x; }");
			var function = program.functions[0];
			function.body.statements[0] = new CoreReturn (function.body.span, new CoreParameterValue (function.span, program.functions[1].parameters[0]));
			expect_invalid (program, "function #0/statement #0/value", "parameter reference is not owned by the containing function");
		});
	add_case ("/core/verifier/unowned-parameter", () => {
			var program = build_ok ("int f(int x) { return x; }");
			program.functions[0].parameters.remove_index (0);
			expect_invalid (program, "function #0/statement #0/value", "parameter reference is not owned by the containing function");
		});
	add_case ("/core/verifier/void-return-value", () => {
			var program = build_ok ("void f() { return; } int g() { return 1; }");
			program.functions[0].body.statements[0] = new CoreReturn (program.span, returned_value (program.functions[1]));
			expect_invalid (program, "function #0/statement #0", "void function return must not carry a value");
		});
	add_case ("/core/verifier/missing-int-return-value", () => {
			var program = build_ok ("int f() { return 1; }");
			program.functions[0].body.statements[0] = new CoreReturn (program.span, null);
			expect_invalid (program, "function #0/statement #0", "non-void function return must carry a value");
		});
	add_case ("/core/verifier/void-value-type", () => {
			var program = build_ok ("int f() { return 1; } void g() {}");
			program.functions[0].body.statements[0] = new CoreReturn (program.span, new CoreIntegerValue (program.span, program.functions[1].return_type, AstraIntValue.from_int64 (7)));
			expect_invalid (program, "function #0/statement #0/value", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/core/verifier/parameter-ordinal", () => {
			var program = build_ok ("int f(int x) {}");
			var parameter = program.functions[0].parameters[0];
			program.functions[0].parameters[0] = new CoreParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, 1);
			expect_invalid (program, "function #0/parameter #0", "expected ordinal 0, found 1");
		});
	add_case ("/core/verifier/shared-parameter", () => {
			var program = build_ok ("int f(int x) {} int g(int x) {}");
			program.functions[1].parameters[0] = program.functions[0].parameters[0];
			expect_invalid (program, "function #1/parameter #0", "parameter identity occurs in more than one declaration slot");
		});
	add_case ("/core/verifier/repeated-parameter", () => {
			var program = build_ok ("int f(int x) {}");
			program.functions[0].parameters.add (program.functions[0].parameters[0]);
			expect_invalid (program, "function #0/parameter #1", "parameter identity occurs in more than one declaration slot");
		});
	add_case ("/core/verifier/repeated-function", () => {
			var program = build_ok ("void f() {}");
			program.functions.add (program.functions[0]);
			expect_invalid (program, "function #1", "function identity occurs more than once");
		});
	add_case ("/core/verifier/void-parameter", () => {
			var program = build_ok ("void f() {}");
			program.functions[0].parameters.add (new CoreParameter (program.span, program.span, "x", program.functions[0].return_type, 0));
			expect_invalid (program, "function #0/parameter #0", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/core/verifier/type-identity", () => {
			var program = build_ok ("int f() { return 1; }");
			program.functions[0].body.statements[0] = new CoreReturn (program.span, new CoreIntegerValue (program.span, new SemanticType (TypeKind.INT), AstraIntValue.from_int64 (7)));
			expect_invalid (program, "function #0/statement #0/value", "inconsistent 'int' semantic type identity");
		});
	add_case ("/core/verifier/prefix-operand-type", () => {
			var program = build_ok ("int f() { return 1; } void g() {}");
			var bad_operand = new CoreIntegerValue (program.span, program.functions[1].return_type, AstraIntValue.from_int64 (7));
			var prefix = new CorePrefixValue (program.span, program.functions[0].return_type, PrefixOperator.NEGATIVE, bad_operand);
			program.functions[0].body.statements[0] = new CoreReturn (program.span, prefix);
			expect_invalid (program, "function #0/statement #0/value/operand", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/core/verifier/binary-operand-type", () => {
			var program = build_ok ("int f() { return 1; } void g() {}");
			var bad_operand = new CoreIntegerValue (program.span, program.functions[1].return_type, AstraIntValue.from_int64 (7));
			var binary = new CoreBinaryValue (program.span, program.functions[0].return_type, BinaryOperator.ADD, returned_value (program.functions[0]), bad_operand);
			program.functions[0].body.statements[0] = new CoreReturn (program.span, binary);
			expect_invalid (program, "function #0/statement #0/value/right", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/core/verifier/prefix-operator", () => {
			var program = build_ok ("int f() { return 1; }");
			var prefix = new CorePrefixValue (program.span, program.functions[0].return_type, (PrefixOperator) 99, returned_value (program.functions[0]));
			program.functions[0].body.statements[0] = new CoreReturn (program.span, prefix);
			expect_invalid (program, "function #0/statement #0/value", "unsupported semantic prefix operator");
		});
	add_case ("/core/verifier/binary-operator", () => {
			var program = build_ok ("int f() { return 1; }");
			var value = returned_value (program.functions[0]);
			var binary = new CoreBinaryValue (program.span, value.semantic_type, (BinaryOperator) 99, value, value);
			program.functions[0].body.statements[0] = new CoreReturn (program.span, binary);
			expect_invalid (program, "function #0/statement #0/value", "unsupported semantic binary operator");
		});
}

private void deterministic_dump() {
	string text = "int identity(int x) { return (x); }";
	string expected = "(core-program\n\t(function \"identity\" -> int\n\t\t(parameters\n\t\t\t(parameter #0 \"x\" : int)\n\t\t)\n\t\t(block\n\t\t\t(return\n\t\t\t\t(parameter #0 : int)\n\t\t\t)\n\t\t)\n\t)\n)\n";
	var program = build_ok (text);
	assert (dump_ok (program) == expected);
	assert (dump_ok (program) == expected);
	assert (dump_ok (build_ok (text)) == expected);
	assert (dump_ok (build_ok ("")) == "(core-program)\n");
	assert (!expected.contains ("LLVM") && !expected.contains ("i32") && !expected.contains ("GObject") && !expected.contains ("parenthesized"));
}

private void depth_boundary() {
	var value = build_value (string.nfill (255, '-') + "1");
	int count = 0;
	while (value is CorePrefixValue) {
		value = ((CorePrefixValue) value).operand;
		count++;
	}
	assert (count == 254 && value is CoreIntegerValue);
	var chain = new StringBuilder ("1");
	for (int i = 0; i < 255; i++) {
		chain.append ("+1");
	}
	assert (dump_ok (build_ok ("int f() { return " + chain.str + "; }")).contains ("(binary + : int"));
	assert (build_value (string.nfill (255, '(') + "1" + string.nfill (255, ')')) is CoreIntegerValue);
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
	var program = build_ok (text.str);
	assert (program.functions.length == 1001);
	assert (program.functions[0].parameters.length == 1000);
	assert (program.functions[0].body.statements.length == 1000);
	for (int i = 0; i < 1000; i++) {
		assert (((CoreParameterValue) returned_value (program.functions[0], i)).parameter == program.functions[0].parameters[i]);
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, TestCase> (str_hash, str_equal);
	register_place_core_tests ();
	register_branch_core_tests ();
	register_program ("empty", "", 0);
	register_program ("comment-only", "/* empty */", 0);
	register_program ("one-function", "int main() { return 0; }", 1);
	register_program ("empty-int-body", "int f() {}", 1);
	register_program ("empty-void-body", "void f() {}", 1);
	Test.add_func ("/core/program/declarations-and-types", declarations_and_types);
	Test.add_func ("/core/identity/parameters", parameter_identity);
	Test.add_func ("/core/identity/binding-over-spelling", semantic_binding_over_spelling);
	Test.add_func ("/core/builder/missing-symbol-mapping", missing_symbol_mapping);
	Test.add_func ("/core/builder/cross-function-reference", checked_cross_function_reference);
	Test.add_func ("/core/value/integer-spelling", integer_spelling);
	Test.add_func ("/core/value/huge-literal", huge_literal);
	register_prefix ("positive", "+", PrefixOperator.POSITIVE);
	register_prefix ("negative", "-", PrefixOperator.NEGATIVE);
	register_binary ("addition", "+", BinaryOperator.ADD);
	register_binary ("subtraction", "-", BinaryOperator.SUBTRACT);
	register_binary ("multiplication", "*", BinaryOperator.MULTIPLY);
	register_binary ("division", "/", BinaryOperator.DIVIDE);
	register_binary ("remainder", "%", BinaryOperator.REMAINDER);
	Test.add_func ("/core/value/arithmetic-structure", arithmetic_structure);
	Test.add_func ("/core/value/no-simplification", no_simplification);
	Test.add_func ("/core/statement/return-order", return_order);
	Test.add_func ("/core/source/provenance", provenance);
	Test.add_func ("/core/source/frontend-lifetime", frontend_lifetime);
	register_verifier_tests ();
	Test.add_func ("/core/dump/deterministic", deterministic_dump);
	Test.add_func ("/core/limits/depth", depth_boundary);
	Test.add_func ("/core/limits/flat-lists", flat_lists);
	int result = Test.run ();
	cases.remove_all ();
	cases = null;
	return result;
}

}
