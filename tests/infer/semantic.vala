// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.Infer {
private void exact_types() {
	foreach (string type in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32", "f32", "f64", "bool", "void*", "int*", "f64*", "int<4>", "f32<4>", "bool<4>"}) {
		var program = check ("void f(" + type + " source){var local=source;}");
		var function = program.functions[0];
		assert (function.locals[0].semantic_type == function.symbol.parameters[0].semantic_type);
		assert (!function.locals[0].is_owned);
	}
	var defaults = check ("void f(){var count=1;var a=1.0f;var b=1.0d;var c=1.0;var exact=1.0000000000000002d;var rounded=1.0000000000000002;var p=null;}");
	var locals = defaults.functions[0].locals;
	assert (locals[0].semantic_type == defaults.types.int_type && locals[0].semantic_type == defaults.types.i32_type);
	assert (locals[6].semantic_type == defaults.types.raw_pointer_type);
	uint64[] bits = {
		0x3f800000UL, 0x3ff0000000000000UL, 0x3f800000UL, 0x3ff0000000000001UL, 0x3f800000UL
	};
	for (int i = 1; i <= 5; i++) {
		var declaration = (CheckedLocalDeclaration) defaults.functions[0].body.statements[i];
		var value = (CheckedFloatExpression) declaration.initializer;
		assert (value.value.exact_bits == bits[i - 1]);
		assert (value.semantic_type == (i == 2 || i == 4 ? (SemanticType) defaults.types.f64_type : defaults.types.f32_type));
	}
	foreach (string suffix in new string[] {"f", "F", "d", "D"}) {
		var program = check ("void f(){var x=1.0000000000000002" + suffix + ";}");
		var value = (CheckedFloatExpression) ((CheckedLocalDeclaration) program.functions[0].body.statements[0]).initializer;
		assert (value.value.exact_bits == (suffix.down () == "d" ? 0x3ff0000000000001UL : 0x3f800000UL));
	}
}
private void contracts() {
	foreach (string name in fixtures ()) {
		var inferred = fixture (name);
		var explicit = fixture (name, false);
		assert (SemanticDump.format (inferred) == SemanticDump.format (explicit));
	}
	var buffer = check ("void f(){var samples=new f64[3];var moved=move samples;}");
	var first = buffer.functions[0].locals[0];
	var second = buffer.functions[0].locals[1];
	assert (first.semantic_type == buffer.types.slice_of (buffer.types.f64_type) && second.semantic_type == first.semantic_type);
	assert (first.is_buffer_owner && second.is_buffer_owner && first.cleanup == null);
	assert (buffer.functions[0].body.statements[0] is CheckedOwnedLocalDeclaration);
	assert (((CheckedOwnedLocalDeclaration) buffer.functions[0].body.statements[1]).initializer is CheckedOwnershipMove);
	var resource = check ("void f(){var first=resource(1);var next=move first;}");
	assert (resource.functions[0].locals[0].cleanup != null && resource.functions[0].locals[0].cleanup == resource.functions[0].locals[1].cleanup);
	var object = fixture ("object");
	CheckedFunction? main = null;
	foreach (var function in object.functions) {
		if (function.symbol.name == "main") {
			main = function;
		}
	}
	assert (main != null);
	assert (main.locals[0].object_owner != null);
	var initializer = (CheckedCallExpression) ((CheckedOwnedLocalDeclaration) main.body.statements[0]).initializer;
	assert (initializer.candidate_storage != null && initializer.candidate_storage.result_candidate);
	assert (main.locals[0].name_span.text () == "image" && main.locals[0].span.text ().has_prefix ("var image"));
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/infer/semantic/exact-identities-literal-bits-null", exact_types);
	Test.add_func ("/infer/semantic/explicit-equivalence-ownership-storage-provenance", contracts);
	return Test.run ();
}
}
