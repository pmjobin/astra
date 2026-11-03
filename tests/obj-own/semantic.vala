// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.ObjectOwn {
private void contracts() {
	var p = check ("class C{int x;deinit(){}}void sink(owned C c){}void f(){owned C c={x=42};sink(move c);}");
	var c = p.classes[0];
	var f = p.functions[1];
	var construction = (CheckedObjectConstruction) f.body.statements[0];
	var owner = f.locals[0];
	assert (owner.object_owner == c && owner.semantic_type == c.semantic_type && owner.semantic_type is ClassType);
	assert (owner.ownership_kind == OwnershipKind.TRANSFERABLE_OBJECT_OWNER && owner.cleanup == null && owner.is_owned);
	assert (owner.object_storage == construction.storage && construction.storage.destructor == c.destructor);
	var argument = (CheckedOwnedArgument) ((CheckedCallStatement) f.body.statements[1]).arguments[0];
	assert (argument.parameter == p.functions[0].symbol.parameters[0] && argument.object_owner == c && argument.cleanup == null);
	assert (argument.ownership_kind == OwnershipKind.TRANSFERABLE_OBJECT_OWNER);
	assert (argument.transfer.source == owner && argument.transfer.object_storage == construction.storage && argument.transfer.ownership_kind == OwnershipKind.TRANSFERABLE_OBJECT_OWNER);
	var parameter_owner = p.functions[0].locals[0];
	assert (parameter_owner.incoming_parameter == argument.parameter && parameter_owner.object_storage == null && parameter_owner.object_owner == c);
	assert (argument.parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && argument.parameter.semantic_type.is_nullable_pointer_value ());
	assert (SemanticDump.format (p).contains ("(domain object) (class #0) (storage #0)"));
}

private void uses() {
	check ("class C{int x;init(int n){this.x=n;}void add(int n){this.x=this.x+n;}}void inspect(borrowed C c){c.x=c.x+1;}void sink(owned C c){if(c!=null){inspect(c);c.add(1);}}void f(){owned C c=C.init(40);inspect(c);c.x=c.x+1;c.add(1);sink(move c);sink(null);}");
	check ("class C{int x;}void f(){C c={x=1};C alias=c;c=null;alias.x=42;alias=null;}");
	check ("class C{}void sink(owned C c){}void forward(owned C c){sink(move c);}");
	check ("class C{}class D{init(owned C source){}void f(owned C other){}}struct S{int marker;void f(owned C other){}}");
}

private void restrictions() {
	reject ("class C{owned C field;}", "requires an explicit constructor and definite initialization");
	reject ("class C{int x;}void f(){owned C a={x=1};owned C c=move a.x;}", "moving ownership out of an owned field");
	foreach (var initializer in new string[] { "null", "a", "move a" }) {
		reject ("class C{}void f(){owned C a={};owned C b=" + initializer + ";}", "requires fresh object construction");
	}
	reject ("class C{init(){}}void f(){owned C c={};}", "cannot bypass its constructor");
	reject ("class C{}void f(){owned C c={};c=null;}", "cannot be rebound");
	reject ("class C{}void f(owned C c){c=null;}", "cannot be rebound");
	reject ("class C{}void f(){owned C c={};C alias=c;}", "persistent alias");
	reject ("class C{}void f(owned C c){C alias=c;}", "persistent alias");
	reject ("class C{}void f(){owned C c={};C alias=null;alias=c;}", "persistent alias");
	reject ("class C{}void sink(owned C c){}void f(){C c={};sink(move c);}", "requires an owned ClassType binding");
	reject ("class C{}void sink(owned C c){}void f(borrowed C c){sink(move c);}", "requires an owned ClassType binding");
	reject ("class C{}void sink(owned C c){}void f(){owned C c={};sink(c);}", "requires explicit 'move owner' or null");
	reject ("class C{}void sink(owned C a,owned C b){}void f(){owned C c={};sink(move c,move c);}", "use of moved owned value 'c'");
	reject ("class A{}class B{}void sink(owned B b){}void f(){owned A a={};sink(move a);}", "requires exact type 'B'");
	check ("class C{}owned C f(){return null;}");
	reject ("class C{}C f(){return null;}", "object-reference results are unsupported");
	reject ("class C{}void f(){owned C c={};release c;}", "release operand");
	foreach (var boundary in new string[] { "extern(C) void f(owned C c);", "export(C) void f(owned C c){}" }) {
		reject ("class C{}" + boundary, "unsupported at C boundaries");
	}
}

private void receivers() {
	reject ("class C{void f(owned C c){}}void g(){owned C c={};c.f(move c);}", "method receiver cannot consume the same");
	reject ("class C{void f(int n){}}int sink(owned C c){return 1;}void g(){owned C c={};c.f(sink(move c));}", "method receiver cannot consume the same");
	check ("class C{void f(owned C c){}}void g(){owned C a={};owned C b={};a.f(move b);}");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-own/semantic/exact-binding-storage-cleanup-and-generic-move", contracts);
	Test.add_func ("/obj-own/semantic/temporary-use-and-fixed-object-regression", uses);
	Test.add_func ("/obj-own/semantic/fresh-only-no-alias-rebind-result-or-foreign", restrictions);
	Test.add_func ("/obj-own/semantic/receiver-consumption-direct-and-nested", receivers);
	return Test.run ();
}

}
