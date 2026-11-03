// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Foreign;

namespace Astra.Tests.ResourceSemantic {
private SourceSpan span(string spelling) {
	var file = new SourceFile.from_text ("foreign-input", spelling);
	return SourceSpan (file, 0, file.length);
}

private GenericArray<ForeignHandleInput> handles() {
	var result = new GenericArray<ForeignHandleInput> ();
	result.add (new ForeignHandleInput (span ("Resource"), span ("Resource"), new CForeignCleanupContract ("destroy"), new CForeignHeader ("nonexistent.h")));
	result.add (new ForeignHandleInput (span ("Other"), span ("Other"), new CForeignCleanupContract ("destroy")));
	return result;
}

private void nominal() {
	var inputs = new GenericArray<ForeignDeclarationInput> ();
	inputs.add (new ForeignDeclarationInput (span ("create"), span ("create"), span ("Resource"), new GenericArray<ForeignParameterInput> (), null, "Resource", true));
	var parsed = Parser.parse (new SourceFile.from_text ("native.astra", "Resource empty(Resource r) { return null; } void f() { owned Resource r = create(); }"));
	var result = SemanticAnalyzer.analyze (parsed.unit, inputs, handles ());
	assert (result.diagnostic == null);
	var a = result.program.handles[0];
	var b = result.program.handles[1];
	assert (a.semantic_type != b.semantic_type && a.cleanup == b.cleanup);
	assert (a.semantic_type.is_ownable_handle_type () && !a.semantic_type.is_void_pointer ());
	assert (a.header.name == "nonexistent.h" && a.ordinal == 0 && b.ordinal == 1);
	assert (result.program.c_functions[0].metadata.owned_result.cleanup == a.cleanup);
	assert (result.program.functions[0].symbol.return_type == a.semantic_type);
	assert (result.program.functions[0].symbol.parameters[0].semantic_type == a.semantic_type && result.program.functions[0].symbol.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (result.program.functions[1].locals[0].cleanup == a.cleanup);
}

private void invalid() {
	foreach (string name in new string[] {"Resource", "int", "bool", "void"}) {
		var inputs = handles ();
		inputs.add (new ForeignHandleInput (span (name), span (name), new CForeignCleanupContract ("destroy")));
		var result = SemanticAnalyzer.analyze (Parser.parse (new SourceFile.from_text ("empty.astra", "")).unit, null, inputs);
		assert (result.program == null && result.diagnostic.message.contains ("conflicts with an existing type"));
	}
	var inputs = handles ();
	inputs.add (new ForeignHandleInput (span ("Empty"), span ("Empty"), new CForeignCleanupContract ("")));
	assert (SemanticAnalyzer.analyze (Parser.parse (new SourceFile.from_text ("empty.astra", "")).unit, null, inputs).diagnostic.message.contains ("nonempty"));
	assert (SemanticAnalyzer.analyze (Parser.parse (new SourceFile.from_text ("collision.astra", "struct Resource { int x; }")).unit, null, handles ()).diagnostic.message.contains ("conflicts with imported handle"));
}

private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/resource/semantic/nominal-contract-input", nominal);
	Test.add_func ("/resource/semantic/namespace-and-cleanup-rejections", invalid);
	return Test.run ();
}

}
