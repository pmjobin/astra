// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.ScalarPipeline {
private ParseResult parse(string text) {
	var result = Parser.parse (new SourceFile.from_text ("scalar.astra", text));
	assert (result.diagnostic == null);
	return result;
}

private CheckedProgram check(string text) {
	var result = SemanticAnalyzer.analyze (parse (text).unit);
	assert (result.diagnostic == null && result.program != null);
	return result.program;
}

private CheckedIntegerExpression constant(CheckedProgram program) {
	return (CheckedIntegerExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
}

private void stage_constant(string expression, int64 expected, string provenance) {
	var parsed = parse ("int f(){return " + expression + ";}");
	string syntax_dump = SyntaxDump.format (parsed.unit);
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var checked_value = constant (checked_result.program);
	assert (checked_value.value.signed_value == expected && checked_value.span.text () == provenance);
	assert (checked_value.semantic_type == checked_result.program.types.int_type);
	string canonical = "(integer %s : int)".printf (expected.to_string ());
	assert (SemanticDump.format (checked_result.program).contains (canonical));
	assert (SyntaxDump.format (parsed.unit) == syntax_dump);
	try {
		var core = CoreBuilder.build (checked_result.program);
		var core_value = (CoreIntegerValue) ((CoreReturn) core.functions[0].body.statements[0]).value;
		assert (core_value.value == checked_value.value && core_value.semantic_type == checked_value.semantic_type && core_value.span.text () == provenance);
		assert (CoreDump.format (core).contains (canonical));
		var cfg = CfgBuilder.build (core);
		var cfg_value = (CfgIntegerValue) ((CfgReturn) cfg.functions[0].entry.terminator).value;
		assert (cfg_value.value == checked_value.value && cfg_value.semantic_type == checked_value.semantic_type && cfg_value.span.text () == provenance);
		assert (CfgDump.format (cfg).contains (canonical));
		var ssa = SsaBuilder.build (cfg);
		var ssa_value = (SsaIntegerConstant) ((SsaReturn) ssa.functions[0].entry.terminator).value;
		assert (ssa_value.value == checked_value.value && ssa_value.semantic_type == checked_value.semantic_type && ssa_value.span.text () == provenance);
		assert (SsaDump.format (ssa).contains (canonical));
	} catch (GLib.Error error) {
		GLib.error ("Scalar stage constant failed: %s", error.message);
	}
}

private void boundaries() {
	stage_constant ("0", 0, "0");
	stage_constant ("2147483647", AstraIntValue.MAX, "2147483647");
	stage_constant ("-2147483648", AstraIntValue.MIN, "-2147483648");
	stage_constant ("+2147483647", AstraIntValue.MAX, "+2147483647");
	stage_constant ("-0", 0, "-0");
	stage_constant ("+0", 0, "+0");
}

private void parentheses() {
	foreach (string expression in new string[] {"-(2147483648)", "-((2147483648))", "-(((2147483648)))", "- /* sign */ (0002147483648)"}) {
		stage_constant (expression, AstraIntValue.MIN, expression);
	}
	stage_constant ("((-2147483648))", AstraIntValue.MIN, "-2147483648");
	stage_constant ("+((00042))", 42, "+((00042))");
}

private void spelling() {
	foreach (string digits in new string[] {"42", "042", "00042", "00000000042"}) {
		var parsed = parse ("int f(){return " + digits + ";}");
		assert (SyntaxDump.format (parsed.unit).contains ("(integer \"" + digits + "\")"));
		stage_constant (digits, 42, digits);
	}
	stage_constant (string.nfill (1003, '0'), 0, string.nfill (1003, '0'));
}

private void overflow() {
	foreach (string expression in new string[] {"2147483648", "+2147483648", "-2147483649", "-(2147483649)", "-((2147483649))", "-+(2147483648)", "-(2147483648 + 0)", "000" + string.nfill (1000, '9')}) {
		var parsed = parse ("int valid(){return 0;} int f(){return " + expression + ";}");
		string before = SyntaxDump.format (parsed.unit);
		for (int attempt = 0; attempt < 2; attempt++) {
			var result = SemanticAnalyzer.analyze (parsed.unit);
			assert (result.program == null && result.diagnostic.message == "integer literal is out of range for 'int'");
			assert (result.diagnostic.span.file == parsed.unit.span.file);
			assert (expression.contains (result.diagnostic.span.text ()));
		}
		assert (SyntaxDump.format (parsed.unit) == before);
	}
}

private void contexts() {
	foreach (string expression in new string[] {"2147483647", "-2147483648"}) {
		var program = check ("int identity(int x){return x;} int f(){int x = " + expression + ";x = " + expression + ";return identity(" + expression + ");}");
		try {
			var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (program)));
			var call = (SsaCallInstruction) ssa.functions[1].entry.instructions[0];
			assert (((SsaIntegerConstant) call.arguments[0]).value.to_string () == expression);
			assert (call.target == ssa.functions[0]);
		} catch (GLib.Error error) {
			GLib.error ("Scalar call/local failed: %s", error.message);
		}
	}
	foreach (string expression in new string[] {"2147483648", "-2147483649"}) {
		foreach (string statement in new string[] {"int x = " + expression + ";return x;", "int x = 0;x = " + expression + ";return x;", "return identity(" + expression + ");"}) {
			var result = SemanticAnalyzer.analyze (parse ("int identity(int x){return x;} int f(){" + statement + "}").unit);
			assert (result.program == null && result.diagnostic.message == "integer literal is out of range for 'int'");
			assert (result.diagnostic.span.text () == expression);
		}
	}
}

private void operations() {
	foreach (string expression in new string[] {"2147483647 + 1", "4 * 5", "1 / 0", "1 % 0", "-2147483648 / -1", "-2147483648 % -1", "-(-2147483648)"}) {
		var program = check ("int f(){return " + expression + ";}");
		var checked_value = ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
		assert (checked_value is CheckedBinaryExpression || checked_value is CheckedPrefixExpression);
		try {
			var core = CoreBuilder.build (program);
			var core_value = ((CoreReturn) core.functions[0].body.statements[0]).value;
			assert (core_value is CoreBinaryValue || core_value is CorePrefixValue);
			var cfg = CfgBuilder.build (core);
			var cfg_value = ((CfgReturn) cfg.functions[0].entry.terminator).value;
			assert (cfg_value is CfgBinaryValue || cfg_value is CfgPrefixValue);
			var entry = SsaBuilder.build (cfg).functions[0].entry;
			assert (entry.instructions.length == 1);
			assert (entry.instructions[0] is SsaBinaryInstruction || entry.instructions[0] is SsaPrefixInstruction);
			assert (((SsaReturn) entry.terminator).value == entry.instructions[0].result);
		} catch (GLib.Error error) {
			GLib.error ("Scalar operation was lost: %s", error.message);
		}
	}
	var boolean = check ("bool f(){return !false;}");
	assert (((CheckedReturnStatement) boolean.functions[0].body.statements[0]).expression is CheckedPrefixExpression);
}

private void numeric_authority() {
	// Deliberately unrelated provenance proves builders/verifiers do not
	// re-parse text, even when its apparent positive magnitude is invalid.
	var program = check ("int f(){return -2147483648;}");
	var original = constant (program);
	var magnitude_span = SourceSpan (original.span.file, original.span.start + 1, original.span.end);
	program.functions[0].body.statements[0] = new CheckedReturnStatement (original.span, new CheckedIntegerExpression (magnitude_span, original.semantic_type, AstraIntValue.from_int64 (42)));
	try {
		var core = CoreBuilder.build (program);
		assert (CoreDump.format (core).contains ("(integer 42 : int)"));
		var cfg = CfgBuilder.build (core);
		assert (CfgDump.format (cfg).contains ("(integer 42 : int)"));
		var ssa = SsaBuilder.build (cfg);
		assert (SsaDump.format (ssa).contains ("(integer 42 : int)"));
		var value = (SsaIntegerConstant) ((SsaReturn) ssa.functions[0].entry.terminator).value;
		assert (value.value.signed_value == 42 && value.span.text () == "2147483648");
	} catch (GLib.Error error) {
		GLib.error ("Source text became numeric authority: %s", error.message);
	}
}

private void trap_order() {
	string declarations = "int effect(){return 1;} int pair(int a,int b){return a+b;} int use(bool a,int b){return b;} ";
	string[] bodies = {
		"return a / b + effect();",
		"return pair(a % b,effect());",
		"return -(a / b) + effect();",
		"return use(a / b == 0,effect());",
		"int x = a / b + effect();return x;",
		"int x = 0;x = a % b + effect();return x;",
		"if(a / b < effect()){return 1;}else{return 0;}",
		"return pair(a / b,(a % b) + effect());"
	};
	foreach (string body in bodies) {
		try {
			CoreProgram? core = CoreBuilder.build (check (declarations + "int f(int a,int b){" + body + "}"));
			CfgProgram? cfg = CfgBuilder.build (core);
			var cfg_ref = WeakRef (cfg);
			var core_ref = WeakRef (core);
			var f = cfg.functions[3];
			bool evaluated = false;
			foreach (var instruction in f.entry.instructions) {
				if (instruction is CfgEvaluateInstruction) {
					evaluated = true;
				} else if (instruction is CfgCallInstruction) {
					assert (evaluated);
					break;
				}
			}
			assert (evaluated);
			var evaluation_ref = WeakRef (f.entry.instructions[body.has_prefix ("int x = 0") ? 1 : 0]);
			var ssa = SsaBuilder.build (cfg);
			f = null;
			core = null;
			cfg = null;
			assert (core_ref.get () == null && cfg_ref.get () == null && evaluation_ref.get () == null);
			SsaVerifier.verify (ssa);
			var instructions = ssa.functions[3].entry.instructions;
			var first = instructions[0] as SsaBinaryInstruction;
			assert (first != null && (first.operator_kind == BinaryOperator.DIVIDE || first.operator_kind == BinaryOperator.REMAINDER));
			assert (first.span.text () == (body.contains ("a / b") ? "a / b" : "a % b"));
			int calls = 0;
			foreach (var instruction in instructions) {
				if (instruction is SsaCallInstruction) {
					calls++;
				}
			}
			assert (calls == (body.contains ("pair(") || body.contains ("use(") ? 2 : 1));
		} catch (GLib.Error error) {
			GLib.error ("Trap/call order failed: %s", error.message);
		}
	}
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check (declarations + "int f(int a,int b){return effect() + a / b;}"))));
		assert (ssa.functions[3].entry.instructions[0] is SsaCallInstruction);
		assert (((SsaBinaryInstruction) ssa.functions[3].entry.instructions[1]).operator_kind == BinaryOperator.DIVIDE);
	} catch (GLib.Error error) {
		GLib.error ("Call before trap order failed: %s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/scalar/pipeline/boundaries", boundaries);
	Test.add_func ("/scalar/pipeline/parentheses", parentheses);
	Test.add_func ("/scalar/pipeline/spelling", spelling);
	Test.add_func ("/scalar/pipeline/overflow", overflow);
	Test.add_func ("/scalar/pipeline/calls-and-locals", contexts);
	Test.add_func ("/scalar/pipeline/operations", operations);
	Test.add_func ("/scalar/pipeline/numeric-authority", numeric_authority);
	Test.add_func ("/scalar/pipeline/trap-call-order-and-lifetime", trap_order);
	return Test.run ();
}

}
