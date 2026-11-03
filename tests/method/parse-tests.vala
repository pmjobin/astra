// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.MethodParser {
private void members() {
	var source = new SourceFile.from_text ("method", "struct S { int first; void set(int value) { this.first = value; this.later(); } int second; int later() { return this.first; } } int main() { S s = { first = 1, second = 2 }; s.set(40); return s.later(); }");
	ParseResult? result = Parser.parse (source);
	assert (result.diagnostic == null);
	var structure = result.unit.structs[0];
	assert (structure.fields.length == 2 && structure.methods.length == 2 && structure.members.length == 4);
	assert (structure.members[0] == structure.fields[0] && structure.members[1] == structure.methods[0] && structure.members[2] == structure.fields[1]);
	var assignment = (FieldAssignmentStatementSyntax) structure.methods[0].body.statements[0];
	assert (assignment.target.identifier.kind == TokenKind.THIS);
	var call = ((CallStatementSyntax) structure.methods[0].body.statements[1]).call;
	assert (call.receiver.kind == TokenKind.THIS && call.member_operator.kind == TokenKind.DOT && call.identifier.spelling () == "later");
	string dump = SyntaxDump.format (result.unit);
	assert (dump.contains ("(method") && dump.contains ("(method-call"));
	assert (dump == SyntaxDump.format (Parser.parse (source).unit));
	var witness = WeakRef (call);
	assignment = null;
	call = null;
	structure = null;
	result = null;
	assert (witness.get () == null);
}

private void malformed() {
	foreach (string text in new string[] {
			"struct S { int x; void f( {} }", "struct S { int x; void f() ; }",
			"struct S { int x; static void f() {} }", "struct S { int this; }",
			"struct S { int x; void f(int this) {} }", "struct S { int x; void f(S* this) {} }",
			"struct S { int x; void f() {} } int main(){ S s={x=0}; s.f(,); return 0; }",
			"struct S { int x; void f() {} } int main(){ S s={x=0}; (s).f(); return 0; }"
		}) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", text)).diagnostic != null);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/method/parser/mixed-members-this-calls-and-lifetime", members);
	Test.add_func ("/method/parser/malformed-and-deferred-grammar", malformed);
	return Test.run ();
}

}
