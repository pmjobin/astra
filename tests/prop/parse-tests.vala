// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.PropParser {
private void declarations() {
	var text = "struct S{int raw;property int value{get{return this.raw;}set(int next){this.raw=next;}}}class C{property f64 gain{get{return 1.25;}}}int main(){S s={raw=1};s.value=42;return s.value;}";
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("property", text));
	assert (parsed.diagnostic == null);
	assert (parsed.unit.structs[0].fields.length == 1 && parsed.unit.structs[0].methods.length == 0);
	var property = parsed.unit.structs[0].members[1] as PropertyDeclarationSyntax;
	assert (property != null && property.name.spelling () == "value" && property.getter.parameter == null);
	assert (property.setter.parameter.name.spelling () == "next" && property.setter.parameter.type_name.spelling () == "int");
	assert (((PropertyDeclarationSyntax) parsed.unit.classes[0].members[0]).setter == null);
	assert (parsed.unit.functions[0].body.statements[1] is FieldAssignmentStatementSyntax);
	assert (((ReturnStatementSyntax) parsed.unit.functions[0].body.statements[2]).expression is FieldAccessExpressionSyntax);
	assert (SyntaxDump.format (parsed.unit).contains ("(property (type \"f64\")"));
	var witness = WeakRef (property);
	property = null;
	parsed = null;
	assert (witness.get () == null);
}

private void malformed() {
	foreach (string declaration in new string[] {
			"property int p{set(int n){}get{}}", "property int p{}", "property int p{set(int next){}}", "property int p{get{}get{}}", "property int p{get{}set(int n){}set(int n){}}",
			"property int p{get;set;}", "property int p=3;", "property int p{get() {}}", "property int p{get(int n){}}",
			"property int p{get{}set{}}", "property int p{get{}set(){}}", "property int p{get{}set(int){}}", "property int p{get{}set(int n,int m){}}",
			"property int p[int i]{get{}}", "property int p(int i){get{}}", "static property int p{get{}}",
			"property owned owned C p{get{}}", "property borrowed C p{get{}}", "property int p{get{}set(owned int n){}}", "property int p{get{}set(borrowed int n){}}"
		}) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", "class C{" + declaration + "}")).diagnostic != null);
	}
	foreach (string statement in new string[] {"c.p+=1;", "c.p++;", "int* p=&c.p;"}) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", "class C{property int p{get{return 1;}}}void f(){C c={};" + statement + "}")).diagnostic != null);
	}
	// Shared nested member-call grammar; semantic integer-property refusals
	// and typed Class counterparts live in historical-observations.
	foreach (string statement in new string[] {"c.p.get();", "c.p.set(1);"}) {
		assert (Parser.parse (new SourceFile.from_text ("accepted", "class C{property int p{get{return 1;}}}void f(){C c={};" + statement + "}")).diagnostic == null);
	}
	assert (Parser.parse (new SourceFile.from_text ("error-1", "class C{virtual property int p{get{return 1;}}}")).diagnostic == null);
	// Field-index assignment syntax is shared with owned buffers; property
	// eligibility is still rejected by the semantic property tests.
	assert (Parser.parse (new SourceFile.from_text ("property-index", "class C{property int p{get{return 1;}}}void f(){C c={};c.p[0]=1;}")).diagnostic == null);
}

private void accepted_current_grammar() {
	assert (Parser.parse (new SourceFile.from_text ("accepted-current-grammar", "class C{property owned C p{get{}}}")).diagnostic == null);
}

int main(string[] args) {
	Test.init (ref args);
	accepted_current_grammar ();
	Test.add_func ("/prop/parser/declarations-explicit-parameter-read-write-and-lifetime", declarations);
	Test.add_func ("/prop/parser/malformed-and-deferred-grammar", malformed);
	return Test.run ();
}

}
