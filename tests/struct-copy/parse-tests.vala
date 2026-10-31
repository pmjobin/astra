// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Tests.StructCopyParser {
private void forms() {
	var parsed = Parser.parse (new SourceFile.from_text ("copy.astra", "void f(){S b=a;b=a;S c=outer.inner;outer.left=outer.right;root.a.b.left=root.c.d.right;S d=*p;*q=a;*q=*p;}"));
	assert (parsed.diagnostic == null);
	string dump = SyntaxDump.format (parsed.unit);
	assert (dump.contains ("(assign "));
}
private void malformed() {
	foreach (string body in new string[] {"S b=;", "b=;", "*p=;", "a.b=;", "a=b=c;", "S b=a", "a.b.c=;", "S b=move a.;"}) {
		var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", "void f(){" + body + "}"));
		assert (parsed.diagnostic != null);
	}
}
private void accepted_current_grammar() {
	assert (Parser.parse (new SourceFile.from_text ("accepted-current-grammar", "void f(){S b=move a;}")).diagnostic == null);
}
int main(string[] args) {
	Test.init (ref args);
	accepted_current_grammar ();
	Test.add_func ("/struct-copy/parser/existing-copy-forms-no-keyword", forms);
	Test.add_func ("/struct-copy/parser/malformed-assignment-regressions", malformed);
	return Test.run ();
}
}
