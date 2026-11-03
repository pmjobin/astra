// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.ObjectBound {
private void contract() {
	var p = check ("class C{int x;void set(int n){this.x=n;}}void f(borrowed C c){C local=c;c.x=local.x;c.set(42);f(local);}void g(){C c={x=1};f(c);f(null);}");
	var type = p.classes[0].semantic_type;
	var parameter = p.functions[0].symbol.parameters[0];
	assert (parameter.semantic_type == type && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (type is ClassType && !(type is TypedPointerType) && type.is_nullable_pointer_value ());
	var body = p.functions[0].body;
	assert (((CheckedLocalDeclaration) body.statements[0]).initializer is CheckedParameterReferenceExpression);
	var field = (CheckedObjectFieldPlace) ((CheckedStore) body.statements[1]).target;
	assert (((CheckedParameterReferenceExpression) field.reference).parameter == parameter && field.traps_on_null && field.field == p.classes[0].fields[0]);
	var method = (CheckedCallStatement) body.statements[2];
	assert (method.target == p.classes[0].methods[0] && method.receiver is CheckedObjectReceiverExpression);
	foreach (int i in new int[] {1, 2}) {
		var call = (CheckedCallStatement) p.functions[1].body.statements[i];
		assert (call.target == p.functions[0].symbol && call.arguments.length == 1 && call.arguments[0].semantic_type == type);
	}
	assert (((CheckedCallStatement) p.functions[1].body.statements[2]).arguments[0] is CheckedNullPointerExpression);
	assert (SemanticDump.format (p).contains ("(contract borrowed-noescape)"));
}

private void callables() {
	var p = check ("class C{int x;init(borrowed C source){if(source==null){this.x=0;}else{this.x=source.x;}}int f(borrowed C other){if(other==null){return this.x;}other.x=this.x;return other.x;}}struct S{int marker;int f(borrowed C other){return other.x;}}");
	assert (p.classes[0].constructor.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (p.classes[0].methods[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (p.structs[0].methods[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (p.classes[0].methods[0].receiver.semantic_type.is_nonnull && p.classes[0].methods[0].parameters[0].semantic_type is ClassType);
	reject ("class C{bool f(borrowed C other){return this==other;}}", "nonnull, non-owning receiver");
	reject ("class C{}void f(borrowed C c){c=null;}", "assignment to parameter 'c' is not supported");
	reject ("class C{deinit(){}}void f(borrowed C c){c.deinit();}", "destructor deinit cannot be invoked explicitly");
}

private void exact_types() {
	reject ("class A{}class B{}void f(borrowed A a){}void g(borrowed B b){f(b);}", "expects type 'A', provided 'B'");
	reject ("class A{}class B{}bool f(borrowed A a,borrowed B b){return a==b;}", "matching non-void operands");
	foreach (var type in new string[] { "void*", "S*", "int*", "f32<4>*" }) {
		reject ("class C{}struct S{int x;}void f(borrowed C c){}void g(" + type + " p){f(p);}", "expects type 'C', provided '" + type + "'");
	}
	reject ("class C{int x;}struct S{int x;}void f(borrowed C c){}void g(){S s={x=1};f(s);}", "whole-struct values are not supported");
	reject ("class C{}void f(borrowed C c){}void g(){f(42);}", "expects type 'C', provided 'int'");
	reject ("class C{}void f(C* c){}", "ClassType*");
}

private void boundaries() {
	assert (check ("class C{}void f(C c){}").functions[0].symbol.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (check ("class C{}void f(owned C c){}").functions[0].symbol.parameters[0].pointer_contract == PointerParameterContract.OWNED_TRANSFER);
	foreach (var qualifier in new string[] { "", "owned " }) {
		reject ("class C{}" + qualifier + "C f(borrowed C c){return c;}", qualifier == "" ? "object-reference results are unsupported" : "fixed and borrowed references");
	}
	foreach (var declaration in new string[] { "extern(C) void f(borrowed C c);", "export(C) void f(borrowed C c){}", "extern(C) void f(C c);", "export(C) void f(C c){}" }) {
		reject ("class C{}" + declaration, "object-reference parameters are unsupported at C boundaries");
	}
	reject ("class C{}class Holder{C field;}", "field");
	reject ("class C{}void f(borrowed C c){C[1] a={c};}", "array");
	reject ("class C{}void f(borrowed C c){C[] a=null;}", "slice");
	reject ("class C{}void f(borrowed C c){C local=c;void* raw=local;}", "initializer");
	reject ("class C{}void raw(void* p){}void f(borrowed C c){C local=c;raw(local);}", "expects type 'void*', provided 'C'");
	reject ("class C{}void f(borrowed C c){C local=c;C* slot=&local;}", "ClassType*");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/semantic/exact-contract-null-fields-method-and-call-binding", contract);
	Test.add_func ("/obj-bound/semantic/shared-callables-immutable-bindings-and-distinct-receiver", callables);
	Test.add_func ("/obj-bound/semantic/nominal-class-struct-pointer-and-scalar-mismatches", exact_types);
	Test.add_func ("/obj-bound/semantic/no-owned-results-foreign-or-aggregate-escape", boundaries);
	return Test.run ();
}

}
