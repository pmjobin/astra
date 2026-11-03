// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Tests.StructAggParser {
private void syntax() {
	var parsed = Parser.parse (new SourceFile.from_text ("nested.astra", "struct I { int x; i16<8> v; } struct O { I inner; } int f(){ O o={inner={x=1,v=splat(0,8)}}; o.inner.x=2; return o.inner.x; }"));
	assert (parsed.diagnostic == null);
	var declaration = (StructLocalDeclarationSyntax) parsed.unit.functions[0].body.statements[0];
	assert (declaration.initializer.fields[0].initializer.fields.length == 2);
	var store = (FieldAssignmentStatementSyntax) parsed.unit.functions[0].body.statements[1];
	assert (store.target.aggregate is FieldAccessExpressionSyntax && ((FieldAccessExpressionSyntax) store.target.aggregate).field_name.spelling () == "inner" && store.target.field_name.spelling () == "x");
	assert (SyntaxDump.format (parsed.unit).contains ("storage-initializer"));
}

private void malformed() {
	foreach (string source in new string[] {"int f(){O o={inner={x=1,}};}", "int f(){O o={inner={x=}};}", "int f(){O o={inner={x=1};}", "int f(){return o.inner.;}"}) {
		assert (Parser.parse (new SourceFile.from_text ("bad.astra", source)).diagnostic != null);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-agg/parser/recursive-storage-syntax", syntax);
	Test.add_func ("/struct-agg/parser/malformed", malformed);
	return Test.run ();
}

}
