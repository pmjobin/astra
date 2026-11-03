// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Foreign;

namespace Astra.Tests.OwnboundSemantic {
private SourceSpan span(string text) {
	var file = new SourceFile.from_text ("boundary-input", text);
	return SourceSpan (file, 0, file.length);
}

private SemanticResult analyze(string text) {
	var handles = new GenericArray<ForeignHandleInput> ();
	handles.add (new ForeignHandleInput (span ("Resource"), span ("Resource"), new CForeignCleanupContract ("destroy")));
	handles.add (new ForeignHandleInput (span ("Other"), span ("Other"), new CForeignCleanupContract ("destroy")));
	var parsed = Parser.parse (new SourceFile.from_text ("boundary.astra", text));
	assert (parsed.diagnostic == null);
	return SemanticAnalyzer.analyze (parsed.unit, null, handles);
}

private void exact() {
	var result = analyze ("owned Resource pass(owned Resource r) { return move r; } void f() { owned Resource r = pass(null); pass(move r); }");
	assert (result.diagnostic.message.contains ("ownership responsibility"));
	result = analyze ("owned Resource pass(owned Resource r) { return move r; } void f() { owned Resource r = pass(null); owned Resource b = pass(move r); }");
	assert (result.diagnostic == null);
	var function = result.program.functions[0];
	assert (function.symbol.parameters[0].pointer_contract == PointerParameterContract.OWNED_TRANSFER);
	assert (function.symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER);
	assert (function.symbol.return_type == result.program.handles[0].semantic_type);
	assert (function.locals[0].incoming_parameter == function.symbol.parameters[0]);
	assert (function.locals[0].cleanup == function.symbol.owned_cleanup);
	assert (function.body.statements[0] is CheckedOwnershipReturn);
	assert (SemanticDump.format (result.program).contains ("owned-transfer-argument"));
}

private void invalid() {
	foreach (string type in new string[] {"void*", "int", "bool", "Pair", "Pair*"}) {
		assert (analyze ("struct Pair { int n; } owned " + type + " f() { return null; }").diagnostic.message.contains ("nominal handle"));
		assert (analyze ("struct Pair { int n; } void f(owned " + type + " r) { }").diagnostic.message.contains ("nominal handle"));
	}
	assert (analyze ("owned Resource f(owned Other r) { return move r; }").diagnostic.message.contains ("exact type 'Resource'"));
	assert (analyze ("void consume(owned Resource r) { } void f(borrowed Resource r) { consume(r); }").diagnostic.message.contains ("carry no transferable responsibility"));
	assert (analyze ("owned Resource f(owned Resource r) { return r; }").diagnostic.message.contains ("return move owner"));
}

private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ownbound/semantic/standalone-contracts", exact);
	Test.add_func ("/ownbound/semantic/standalone-rejections", invalid);
	return Test.run ();
}

}
