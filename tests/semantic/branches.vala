// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Semantics {
private void boolean_types_and_places() {
	var program = check_ok ("bool yes(){return true;} bool f(bool x){bool y = false; y = x; return y;} bool invert(bool x){return !x;}");
	var type = program.types.bool_type;
	assert (type.kind == TypeKind.BOOL && type.display_name () == "bool" && program.types.resolve ("bool") == type);
	assert (type != program.types.int_type && type != program.types.void_type);
	var literal = (CheckedBooleanExpression) returned_expression (program.functions[0]);
	assert (literal.literal == BooleanLiteral.TRUE && literal.semantic_type == type && literal.span.text () == "true");
	var function = program.functions[1];
	assert (function.symbol.return_type == type && function.symbol.parameters[0].semantic_type == type && function.locals[0].semantic_type == type);
	var declaration = (CheckedLocalDeclaration) function.body.statements[0];
	assert (declaration.local == function.locals[0] && ((CheckedBooleanExpression) declaration.initializer).literal == BooleanLiteral.FALSE);
	var assignment = (CheckedAssignment) function.body.statements[1];
	assert (assignment.target == declaration.local && ((CheckedParameterReferenceExpression) assignment.expression).parameter == function.symbol.parameters[0]);
	assert (((CheckedLocalReferenceExpression) returned_expression (function, 2)).local == declaration.local);
	var prefix = (CheckedPrefixExpression) returned_expression (program.functions[2]);
	assert (prefix.operator_kind == PrefixOperator.NOT && prefix.semantic_type == type && prefix.operand.semantic_type == type);
	assert (SemanticDump.format (program).contains ("(bool false : bool)"));
}

private void branch_scope_identities() {
	string text = "int f(bool c, bool d){int outer = 0; if(c){int x = 1; if(d){int y = x; outer = y;}}else{int x = 2; outer = x;} int x = outer; return x;}";
	var program = check_ok (text);
	var function = program.functions[0];
	assert (function.locals.length == 5);
	for (int i = 0; i < 5; i++) {
		assert (function.locals[i].ordinal == i);
	}
	var branch = (CheckedIf) function.body.statements[1];
	assert (branch.condition.semantic_type == program.types.bool_type);
	assert (((CheckedParameterReferenceExpression) branch.condition).parameter == function.symbol.parameters[0]);
	var then_local = ((CheckedLocalDeclaration) branch.then_body.statements[0]).local;
	var else_local = ((CheckedLocalDeclaration) branch.else_body.statements[0]).local;
	assert (then_local == function.locals[1] && else_local == function.locals[3] && then_local != else_local);
	assert (then_local.name == "x" && else_local.name == "x" && function.locals[4].name == "x");
	var nested = (CheckedIf) branch.then_body.statements[1];
	var nested_local = (CheckedLocalDeclaration) nested.then_body.statements[0];
	assert (nested_local.local == function.locals[2] && ((CheckedLocalReferenceExpression) nested_local.initializer).local == then_local);
	assert (((CheckedAssignment) nested.then_body.statements[1]).target == function.locals[0]);
	assert (((CheckedAssignment) branch.else_body.statements[1]).target == function.locals[0]);
	assert (((CheckedLocalReferenceExpression) ((CheckedAssignment) branch.else_body.statements[1]).expression).local == else_local);
	assert (SemanticDump.format (program) == SemanticDump.format (check_ok (text)));
}

private void branch_semantic_error(string name, string text, string message) {
	add_case ("/semantic/branch/error/" + name, () => {
			var result = SemanticAnalyzer.analyze (parse_ok (text));
			assert (result.program == null && result.diagnostic != null);
			if (result.diagnostic.message != message) {
				GLib.error ("Expected %s; got %s", message, result.diagnostic.message);
			}
		});
}

private void register_branch_semantic_tests() {
	Test.add_func ("/semantic/branch/bool-types-and-places", boolean_types_and_places);
	Test.add_func ("/semantic/branch/scope-identities", branch_scope_identities);
	string[] operators = {
		"<", "<=", ">", ">=", "==", "!="
	};
	BinaryOperator[] kinds = {
		BinaryOperator.LESS, BinaryOperator.LESS_EQUAL, BinaryOperator.GREATER, BinaryOperator.GREATER_EQUAL, BinaryOperator.EQUAL, BinaryOperator.NOT_EQUAL
	};
	for (int i = 0; i < operators.length; i++) {
		string spelling = operators[i];
		BinaryOperator kind = kinds[i];
		add_case ("/semantic/branch/operator/" + spelling, () => {
				var program = check_ok ("bool f(int a, int b){return a " + spelling + " b;}");
				var binary = (CheckedBinaryExpression) returned_expression (program.functions[0]);
				assert (binary.operator_kind == kind && binary.semantic_type == program.types.bool_type);
				assert (binary.left.semantic_type == program.types.int_type && binary.right.semantic_type == program.types.int_type);
			});
	}
	register_program ("bool-equality", "bool f(bool a, bool b){return a == b != false;}", 1);
	register_program ("not-equality", "bool f(int a, int b){return !(a == b);}", 1);
	register_program ("comparison-condition", "int f(int a, int b){if(a + 1 < b * 2){return a;}else{return b;}}", 1);
	register_program ("comparison-equality", "bool f(int a, int b){return a < b == true;}", 1);
	register_program ("bool-names", "bool bool(bool bool){return bool;}", 1);
	register_program ("sibling-locals", "void f(bool c){if(c){int x = 1;}else{int x = 2;}return;}", 1);
	register_program ("partial-return-still-semantic", "bool f(bool c){if(c){return true;}}", 1);
	branch_semantic_error ("integer-condition", "void f(){if(1){}}", "if condition must have type 'bool', found 'int'");
	branch_semantic_error ("not-integer", "bool f(){return !1;}", "operator '!' requires a 'bool' operand, found 'int'");
	branch_semantic_error ("positive-bool", "bool f(){return +true;}", "operator '+' requires an 'int' operand, found 'bool'");
	branch_semantic_error ("negative-bool", "bool f(){return -false;}", "operator '-' requires an 'int' operand, found 'bool'");
	branch_semantic_error ("relational-left", "bool f(){return true < 1;}", "operator '<' requires an 'int' operand, found 'bool'");
	branch_semantic_error ("relational-right", "bool f(){return 1 >= false;}", "operator '>=' requires an 'int' operand, found 'bool'");
	branch_semantic_error ("parenthesized-chained-relational", "bool f(){return (1 < 2) < 3;}", "operator '<' requires an 'int' operand, found 'bool'");
	branch_semantic_error ("arithmetic-bool", "bool f(){return true + false;}", "operator '+' requires an 'int' operand, found 'bool'");
	branch_semantic_error ("equality-bool-int", "bool f(){return true == 1;}", "operator '==' requires matching non-void operands, found 'bool' and 'int'");
	branch_semantic_error ("equality-int-bool", "bool f(){return 1 != false;}", "operator '!=' requires matching non-void operands, found 'int' and 'bool'");
	branch_semantic_error ("bare-bool-return", "bool f(){return;}", "return requires a value of type 'bool'");
	branch_semantic_error ("bool-return-int", "bool f(){return 1;}", "expected return value of type 'bool', found 'int'");
	branch_semantic_error ("int-return-bool", "int f(){return true;}", "expected return value of type 'int', found 'bool'");
	branch_semantic_error ("bool-initializer", "void f(){bool x = 1;}", "expected initializer of type 'bool', found 'int'");
	branch_semantic_error ("bool-assignment", "void f(){bool x = true; x = 1;}", "expected assignment value of type 'bool', found 'int'");
	branch_semantic_error ("escape", "int f(bool c){if(c){int x = 1;}return x;}", "unknown name 'x'");
	branch_semantic_error ("sibling-visibility", "int f(bool c){if(c){int x = 1;}else{return x;}return 0;}", "unknown name 'x'");
	branch_semantic_error ("shadow-outer", "int f(bool c){int x = 1;if(c){int x = 2;}return x;}", "duplicate local 'x'");
	branch_semantic_error ("shadow-parameter", "int f(int x,bool c){if(c){int x = 2;}return x;}", "local 'x' conflicts with parameter");
	branch_semantic_error ("shadow-nested", "void f(bool c){if(c){int x = 1;if(c){int x = 2;}}}", "duplicate local 'x'");
	branch_semantic_error ("branch-before-declaration", "void f(bool c){if(c){int y = x;int x = 1;}}", "unknown name 'x'");
	branch_semantic_error ("branch-self-initializer", "void f(bool c){if(c){bool x = x;}}", "unknown name 'x'");
	branch_semantic_error ("nested-escape", "void f(bool c){if(c){if(c){int x = 1;}int y = x;}}", "unknown name 'x'");
	branch_semantic_error ("escaped-assignment", "void f(bool c){if(c){int x = 1;}x = 2;}", "unknown assignment target 'x'");
	branch_semantic_error ("branch-parameter-assignment", "void f(bool c){if(c){c = false;}}", "assignment to parameter 'c' is not supported");
	branch_semantic_error ("unreachable-still-checked", "int f(bool c){return 1;if(c){return missing;}}", "unknown name 'missing'");
}

}
