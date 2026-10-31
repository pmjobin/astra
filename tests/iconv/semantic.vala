// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.IntegerConversionSemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("iconv.astra", text));
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.program == null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string expected, bool parsing = false) {
	var syntax = Parser.parse (new SourceFile.from_text ("invalid.astra", text));
	if (parsing) {
		if (syntax.unit != null || !syntax.diagnostic.message.contains (expected)) {
			GLib.error ("Expected parse rejection %s for %s", expected, text);
		}
		return;
	}
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	string before = SyntaxDump.format (syntax.unit);
	for (int repeat = 0; repeat < 2; repeat++) {
		var result = SemanticAnalyzer.analyze (syntax.unit);
		if (result.program != null || !result.diagnostic.message.contains (expected)) {
			GLib.error ("Expected %s for %s; got %s", expected, text, result.diagnostic == null ? "success" : result.diagnostic.message);
		}
	}
	assert (SyntaxDump.format (syntax.unit) == before);
}

private void matrix() {
	var types = new BuiltinTypes ();
	int scalar = 0;
	int vector = 0;
	foreach (string source in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
		foreach (string destination in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
			check ("%s f(%s x){return x as %s;}".printf (destination, source, destination));
			scalar++;
			foreach (int lanes in new int[] {2, 4, 8, 16}) {
				if (types.vector_of (types.resolve (source), lanes) == null || types.vector_of (types.resolve (destination), lanes) == null) {
					continue;
				}
				check ("%s<%d> f(%s<%d> x){return x as %s<%d>;}".printf (destination, lanes, source, lanes, destination, lanes));
				vector++;
			}
		}
	}
	assert (scalar == 36 && vector == 92);
	check ("i32 f(int x){return x as i32;} int g(i32 x){return x as int;}");
}

private ExpressionSyntax expression(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("grammar", "void f(){return " + text + ";}"));
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	return ((ReturnStatementSyntax) syntax.unit.functions[0].body.statements[0]).expression;
}

private void grammar() {
	foreach (string op in new string[] {"*", "/", "%", "+", "-", "<", "<=", ">", ">=", "==", "!="}) {
		var left = (BinaryExpressionSyntax) expression ("x as i16 " + op + " y");
		var right = (BinaryExpressionSyntax) expression ("x " + op + " y as i16");
		assert (left.left is ConversionExpressionSyntax && right.right is ConversionExpressionSyntax);
	}
	foreach (string op in new string[] {"&&", "||"}) {
		assert (((ShortCircuitExpressionSyntax) expression ("x as i16 " + op + " y")).left is ConversionExpressionSyntax);
	}
	assert (((ConversionExpressionSyntax) expression ("-1 as u8")).operand is PrefixExpressionSyntax);
	assert (((ConversionExpressionSyntax) expression ("x as i16 as u32")).operand is ConversionExpressionSyntax);
	assert (((ConversionExpressionSyntax) expression ("(x+y) as i16")).operand is ParenthesizedExpressionSyntax);
	assert (((VectorExtractExpressionSyntax) expression ("v as i16<8>[3]")).vector is ConversionExpressionSyntax);
	assert (((BinaryExpressionSyntax) expression ("x as i16 * -y")).left is ConversionExpressionSyntax);
	assert (((BinaryExpressionSyntax) expression ("x as i16 < 3")).left is ConversionExpressionSyntax);
	assert (((BinaryExpressionSyntax) expression ("x as i16<4> * y")).left is ConversionExpressionSyntax);
	assert (((BinaryExpressionSyntax) expression ("x as i16<4> < y")).left is ConversionExpressionSyntax);
	assert (((ConversionExpressionSyntax) expression ("x as void*")).destination.spelling () == "void*");
	reject ("int as(){return 0;}", "expected function name", true);
	reject ("void f(){int as=0;}", "expected '=' after assignment target", true);
	reject ("void f(){int x=1 as;}", "expected destination type after 'as'", true);
	reject ("void f(){int x=(u8)1;}", "expected ';'", true);
	reject ("void f(){int x=u8(1);}", "unknown function");
	var chain = new StringBuilder ("void f(){return 1");
	for (int i = 0; i < 256; i++) {
		chain.append (" as int");
	}
	reject (chain.str + ";}", "nesting limit", true);
	// Every truncation of a cast token stream must fail without losing its diagnostic.
	string text = "u8<8> f(i16<8> x){return x as u8<8>; }";
	for (int i = 0; i < text.length; i++) {
		var parsed = Parser.parse (new SourceFile.from_text ("prefix", text.substring (0, i)));
		assert ((parsed.unit == null) != (parsed.diagnostic == null));
	}
}

private void literals_and_provenance() {
	var program = check ("u8 f(){return 256 as u8;} u8 g(){return -1 as u8;} u32 h(i8 x){return x as i16 as u32;}");
	var wrap = (CheckedIntegerConversionExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
	assert (wrap.source_type == program.types.int_type && wrap.destination_type == program.types.u8_type);
	assert (((CheckedIntegerExpression) wrap.operand).value.mathematical_value == 256);
	assert (wrap.span.text () == "256 as u8" && wrap.operand.span.text () == "256");
	var chain = (CheckedIntegerConversionExpression) ((CheckedReturnStatement) program.functions[2].body.statements[0]).expression;
	assert (chain.source_type == program.types.i16_type && ((CheckedIntegerConversionExpression) chain.operand).source_type == program.types.i8_type);
	assert (SemanticDump.format (program).contains ("(integer-convert (from int) (to u8)"));
	check ("i16 f(i8 x){return (x as i16)+1;} bool g(i8 x){return 255==(x as u8);}");
	check ("bool f(u8<8> v){return (v as i16<8>)[3]==255;}");
	check ("u32 f(){u32 x=4294967295;return x as u32;}");
	check ("u8 f(){return -2147483648 as u8;}");
	reject ("u32 f(){return 4294967295 as u32;}", "out of range for 'int'");
	reject ("u8 f(){return 256;}", "out of range for 'u8'");
	reject ("i16 f(i8 x){return x;}", "expected return value");
	reject ("u32 f(int x){return x;}", "expected return value");
	reject ("i16 f(i8 x,i16 y){return x+y;}", "matching non-void operands");
	reject ("bool f(u8 x,i8 y){return x==y;}", "matching non-void operands");
	reject ("i16<8> f(bool<8> m,i8<8> x,i16<8> y){return select(m,x,y);}", "same exact VectorType");
}

private void unsupported() {
	check ("u8 f(f32 x){return x as u8;} f32 g(u8 x){return x as f32;}");
	foreach (string type in new string[] {"bool", "void*"}) {
		reject ("u8 f(" + type + " x){return x as u8;}", "unsupported integer conversion source type '" + type + "'");
		reject (type + " f(u8 x){return x as " + type + ";}", "unsupported integer conversion destination type '" + type + "'");
	}
	foreach (string type in new string[] {"bool<4>", "f32<4>"}) {
		reject ("u8<4> f(" + type + " x){return x as u8<4>;}", "unsupported integer conversion source type");
		reject (type + " f(u8<4> x){return x as " + type + ";}", "unsupported integer conversion destination type");
	}
	reject ("struct S{int x;} u32 f(S* x){return x as u32;}", "source type 'S*'");
	reject ("struct S{int x;} void f(u32 x){S* y=x as S*;}", "destination type 'S*'");
	reject ("struct S{int x;} void f(u32 x){u32 y=x as S;}", "destination type 'S'");
	reject ("struct S{int x;} void f(){S s={x=1};u32 y=s as u32;}", "whole-struct values are not supported");
	reject ("u8<8> f(u8 x){return x as u8<8>;}", "between scalar and vector");
	reject ("u8 f(u8<8> x){return x as u8;}", "between scalar and vector");
	reject ("i16<4> f(i8<8> x){return x as i16<4>;}", "equal lane counts");
	reject ("void f(i8<16> x){i8<16> y=x as i16<16>;}", "unsupported VEC-1 vector shape 'i16<16>'");
	reject ("void f(i8 x){i8 y=x as i8<3>;}", "unsupported VEC-1 vector shape");
	reject ("void f(i8 x){i8 y=x as void;}", "destination type 'void'");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/iconv/semantic/scalar-and-vector-matrix", matrix);
	Test.add_func ("/iconv/semantic/grammar-and-precedence", grammar);
	Test.add_func ("/iconv/semantic/literals-provenance-no-implicit-conversion", literals_and_provenance);
	Test.add_func ("/iconv/semantic/unsupported-domains-and-shapes", unsupported);
	return Test.run ();
}
}
