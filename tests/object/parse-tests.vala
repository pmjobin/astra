// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.ObjectParser {
private void grammar() {
	var parsed = Parser.parse (new SourceFile.from_text ("object", "class C { int first; void set(int n) { this.first=n; this.later(); } int second; int later(){return this.first;} } class Empty {} int main(){C c={second=2,first=1};C alias=c;C nil=null;Empty e={};alias.set(40);return c.first;}"));
	assert (parsed.diagnostic == null && parsed.unit.structs.length == 0 && parsed.unit.classes.length == 2);
	var declaration = parsed.unit.classes[0];
	assert (declaration is ClassDeclarationSyntax && declaration.keyword.kind == TokenKind.CLASS);
	assert (declaration.fields.length == 2 && declaration.methods.length == 2 && declaration.members.length == 4);
	assert (declaration.members[0] == declaration.fields[0] && declaration.members[1] == declaration.methods[0] && declaration.members[2] == declaration.fields[1]);
	assert (parsed.unit.classes[1].members.length == 0);
	var construction = (StructLocalDeclarationSyntax) parsed.unit.functions[0].body.statements[0];
	assert (construction.initializer.fields[0].name.spelling () == "second");
	string dump = SyntaxDump.format (parsed.unit);
	assert (dump.contains ("(class \"C\"") && dump.contains ("(method") && dump.contains ("(method-call"));
}

private void deferred() {
	foreach (string source in new string[] {
			"class C { static int x; }", "class C { abstract int f(); }",
			"class C { public int x; }", "class C { private private int x; }", "class C { protected int x; }",
			"abstract class C {}", "sealed class C {}", "final class C {}", "class C { int x }",
			"class C { void f(); }", "class C { int this; }",
			"int main(){class C{}return 0;}",
			"class C{} int main(){C c={};c={};return 0;}", "class C{} int main(){C c={x=1,};return 0;}",
			"class C{} int main(){return {};}", "class C{} int main(){f({});return 0;}"
		}) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", source)).diagnostic != null);
	}
	// ERROR-1 now parses these contracts; missing base/owned/init premises
	// remain semantic obligations instead of parser restrictions.
	foreach (string source in new string[] {"class B:A{}", "class C{virtual int f(){return 1;}}", "class C{override int f(){return 1;}}", "class C{}int main(){C c=new C();return 0;}"}) {
		assert (Parser.parse (new SourceFile.from_text ("error-1", source)).diagnostic == null);
	}
	// Private field declarations are accepted; duplicate qualifiers remain invalid.
	assert (Parser.parse (new SourceFile.from_text ("private-field", "class C { private int x; }")).diagnostic == null);
	// OWN-FIELD-1 parses the qualifier and rejects non-Resource fields semantically.
	assert (Parser.parse (new SourceFile.from_text ("field", "class C { owned void* x; }")).diagnostic == null);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/object/parser/shared-members-construction-alias-null-empty", grammar);
	Test.add_func ("/object/parser/deferred-grammar", deferred);
	return Test.run ();
}

}
