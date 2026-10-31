// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Tests.GenCapParser {
private ParseResult parse(string source) {
	return Parser.parse (new SourceFile.from_text ("capability.astra", source));
}
private void clauses() {
	var result = parse ("T choose<T,U>(T a,T b,U token) where U : Eq where T : Ordered, Numeric {return a;}");
	assert (result.diagnostic == null);
	var clauses = result.unit.functions[0].where_clauses;
	assert (clauses.length == 2 && clauses[0].type_parameter.spelling () == "U" && clauses[1].capabilities.length == 2);
	assert (clauses[1].capabilities[0].span.text () == "Ordered" && clauses[1].commas.length == 1);
	assert (SyntaxDump.format (result.unit).contains ("(where T Ordered Numeric)"));
	assert (parse ("int where(int Eq){return Eq;}").diagnostic == null);
}
private void malformed() {
	foreach (string clause in new string[] {"where", "where : Eq", "where T Eq", "where T :", "where T : Eq,", "where T : Eq Ordered", "where T : Eq where T : Ordered", "where T : Eq, Eq"}) {
		assert (parse ("T f<T>(T a) " + clause + " {return a;}").diagnostic != null);
	}
	assert (parse ("int f() where T : Eq {return 1;}").diagnostic != null);
	assert (parse ("class C{int f() where T : Eq {return 1;}}").diagnostic != null);
	var duplicate = parse ("T f<T>(T a) where T : Eq where T : Ordered {return a;}");
	assert (duplicate.diagnostic.message.contains ("duplicate where clause"));
	assert (parse ("T f<T>(T a) where T : Eq, Eq {return a;}").diagnostic.message.contains ("duplicate capability"));
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-cap/parser/ordered-clauses-contextual-keyword", clauses);
	Test.add_func ("/gen-cap/parser/malformed-duplicate-deferred", malformed);
	return Test.run ();
}
}
