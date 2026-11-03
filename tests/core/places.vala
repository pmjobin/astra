// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.Core {
private void local_storage_identity() {
	var checked_program = check_ok ("int f(int x) { int a = x; int b = a + 1; b = b * 2; return b; } int g() { int a = 1; return a; }");
	string before = SemanticDump.format (checked_program);
	var program = build_checked (checked_program);
	var function = program.functions[0];
	assert (function.locals.length == 2 && function.body.statements.length == 4);
	for (int i = 0; i < 2; i++) {
		var place = function.locals[i];
		var symbol = checked_program.functions[0].locals[i];
		assert ((Object) place != (Object) symbol && !((Object) place is CoreValue));
		assert (place.ordinal == i && place.name == symbol.name && place.semantic_type == symbol.semantic_type);
		assert (place.span.text () == symbol.span.text () && place.name_span.start == symbol.name_span.start);
		assert (((CoreInitialize) function.body.statements[i]).target == place);
	}
	var first = (CoreInitialize) function.body.statements[0];
	assert (((CoreParameterValue) first.value).parameter == function.parameters[0]);
	var second = (CoreInitialize) function.body.statements[1];
	assert (((CoreLoadValue) ((CoreBinaryValue) second.value).left).source == function.locals[0]);
	var store = (CoreStore) function.body.statements[2];
	assert (store.target == function.locals[1] && store.value.semantic_type == store.target.semantic_type);
	assert (((CoreLoadValue) ((CoreBinaryValue) store.value).left).source == store.target);
	var load = (CoreLoadValue) returned_value (function, 3);
	assert (load.source == store.target && load.semantic_type == load.source.semantic_type);
	assert (program.functions[1].locals[0] != function.locals[0] && program.functions[1].locals[0].ordinal == 0);
	var rebuilt = build_checked (checked_program);
	assert (rebuilt.functions[0].locals[0] != function.locals[0]);
	assert (dump_ok (rebuilt) == dump_ok (program));
	assert (SemanticDump.format (checked_program) == before);
}

private void local_binding_over_spelling() {
	var checked_program = check_ok ("int f() { int a = 1; int b = 2; b = b + 1; return b; }");
	var function = checked_program.functions[0];
	var first = (CheckedLocalDeclaration) function.body.statements[0];
	var second = (CheckedLocalDeclaration) function.body.statements[1];
	// Exchange declaration provenance, retaining exact declaration authority.
	function.body.statements[0] = new CheckedLocalDeclaration (second.span, first.local, first.initializer);
	function.body.statements[1] = new CheckedLocalDeclaration (first.span, second.local, second.initializer);
	var assignment = (CheckedAssignment) function.body.statements[2];
	function.body.statements[2] = new CheckedAssignment (assignment.span, first.local, new CheckedLocalReferenceExpression (assignment.expression.span, first.local));
	var returned = (CheckedReturnStatement) function.body.statements[3];
	function.body.statements[3] = new CheckedReturnStatement (returned.span, new CheckedLocalReferenceExpression (returned.expression.span, first.local));
	var core = build_checked (checked_program).functions[0];
	assert (((CoreInitialize) core.body.statements[0]).target == core.locals[0]);
	assert (core.body.statements[0].span.text () == "int b = 2;");
	assert (((CoreInitialize) core.body.statements[1]).target == core.locals[1]);
	var store = (CoreStore) core.body.statements[2];
	assert (store.span.text () == "b = b + 1;" && store.target == core.locals[0]);
	assert (((CoreLoadValue) store.value).source == core.locals[0]);
	var load = (CoreLoadValue) returned_value (core, 3);
	assert (load.span.text () == "b" && load.source == core.locals[0]);
}

private void local_lifetime() {
	string digits = string.nfill (993, '0') + "2147483647";
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("local-lifetime.astra", "int f(int x) { int y = " + digits + "; y = y + x; return y; }"));
	assert (parsed.diagnostic == null);
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	assert (SyntaxDump.format (parsed.unit).contains (digits));
	assert (SemanticDump.format (checked_result.program).contains ("(integer 2147483647 : int)"));
	var syntax_ref = WeakRef (parsed.unit);
	var token_ref = WeakRef (((LocalDeclarationSyntax) parsed.unit.functions[0].body.statements[0]).name);
	var checked_ref = WeakRef (checked_result.program);
	var symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
	var parameter_ref = WeakRef (checked_result.program.functions[0].symbol.parameters[0]);
	var local_ref = WeakRef (checked_result.program.functions[0].locals[0]);
	var declaration_ref = WeakRef (checked_result.program.functions[0].body.statements[0]);
	var assignment_ref = WeakRef (checked_result.program.functions[0].body.statements[1]);
	var value_ref = WeakRef (((CheckedReturnStatement) checked_result.program.functions[0].body.statements[2]).expression);
	var types_ref = WeakRef (checked_result.program.types);
	var type_ref = WeakRef (checked_result.program.types.int_type);
	var source_ref = WeakRef (parsed.unit.span.file);
	CoreProgram? core = build_checked (checked_result.program);
	parsed = null;
	checked_result = null;
	assert (syntax_ref.get () == null && token_ref.get () == null && checked_ref.get () == null);
	assert (symbol_ref.get () == null && parameter_ref.get () == null && local_ref.get () == null);
	assert (declaration_ref.get () == null && assignment_ref.get () == null && value_ref.get () == null && types_ref.get () == null);
	verify_ok (core);
	assert (dump_ok (core).contains ("(integer 2147483647 : int)"));
	{
		var function = core.functions[0];
		var place = function.locals[0];
		var initialization = (CoreInitialize) function.body.statements[0];
		var integer = (CoreIntegerValue) initialization.value;
		assert (integer.value.signed_value == AstraIntValue.MAX);
		assert (initialization.target == place && integer.span.text () == digits && integer.span.text ().length == 1003);
		assert (place.name == "y" && place.name_span.text () == "y" && place.span.text () == "int y = " + digits + ";");
		var store = (CoreStore) function.body.statements[1];
		assert (store.target == place && ((CoreLoadValue) ((CoreBinaryValue) store.value).left).source == place);
		assert (((CoreParameterValue) ((CoreBinaryValue) store.value).right).parameter == function.parameters[0]);
		assert (((CoreLoadValue) returned_value (function, 2)).source == place);
		int line;
		int column;
		integer.span.file.locate (integer.span.start, out line, out column);
		assert (line == 1 && column == 24 && integer.span.start == 23 && integer.span.end - integer.span.start == 1003);
		assert (integer.span.file.path == "local-lifetime.astra");
	}
	core = null;
	assert (source_ref.get () == null && type_ref.get () == null);
}

private void register_place_core_tests() {
	Test.add_func ("/core/places/identity-and-types", local_storage_identity);
	Test.add_func ("/core/places/binding-over-spelling", local_binding_over_spelling);
	Test.add_func ("/core/places/lifetime-and-scalar-value", local_lifetime);
	add_case ("/core/places/builder/ordinal", () => {
			var program = check_ok ("void f(){int x = 1;}");
			var local = program.functions[0].locals[0];
			program.functions[0].locals[0] = new LocalSymbol (local.span, local.name_span, local.semantic_type, 1, local.lexical_region);
			expect_build_error (program, "inconsistent local declaration at function #0/local #0");
		});
	add_case ("/core/places/builder/repeated-local", () => {
			var program = check_ok ("void f(){int x = 1;}");
			program.functions[0].locals.add (program.functions[0].locals[0]);
			expect_build_error (program, "inconsistent local declaration at function #0/local #1");
		});
	add_case ("/core/places/builder/shared-local", () => {
			var program = check_ok ("void f(){int x = 1;} void g(){int x = 2;}");
			program.functions[1].locals[0] = program.functions[0].locals[0];
			expect_build_error (program, "inconsistent local declaration at function #1/local #0");
		});
	for (int kind = 0; kind < 3; kind++) {
		int operation = kind;
		for (int owner = 0; owner < 2; owner++) {
			bool foreign = owner == 1;
			add_case ("/core/places/builder/%d/%d".printf (kind, owner), () => {
					var program = check_ok ("int f(){int x = 1; x = 2; return x;} int g(){int x = 1; return x;}");
					var function = program.functions[0];
					var local = function.locals[0];
					var target = foreign ? program.functions[1].locals[0] : new LocalSymbol (local.span, local.name_span, local.semantic_type, local.ordinal, local.lexical_region);
					if (operation == 0) {
						function.body.statements[2] = new CheckedReturnStatement (function.span, new CheckedLocalReferenceExpression (local.name_span, target));
					} else if (operation == 1) {
						function.body.statements[0] = new CheckedLocalDeclaration (function.span, target, ((CheckedLocalDeclaration) function.body.statements[0]).initializer);
					} else {
						function.body.statements[1] = new CheckedAssignment (function.span, target, ((CheckedAssignment) function.body.statements[1]).expression);
					}
					expect_build_error (program, "local reference has no declaration in the containing function");
				});
		}
		add_case ("/core/places/verifier/foreign-%d".printf (kind), () => {
				var program = build_ok ("int f(){int x = 1; x = 2; return x;} int g(){int x = 1; return x;}");
				var function = program.functions[0];
				var foreign = program.functions[1].locals[0];
				string path;
				if (operation == 0) {
					function.body.statements[2] = new CoreReturn (function.span, new CoreLoadValue (function.span, foreign));
					path = "function #0/statement #2/value/source";
				} else if (operation == 1) {
					function.body.statements[0] = new CoreInitialize (function.span, foreign, ((CoreInitialize) function.body.statements[0]).value);
					path = "function #0/statement #0/target";
				} else {
					function.body.statements[1] = new CoreStore (function.span, foreign, ((CoreStore) function.body.statements[1]).value);
					path = "function #0/statement #1/target";
				}
				expect_invalid (program, path, "local place is not owned by the containing function");
			});
	}
	add_case ("/core/places/verifier/missing-initialization", () => {
			var program = build_ok ("void f(){int x = 1;}");
			program.functions[0].body.statements.remove_index (0);
			expect_invalid (program, "function #0/local #0", "local must have exactly one initialization");
		});
	add_case ("/core/places/verifier/repeated-initialization", () => {
			var program = build_ok ("void f(){int x = 1; return;}");
			var statements = program.functions[0].body.statements;
			statements.add (statements[0]);
			expect_invalid (program, "function #0/statement #2", "local must have exactly one initialization");
		});
	add_case ("/core/places/verifier/load-before-initialization", () => {
			var program = build_ok ("int f(){int x = 1; return x;}");
			var statements = program.functions[0].body.statements;
			var initialization = statements[0];
			statements[0] = statements[1];
			statements[1] = initialization;
			expect_invalid (program, "function #0/statement #0/value/source", "local place is used before initialization in structured statement order");
		});
	add_case ("/core/places/verifier/store-before-initialization", () => {
			var program = build_ok ("void f(){int x = 1; x = 2;}");
			var statements = program.functions[0].body.statements;
			var initialization = statements[0];
			statements[0] = statements[1];
			statements[1] = initialization;
			expect_invalid (program, "function #0/statement #0/target", "local place is used before initialization in structured statement order");
		});
	add_case ("/core/places/verifier/self-initialization", () => {
			var program = build_ok ("void f(){int x = 1;}");
			var function = program.functions[0];
			function.body.statements[0] = new CoreInitialize (function.span, function.locals[0], new CoreLoadValue (function.span, function.locals[0]));
			expect_invalid (program, "function #0/statement #0/value/source", "local place is used before initialization in structured statement order");
		});
	add_case ("/core/places/verifier/unowned-local", () => {
			var program = build_ok ("void f(){int x = 1;}");
			program.functions[0].locals.remove_index (0);
			expect_invalid (program, "function #0/statement #0/target", "local place is not owned by the containing function");
		});
	add_case ("/core/places/verifier/shared-local", () => {
			var program = build_ok ("void f(){int x = 1;} void g(){int x = 2;}");
			program.functions[1].locals[0] = program.functions[0].locals[0];
			expect_invalid (program, "function #1/local #0", "local identity occurs in more than one declaration slot");
		});
	add_case ("/core/places/verifier/repeated-local", () => {
			var program = build_ok ("void f(){int x = 1;}");
			program.functions[0].locals.add (program.functions[0].locals[0]);
			expect_invalid (program, "function #0/local #1", "local identity occurs in more than one declaration slot");
		});
	add_case ("/core/places/verifier/ordinal", () => {
			var program = build_ok ("void f(){int x = 1;}");
			var place = program.functions[0].locals[0];
			program.functions[0].locals[0] = new CoreLocalPlace (place.span, place.name_span, place.name, place.semantic_type, 1);
			expect_invalid (program, "function #0/local #0", "expected ordinal 0, found 1");
		});
	for (int kind = 0; kind < 3; kind++) {
		int invalid_type = kind;
		add_case ("/core/places/verifier/local-type-%d".printf (kind), () => {
				var program = build_ok ("int f(){int x = 1; return x;}");
				var place = program.functions[0].locals[0];
				var type = new SemanticType (invalid_type == 0 ? TypeKind.VOID : invalid_type == 1 ? TypeKind.INT : (TypeKind) 99);
				program.functions[0].locals[0] = new CoreLocalPlace (place.span, place.name_span, place.name, type, 0);
				string message = invalid_type == 0 ? "value or parameter type must be 'int', 'bool' or 'void*', found 'void'" : invalid_type == 1 ? "inconsistent 'int' semantic type identity" : "unsupported semantic type";
				expect_invalid (program, "function #0/local #0", message);
			});
	}
	for (int kind = 0; kind < 2; kind++) {
		int operation = kind;
		add_case ("/core/places/verifier/write-type-%d".printf (kind), () => {
				var program = build_ok ("void f(){int x = 1; x = 2;}");
				var function = program.functions[0];
				var bad = new CoreIntegerValue (function.span, function.return_type, AstraIntValue.from_int64 (7));
				function.body.statements[operation] = operation == 0 ? (CoreStatement) new CoreInitialize (function.span, function.locals[0], bad) : new CoreStore (function.span, function.locals[0], bad);
				expect_invalid (program, "function #0/statement #%d/value".printf (operation), "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
			});
	}
}

}
