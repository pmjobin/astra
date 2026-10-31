// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Foreign;

namespace Astra.Tests.OwnedFieldSemantic {
private SourceSpan span(string text) {
	var file = new SourceFile.from_text ("resource-contract", text);
	return SourceSpan (file, 0, file.length);
}
private SemanticResult check(string source) {
	var resources = new GenericArray<ForeignHandleInput> ();
	resources.add (new ForeignHandleInput (span ("R"), span ("R"), new CForeignCleanupContract ("release_r")));
	resources.add (new ForeignHandleInput (span ("Other"), span ("Other"), new CForeignCleanupContract ("release_other")));
	var parsed = Parser.parse (new SourceFile.from_text ("field", source));
	assert (parsed.diagnostic == null);
	return SemanticAnalyzer.analyze (parsed.unit, null, resources);
}
private void valid() {
	var result = check ("void use(borrowed R r) {} owned R empty() { return null; } class C { owned R r; init(owned R incoming) { this.r = move incoming; use(this.r); } void replace(owned R next) { this.r = move next; } deinit() { this.r = empty(); use(this.r); } }");
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	var field = result.program.classes[0].fields[0];
	assert (field.ownership_kind == OwnershipKind.OWNED_FIELD && field.semantic_type == result.program.handles[0].semantic_type);
	assert (field.owned_cleanup == result.program.handles[0].cleanup && field.semantic_type is HandleType);
	foreach (var function in result.program.functions) {
		if (function is CheckedConstructor) {
			var transfer = (CheckedOwnedFieldTransfer) function.body.statements[0];
			assert (transfer.initializes && transfer.field == field && ((CheckedOwnershipMove) transfer.incoming).source.incoming_parameter == function.symbol.parameters[0]);
			assert (((CheckedConstructor) function).initialization.is_definite (0));
		}
		if (function is CheckedDestructor) {
			assert (!((CheckedOwnedFieldTransfer) function.body.statements[0]).initializes);
		}
	}
	assert (SemanticDump.format (result.program).contains ("owned-field-borrow"));
}
private void invalid() {
	assert (check ("class C { owned int[] field; init() { this.field = new int[2]; } }").diagnostic == null);
	foreach (var type in new string[] { "Child", "Pair", "int", "bool", "f32", "f64", "f32<4>", "void*", "int*", "int[2]" }) {
		var result = check ("class Child {} struct Pair { int x; } class C { owned " + type + " field; init() {} }");
		// Q08 already permits owned Class children; this constructor still
		// rejects because its required child slot has no initialization.
		string message = type == "Child" ? "not definitely initialized" : "owned fields require an exact nominal Resource";
		assert (result.diagnostic != null && result.diagnostic.message.contains (message));
	}
	string[] bodies = {
		"", "this.r = empty(); this.r = empty();", "use(this.r); this.r = empty();", "if (choose) { this.r = empty(); }", "this.r = null;", "this.r = wrong();"
	};
	string[] errors = {
		"not definitely initialized", "initialized twice", "read before definite initialization", "not definitely initialized", "exact Resource type", "exact Resource type"
	};
	for (int i = 0; i < bodies.length; i++) {
		var result = check ("void use(borrowed R r) {} owned R empty() { return null; } owned Other wrong() { return null; } class C { owned R r; init(bool choose) { " + bodies[i] + " } }");
		assert (result.diagnostic != null && result.diagnostic.message.contains (errors[i]));
	}
	assert (check ("class C { R r; }").diagnostic.message.contains ("resource-valued struct fields are unsupported"));
	assert (check ("struct S { R r; }").diagnostic.message.contains ("resource-valued struct fields are unsupported"));
	assert (check ("class C { owned R r; }").diagnostic.message.contains ("explicit constructor"));
	foreach (var body in new string[] { "R copy = this.r;", "return this.r;" }) {
		assert (check ("class C { owned R r; init(owned R r) { this.r = move r; } R escape() { " + body + " } }").diagnostic.message.contains ("copying and escaping"));
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/semantic/exact-contract-initialization-borrow-replacement", valid);
	Test.add_func ("/own-field/semantic/eligibility-definite-initialization-and-escape", invalid);
	return Test.run ();
}
}
