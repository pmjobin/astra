// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.F32Semantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("f32.astra", text));
	assert (syntax.unit != null);
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.program == null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string expected) {
	var syntax = Parser.parse (new SourceFile.from_text ("f32-invalid.astra", text));
	assert (syntax.unit != null);
	string before = SyntaxDump.format (syntax.unit);
	for (int repeat = 0; repeat < 2; repeat++) {
		var result = SemanticAnalyzer.analyze (syntax.unit);
		if (result.program != null || !result.diagnostic.message.contains (expected)) {
			GLib.error ("Expected %s for %s; got %s", expected, text, result.diagnostic == null ? "success" : result.diagnostic.message);
		}
	}
	assert (SyntaxDump.format (syntax.unit) == before);
}

private void identity() {
	var types = new BuiltinTypes ();
	assert (types.resolve ("f32") == types.f32_type && types.f32_type.kind == TypeKind.F32);
	foreach (var name in new string[] {"int", "i32", "u32", "i16", "u16", "i8", "u8", "bool", "void", "void*"}) {
		assert (types.resolve (name) != types.f32_type);
	}
	var program = check ("struct S { f32 x; } f32 id(f32 x){return x;} f32 f(){f32 x=1.0; S s={x=-0.0}; s.x=s.x+1e0; x=id(s.x); return +x;} f32 zero(){return -0.0;}");
	var type = program.functions[0].symbol.return_type;
	assert (type is F32Type && program.functions[0].symbol.parameters[0].semantic_type == type && program.functions[1].symbol.return_type == type);
	var literal = (CheckedFloatExpression) ((CheckedReturnStatement) program.functions[2].body.statements[0]).expression;
	assert (literal.semantic_type == type && literal.value.exact_bits == 0x80000000U && literal.span.text () == "-0.0");
	check ("f32 f(f32 a,f32 b){return -(+a*b+a/b-b);} bool g(f32 a,f32 b){return a==b || a!=b || a<b || a<=b || a>b || a>=b;}");
}

private void grammar() {
	var source = new SourceFile.from_text ("tokens", "0.0 1e3 1E3 1.25e-4 123.456E+7 p.x -1.0");
	var lexer = new Lexer (source);
	foreach (string text in new string[] {"0.0", "1e3", "1E3", "1.25e-4", "123.456E+7"}) {
		var token = lexer.next_token ();
		assert (token.kind == TokenKind.FLOAT && token.spelling () == text && token.span.file == source);
	}
	foreach (var kind in new TokenKind[] {TokenKind.IDENTIFIER, TokenKind.DOT, TokenKind.IDENTIFIER, TokenKind.MINUS, TokenKind.FLOAT, TokenKind.EOF}) {
		assert (lexer.next_token ().kind == kind);
	}
	check ("f32 suffix(){return 1.0f;}");
	var parsed = Parser.parse (new SourceFile.from_text ("syntax", "f32 f(){return -1.0;}"));
	assert (SyntaxDump.format (parsed.unit).contains ("(prefix \"-\" (float \"1.0\"))"));
	foreach (string spelling in new string[] {".5", "1.", "1e", "1e+", "1E-", "0x1.0p0", "1_0.0", "1.0.0"}) {
		var bad = Parser.parse (new SourceFile.from_text ("invalid", "f32 f(){return " + spelling + ";}"));
		assert (bad.unit == null && bad.diagnostic != null);
	}
}

private void diagnostics() {
	reject ("struct f32 { int x; }", "conflicts with builtin type");
	foreach (string t in new string[] {"int", "i32", "u32", "i16", "u16", "i8", "u8"}) {
		reject ("void f(){f32 x=1;}", "type 'f32'");
		reject ("void f(){" + t + " x=1.0;}", "f32");
		reject ("f32 f(" + t + " x){return x;}", "f32");
		reject (t + " f(f32 x){return x;}", "f32");
		reject ("f32 f(f32 x){return x;} void g(){f(1);}", "expects type 'f32'");
		reject ("void f(" + t + " x){} void g(){f(1.0);}", "f32");
		reject ("void f(" + t + " y){f32 x=0.0;x=y;}", "f32");
		reject ("void f(f32 x){" + t + " y=0;y=x;}", "f32");
		foreach (string op in new string[] {"+", "-", "*", "/", "==", "!=", "<", "<=", ">", ">="}) {
			string result = op == "+" || op == "-" || op == "*" || op == "/" ? "f32" : "bool";
			reject (result + " f(f32 x," + t + " y){return x" + op + "y;}", "requires matching non-void operands");
			reject (result + " f(f32 x," + t + " y){return y" + op + "x;}", "requires matching non-void operands");
		}
	}
	reject ("f32 f(f32 x){return x+1;}", "requires matching non-void operands");
	reject ("void f(f32 x){if(x){return;}}", "condition must have type 'bool'");
	reject ("bool f(f32 x){return !x;}", "requires a 'bool' operand");
	reject ("bool f(f32 x){return x==true;}", "requires matching non-void operands");
	reject ("f32 f(f32 x){return x%1.0;}", "not supported for f32");
	reject ("f32 f(){return NaN;}", "unknown name");
	reject ("f32 f(){return infinity;}", "unknown name");
	foreach (string decl in new string[] {"extern(C) f32 f(f32 x);", "extern(C) int f(f32 x);", "export(C) f32 f(){return 1.0;}", "export(C) int f(f32 x){return 0;}"}) {
		check (decl);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f32/semantic/canonical-identity-constants-operators", identity);
	Test.add_func ("/f32/semantic/grammar-provenance", grammar);
	Test.add_func ("/f32/semantic/no-conversions-foreign-scalars", diagnostics);
	return Test.run ();
}
}
