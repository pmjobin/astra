// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.ObjectResultParser {
private void grammar() {
	var parsed = Parser.parse (new SourceFile.from_text ("result", "owned C make(){return C.init(42);}owned C identity(owned C c){return move c;}owned C absent(){return null;}void f(){owned C c=make();}"));
	assert (parsed.diagnostic == null);
	assert (parsed.unit.functions[0].owned_keyword != null && parsed.unit.functions[0].return_type.spelling () == "C");
	assert (((ReturnStatementSyntax) parsed.unit.functions[0].body.statements[0]).expression is CallExpressionSyntax);
	assert (((ReturnStatementSyntax) parsed.unit.functions[1].body.statements[0]).expression is MoveExpressionSyntax);
	assert (((ReturnStatementSyntax) parsed.unit.functions[2].body.statements[0]).expression is NullPointerExpressionSyntax);
	assert (((LocalDeclarationSyntax) parsed.unit.functions[3].body.statements[0]).owned_keyword != null);
}

private void restrictions() {
	foreach (var source in new string[] { "borrowed C f(){return null;}", "owned borrowed C f(){}", "owned C f(){return move c.;}", "owned C f(){return C{x=1};}", "void f(){make().method();}" }) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", source)).diagnostic != null);
	}
}

private void accepted_current_grammar() {
	assert (Parser.parse (new SourceFile.from_text ("accepted-current-grammar", "owned C f(){return move c.field;}")).diagnostic == null);
}

int main(string[] args) {
	Test.init (ref args);
	accepted_current_grammar ();
	Test.add_func ("/obj-ret/parser/result-context-grammar", grammar);
	Test.add_func ("/obj-ret/parser/qualifiers-and-deferred-grammar", restrictions);
	return Test.run ();
}

}
