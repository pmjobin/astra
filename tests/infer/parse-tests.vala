// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.InferParser {
private void provenance() {
	var source = new SourceFile.from_text ("infer.astra", "void f(){var value = 1.0d; {var next = value;} }");
	var lexer = new Lexer (new SourceFile.from_text ("keyword", "var variable Var"));
	assert (lexer.next_token ().kind == TokenKind.VAR);
	assert (lexer.next_token ().kind == TokenKind.IDENTIFIER && lexer.next_token ().kind == TokenKind.IDENTIFIER);
	var parsed = Parser.parse (source);
	assert (parsed.diagnostic == null);
	var declaration = (InferredLocalDeclarationSyntax) parsed.unit.functions[0].body.statements[0];
	assert (declaration.keyword.kind == TokenKind.VAR && declaration.keyword.span.start == 9 && declaration.keyword.span.end == 12);
	assert (declaration.name.span.text () == "value" && declaration.name.span.start == 13);
	assert (declaration.initializer.span.text () == "1.0d" && declaration.initializer.span.start == 21);
	assert (declaration.equals_token.spelling () == "=" && declaration.semicolon.spelling () == ";");
	assert (declaration.span.text () == "var value = 1.0d;");
	assert (SyntaxDump.format (parsed.unit).contains ("(inferred-local (name \"value\")"));
	for (int i = 0; i <= source.length; i++) {
		var prefix = Parser.parse (new SourceFile.from_text ("prefix", source.slice (0, i)));
		assert ((prefix.unit == null) != (prefix.diagnostic == null));
	}
}

private void reserved() {
	foreach (string text in new string[] {
			"int var(){return 1;}", "struct var{int x;}", "class var{}", "void f(){int var=1;}",
			"void f(){var=var+1;}", "void f(int var){}", "struct S{int var;}", "class C{int var;}",
			"var f(){return 1;}", "void f(var x){}", "struct S{var x;}", "class C{var x;}",
			"class C{property var x{get{return 1;}}}", "T f<var>(T x){return x;}",
			"extern(C) var f();", "extern(C) int var();", "void f(){int x=var;}", "void f(){var var=1;}",
			"void f(){owned var x=make();}", "struct S{int x;}void f(){S s={x=1};int x=s.var;}"
		}) {
		var parsed = Parser.parse (new SourceFile.from_text ("reserved", text));
		assert (parsed.unit == null && parsed.diagnostic != null && parsed.diagnostic.message.contains ("'var' is a reserved keyword for inferred local declarations"));
	}
}

private void malformed() {
	foreach (string text in new string[] {"void f(){var x;}", "void f(){var x=;}", "void f(){var x=}"}) {
		var parsed = Parser.parse (new SourceFile.from_text ("required", text));
		assert (parsed.diagnostic.message == "inferred local declaration requires an initializer");
	}
	foreach (string text in new string[] {"void f(){var int x=1;}", "void f(){var x:int=1;}"}) {
		assert (Parser.parse (new SourceFile.from_text ("type", text)).diagnostic.message == "inferred local declaration cannot include an explicit type");
	}
	foreach (string text in new string[] {"void f(){var x={};}", "void f(){var x={1,2};}", "void f(){var x={value=1};}"}) {
		assert (Parser.parse (new SourceFile.from_text ("aggregate", text)).diagnostic.message == "cannot infer local type from this initializer; write an explicit type");
	}
	foreach (string text in new string[] {"void f(){x:=1;}", "void f(){var x=1}"}) {
		assert (Parser.parse (new SourceFile.from_text ("malformed", text)).diagnostic != null);
	}
	foreach (string text in new string[] {"void f(){let x=1;}", "void f(){final x=1;}"}) {
		// Unknown explicit type names remain syntactically legal and never
		// become inferred declarations. Semantic negatives reject the names.
		var parsed = Parser.parse (new SourceFile.from_text ("non-goal", text));
		assert (parsed.diagnostic == null && parsed.unit.functions[0].body.statements[0] is LocalDeclarationSyntax);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/infer/parser/keyword-spans-nesting-prefixes", provenance);
	Test.add_func ("/infer/parser/reserved-identifiers-nonlocal", reserved);
	Test.add_func ("/infer/parser/required-targetless-initializer", malformed);
	return Test.run ();
}
}
