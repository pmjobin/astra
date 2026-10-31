// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
namespace Astra.Tests.GenOwnParser {
private ParseResult parse(string text) {
	return Parser.parse (new SourceFile.from_text ("ownership.astra", text));
}
private void contracts() {
	var result = parse ("owned T relay<T>(owned T value) where T : Ownable {return move value;}");
	assert (result.diagnostic == null);
	var function = result.unit.functions[0];
	assert (function.owned_keyword != null && function.parameters[0].owned_keyword != null && function.return_type.spelling () == "T");
	assert (function.where_clauses[0].capabilities[0].spelling () == "Ownable");
	assert (((ReturnStatementSyntax) function.body.statements[0]).expression is MoveExpressionSyntax);
	assert (SyntaxDump.format (result.unit).contains ("(where T Ownable)"));
	assert (parse ("U keep<T,U>(owned T owner,U value) where T : Ownable where U : Numeric {return value;}").diagnostic == null);
}
private void malformed() {
	foreach (string text in new string[] {"owned relay<T>(owned T v) where T : Ownable {}", "owned T relay<T>(owned value) where T : Ownable {}", "void drop<T>(owned T v) where T Ownable {}", "void drop<T>(owned T v) where T : Ownable, {}", "void drop<T>(owned T v) where T : Ownable, Ownable {}", "owned T relay<T>(owned T v) where T : Ownable {return move;}"}) {
		assert (parse (text).diagnostic != null);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/parser/contracts-move-where", contracts);
	Test.add_func ("/gen-own/parser/malformed-duplicates", malformed);
	return Test.run ();
}
}
