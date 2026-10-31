// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Tests.GenStructParser {
private ParseResult parse(string text) {
	return Parser.parse (new SourceFile.from_text ("generic-struct.astra", text));
}
private void declarations() {
	var result = parse ("struct Pair<T,U>{T first;U second;}struct Quad<A,B,C,D>{A a;B b;C c;D d;}struct Bundle<T>{Pair<T,T> pair;int tag;}");
	assert (result.diagnostic == null && result.unit.structs.length == 3 && result.unit.native_instances (false).length == 0);
	assert (result.unit.structs[0].type_parameters.length == 2 && result.unit.structs[1].type_parameters.length == 4);
	var application = result.unit.structs[2].fields[0].type_name as GenericTypeApplicationSyntax;
	assert (application != null && application.type_arguments.length == 2 && application.spelling () == "Pair<T,T>");
	assert (SyntaxDump.format (result.unit).contains ("(type-parameters A B C D)"));
	// The accepted grammar now parses this; nonempty storage is checked semantically.
	assert (parse ("struct S<T>{}").diagnostic == null);
}
private void applications() {
	foreach (string type in new string[] {"Box<i16<8>>", "Pair<i16<8>,bool<4>>", "Bundle<i16<8>>", "Box<Pair<int,int>>", "Box<i16<8>>*", "Pair<int,f64>*", "Box<int[]>"}) {
		var result = parse ("void f(){" + type + " value={value=x};}");
		assert (result.diagnostic == null);
		var declaration = (StructLocalDeclarationSyntax) result.unit.functions[0].body.statements[0];
		assert (declaration.type_name.spelling () == type);
	}
	foreach (string expression in new string[] {"x >> y", "x << y", "a < b >> c", "a as i16<8> == b"}) {
		var result = parse ("int f(){return " + expression + ";}");
		assert (result.diagnostic == null && !(((ReturnStatementSyntax) result.unit.functions[0].body.statements[0]).expression is CallExpressionSyntax));
	}
	assert (parse ("int f(){return identity<Box<i16<8>>>(x);}").diagnostic == null);
	foreach (string type in new string[] {"i8<n>", "i8<-4>", "i8<4.0>", "Box*<int>"}) {
		assert (parse ("void f(" + type + " value){}").diagnostic.message.contains ("lane count must be"));
	}
}
private void malformed() {
	foreach (string source in new string[] {"struct Bad<>{int x;}", "struct Bad<T,>{T x;}", "struct Bad<T U>{T x;}", "struct Bad<T>{T f(){return x;}}", "struct Bad<T>{property T p{get{return x;}}}", "struct Bad<T> where T:Eq {T x;}", "class Bad<T,>{T x;}", "struct Bad<T>{owned T value;}", "struct Bad<T>{borrowed T value;}", "struct Bad<T>{init(){}}", "void f(){Box<> b={value=1};}", "void f(){Pair<int,> b={first=1};}", "void f(){Pair<int f64> b={first=1};}", "void f(){Pair<int,f64 b={first=1};}"}) {
		assert (parse (source).diagnostic != null);
	}
	var nested = new StringBuilder ("void f(){");
	for (int i = 0; i < 300; i++) {
		nested.append ("Box<");
	}
	nested.append ("int");
	for (int i = 0; i < 300; i++) {
		nested.append (">");
	}
	nested.append (" b={value=1};}");
	assert (parse (nested.str).diagnostic != null);
}
private void accepted_current_grammar() {
	assert (Parser.parse (new SourceFile.from_text ("accepted-current-grammar", "class Bad<T>{T x;}")).diagnostic == null);
}
int main(string[] args) {
	Test.init (ref args);
	accepted_current_grammar ();
	Test.add_func ("/gen-struct/parser/declarations-and-parameters", declarations);
	Test.add_func ("/gen-struct/parser/applications-vector-closes-shifts", applications);
	Test.add_func ("/gen-struct/parser/malformed-and-deferred-members", malformed);
	return Test.run ();
}
}
