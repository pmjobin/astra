// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.Cfg {
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

private CoreProgram build_core(CheckedProgram program) {
	try {
		var core = CoreBuilder.build (program);
		CoreVerifier.verify (core);
		return core;
	} catch (CoreError error) {
		GLib.error ("Unexpected Core failure: %s", error.message);
	}
}

private void verify_ok(CfgProgram program) {
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		GLib.error ("Unexpected CFG verification failure: %s", error.message);
	}
}

private CfgProgram build_from_core(CoreProgram core) {
	try {
		var program = CfgBuilder.build (core);
		verify_ok (program);
		return program;
	} catch (CfgError error) {
		GLib.error ("Unexpected CFG construction failure: %s", error.message);
	}
}

private CfgProgram build_ok(string text) {
	return build_from_core (build_core (check_ok (text)));
}

private string dump_ok(CfgProgram program) {
	try {
		return CfgDump.format (program);
	} catch (CfgError error) {
		GLib.error ("Unexpected CFG dump failure: %s", error.message);
	}
}

private CfgFlowResult flow_result(CfgProgram program) {
	try {
		return CfgFlowChecker.check (program);
	} catch (CfgError error) {
		GLib.error ("Unexpected CFG flow invariant failure: %s", error.message);
	}
}

private CfgValue returned_value(CfgFunction function, int index = 0) {
	assert (function.blocks[index].terminator is CfgReturn);
	var returned = (CfgReturn) function.blocks[index].terminator;
	assert (returned.value != null);
	return returned.value;
}

private CfgValue build_value(string text) {
	return returned_value (build_ok ("int f(int a, int b) { return " + text + "; }").functions[0]);
}

private void register_program(string name, string text, int count) {
	add_case ("/cfg/program/" + name, () => {
			var program = build_ok (text);
			assert (program.functions.length == count && program.span.text () == text);
			for (int i = 0; i < count; i++) {
				assert (program.functions[i].ordinal == i);
				assert (program.functions[i].entry == program.functions[i].blocks[0]);
				assert (program.functions[i].entry.ordinal == 0);
			}
		});
}

private void declarations_and_identity() {
	var checked_program = check_ok ("int z(int a, int b) { return a + b; return a; } void m() { return; } int a(int a) { return a; }");
	var core = build_core (checked_program);
	string before;
	try {
		before = CoreDump.format (core);
	} catch (CoreError error) {
		GLib.error ("Unexpected Core dump failure: %s", error.message);
	}
	var program = build_from_core (core);
	assert (program.functions.length == 3);
	assert (program.functions[0].name == "z" && program.functions[1].name == "m" && program.functions[2].name == "a");
	for (int i = 0; i < program.functions.length; i++) {
		var function = program.functions[i];
		assert ((Object) function != (Object) core.functions[i]);
		assert (function.ordinal == i && function.return_type == core.functions[i].return_type);
		assert (function.parameters.length == core.functions[i].parameters.length);
		assert (function.entry == function.blocks[0]);
		for (int j = 0; j < function.parameters.length; j++) {
			assert ((Object) function.parameters[j] != (Object) core.functions[i].parameters[j]);
			assert (function.parameters[j].name == core.functions[i].parameters[j].name);
			assert (function.parameters[j].ordinal == j);
			assert (function.parameters[j].semantic_type == checked_program.types.int_type);
		}
	}
	var first = program.functions[0];
	var sum = (CfgBinaryValue) returned_value (first);
	assert (((CfgParameterValue) sum.left).parameter == first.parameters[0]);
	assert (((CfgParameterValue) sum.right).parameter == first.parameters[1]);
	assert (((CfgParameterValue) returned_value (first, 1)).parameter == first.parameters[0]);
	assert (((CfgParameterValue) returned_value (program.functions[2])).parameter == program.functions[2].parameters[0]);
	assert (program.functions[2].parameters[0] != first.parameters[0]);
	assert (sum.left.semantic_type == first.parameters[0].semantic_type);
	var second = build_from_core (core);
	assert (second.functions[0] != first && second.functions[0].parameters[0] != first.parameters[0]);
	assert (second.functions[0].entry != first.entry);
	assert (dump_ok (second) == dump_ok (program));
	try {
		assert (CoreDump.format (core) == before);
	} catch (CoreError error) {
		GLib.error ("Core was changed by CFG construction: %s", error.message);
	}
}

private void binding_over_spelling() {
	var core = build_core (check_ok ("int f(int a, int b) { return b; }"));
	var function = core.functions[0];
	var returned = (CoreReturn) function.body.statements[0];
	function.body.statements[0] = new CoreReturn (returned.span, new CoreParameterValue (returned.value.span, function.parameters[0]));
	var cfg = build_from_core (core);
	var reference = (CfgParameterValue) returned_value (cfg.functions[0]);
	assert (reference.span.text () == "b" && reference.parameter.name == "a");
	assert (reference.parameter == cfg.functions[0].parameters[0]);
}

private void invalid_core_input() {
	var core = build_core (check_ok ("int f(int x) { return x; } int g(int x) { return x; }"));
	core.functions[0].body.statements[0] = new CoreReturn (core.span, new CoreParameterValue (core.span, core.functions[1].parameters[0]));
	for (int i = 0; i < 2; i++) {
		try {
			CfgBuilder.build (core);
		} catch (CfgError error) {
			assert (error is CfgError.INVALID_CORE);
			assert (error.message == "internal CFG construction error: internal Core verification error at function #0/statement #0/value: parameter reference is not owned by the containing function");
			continue;
		}
		GLib.error ("Malformed Core reached CFG construction");
	}
}

private void sequential_returns() {
	var core = build_core (check_ok ("void sequential() { return; return; } int sequential_value() { return 1; return 2; }"));
	var program = build_from_core (core);
	for (int i = 0; i < program.functions.length; i++) {
		var function = program.functions[i];
		assert (core.functions[i].body.statements.length == 2 && function.blocks.length == 2);
		assert (function.blocks[0] != function.blocks[1] && function.entry == function.blocks[0]);
		var reachability = CfgReachability.analyze (function);
		for (int j = 0; j < function.blocks.length; j++) {
			var block = function.blocks[j];
			assert (block.ordinal == j && block.terminator is CfgReturn);
			assert (block.terminator.span.text () == core.functions[i].body.statements[j].span.text ());
			assert (block.terminator.successors ().length == 0);
			assert (reachability.is_reachable (block) == (j == 0));
		}
	}
	assert (((CfgReturn) program.functions[0].entry.terminator).value == null);
	assert (((CfgReturn) program.functions[0].blocks[1].terminator).value == null);
	assert (((CfgIntegerValue) returned_value (program.functions[1])).span.text () == "1");
	assert (((CfgIntegerValue) returned_value (program.functions[1], 1)).span.text () == "2");
	assert (flow_result (program).diagnostic == null);
	assert (program.functions[0].blocks.length == 2 && program.functions[1].blocks.length == 2);
}

private void register_completion(string name, string text, bool explicit_return, bool valid) {
	add_case ("/cfg/flow/" + name, () => {
			var checked_program = check_ok (text);
			assert (SemanticDump.format (checked_program).contains ("(function"));
			var core = build_core (checked_program);
			var program = build_from_core (core);
			var function = program.functions[0];
			assert (function.blocks.length == 1);
			assert (CfgReachability.analyze (function).is_reachable (function.entry));
			assert ((function.entry.terminator is CfgReturn) == explicit_return);
			assert ((function.entry.terminator is CfgFunctionEnd) == !explicit_return);
			assert (function.entry.terminator.successors ().length == 0);
			for (int i = 0; i < 2; i++) {
				var result = flow_result (program);
				assert ((result.diagnostic == null) == valid);
				if (!valid) {
					assert (result.diagnostic.format () == "test.astra:1:5: error: not all paths in function 'f' return a value");
					assert (result.diagnostic.span.text () == "f");
				}
			}
			if (!explicit_return) {
				assert (function.entry.terminator.span.text () == "{}");
				assert (dump_ok (program).contains ("(function-end)"));
			}
		});
}

private void source_lifetime() {
	string digits = string.nfill (993, '0') + "2147483647";
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("retained.astra", "int f(int x) { return x + " + digits + "; }"));
	assert (parsed.diagnostic == null);
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var syntax_ref = WeakRef (parsed.unit);
	var token_ref = WeakRef (parsed.unit.functions[0].name);
	var checked_ref = WeakRef (checked_result.program);
	var checked_function_ref = WeakRef (checked_result.program.functions[0]);
	var symbol_ref = WeakRef (checked_result.program.functions[0].symbol);
	var checked_parameter_ref = WeakRef (checked_result.program.functions[0].symbol.parameters[0]);
	var checked_value_ref = WeakRef (((CheckedReturnStatement) checked_result.program.functions[0].body.statements[0]).expression);
	var types_ref = WeakRef (checked_result.program.types);
	var type_ref = WeakRef (checked_result.program.types.int_type);
	var source_ref = WeakRef (parsed.unit.span.file);
	CoreProgram? core = build_core (checked_result.program);
	var core_ref = WeakRef (core);
	var function_ref = WeakRef (core.functions[0]);
	var parameter_ref = WeakRef (core.functions[0].parameters[0]);
	var block_ref = WeakRef (core.functions[0].body);
	var return_ref = WeakRef (core.functions[0].body.statements[0]);
	var value_ref = WeakRef (((CoreReturn) core.functions[0].body.statements[0]).value);
	CfgProgram? cfg = build_from_core (core);
	parsed = null;
	checked_result = null;
	core = null;
	assert (syntax_ref.get () == null && token_ref.get () == null);
	assert (checked_ref.get () == null && checked_function_ref.get () == null && symbol_ref.get () == null);
	assert (checked_parameter_ref.get () == null && checked_value_ref.get () == null && types_ref.get () == null);
	assert (core_ref.get () == null && function_ref.get () == null && parameter_ref.get () == null);
	assert (block_ref.get () == null && return_ref.get () == null && value_ref.get () == null);
	assert (type_ref.get () == cfg.functions[0].return_type && source_ref.get () == cfg.span.file);
	verify_ok (cfg);
	assert (CfgReachability.analyze (cfg.functions[0]).is_reachable (cfg.functions[0].entry));
	assert (flow_result (cfg).diagnostic == null);
	assert (dump_ok (cfg).contains ("(integer 2147483647 : int)"));
	{
		var function = cfg.functions[0];
		assert (function.name_span.text () == "f" && function.parameters[0].span.text () == "int x");
		assert (function.parameters[0].name_span.text () == "x");
		var binary = (CfgBinaryValue) returned_value (function);
		assert (((CfgParameterValue) binary.left).parameter == function.parameters[0]);
		assert (((CfgIntegerValue) binary.right).span.text () == digits);
		assert (((CfgIntegerValue) binary.right).value.signed_value == AstraIntValue.MAX);
		assert (binary.right.span.file.path == "retained.astra");
		int line;
		int column;
		binary.right.span.file.locate (binary.right.span.start, out line, out column);
		assert (line == 1 && column == 27 && binary.right.span.start == 26 && binary.right.span.end - binary.right.span.start == 1003);
	}
	cfg = null;
	assert (type_ref.get () == null && source_ref.get () == null);
}

private void replace_terminator(CfgProgram program, int function_index, int block_index, CfgTerminator terminator) {
	var function = program.functions[function_index];
	var old = function.blocks[block_index];
	var block = new CfgBlock (old.span, old.ordinal, old.instructions, terminator);
	function.blocks[block_index] = block;
	program.functions[function_index] = new CfgFunction (function.span, function.name_span, function.name, function.return_type, function.ordinal, function.parameters, function.locals, function.blocks, function.entry == old ? block : function.entry);
}

private void expect_invalid(CfgProgram program, string path, string message) {
	string expected = "internal CFG verification error at " + path + ": " + message;
	for (int i = 0; i < 2; i++) {
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			assert (error is CfgError.INVALID_CFG);
			if (error.message != expected) {
				GLib.error ("Expected %s; got %s", expected, error.message);
			}
			continue;
		}
		GLib.error ("Malformed CFG passed verification");
	}
	try {
		CfgDump.format (program);
	} catch (CfgError error) {
		assert (error.message == expected);
		return;
	}
	GLib.error ("Malformed CFG produced a dump");
}

private void integer_spelling() {
	var ordinary = (CfgIntegerValue) build_value ("42");
	assert (ordinary.span.text () == "42" && ordinary.semantic_type.kind == TypeKind.INT);
	assert (((CfgIntegerValue) build_value ("00042")).span.text () == "00042");
	assert (((CfgIntegerValue) build_value ("((007))")).span.text () == "007");
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
	add_case ("/cfg/value/" + name, () => {
			var prefix = (CfgPrefixValue) build_value (spelling + "a");
			assert (prefix.operator_kind == operator_kind);
			assert (prefix.semantic_type.kind == TypeKind.INT);
			assert (prefix.operand.semantic_type == prefix.semantic_type);
			assert (prefix.operand is CfgParameterValue);
		});
}

private void register_binary(string name, string spelling, BinaryOperator operator_kind) {
	add_case ("/cfg/value/" + name, () => {
			var binary = (CfgBinaryValue) build_value ("a " + spelling + " b");
			assert (binary.operator_kind == operator_kind);
			assert (binary.semantic_type.kind == TypeKind.INT);
			assert (binary.left.semantic_type == binary.semantic_type && binary.right.semantic_type == binary.semantic_type);
			assert (((CfgParameterValue) binary.left).parameter.ordinal == 0);
			assert (((CfgParameterValue) binary.right).parameter.ordinal == 1);
		});
}

private void arithmetic_structure() {
	var sum = (CfgBinaryValue) build_value ("1 + 2 * 3");
	assert (sum.operator_kind == BinaryOperator.ADD);
	assert (((CfgIntegerValue) sum.left).span.text () == "1");
	var product = (CfgBinaryValue) sum.right;
	assert (product.operator_kind == BinaryOperator.MULTIPLY);
	assert (((CfgIntegerValue) product.left).span.text () == "2");
	assert (((CfgIntegerValue) product.right).span.text () == "3");
	var remainder = (CfgBinaryValue) build_value ("-(a + 2) * b % 3");
	assert (remainder.operator_kind == BinaryOperator.REMAINDER);
	assert (((CfgIntegerValue) remainder.right).span.text () == "3");
	product = (CfgBinaryValue) remainder.left;
	assert (product.operator_kind == BinaryOperator.MULTIPLY);
	assert (((CfgParameterValue) product.right).parameter.ordinal == 1);
	var negative = (CfgPrefixValue) product.left;
	assert (negative.operator_kind == PrefixOperator.NEGATIVE);
	assert (((CfgBinaryValue) negative.operand).operator_kind == BinaryOperator.ADD);
}

private void no_simplification() {
	assert (((CfgPrefixValue) build_value ("+a")).operator_kind == PrefixOperator.POSITIVE);
	var prefix = (CfgPrefixValue) build_value ("+-0007");
	assert (prefix.operator_kind == PrefixOperator.POSITIVE);
	assert (((CfgIntegerValue) prefix.operand).value.signed_value == -7);
	assert (prefix.operand.span.text () == "-0007");
	assert (((CfgBinaryValue) build_value ("a + 0")).operator_kind == BinaryOperator.ADD);
	assert (((CfgBinaryValue) build_value ("1 / 0")).operator_kind == BinaryOperator.DIVIDE);
	assert (((CfgBinaryValue) build_value ("1 % 0")).operator_kind == BinaryOperator.REMAINDER);
	var sum = (CfgBinaryValue) build_value ("8 - 3 + 1");
	assert (sum.operator_kind == BinaryOperator.ADD);
	assert (((CfgBinaryValue) sum.left).operator_kind == BinaryOperator.SUBTRACT);
	var remainder = (CfgBinaryValue) build_value ("8 / 2 * 3 % 5");
	assert (remainder.operator_kind == BinaryOperator.REMAINDER);
	assert (((CfgBinaryValue) remainder.left).operator_kind == BinaryOperator.MULTIPLY);
	assert (((CfgBinaryValue) ((CfgBinaryValue) remainder.left).left).operator_kind == BinaryOperator.DIVIDE);
}

private void depth_boundary() {
	var value = build_value (string.nfill (255, '-') + "1");
	int count = 0;
	while (value is CfgPrefixValue) {
		value = ((CfgPrefixValue) value).operand;
		count++;
	}
	assert (count == 254 && value is CfgIntegerValue);
	var chain = new StringBuilder ("1");
	for (int i = 0; i < 255; i++) {
		chain.append ("+1");
	}
	assert (dump_ok (build_ok ("int f() { return " + chain.str + "; }")).contains ("(binary + : int"));
	assert (build_value (string.nfill (255, '(') + "1" + string.nfill (255, ')')) is CfgIntegerValue);
}

private void register_verifier_tests() {
	add_case ("/cfg/verifier/duplicate-block-ordinal", () => {
			var program = build_ok ("void f() { return; return; }");
			var function = program.functions[0];
			function.blocks[1] = new CfgBlock (function.span, 0, new GenericArray<CfgInstruction> (), new CfgReturn (function.span, null));
			expect_invalid (program, "function #0/block #1", "expected ordinal 1, found 0");
		});
	add_case ("/cfg/verifier/repeated-block", () => {
			var program = build_ok ("void f() { return; return; }");
			program.functions[0].blocks[1] = program.functions[0].entry;
			expect_invalid (program, "function #0/block #1", "block identity occurs in more than one declaration slot");
		});
	add_case ("/cfg/verifier/shared-block", () => {
			var program = build_ok ("void f() {} void g() {}");
			program.functions[1].blocks[0] = program.functions[0].entry;
			expect_invalid (program, "function #1/block #0", "block identity occurs in more than one declaration slot");
		});
	add_case ("/cfg/verifier/foreign-entry", () => {
			var program = build_ok ("void f() {} void g() {}");
			var function = program.functions[0];
			program.functions[0] = new CfgFunction (function.span, function.name_span, function.name, function.return_type, 0, function.parameters, function.locals, function.blocks, program.functions[1].entry);
			expect_invalid (program, "function #0/entry", "entry block is not owned by the containing function");
		});
	add_case ("/cfg/verifier/no-blocks", () => {
			var program = build_ok ("void f() {}");
			program.functions[0].blocks.remove_index (0);
			expect_invalid (program, "function #0/entry", "entry block is not owned by the containing function");
		});
	add_case ("/cfg/verifier/function-ordinal", () => {
			var program = build_ok ("void f() {}");
			var function = program.functions[0];
			program.functions[0] = new CfgFunction (function.span, function.name_span, function.name, function.return_type, 1, function.parameters, function.locals, function.blocks, function.entry);
			expect_invalid (program, "function #0", "expected ordinal 0, found 1");
		});
	add_case ("/cfg/verifier/invalid-type-kind", () => {
			var program = build_ok ("int f() { return 1; }");
			replace_terminator (program, 0, 0, new CfgReturn (program.span, new CfgIntegerValue (program.span, new SemanticType ((TypeKind) 99), AstraIntValue.from_int64 (7))));
			expect_invalid (program, "function #0/block #0/terminator/value", "unsupported semantic type");
		});
	add_case ("/cfg/verifier/cross-function-reference", () => {
			var program = build_ok ("int f(int x) { return x; } int g(int x) { return x; }");
			var function = program.functions[0];
			replace_terminator (program, 0, 0, new CfgReturn (function.span, new CfgParameterValue (function.span, program.functions[1].parameters[0])));
			expect_invalid (program, "function #0/block #0/terminator/value", "parameter reference is not owned by the containing function");
		});
	add_case ("/cfg/verifier/unowned-parameter", () => {
			var program = build_ok ("int f(int x) { return x; }");
			program.functions[0].parameters.remove_index (0);
			expect_invalid (program, "function #0/block #0/terminator/value", "parameter reference is not owned by the containing function");
		});
	add_case ("/cfg/verifier/void-return-value", () => {
			var program = build_ok ("void f() { return; } int g() { return 1; }");
			replace_terminator (program, 0, 0, new CfgReturn (program.span, returned_value (program.functions[1])));
			expect_invalid (program, "function #0/block #0/terminator", "void function return must not carry a value");
		});
	add_case ("/cfg/verifier/missing-int-return-value", () => {
			var program = build_ok ("int f() { return 1; }");
			replace_terminator (program, 0, 0, new CfgReturn (program.span, null));
			expect_invalid (program, "function #0/block #0/terminator", "non-void function return must carry a value");
		});
	add_case ("/cfg/verifier/void-value-type", () => {
			var program = build_ok ("int f() { return 1; } void g() {}");
			replace_terminator (program, 0, 0, new CfgReturn (program.span, new CfgIntegerValue (program.span, program.functions[1].return_type, AstraIntValue.from_int64 (7))));
			expect_invalid (program, "function #0/block #0/terminator/value", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/cfg/verifier/parameter-ordinal", () => {
			var program = build_ok ("int f(int x) {}");
			var parameter = program.functions[0].parameters[0];
			program.functions[0].parameters[0] = new CfgParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, 1);
			expect_invalid (program, "function #0/parameter #0", "expected ordinal 0, found 1");
		});
	add_case ("/cfg/verifier/shared-parameter", () => {
			var program = build_ok ("int f(int x) {} int g(int x) {}");
			program.functions[1].parameters[0] = program.functions[0].parameters[0];
			expect_invalid (program, "function #1/parameter #0", "parameter identity occurs in more than one declaration slot");
		});
	add_case ("/cfg/verifier/repeated-parameter", () => {
			var program = build_ok ("int f(int x) {}");
			program.functions[0].parameters.add (program.functions[0].parameters[0]);
			expect_invalid (program, "function #0/parameter #1", "parameter identity occurs in more than one declaration slot");
		});
	add_case ("/cfg/verifier/repeated-function", () => {
			var program = build_ok ("void f() {}");
			program.functions.add (program.functions[0]);
			expect_invalid (program, "function #1", "function identity occurs more than once");
		});
	add_case ("/cfg/verifier/void-parameter", () => {
			var program = build_ok ("void f() {}");
			program.functions[0].parameters.add (new CfgParameter (program.span, program.span, "x", program.functions[0].return_type, 0));
			expect_invalid (program, "function #0/parameter #0", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/cfg/verifier/type-identity", () => {
			var program = build_ok ("int f() { return 1; }");
			replace_terminator (program, 0, 0, new CfgReturn (program.span, new CfgIntegerValue (program.span, new SemanticType (TypeKind.INT), AstraIntValue.from_int64 (7))));
			expect_invalid (program, "function #0/block #0/terminator/value", "inconsistent 'int' semantic type identity");
		});
	add_case ("/cfg/verifier/prefix-operand-type", () => {
			var program = build_ok ("int f() { return 1; } void g() {}");
			var bad_operand = new CfgIntegerValue (program.span, program.functions[1].return_type, AstraIntValue.from_int64 (7));
			var prefix = new CfgPrefixValue (program.span, program.functions[0].return_type, PrefixOperator.NEGATIVE, bad_operand);
			replace_terminator (program, 0, 0, new CfgReturn (program.span, prefix));
			expect_invalid (program, "function #0/block #0/terminator/value/operand", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/cfg/verifier/binary-operand-type", () => {
			var program = build_ok ("int f() { return 1; } void g() {}");
			var bad_operand = new CfgIntegerValue (program.span, program.functions[1].return_type, AstraIntValue.from_int64 (7));
			var binary = new CfgBinaryValue (program.span, program.functions[0].return_type, BinaryOperator.ADD, returned_value (program.functions[0]), bad_operand);
			replace_terminator (program, 0, 0, new CfgReturn (program.span, binary));
			expect_invalid (program, "function #0/block #0/terminator/value/right", "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
		});
	add_case ("/cfg/verifier/prefix-operator", () => {
			var program = build_ok ("int f() { return 1; }");
			var prefix = new CfgPrefixValue (program.span, program.functions[0].return_type, (PrefixOperator) 99, returned_value (program.functions[0]));
			replace_terminator (program, 0, 0, new CfgReturn (program.span, prefix));
			expect_invalid (program, "function #0/block #0/terminator/value", "unsupported semantic prefix operator");
		});
	add_case ("/cfg/verifier/binary-operator", () => {
			var program = build_ok ("int f() { return 1; }");
			var value = returned_value (program.functions[0]);
			var binary = new CfgBinaryValue (program.span, value.semantic_type, (BinaryOperator) 99, value, value);
			replace_terminator (program, 0, 0, new CfgReturn (program.span, binary));
			expect_invalid (program, "function #0/block #0/terminator/value", "unsupported semantic binary operator");
		});
}

private void reachability_and_unreachable_end() {
	var program = build_ok ("int f() { return 1; return 2; }");
	replace_terminator (program, 0, 0, new CfgFunctionEnd (program.span));
	var function = program.functions[0];
	// A synthetic entry at #1 proves neither reachability nor flow
	// checking treats array position #0 as an implicit execution fact.
	program.functions[0] = new CfgFunction (function.span, function.name_span, function.name, function.return_type, 0, function.parameters, function.locals, function.blocks, function.blocks[1]);
	function = program.functions[0];
	verify_ok (program);
	var reachability = CfgReachability.analyze (function);
	assert (!reachability.is_reachable (function.blocks[0]));
	assert (reachability.is_reachable (function.blocks[1]));
	assert (flow_result (program).diagnostic == null);
	assert (dump_ok (program).contains ("(block #0 unreachable\n\t\t\t(function-end)"));
	// Mutating a traversal snapshot cannot manufacture an edge.
	var successors = function.entry.terminator.successors ();
	successors.add (function.blocks[0]);
	assert (function.entry.terminator.successors ().length == 0);
	assert (!CfgReachability.analyze (function).is_reachable (function.blocks[0]));
	assert (function.blocks.length == 2);
}

private void deterministic_dump() {
	string text = "void sequential() { return; return; }";
	string expected = "(cfg-program\n\t(function #0 \"sequential\" -> void\n\t\t(parameters)\n\t\t(entry #0)\n\t\t(block #0 reachable\n\t\t\t(return)\n\t\t)\n\t\t(block #1 unreachable\n\t\t\t(return)\n\t\t)\n\t)\n)\n";
	var program = build_ok (text);
	assert (dump_ok (program) == expected);
	assert (dump_ok (program) == expected);
	assert (dump_ok (build_ok (text)) == expected);
	assert (dump_ok (build_ok ("")) == "(cfg-program)\n");
}

private void flow_diagnostic_order() {
	var program = build_ok ("void ok() {}\nint z() {}\nint a() {}");
	assert (flow_result (program).diagnostic.format () == "test.astra:2:5: error: not all paths in function 'z' return a value");
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
	var function = program.functions[0];
	assert (function.parameters.length == 1000 && function.blocks.length == 1000);
	var reachability = CfgReachability.analyze (function);
	for (int i = 0; i < 1000; i++) {
		assert (function.blocks[i].ordinal == i);
		assert (((CfgParameterValue) returned_value (function, i)).parameter == function.parameters[i]);
		assert (reachability.is_reachable (function.blocks[i]) == (i == 0));
	}
	assert (flow_result (program).diagnostic == null);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, TestCase> (str_hash, str_equal);
	register_place_cfg_tests ();
	register_branch_cfg_tests ();
	register_program ("empty", "", 0);
	register_program ("comment-only", "/* empty */", 0);
	register_program ("one-function", "int main() { return 0; }", 1);
	register_program ("multiple-functions", "void z() {} int a() { return 1; }", 2);
	Test.add_func ("/cfg/identity/declarations-and-bindings", declarations_and_identity);
	Test.add_func ("/cfg/identity/binding-over-spelling", binding_over_spelling);
	Test.add_func ("/cfg/builder/requires-verified-core", invalid_core_input);
	Test.add_func ("/cfg/value/integer-spelling", integer_spelling);
	Test.add_func ("/cfg/value/huge-literal", huge_literal);
	register_prefix ("positive", "+", PrefixOperator.POSITIVE);
	register_prefix ("negative", "-", PrefixOperator.NEGATIVE);
	register_binary ("addition", "+", BinaryOperator.ADD);
	register_binary ("subtraction", "-", BinaryOperator.SUBTRACT);
	register_binary ("multiplication", "*", BinaryOperator.MULTIPLY);
	register_binary ("division", "/", BinaryOperator.DIVIDE);
	register_binary ("remainder", "%", BinaryOperator.REMAINDER);
	Test.add_func ("/cfg/value/arithmetic-structure", arithmetic_structure);
	Test.add_func ("/cfg/value/no-simplification", no_simplification);
	Test.add_func ("/cfg/terminator/sequential-returns", sequential_returns);
	register_completion ("empty-void", "void f() {}", false, true);
	register_completion ("return-void", "void f() { return; }", true, true);
	register_completion ("empty-int", "int f() {}", false, false);
	register_completion ("return-int", "int f() { return 0; }", true, true);
	Test.add_func ("/cfg/flow/diagnostic-order", flow_diagnostic_order);
	Test.add_func ("/cfg/source/lifetime", source_lifetime);
	Test.add_func ("/cfg/reachability/entry-and-successor-authority", reachability_and_unreachable_end);
	register_verifier_tests ();
	Test.add_func ("/cfg/dump/deterministic", deterministic_dump);
	Test.add_func ("/cfg/limits/depth", depth_boundary);
	Test.add_func ("/cfg/limits/flat-lists", flat_lists);
	int result = Test.run ();
	cases.remove_all ();
	cases = null;
	return result;
}
}
