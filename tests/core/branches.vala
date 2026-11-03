// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.Core {
private void conditional_places() {
	var checked_program = check_ok ("int choose(bool condition,int a,int b){int x = 0;if(condition){x = a;}else{x = b;}return x;}");
	var program = build_checked (checked_program);
	var function = program.functions[0];
	assert (function.locals.length == 1 && function.body.statements.length == 3);
	var local = function.locals[0];
	var conditional = (CoreIf) function.body.statements[1];
	assert ((Object) conditional != (Object) checked_program.functions[0].body.statements[1]);
	assert (((CoreParameterValue) conditional.condition).parameter == function.parameters[0]);
	assert (conditional.condition.semantic_type == checked_program.types.bool_type);
	assert (((CoreStore) conditional.then_block.statements[0]).target == local);
	assert (((CoreStore) conditional.else_block.statements[0]).target == local);
	assert (((CoreLoadValue) returned_value (function, 2)).source == local);
	assert (conditional.span.text () == "if(condition){x = a;}else{x = b;}");
	assert (conditional.then_block.span.text () == "{x = a;}" && conditional.else_block.span.text () == "{x = b;}");
	assert (dump_ok (program) == dump_ok (build_checked (checked_program)));
	var sibling = build_ok ("void f(bool c){if(c){int x = 1;}else{int x = 2;}}").functions[0];
	var branch = (CoreIf) sibling.body.statements[0];
	assert (sibling.locals.length == 2 && sibling.locals[0] != sibling.locals[1]);
	assert (sibling.locals[0].name == "x" && sibling.locals[1].name == "x");
	assert (((CoreInitialize) branch.then_block.statements[0]).target == sibling.locals[0]);
	assert (((CoreInitialize) branch.else_block.statements[0]).target == sibling.locals[1]);
	var nested = build_ok ("void f(bool c){if(c){if(!c){}}}").functions[0];
	var outer = (CoreIf) nested.body.statements[0];
	assert (outer.else_block == null && outer.then_block.statements[0] is CoreIf);
}

private void boolean_storage() {
	var program = build_ok ("bool f(bool x){bool y = false;y = x;return y;}");
	var function = program.functions[0];
	var local = function.locals[0];
	var initialization = (CoreInitialize) function.body.statements[0];
	assert (local.semantic_type == function.return_type && local.semantic_type.kind == TypeKind.BOOL);
	assert (initialization.target == local && ((CoreBooleanValue) initialization.value).literal == BooleanLiteral.FALSE);
	assert (((CoreStore) function.body.statements[1]).target == local);
	assert (((CoreLoadValue) returned_value (function, 2)).source == local);
	assert (dump_ok (program).contains ("(bool false : bool)"));
}

private void conditional_lifetime() {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("branch-lifetime.astra", "bool f(int a,bool c){bool x = false;if(a < 2 == c){bool y = !c;x = y;}else{bool y = true;x = y;}return x;}"));
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	var syntax_ref = WeakRef (parsed.unit);
	var token_ref = WeakRef (((IfStatementSyntax) parsed.unit.functions[0].body.statements[1]).keyword);
	var checked_ref = WeakRef (checked_result.program);
	var conditional_ref = WeakRef (checked_result.program.functions[0].body.statements[1]);
	var symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
	var local_ref = WeakRef (checked_result.program.functions[0].locals[1]);
	var sibling_ref = WeakRef (checked_result.program.functions[0].locals[2]);
	var types_ref = WeakRef (checked_result.program.types);
	var bool_ref = WeakRef (checked_result.program.types.bool_type);
	var source_ref = WeakRef (parsed.unit.span.file);
	CoreProgram? core = build_checked (checked_result.program);
	parsed = null;
	checked_result = null;
	assert (syntax_ref.get () == null && token_ref.get () == null && checked_ref.get () == null && conditional_ref.get () == null);
	assert (symbol_ref.get () == null && local_ref.get () == null && sibling_ref.get () == null && types_ref.get () == null);
	verify_ok (core);
	assert (bool_ref.get () == core.functions[0].return_type);
	assert (dump_ok (core).contains ("(binary == : bool") && dump_ok (core).contains ("(bool true : bool)"));
	{
		var function = core.functions[0];
		var conditional = (CoreIf) function.body.statements[1];
		assert (((CoreBinaryValue) conditional.condition).operator_kind == BinaryOperator.EQUAL);
		assert (((CoreBinaryValue) ((CoreBinaryValue) conditional.condition).left).operator_kind == BinaryOperator.LESS);
		assert (((CoreInitialize) conditional.then_block.statements[0]).target == function.locals[1]);
		assert (((CoreInitialize) conditional.else_block.statements[0]).target == function.locals[2]);
		assert (((CoreStore) conditional.then_block.statements[1]).target == function.locals[0]);
		assert (((CoreStore) conditional.else_block.statements[1]).target == function.locals[0]);
		assert (conditional.span.file.path == "branch-lifetime.astra" && function.locals[1].span.text () == "bool y = !c;");
	}
	core = null;
	assert (source_ref.get () == null && bool_ref.get () == null);
}

private void register_branch_core_tests() {
	Test.add_func ("/core/branch/structured-places", conditional_places);
	Test.add_func ("/core/branch/bool-storage", boolean_storage);
	Test.add_func ("/core/branch/lifetime", conditional_lifetime);
	register_branch_operator_tests ();
	for (int i = 0; i < 2; i++) {
		int operation = i;
		add_case ("/core/branch/verifier/write-type-%d".printf (operation), () => {
				var program = build_ok ("void f(bool c){bool x = false;if(c){x = true;}}int g(){return 1;}");
				var function = program.functions[0];
				var value = new CoreIntegerValue (function.span, program.functions[1].return_type, AstraIntValue.from_int64 (7));
				string path;
				if (operation == 0) {
					function.body.statements[0] = new CoreInitialize (function.span, function.locals[0], value);
					path = "function #0/statement #0";
				} else {
					((CoreIf) function.body.statements[1]).then_block.statements[0] = new CoreStore (function.span, function.locals[0], value);
					path = "function #0/statement #1/then/statement #0";
				}
				expect_invalid (program, path, operation == 0 ? "initializer value type does not match target place type" : "stored value type does not match target place type");
			});
	}

	add_case ("/core/branch/verifier/condition", () => {
			var program = build_ok ("void f(){if(true){}}");
			var function = program.functions[0];
			var conditional = (CoreIf) function.body.statements[0];
			function.body.statements[0] = new CoreIf (conditional.span, new CoreIntegerValue (conditional.span, new IntegerType (TypeKind.INT), AstraIntValue.from_int64 (7)), conditional.then_block, null);
			expect_invalid (program, "function #0/statement #0/condition", "if condition must have type 'bool'");
		});
	add_case ("/core/branch/verifier/escape", () => {
			var program = build_ok ("int f(bool c){if(c){int x = 1;}return 0;}");
			var function = program.functions[0];
			function.body.statements[1] = new CoreReturn (function.span, new CoreLoadValue (function.span, function.locals[0]));
			expect_invalid (program, "function #0/statement #1/value/source", "local place is used before initialization in structured statement order");
		});
	add_case ("/core/branch/verifier/sibling-load", () => {
			var program = build_ok ("int f(bool c){if(c){int x = 1;}else{return 2;}return 0;}");
			var function = program.functions[0];
			var conditional = (CoreIf) function.body.statements[0];
			conditional.else_block.statements[0] = new CoreReturn (function.span, new CoreLoadValue (function.span, function.locals[0]));
			expect_invalid (program, "function #0/statement #0/else/statement #0/value/source", "local place is used before initialization in structured statement order");
		});
	add_case ("/core/branch/verifier/foreign-place", () => {
			var program = build_ok ("void f(bool c){int x = 1;if(c){x = 2;}}void g(){int x = 3;}");
			var conditional = (CoreIf) program.functions[0].body.statements[1];
			var store = (CoreStore) conditional.then_block.statements[0];
			conditional.then_block.statements[0] = new CoreStore (store.span, program.functions[1].locals[0], store.value);
			expect_invalid (program, "function #0/statement #1/then/statement #0/target", "local place is not owned by the containing function");
		});
	add_case ("/core/branch/verifier/shared-block", () => {
			var program = build_ok ("void f(){if(true){}else{}}");
			var conditional = (CoreIf) program.functions[0].body.statements[0];
			program.functions[0].body.statements[0] = new CoreIf (conditional.span, conditional.condition, conditional.then_block, conditional.then_block);
			expect_invalid (program, "function #0/statement #0/else", "block identity occurs more than once in structured Core");
		});
}

}
