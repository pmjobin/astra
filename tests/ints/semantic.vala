// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.IntegersSemantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("integers.astra", text));
	assert (parsed.unit != null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.program == null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void contexts() {
	string[] names = {
		"i8", "u8", "i16", "u16", "i32", "u32"
	};
	string[] maxima = {
		"127", "255", "32767", "65535", "2147483647", "4294967295"
	};
	for (int i = 0; i < names.length; i++) {
		string t = names[i];
		string max = maxima[i];
		string text = "struct S { " + t + " x; } " + t + " id(" + t + " x){return x;} " + t + " literal(){return " + max + ";} " + t + " f(){" + t + " x=1+2; x=" + max + "; S s={x=" + max + "}; s.x=42; x=id(" + max + "); if(x<" + max + "){x=1+(2+x);} if(" + max + ">=s.x){s.x=1+s.x;} return x+(1+id(2));}";
		var program = check (text);
		var type = program.functions[0].symbol.return_type;
		var literal = (CheckedIntegerExpression) ((CheckedReturnStatement) program.functions[1].body.statements[0]).expression;
		assert (literal.semantic_type == type && literal.value.integer_type == type && literal.value.to_string () == max);
		string dump = SemanticDump.format (program);
		assert (dump.contains ("(binary + : " + type.display_name ()));
		check ("bool f(" + t + " x){return (1+2)<(3+x) && +(1+x)>0;}");
	}
	var aliases = check ("int f(i32 x){int y=x;i32 z=y;return z;} i32 main(){return f(0);}");
	assert (aliases.functions[0].symbol.return_type == aliases.functions[0].symbol.parameters[0].semantic_type);
	check ("i8 a(){return -(128);} i16 b(){return -((32768));} i32 c(){return -2147483648;}");
	var defaults = check ("bool f(){return 1+2<4;} int g(){return 1+2;}");
	var comparison = (CheckedBinaryExpression) ((CheckedReturnStatement) defaults.functions[0].body.statements[0]).expression;
	assert (comparison.left.semantic_type == defaults.functions[1].symbol.return_type);
}

private void reject(string text, string expected) {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", text));
	assert (parsed.unit != null);
	string syntax = SyntaxDump.format (parsed.unit);
	for (int repeat = 0; repeat < 2; repeat++) {
		var result = SemanticAnalyzer.analyze (parsed.unit);
		if (result.program != null || !result.diagnostic.message.contains (expected)) {
			GLib.error ("Expected %s for %s; got %s", expected, text, result.diagnostic == null ? "success" : result.diagnostic.message);
		}
	}
	assert (syntax == SyntaxDump.format (parsed.unit));
}

private void diagnostics() {
	foreach (var declaration in new string[] {"u8 x=256;", "i8 x=128;", "i8 x=-129;", "i8 x=+128;", "i16 x=32768;", "i16 x=-32769;", "u16 x=65536;", "u32 x=4294967296;", "int x=2147483648;", "i8 x=-(128+0);", "i8 x=-+128;"}) {
		reject ("void f(){" + declaration + "}", "integer literal is out of range");
	}
	foreach (var t in new string[] {"u8", "u16", "u32"}) {
		reject ("void f(){" + t + " x=-1;}", "unary '-' is not supported for unsigned integer type");
		reject (t + " f(" + t + " x){return -x;}", "unary '-' is not supported for unsigned integer type");
	}
	foreach (var left in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
		foreach (var right in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
			if (left == right) {
				continue;
			}
			foreach (var op in new string[] {"+", "-", "*", "/", "%", "==", "!=", "<", "<=", ">", ">="}) {
				string result = op == "+" || op == "-" || op == "*" || op == "/" || op == "%" ? left : "bool";
				reject (result + " f(" + left + " x," + right + " y){return x" + op + "y;}", "requires matching non-void operands");
			}
		}
		reject ("void f(" + left + " x){if(x){return;}}", "condition must have type 'bool'");
		reject ("bool f(" + left + " x){return x==true;}", "requires matching non-void operands");
		reject ("struct " + left + " { int x; }", "conflicts with builtin type");
	}
	reject ("struct i32 { int x; }", "conflicts with builtin type");
	reject ("void f(){uint x=1;}", "unknown type 'uint'");
	reject ("u32 f(){return " + string.nfill (4000, '9') + ";}", "out of range for 'u32'");
	foreach (var t in new string[] {"i8", "u8", "i16", "u16", "u32"}) {
		reject ("extern(C) " + t + " f();", "exact-width C integer channels are not supported yet");
		reject ("extern(C) int f(" + t + " x);", "exact-width C integer channels are not supported yet");
		reject ("export(C) " + t + " f(){return 0;}", "exact-width C integer channels are not supported yet");
		reject ("export(C) int f(" + t + " x){return 0;}", "exact-width C integer channels are not supported yet");
	}
	check ("extern(C) i32 f(i32 x); i32 g(){return f(0);}");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ints/semantic/contextual-literals-aliases-defaults", contexts);
	Test.add_func ("/ints/semantic/diagnostics", diagnostics);
	return Test.run ();
}
}
