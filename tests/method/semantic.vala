// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.MethodSemantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("method", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private void reject(string text, string message) {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid", text));
	if (parsed.diagnostic != null) {
		assert (parsed.diagnostic.message.contains (message));
		return;
	}
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic == null || !result.diagnostic.message.contains (message)) {
		GLib.error ("expected %s for %s, got %s", message, text, result.diagnostic == null ? "accepted" : result.diagnostic.format ());
	}
	assert (result.diagnostic.format () == SemanticAnalyzer.analyze (parsed.unit).diagnostic.format ());
}
private void identity() {
	CheckedProgram? p = check ("struct S { int x; void set(int x){this.x=x;this.later();} int y; void later(){this.set(2);} } struct T { int x; void set(){} } void set(){} void f(){S a={x=0,y=1};S b={x=1,y=2};b.set(3);}");
	var structure = p.structs[0];
	var method = structure.methods[0];
	assert (method.declaring_struct == structure && method.domain == CallableDomain.METHOD && method.ordinal == 0 && method.member_ordinal == 1);
	assert (structure.methods[1].member_ordinal == 3 && p.structs[1].methods[0] != method);
	assert (p.functions[0].symbol != method && p.functions[0].symbol.name == method.name);
	assert (!p.functions[1].locals[0].address_taken && p.functions[1].locals[1].address_taken);
	var body = (CheckedMethod) p.functions[2];
	assert (body.method == method && body.locals.length == 0 && method.parameters.length == 1);
	assert (method.receiver.semantic_type.instance_type == structure.semantic_type && method.receiver.semantic_type.is_nonnull && !method.receiver.semantic_type.is_owning && method.receiver.semantic_type.is_mutable);
	assert (!(method.receiver is ParameterSymbol) && !(method.receiver is LocalSymbol) && !method.receiver.semantic_type.is_typed_pointer () && !method.receiver.semantic_type.is_nullable_pointer_value ());
	var place = (CheckedReceiverFieldPlace) ((CheckedStore) body.body.statements[0]).target;
	assert (place.field == structure.fields[0] && place.receiver is CheckedThisExpression && ((CheckedThisExpression) place.receiver).receiver == method.receiver);
	var call = (CheckedCallStatement) body.body.statements[1];
	assert (call.target == structure.methods[1] && ((CheckedThisExpression) call.receiver).receiver == method.receiver);
	assert (SemanticDump.format (p).contains ("(target S::later #1)"));
	var witness = WeakRef (method);
	var receiver_witness = WeakRef (method.receiver);
	place = null;
	call = null;
	body = null;
	method = null;
	structure = null;
	p = null;
	assert (witness.get () == null && receiver_witness.get () == null);
}
private void diagnostics() {
	reject ("int main(){return this;}", "only valid inside");
	reject ("int main(){return this.x;}", "only valid inside");
	reject ("void f(){this.f();}", "only valid inside");
	reject ("void f(){int x=this;}", "only valid inside");
	reject ("struct S{int x;void f(){this=null;}}", "cannot be rebound");
	reject ("struct S{int x;bool f(){return this==null;}}", "nonnull, non-owning receiver");
	reject ("struct S{int x;void f(){x=1;}}", "unknown assignment target 'x'");
	reject ("struct S{int x;int f(){return x;}}", "unknown name 'x'");
	reject ("struct S{int x;void x(){}}", "field/method name collision");
	reject ("struct S{void x(){}int x;}", "field/method name collision");
	reject ("struct S{int x;void f(){}void f(int x){}}", "duplicate method");
	reject ("struct S{int x;void f(){}} void g(S* p){p.f();}", "pointer and arbitrary expression");
	reject ("struct S{int x;void f(){}} void g(S* p){p->f();}", "pointer receiver calls");
	reject ("struct S{int x;void f(){}} void g(){S.f();}", "direct struct local");
	reject ("struct S{int x;void f(){}} int g(){S s={x=0};return s.f;}", "unknown field");
	reject ("struct S{int x;void f(){this->x=1;}}", "not a source pointer");
	reject ("struct S{int x;void f(){this.missing();}}", "unknown method");
	reject ("struct S{int x;void f(){}} void g(){S s={x=0};s.x();}", "unknown method");
	reject ("struct S{int x;void f(int x){}} void g(){S s={x=0};s.f();}", "expects 1 arguments");
	reject ("struct S{int x;void f(int x){}} void g(){S s={x=0};s.f(true);}", "expects type 'int'");
	reject ("struct S{int x;void f(){}} int g(){S s={x=0};return s.f();}", "void function");
	reject ("struct S{int x;int[] f(){}}", "slice results");
	check ("struct S{int x;void f(int[] s){}}");
	assert (check ("struct S{int x;S f(S value){return value;}}").structs[0].methods[0].struct_result_contract != null);
	reject ("struct S{int x;void f(){owned void* r=move this;}}", "expected");
	reject ("struct S{int x;void f(){release this;}}", "expected");
	reject ("struct S{int x;void f(){S* p=&this;}}", "expected direct local");
}
private void signatures() {
	foreach (string type in new string[] {"int", "u8", "f32", "i16<8>", "f32<4>"}) {
		var p = check ("struct S{int x;%s f(%s value){return value;}}".printf (type, type));
		assert (p.structs[0].methods[0].return_type == p.structs[0].methods[0].parameters[0].semantic_type);
	}
	check ("struct S{int x;u8 byte(u8 n){return n;}bool test(){return this.byte(255)==255;}void p(S* p,int* q,borrowed int[] s){this.x=p->x+*q+s[0];}}");
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/method/semantic/identity-namespace-receiver-places-and-addressability", identity);
	Test.add_func ("/method/semantic/diagnostics", diagnostics);
	Test.add_func ("/method/semantic/native-signature-reuse", signatures);
	return Test.run ();
}
}
