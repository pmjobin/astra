// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.Cfg {
private void local_storage_identity() {
	var core = build_core (check_ok ("int f(int x) { int a = x; int b = a + 1; b = b * 2; return b; } int g() { int a = 1; return a; }"));
	var program = build_from_core (core);
	var function = program.functions[0];
	assert (function.locals.length == 2 && function.blocks.length == 1);
	assert (function.entry.instructions.length == 3 && function.entry.terminator is CfgReturn);
	for (int i = 0; i < 2; i++) {
		var place = function.locals[i];
		var original = core.functions[0].locals[i];
		assert ((Object) place != (Object) original && !((Object) place is CfgValue));
		assert (place.name == original.name && place.ordinal == i && place.semantic_type == original.semantic_type);
		assert (place.span.text () == original.span.text () && place.name_span.start == original.name_span.start);
		assert (((CfgInitialize) function.entry.instructions[i]).target == place);
	}
	var first = (CfgInitialize) function.entry.instructions[0];
	assert (((CfgParameterValue) first.value).parameter == function.parameters[0]);
	var second = (CfgInitialize) function.entry.instructions[1];
	assert (((CfgLoadValue) ((CfgBinaryValue) second.value).left).source == function.locals[0]);
	var store = (CfgStore) function.entry.instructions[2];
	assert (store.target == function.locals[1] && store.value.semantic_type == store.target.semantic_type);
	assert (((CfgLoadValue) ((CfgBinaryValue) store.value).left).source == store.target);
	var load = (CfgLoadValue) returned_value (function);
	assert (load.source == store.target && load.semantic_type == load.source.semantic_type);
	assert (program.functions[1].locals[0] != function.locals[0] && program.functions[1].locals[0].ordinal == 0);
	var rebuilt = build_from_core (core);
	assert (rebuilt.functions[0].locals[0] != function.locals[0] && dump_ok (rebuilt) == dump_ok (program));
	assert (function.entry.terminator.successors ().length == 0 && flow_result (program).diagnostic == null);
	assert (function.entry.span.text () == "int a = x; int b = a + 1; b = b * 2; return b;");
}

private void local_binding_over_spelling() {
	var core = build_core (check_ok ("int f(){int a = 1; int b = 2; b = b + 1; return b;}"));
	var function = core.functions[0];
	var first = (CoreInitialize) function.body.statements[0];
	var second = (CoreInitialize) function.body.statements[1];
	function.body.statements[0] = new CoreInitialize (second.span, first.target, first.value);
	function.body.statements[1] = new CoreInitialize (first.span, second.target, second.value);
	var old_store = (CoreStore) function.body.statements[2];
	function.body.statements[2] = new CoreStore (old_store.span, first.target, new CoreLoadValue (old_store.value.span, first.target));
	var returned = (CoreReturn) function.body.statements[3];
	function.body.statements[3] = new CoreReturn (returned.span, new CoreLoadValue (returned.value.span, first.target));
	var cfg = build_from_core (core).functions[0];
	assert (((CfgInitialize) cfg.entry.instructions[0]).target == cfg.locals[0]);
	assert (cfg.entry.instructions[0].span.text () == "int b = 2;");
	assert (((CfgInitialize) cfg.entry.instructions[1]).target == cfg.locals[1]);
	var store = (CfgStore) cfg.entry.instructions[2];
	assert (store.span.text () == "b = b + 1;" && store.target == cfg.locals[0]);
	assert (((CfgLoadValue) store.value).source == cfg.locals[0]);
	var load = (CfgLoadValue) returned_value (cfg);
	assert (load.span.text () == "b" && load.source == cfg.locals[0]);
}

private void post_return_storage() {
	var core = build_core (check_ok ("int f(){int x = 1; return x; x = 2; return x;}"));
	var statements = core.functions[0].body.statements;
	assert (statements.length == 4 && statements[0] is CoreInitialize && statements[1] is CoreReturn && statements[2] is CoreStore && statements[3] is CoreReturn);
	var cfg = build_from_core (core);
	var function = cfg.functions[0];
	assert (function.blocks.length == 2);
	var reachable = CfgReachability.analyze (function);
	for (int i = 0; i < 2; i++) {
		var block = function.blocks[i];
		assert (block.instructions.length == 1 && block.terminator is CfgReturn);
		assert (block.terminator.successors ().length == 0 && reachable.is_reachable (block) == (i == 0));
		assert (((CfgLoadValue) returned_value (function, i)).source == function.locals[0]);
	}
	assert (((CfgInitialize) function.entry.instructions[0]).target == function.locals[0]);
	var store = (CfgStore) function.blocks[1].instructions[0];
	assert (store.target == function.locals[0] && ((CfgIntegerValue) store.value).span.text () == "2");
	assert (flow_result (cfg).diagnostic == null);
	assert (dump_ok (cfg).contains ("(block #1 unreachable\n\t\t\t(store"));
}

private void storage_function_end() {
	var cfg = build_ok ("void f(){int x = 1; x = 2;} int g(){return 1; int x = 2; x = x + 1;}");
	assert (cfg.functions[0].blocks.length == 1 && cfg.functions[0].entry.instructions.length == 2);
	assert (cfg.functions[0].entry.terminator is CfgFunctionEnd);
	assert (cfg.functions[1].blocks.length == 2 && cfg.functions[1].entry.instructions.length == 0);
	assert (cfg.functions[1].blocks[1].instructions.length == 2 && cfg.functions[1].blocks[1].terminator is CfgFunctionEnd);
	assert (!CfgReachability.analyze (cfg.functions[1]).is_reachable (cfg.functions[1].blocks[1]));
	assert (flow_result (cfg).diagnostic == null);
	var invalid = build_ok ("int f(){int x = 1; x = 2;}");
	assert (invalid.functions[0].entry.terminator is CfgFunctionEnd);
	assert (flow_result (invalid).diagnostic.message == "not all paths in function 'f' return a value");
}

private void local_lifetime() {
	string digits = string.nfill (993, '0') + "2147483647";
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("local-lifetime.astra", "int f(int x) { int y = " + digits + "; y = y + x; return y; }"));
	assert (parsed.diagnostic == null);
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	assert (((IntegerLiteralExpressionSyntax) ((LocalDeclarationSyntax) parsed.unit.functions[0].body.statements[0]).initializer).literal.spelling () == digits);
	assert (((CheckedIntegerExpression) ((CheckedLocalDeclaration) checked_result.program.functions[0].body.statements[0]).initializer).span.text () == digits);
	assert (SyntaxDump.format (parsed.unit).contains (digits) && SemanticDump.format (checked_result.program).contains ("(integer 2147483647 : int)"));
	var syntax_ref = WeakRef (parsed.unit);
	var token_ref = WeakRef (((LocalDeclarationSyntax) parsed.unit.functions[0].body.statements[0]).name);
	var checked_ref = WeakRef (checked_result.program);
	var symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
	var semantic_parameter_ref = WeakRef (checked_result.program.functions[0].symbol.parameters[0]);
	var semantic_local_ref = WeakRef (checked_result.program.functions[0].locals[0]);
	var checked_declaration_ref = WeakRef (checked_result.program.functions[0].body.statements[0]);
	var checked_assignment_ref = WeakRef (checked_result.program.functions[0].body.statements[1]);
	var checked_load_ref = WeakRef (((CheckedReturnStatement) checked_result.program.functions[0].body.statements[2]).expression);
	var types_ref = WeakRef (checked_result.program.types);
	var type_ref = WeakRef (checked_result.program.types.int_type);
	var source_ref = WeakRef (parsed.unit.span.file);
	CoreProgram? core = build_core (checked_result.program);
	var core_ref = WeakRef (core);
	var function_ref = WeakRef (core.functions[0]);
	var parameter_ref = WeakRef (core.functions[0].parameters[0]);
	var local_ref = WeakRef (core.functions[0].locals[0]);
	var initialization_ref = WeakRef (core.functions[0].body.statements[0]);
	var store_ref = WeakRef (core.functions[0].body.statements[1]);
	var load_ref = WeakRef (((CoreReturn) core.functions[0].body.statements[2]).value);
	CfgProgram? cfg = build_from_core (core);
	parsed = null;
	checked_result = null;
	core = null;
	assert (syntax_ref.get () == null && token_ref.get () == null && checked_ref.get () == null && symbol_ref.get () == null);
	assert (semantic_parameter_ref.get () == null && semantic_local_ref.get () == null && types_ref.get () == null);
	assert (checked_declaration_ref.get () == null && checked_assignment_ref.get () == null && checked_load_ref.get () == null);
	assert (core_ref.get () == null && function_ref.get () == null && parameter_ref.get () == null && local_ref.get () == null);
	assert (initialization_ref.get () == null && store_ref.get () == null && load_ref.get () == null);
	verify_ok (cfg);
	assert (CfgReachability.analyze (cfg.functions[0]).is_reachable (cfg.functions[0].entry));
	assert (flow_result (cfg).diagnostic == null && dump_ok (cfg).contains ("(integer 2147483647 : int)"));
	{
		var function = cfg.functions[0];
		var place = function.locals[0];
		var initialization = (CfgInitialize) function.entry.instructions[0];
		var integer = (CfgIntegerValue) initialization.value;
		assert (integer.value.signed_value == AstraIntValue.MAX);
		assert (initialization.target == place && integer.span.text () == digits && integer.span.text ().length == 1003);
		assert (place.name == "y" && place.name_span.text () == "y" && place.span.text () == "int y = " + digits + ";");
		var store = (CfgStore) function.entry.instructions[1];
		assert (store.target == place && ((CfgLoadValue) ((CfgBinaryValue) store.value).left).source == place);
		assert (((CfgParameterValue) ((CfgBinaryValue) store.value).right).parameter == function.parameters[0]);
		assert (((CfgLoadValue) returned_value (function)).source == place);
		int line;
		int column;
		integer.span.file.locate (integer.span.start, out line, out column);
		assert (line == 1 && column == 24 && integer.span.start == 23 && integer.span.end - integer.span.start == 1003);
		assert (integer.span.file.path == "local-lifetime.astra");
	}
	cfg = null;
	assert (source_ref.get () == null && type_ref.get () == null);
}

private void register_place_cfg_tests() {
	Test.add_func ("/cfg/places/identity-and-types", local_storage_identity);
	Test.add_func ("/cfg/places/binding-over-spelling", local_binding_over_spelling);
	Test.add_func ("/cfg/places/post-return", post_return_storage);
	Test.add_func ("/cfg/places/function-end", storage_function_end);
	Test.add_func ("/cfg/places/lifetime-and-scalar-value", local_lifetime);
	add_case ("/cfg/places/builder/foreign-core-local", () => {
			var core = build_core (check_ok ("int f(){int x = 1; return x;} int g(){int x = 2; return x;}"));
			core.functions[0].body.statements[1] = new CoreReturn (core.span, new CoreLoadValue (core.span, core.functions[1].locals[0]));
			for (int i = 0; i < 2; i++) {
				try {
					CfgBuilder.build (core);
				} catch (CfgError error) {
					assert (error is CfgError.INVALID_CORE);
					assert (error.message == "internal CFG construction error: internal Core verification error at function #0/statement #1/value/source: local place is not owned by the containing function");
					continue;
				}
				GLib.error ("Malformed Core local reached CFG construction");
			}
		});
	for (int kind = 0; kind < 3; kind++) {
		int operation = kind;
		for (int owner = 0; owner < 2; owner++) {
			bool foreign = owner == 1;
			add_case ("/cfg/places/verifier/foreign-%d/%d".printf (kind, owner), () => {
					var program = build_ok ("int f(){int x = 1; x = 2; return x;} int g(){int x = 1; return x;}");
					var function = program.functions[0];
					var place = function.locals[0];
					var target = foreign ? program.functions[1].locals[0] : new CfgLocalPlace (place.span, place.name_span, place.name, place.semantic_type, place.ordinal);
					string path;
					if (operation == 0) {
						replace_terminator (program, 0, 0, new CfgReturn (function.span, new CfgLoadValue (function.span, target)));
						path = "function #0/block #0/terminator/value/source";
					} else if (operation == 1) {
						function.entry.instructions[0] = new CfgInitialize (function.span, target, ((CfgInitialize) function.entry.instructions[0]).value);
						path = "function #0/block #0/instruction #0/target";
					} else {
						function.entry.instructions[1] = new CfgStore (function.span, target, ((CfgStore) function.entry.instructions[1]).value);
						path = "function #0/block #0/instruction #1/target";
					}
					expect_invalid (program, path, "local place is not owned by the containing function");
				});
		}
	}
	add_case ("/cfg/places/verifier/missing-initialization", () => {
			var program = build_ok ("int f(){int x = 1; return x;}");
			program.functions[0].entry.instructions.remove_index (0);
			expect_invalid (program, "function #0/local #0", "local must have exactly one initialization");
		});
	add_case ("/cfg/places/verifier/repeated-initialization", () => {
			var program = build_ok ("void f(){int x = 1; return; return;}");
			program.functions[0].blocks[1].instructions.add (program.functions[0].entry.instructions[0]);
			expect_invalid (program, "function #0/block #1/instruction #0", "local must have exactly one initialization");
		});
	add_case ("/cfg/places/verifier/unowned-local", () => {
			var program = build_ok ("void f(){int x = 1;}");
			program.functions[0].locals.remove_index (0);
			expect_invalid (program, "function #0/block #0/instruction #0/target", "local place is not owned by the containing function");
		});
	add_case ("/cfg/places/verifier/shared-local", () => {
			var program = build_ok ("void f(){int x = 1;} void g(){int x = 2;}");
			program.functions[1].locals[0] = program.functions[0].locals[0];
			expect_invalid (program, "function #1/local #0", "local identity occurs in more than one declaration slot");
		});
	add_case ("/cfg/places/verifier/repeated-local", () => {
			var program = build_ok ("void f(){int x = 1;}");
			program.functions[0].locals.add (program.functions[0].locals[0]);
			expect_invalid (program, "function #0/local #1", "local identity occurs in more than one declaration slot");
		});
	add_case ("/cfg/places/verifier/ordinal", () => {
			var program = build_ok ("void f(){int x = 1;}");
			var place = program.functions[0].locals[0];
			program.functions[0].locals[0] = new CfgLocalPlace (place.span, place.name_span, place.name, place.semantic_type, 1);
			expect_invalid (program, "function #0/local #0", "expected ordinal 0, found 1");
		});
	for (int kind = 0; kind < 3; kind++) {
		int invalid_type = kind;
		add_case ("/cfg/places/verifier/local-type-%d".printf (kind), () => {
				var program = build_ok ("int f(){int x = 1; return x;}");
				var place = program.functions[0].locals[0];
				var type = new SemanticType (invalid_type == 0 ? TypeKind.VOID : invalid_type == 1 ? TypeKind.INT : (TypeKind) 99);
				program.functions[0].locals[0] = new CfgLocalPlace (place.span, place.name_span, place.name, type, 0);
				string message = invalid_type == 0 ? "value or parameter type must be 'int', 'bool' or 'void*', found 'void'" : invalid_type == 1 ? "inconsistent 'int' semantic type identity" : "unsupported semantic type";
				expect_invalid (program, "function #0/local #0", message);
			});
	}
	for (int kind = 0; kind < 2; kind++) {
		int operation = kind;
		add_case ("/cfg/places/verifier/write-type-%d".printf (kind), () => {
				var program = build_ok ("void f(){int x = 1; x = 2;}");
				var function = program.functions[0];
				var bad = new CfgIntegerValue (function.span, function.return_type, AstraIntValue.from_int64 (7));
				function.entry.instructions[operation] = operation == 0 ? (CfgInstruction) new CfgInitialize (function.span, function.locals[0], bad) : new CfgStore (function.span, function.locals[0], bad);
				expect_invalid (program, "function #0/block #0/instruction #%d/value".printf (operation), "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
			});
	}
}
}
