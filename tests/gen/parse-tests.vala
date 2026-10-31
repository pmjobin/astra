// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Tests.GenParser {
private ParseResult parse(string text) {
	return Parser.parse (new SourceFile.from_text ("generic.astra", text));
}
private void declarations() {
	var result = parse ("T first<T,U>(T a,U b){T local=a;return first<T,U>(local,b);}int tag<X>(){return 1;}");
	assert (result.diagnostic == null);
	assert (result.unit.functions[0].type_parameters.length == 2 && result.unit.functions[1].type_parameters.length == 1);
	var call = ((ReturnStatementSyntax) result.unit.functions[0].body.statements[1]).expression as CallExpressionSyntax;
	assert (call != null && call.type_arguments.length == 2);
	assert (SyntaxDump.format (result.unit).contains ("(type-parameters T U)"));
}
private void closes() {
	foreach (string spelling in new string[] {"i16<8>", "u32<4>", "bool<16>", "f32<4>", "void*", "f64", "int[]", "int[4]", "int*"}) {
		var result = parse ("void f(){identity<" + spelling + ">(x);}");
		assert (result.diagnostic == null);
		var call = ((CallStatementSyntax) result.unit.functions[0].body.statements[0]).call;
		assert (call.type_arguments.length == 1 && call.type_arguments[0].spelling () == spelling);
	}
	var nested = parse ("int f(){return outer<int>(inner<int>(42));}");
	assert (nested.diagnostic == null);
}
private void regressions() {
	foreach (string expression in new string[] {"a < b", "a > b", "a >> b", "a << b", "a < b > c", "a < b >> c", "id<i16<8>(x)", "a as i16<8> == b"}) {
		var result = parse ("bool f(){return " + expression + ";}");
		assert (result.diagnostic == null);
		assert (!(((ReturnStatementSyntax) result.unit.functions[0].body.statements[0]).expression is CallExpressionSyntax));
	}
	var call = parse ("bool f(){return a < B > (c);}");
	assert (call.diagnostic == null && ((ReturnStatementSyntax) call.unit.functions[0].body.statements[0]).expression is CallExpressionSyntax);
}
private void malformed() {
	foreach (string source in new string[] {"int f(){return len<int>(x);}", "void f(){int[] s=slice<int>(a);}", "class C{init(){}}int f(){C c=C.init<int>();return 1;}", "class C{init(){}}owned C f(){return C.init<int>();}"}) {
		var result = parse (source);
		assert (result.diagnostic != null && result.diagnostic.message.contains ("do not accept type arguments"));
	}
	foreach (string source in new string[] {"T f<>(T x){return x;}", "T f<T,>(T x){return x;}", "T f<T T>(T x){return x;}", "T f<T(T x){return x;}", "T f<T:Copy>(T x){return x;}", "class C{T f<T>(T x){return x;}}", "class C{init<T>(){}}", "struct S<>{}", "class C<T,>{}", "extern(C) T f<T>(T x);", "export(C) T f<T>(T x){return x;}", "int f(){return id<>(1);}", "int f(){return id<int,>(1);}", "int f(){return id<int bool>(1);}"}) {
		assert (parse (source).diagnostic != null);
	}
}
private void accepted_current_grammar() {
	assert (Parser.parse (new SourceFile.from_text ("accepted-current-grammar", "class C<T>{}")).diagnostic == null);
}
int main(string[] args) {
	Test.init (ref args);
	accepted_current_grammar ();
	Test.add_func ("/gen/parser/declarations", declarations);
	Test.add_func ("/gen/parser/vector-closes-and-nested-calls", closes);
	Test.add_func ("/gen/parser/relations-and-shifts", regressions);
	Test.add_func ("/gen/parser/malformed-deferred", malformed);
	return Test.run ();
}
}
