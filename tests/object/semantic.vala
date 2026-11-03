// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;
using Astra.Syntax;
using Astra.Foreign;

namespace Astra.Tests.Objects {
private void identity() {
	var p = check ("struct S{int x;void f(){this.x=1;}}class A{int x;void f(){this.x=2;}}class B{int x;void f(){this.x=3;}}int main(){A a={x=40};A b=a;b.x=41;b.f();return a.x;}");
	var a = p.classes[0];
	var b = p.classes[1];
	var s = p.structs[0];
	assert (a.ordinal == 0 && b.ordinal == 1 && s.ordinal == 0);
	assert (a.semantic_type is ClassType && b.semantic_type is ClassType && s.semantic_type is StructType);
	assert (a.semantic_type != b.semantic_type && a.semantic_type != s.semantic_type && !(a.semantic_type is TypedPointerType));
	assert (!a.semantic_type.is_typed_data_pointee () && !a.semantic_type.is_typed_pointer () && a.semantic_type.is_nullable_pointer_value () && a.semantic_type.is_lexically_borrowed_value ());
	assert (a.methods[0] is MethodSymbol && a.methods[0].declaring_type == a && a.methods[0].declaring_struct == null);
	assert (a.methods[0] != s.methods[0] && a.methods[0] != b.methods[0]);
	assert (a.methods[0].receiver.semantic_type == a.receiver_type && a.receiver_type.instance_type == a.semantic_type && a.receiver_type.is_nonnull);
	var construction = (CheckedObjectConstruction) p.functions[0].body.statements[0];
	assert ((Object) construction.storage != (Object) construction.local);
	assert (construction.storage.object_class == a && construction.reference.semantic_type == a.semantic_type);
	assert (!construction.local.address_taken && !p.functions[0].locals[1].address_taken);
	var store = (CheckedStore) p.functions[0].body.statements[2];
	var field = (CheckedObjectFieldPlace) store.target;
	assert (field.field == a.fields[0] && field.traps_on_null && field.reference.semantic_type == a.semantic_type);
	var call = (CheckedCallStatement) p.functions[0].body.statements[3];
	assert (call.target == a.methods[0] && call.receiver is CheckedObjectReceiverExpression);
	var method = (CheckedMethod) p.functions[2];
	assert (((CheckedReceiverFieldPlace) ((CheckedStore) method.body.statements[0]).target).receiver is CheckedThisExpression && ((CheckedThisExpression) ((CheckedReceiverFieldPlace) ((CheckedStore) method.body.statements[0]).target).receiver).receiver == a.methods[0].receiver);
	string dump = SemanticDump.format (p);
	assert (dump.contains ("(class #0") && dump.contains ("object-storage") && dump.contains ("object-ref") && dump.contains ("object-field-place") && dump.contains ("null-traps-before-arguments"));
}

private void members() {
	reject ("class C { owned void* x; }", "owned fields require an exact nominal Resource");
	check ("class Empty{}class C{int a;i8 b;u8 c;i16 d;u16 e;u32 f;f32 g;bool h;void* p;}int main(){Empty e={};C c={p=null,h=true,g=1.0,f=1,e=1,d=1,c=1,b=1,a=1};return c.a;}");
	foreach (string source in new string[] {"class A{}class A{}", "class int{}", "class i32{}", "class bool{}", "class f32{}", "class void{}", "struct A{int x;}class A{}"}) {
		reject (source, "type");
	}
	reject ("class C{int x;int x;}", "duplicate field");
	reject ("class C{void f(){}void f(int n){}}", "duplicate method");
	reject ("class C{int f;void f(){}}", "collision");
	reject ("class C{void f(){}int f;}", "collision");
	foreach (string type in new string[] {"void", "C", "int*", "int<4>", "int[2]", "int[]"}) {
		reject ("class C{%s field;}".printf (type), "field");
	}
	reject ("class C{}struct S{C field;}", "object-reference fields");
}

private void construction() {
	var p = check ("class C{int a;int b;}int main(){C c={b=2,a=1};return c.a;}");
	var construction = (CheckedObjectConstruction) p.functions[0].body.statements[0];
	assert (construction.initializers[0].field == p.classes[0].fields[1] && construction.initializers[1].field == p.classes[0].fields[0]);
	reject ("class C{int x;}int main(){C c={};return 0;}", "missing initializer");
	reject ("class C{int x;}int main(){C c={x=1,x=2};return 0;}", "duplicate initializer");
	reject ("class C{void f(){}}int main(){C c={f=1};return 0;}", "unknown initializer field");
	reject ("class C{int x;}int main(){C c={x=c.x};return 0;}", "unknown name");
	reject ("class C{int x;}int main(){C c={x=true};return 0;}", "expects initializer");
}

private void references() {
	check ("class C{}int main(){C a={};C b=a;C c=null;b=c;c=a;if(a!=b&&a==c&&null!=a&&b==null){return 42;}return 1;}");
	reject ("class A{}class B{}int main(){A a={};B b={};a=b;return 0;}", "type 'A'");
	reject ("class A{}class B{}int main(){A a={};B b={};bool same=a==b;return 0;}", "matching non-void operands");
	reject ("class C{}int main(){C c={};if(c){return 1;}return 0;}", "bool");
	foreach (string op in new string[] {"<", "<=", ">", ">=", "+", "-", "*", "/", "%", "&", "|", "^", "<<", ">>"}) {
		reject ("class C{}int main(){C a={};C b={};bool result=a%s b;return 0;}".printf (op), op == "<<" || op == ">>" ? "shift requires an integer" : "operator");
	}
	foreach (string type in new string[] {"void*", "int*"}) {
		reject ("class C{}int main(){C c={};%s p=c;return 0;}".printf (type), "initializer");
		reject ("class C{}int main(){%s p=null;C c=p;return 0;}".printf (type), "initializer");
	}
	reject ("class C{}int main(){C* p=null;return 0;}", "ClassType*");
	reject ("class C{}int main(){C c={};int x=c as int;return 0;}", "integer");
	reject ("class C{}int main(){C c={};bool x=!c;return 0;}", "bool");
}

private void boundaries() {
	assert (check ("class C{}void f(C c){}").functions[0].symbol.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	check ("class C{}void f(borrowed C c){}");
	reject ("class C{}C f(){return null;}", "object-reference results");
	assert (check ("class C{void f(C c){}}").classes[0].methods[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	reject ("class C{C f(){return null;}}", "object-reference results");
	reject ("class C{}extern(C) C f();", "object-reference results");
	reject ("class C{}extern(C) void f(C c);", "object-reference parameters");
	reject ("class C{}export(C) void f(C c){}", "object-reference parameters");
	reject ("class C{}int main(){owned C c=null;return 0;}", "owned");
	reject ("class C{}int main(){C[2] values={null,null};return 0;}", "array");
	reject ("class C{}int main(){C[] values=null;return 0;}", "slice");
	reject ("class C{void f(){this=null;}}", "cannot be rebound");
	reject ("class C{void f(){C alias=this;}}", "nonnull, non-owning receiver");
}

private void foreign_boundaries() {
	var handle_span = SourceSpan (new SourceFile.from_text ("handle", "Resource"), 0, 8);
	var handles = new GenericArray<ForeignHandleInput> ();
	handles.add (new ForeignHandleInput (handle_span, handle_span, new CForeignCleanupContract ("destroy_resource")));
	foreach (string source in new string[] {"class Resource{}", "class C{Resource field;}"}) {
		var result = SemanticAnalyzer.analyze (Parser.parse (new SourceFile.from_text ("object", source)).unit, null, handles);
		assert (result.program == null && result.diagnostic != null);
		assert (result.diagnostic.message.contains (source.has_prefix ("class Resource") ? "imported handle type" : "field"));
	}
	var span = SourceSpan (new SourceFile.from_text ("foreign", "f"), 0, 1);
	for (int variant = 0; variant < 2; variant++) {
		var parameters = new GenericArray<ForeignParameterInput> ();
		if (variant == 1) {
			parameters.add (new ForeignParameterInput (span, span, span, "C"));
		}
		var declarations = new GenericArray<ForeignDeclarationInput> ();
		declarations.add (new ForeignDeclarationInput (span, span, span, parameters, null, variant == 0 ? "C" : "void"));
		var result = SemanticAnalyzer.analyze (Parser.parse (new SourceFile.from_text ("object", "class C{}")).unit, declarations);
		assert (result.program == null && result.diagnostic != null && result.diagnostic.message.contains (variant == 0 ? "C result type" : "C parameter type"));
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/object/semantic/nominal-identity-receiver-storage-and-places", identity);
	Test.add_func ("/object/semantic/member-namespace-and-field-authority", members);
	Test.add_func ("/object/semantic/complete-ordered-invisible-construction", construction);
	Test.add_func ("/object/semantic/reference-operations-and-diagnostics", references);
	Test.add_func ("/object/semantic/deferred-boundaries-and-receiver-rebinding", boundaries);
	Test.add_func ("/object/semantic/handle-collisions-fields-and-normalized-foreign-boundaries", foreign_boundaries);
	return Test.run ();
}

}
