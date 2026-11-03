// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.OwnedFieldParser {
private void declarations() {
	foreach (var type in new string[] { "R", "int", "Child", "Pair", "void*", "f32<4>" }) {
		var result = Parser.parse (new SourceFile.from_text ("field", "class C { owned " + type + " field; }"));
		assert (result.diagnostic == null && result.unit.classes[0].fields[0].owned_keyword != null);
		assert (SyntaxDump.format (result.unit).contains ("owned-field"));
	}
	var record = Parser.parse (new SourceFile.from_text ("owning-record", "struct S { owned R field; } void f() { S s={field=move input}; S moved=move s; }"));
	assert (record.diagnostic == null && record.unit.structs[0].fields[0].owned_keyword != null);
	foreach (var source in new string[] { "struct S<T> { owned T field; }", "class C { owned R r; init(owned R r) { this.r = move this.r; } }", "void f() { release this.r; }", "void f() { release c.r; }" }) {
		assert (Parser.parse (new SourceFile.from_text ("invalid-field", source)).diagnostic != null);
	}
	assert (Parser.parse (new SourceFile.from_text ("transfer", "class C { owned R field; init(owned R r) { this.field = move r; } }")).diagnostic == null);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/parser/contracts-and-deferred-forms", declarations);
	return Test.run ();
}

}
