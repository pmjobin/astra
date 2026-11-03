// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.ParamBorrow {
private void contracts() {
	foreach (string name in fixtures ()) {
		assert (SemanticDump.format (fixture (name)) == SemanticDump.format (fixture (name, false)));
	}
	var p = check ("class C{}void plain(R r,C c,f64[] s){}void explicit(borrowed R r,borrowed C c,borrowed f64[] s){}void consuming(owned R r,owned C c,owned f64[] s){}");
	for (int i = 0; i < 3; i++) {
		var plain = p.functions[0].symbol.parameters[i];
		var explicit = p.functions[1].symbol.parameters[i];
		var owner = p.functions[2].symbol.parameters[i];
		assert (plain.semantic_type == explicit.semantic_type && plain.semantic_type == owner.semantic_type);
		assert (plain.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && explicit.pointer_contract == plain.pointer_contract);
		assert (owner.pointer_contract == PointerParameterContract.OWNED_TRANSFER);
	}
	assert (p.functions[0].locals.length == 0 && p.functions[1].locals.length == 0 && p.functions[2].locals.length == 3);
	assert (p.functions[0].symbol.parameters[0].semantic_type == p.handles[0].semantic_type);
	assert (p.functions[0].symbol.parameters[1].semantic_type == p.classes[0].semantic_type);
	assert (p.functions[0].symbol.parameters[2].semantic_type == p.types.slice_of (p.types.f64_type));
}

private void controls() {
	var p = check ("struct S{int x;}void values(bool b,int i,f32 f,f64 d,int<4> v,bool<4> m,S s,void* raw,int* ptr){}extern(C) void foreign_raw(R r);extern(C) void foreign_borrow(borrowed R r);export(C) void exported(void* p){}T copy<T>(T value){return value;}void consume<T>(owned T value) where T:Ownable{}");
	foreach (var parameter in p.functions[0].symbol.parameters) {
		assert (parameter.pointer_contract == PointerParameterContract.UNMANAGED);
	}
	assert (p.functions[0].symbol.parameters[6].struct_value_contract != null);
	int checked_foreign = 0;
	foreach (var function in p.c_functions) {
		if (function.name == "foreign_raw") {
			assert (function.parameters[0].pointer_contract == PointerParameterContract.UNMANAGED);
			checked_foreign++;
		}
		if (function.name == "foreign_borrow") {
			assert (function.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
			checked_foreign++;
		}
	}
	assert (checked_foreign == 2);
	assert (p.functions[1].symbol.parameters[0].pointer_contract == PointerParameterContract.UNMANAGED);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/param-borrow/semantic/exact-type-canonical-contract-and-no-owner", contracts);
	Test.add_func ("/param-borrow/semantic/value-struct-pointer-generic-and-foreign-controls", controls);
	return Test.run ();
}

}
