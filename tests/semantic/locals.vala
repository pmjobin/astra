// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Semantics {
private void local_binding() {
	var program = check_ok ("int f(int x) { int a = x; int b = a + 1; b = b * 2; return b; } int g() { int a = 1; return a; }");
	var function = program.functions[0];
	assert (function.locals.length == 2);
	for (int i = 0; i < function.locals.length; i++) {
		var local = function.locals[i];
		assert (local.ordinal == i && local.semantic_type == program.types.int_type);
		assert (((CheckedLocalDeclaration) function.body.statements[i]).local == local);
		assert (((CheckedLocalDeclaration) function.body.statements[i]).initializer.semantic_type == local.semantic_type);
	}
	var first = (CheckedLocalDeclaration) function.body.statements[0];
	assert (((CheckedParameterReferenceExpression) first.initializer).parameter == function.symbol.parameters[0]);
	assert (first.local.name == "a" && first.local.span.text () == "int a = x;" && first.local.name_span.text () == "a");
	var second = (CheckedLocalDeclaration) function.body.statements[1];
	assert (((CheckedLocalReferenceExpression) ((CheckedBinaryExpression) second.initializer).left).local == first.local);
	var assignment = (CheckedAssignment) function.body.statements[2];
	assert (assignment.target == second.local && assignment.expression.semantic_type == second.local.semantic_type);
	assert (((CheckedLocalReferenceExpression) ((CheckedBinaryExpression) assignment.expression).left).local == second.local);
	assert (((CheckedLocalReferenceExpression) returned_expression (function, 3)).local == second.local);
	assert (program.functions[1].locals[0].ordinal == 0 && program.functions[1].locals[0] != first.local);
	assert (((CheckedLocalReferenceExpression) returned_expression (program.functions[1], 1)).local == program.functions[1].locals[0]);
}

private void local_dump_and_syntax_independence() {
	var syntax = parse_ok ("int mutate(int x) { int y = x + 1; y = y * 2; return y; }");
	string before = SyntaxDump.format (syntax);
	var first = SemanticAnalyzer.analyze (syntax).program;
	var second = SemanticAnalyzer.analyze (syntax).program;
	assert (first != null && second != null);
	assert (first.functions[0].locals[0] != second.functions[0].locals[0]);
	assert (SyntaxDump.format (syntax) == before);
	string dump = SemanticDump.format (first);
	assert (dump == SemanticDump.format (second) && dump == SemanticDump.format (first));
	assert (dump.contains ("(local #0 \"y\" : int)") && dump.contains ("(local-init #0 \"y\" : int"));
	assert (dump.contains ("(assign (local-ref #0 \"y\" : int)") && dump.contains ("(return (local-ref #0 \"y\" : int))"));
	assert (!dump.contains ("place") && !dump.contains ("load") && !dump.contains ("LLVM"));
}

private void many_locals() {
	var text = new StringBuilder ("int f() { int x0 = 1;");
	for (int i = 1; i < 1000; i++) {
		text.append_printf ("int x%d = x%d;", i, i - 1);
	}
	text.append ("return x999; }");
	var function = check_ok (text.str).functions[0];
	assert (function.locals.length == 1000);
	for (int i = 1; i < 1000; i++) {
		assert (function.locals[i].ordinal == i);
		var declaration = (CheckedLocalDeclaration) function.body.statements[i];
		assert (((CheckedLocalReferenceExpression) declaration.initializer).local == function.locals[i - 1]);
	}
}

private void register_local_semantic_tests() {
	Test.add_func ("/semantic/locals/binding-and-types", local_binding);
	Test.add_func ("/semantic/locals/dump-and-syntax-independence", local_dump_and_syntax_independence);
	Test.add_func ("/semantic/locals/flat-list", many_locals);
	register_program ("local-mutation", "int f() { int x = 1; x = 2; return x; }", 1);
	register_program ("local-repeated-mutation", "int f() { int x = 1; x = x + 1; x = x * 2; return x; }", 1);
	register_program ("local-void-function", "void f() { int x = 1; x = 2; return; }", 1);
	register_program ("local-post-return", "int f() { int x = 1; return x; x = 2; return x; }", 1);
	register_program ("local-declaration-after-return", "int f() { return 1; int x = 2; return x; }", 1);
	register_program ("local-type-function-names", "int f() { int int = 1; int f = int; f = f + 1; return f; }", 1);
	register_error ("unknown-local-type", "int f(){Mystery x = 1; return x;}", 8, 7, "unknown type 'Mystery'");
	register_error ("void-local-type", "int f(){void x = 1; return x;}", 8, 4, "local type cannot be 'void'");
	register_error ("local-before-declaration", "int f(){int b = a + 1; int a = 1; return b;}", 16, 1, "unknown name 'a'");
	register_error ("local-self-reference", "int f(){int a = a + 1; return a;}", 16, 1, "unknown name 'a'");
	register_error ("duplicate-local", "int f(){int a = 1; int a = 2; return a;}", 23, 1, "duplicate local 'a'");
	register_error ("local-parameter-conflict", "int f(int a){int a = 1; return a;}", 17, 1, "local 'a' conflicts with parameter");
	register_error ("local-name-before-initializer", "int f(){int a = 1; int a = missing; return a;}", 23, 1, "duplicate local 'a'");
	register_error ("local-type-before-initializer", "int f(){void a = missing; return a;}", 8, 4, "local type cannot be 'void'");
	register_error ("local-return-before-declaration", "int f(){return a; int a = 1;}", 15, 1, "unknown name 'a'");
	register_error ("local-scope-does-not-leak", "int f(){int x = 1; return x;} int g(){return x;}", 45, 1, "unknown name 'x'");
	register_error ("assignment-before-declaration", "int f(){x = 1; int x = 2; return x;}", 8, 1, "unknown assignment target 'x'");
	register_error ("assignment-unknown-target", "int f(){missing = 1; return 0;}", 8, 7, "unknown assignment target 'missing'");
	register_error ("assignment-parameter", "int f(int x){x = 2; return x;}", 13, 1, "assignment to parameter 'x' is not supported");
	register_error ("assignment-function", "int f(){f = 2; return 0;}", 8, 1, "name 'f' is not an assignable local");
	register_error ("assignment-type", "int f(){int = 2; return 0;}", 8, 3, "name 'int' is not an assignable local");
	register_error ("assignment-target-before-rhs", "int f(){x = missing; return 0;}", 8, 1, "unknown assignment target 'x'");
	register_error ("assignment-rhs-unknown", "int f(){int x = 1; x = missing; return x;}", 23, 7, "unknown name 'missing'");
	register_error ("local-errors-after-return", "int f(){return 1; int x = x; return x;}", 26, 1, "unknown name 'x'");
}
}
