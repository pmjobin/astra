// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.ObjectOwnParser {
private void grammar() {
	var parsed = Parser.parse (new SourceFile.from_text ("own", "class C{}void f(owned C c){}void g(){owned C a=C.init(1);owned C b={};f(move a);f(null);}"));
	assert (parsed.diagnostic == null);
	assert (parsed.unit.functions[0].parameters[0].owned_keyword != null);
	var statements = parsed.unit.functions[1].body.statements;
	assert (((LocalDeclarationSyntax) statements[0]).owned_keyword != null && ((LocalDeclarationSyntax) statements[0]).initializer is ConstructorInitializerSyntax);
	assert (((StructLocalDeclarationSyntax) statements[1]).owned_keyword != null);
	assert (SyntaxDump.format (parsed.unit).contains ("transferable-owned"));
	// Parsing retains these forms for precise semantic fresh-only/result diagnostics.
	foreach (var text in new string[] { "owned C f(){return null;}", "void f(){owned C c=null;}", "void f(){owned C b=move a;}", "void f(){owned C b=a;}" }) {
		assert (Parser.parse (new SourceFile.from_text ("deferred", text)).diagnostic == null);
	}
}
private void malformed() {
	foreach (var text in new string[] { "void f(owned borrowed C c){}", "void f(borrowed owned C c){}", "void f(){owned C c;}", "void f(){owned C c=C.init(1)+1;}", "void f(){owned C c=move a.;}" }) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", text)).diagnostic != null);
	}
	// OWN-FIELD-1 retains the qualifier; exact ClassType eligibility rejects semantically.
	assert (Parser.parse (new SourceFile.from_text ("field", "class C{owned C field;}")).diagnostic == null);
}
private void accepted_current_grammar() {
	assert (Parser.parse (new SourceFile.from_text ("accepted-current-grammar", "void f(){owned C c=move a.x;}")).diagnostic == null);
}
int main(string[] args) {
	Test.init (ref args);
	accepted_current_grammar ();
	Test.add_func ("/obj-own/parser/fresh-constructor-brace-parameter-and-move", grammar);
	Test.add_func ("/obj-own/parser/invalid-qualifiers-and-construction", malformed);
	return Test.run ();
}
}
