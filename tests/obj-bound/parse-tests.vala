// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.ObjectBoundParser {
private void grammar() {
	foreach (var qualifier in new string[] { "borrowed ", "owned ", "" }) {
		var result = Parser.parse (new SourceFile.from_text ("obj-bound", "class C{}void f(" + qualifier + "C c){}"));
		assert (result.diagnostic == null);
		var p = result.unit.functions[0].parameters[0];
		assert (p.type_name.spelling () == "C" && p.name.spelling () == "c");
		assert ((p.borrowed_keyword != null) == (qualifier == "borrowed ") && (p.owned_keyword != null) == (qualifier == "owned "));
	}
	var result = Parser.parse (new SourceFile.from_text ("obj-bound", "class C{init(borrowed C c){}void f(borrowed C c){}}struct S{void f(borrowed C c){}}"));
	assert (result.diagnostic == null);
	assert (SyntaxDump.format (result.unit).contains ("borrowed"));
}
private void malformed() {
	foreach (var parameter in new string[] { "borrowed borrowed C c", "owned borrowed C c", "borrowed owned C c", "borrowed C", "C borrowed c", "borrowed c", "borrowed" }) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", "void f(" + parameter + "){}")).diagnostic != null);
	}
	assert (Parser.parse (new SourceFile.from_text ("invalid", "borrowed C f(){return null;}")).diagnostic != null);
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/parser/shared-qualifiers-and-callables", grammar);
	Test.add_func ("/obj-bound/parser/malformed-qualifiers-and-borrowed-result", malformed);
	return Test.run ();
}
}
