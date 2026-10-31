// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Tests.StructAbiParser {
private void forms() {
	foreach (string source in new string[] {"Pair identity(Pair value){return value;}", "Pair outer(){return inner();}", "void f(){Pair p=make();p=make();consume(make());}", "Box<int> f(Box<i32> value){return value;}", "struct S{int x;Pair method(Pair value){return value;}}", "void f(){Pair p=make().field;}"}) {
		var p = Parser.parse (new SourceFile.from_text ("boundary.astra", source));
		assert (p.diagnostic == null && SyntaxDump.format (p.unit).length > 0);
	}
}
private void bounded() {
	foreach (string source in new string[] {"Pair f(){return {x=1};}", "Pair f(Pair){}"}) {
		assert (Parser.parse (new SourceFile.from_text ("invalid.astra", source)).diagnostic != null);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-abi/parser/boundaries-and-four-call-consumers", forms);
	Test.add_func ("/struct-abi/parser/no-arbitrary-literals-or-unnamed-parameters", bounded);
	return Test.run ();
}
}
