// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
namespace Astra.Tests.StructAbiSemantic {
private SemanticResult analyze(string text) {
	var p = Parser.parse (new SourceFile.from_text ("boundary.astra", text));
	if (p.diagnostic != null) {
		GLib.error ("%s", p.diagnostic.format ());
	}
	return SemanticAnalyzer.analyze (p.unit);
}
private CheckedProgram check(string text) {
	var r = analyze (text);
	if (r.diagnostic != null) {
		GLib.error ("%s", r.diagnostic.format ());
	}
	return r.program;
}
private void reject(string text, string message) {
	var r = analyze (text);
	if (r.diagnostic == null || !r.diagnostic.message.contains (message)) {
		GLib.error ("expected %s, found %s", message, r.diagnostic == null ? "accepted" : r.diagnostic.format ());
	}
}
private void contracts() {
	var p = check ("struct Pair{int x;f64 y;}Pair identity(Pair value){return value;}int main(){Pair a={x=7,y=3.5};Pair b=identity(a);b=identity(identity(a));return a.x;}");
	var f = p.functions[0];
	var type = p.structs[0].semantic_type;
	assert (f.symbol.struct_result_contract.semantic_type == type && f.symbol.struct_result_contract.mode == StructValueMode.COPY_VALUE);
	assert (f.symbol.parameters[0].struct_value_contract.semantic_type == type && f.locals[0].is_struct_parameter && !f.locals[0].address_taken);
	var returned = (CheckedStructReturn)f.body.statements[0];
	var snapshot = (CheckedStructSnapshot)returned.producer;
	assert (snapshot.copyability == Copyability.COPYABLE && ((CheckedLocalPlace)snapshot.source).local == f.locals[0]);
	var store = (CheckedStructResultStore)p.functions[1].body.statements[1];
	var call = (CheckedStructCallResult)store.producer;
	assert (store.initializes_destination && call.target == f.symbol);
	var arg = (CheckedStructArgument)call.arguments[0];
	assert (arg.parameter == f.symbol.parameters[0] && arg.producer is CheckedStructSnapshot);
	store = (CheckedStructResultStore)p.functions[1].body.statements[2];
	call = (CheckedStructCallResult)store.producer;
	assert (!store.initializes_destination && ((CheckedStructArgument)call.arguments[0]).producer is CheckedStructCallResult);
	assert (!(((Object)store.producer) is CheckedExpression) && !SemanticDump.format (p).contains ("StructValue"));
}
private void negatives() {
	string s = "struct A{int x;}struct B{int x;}A make(){A a={x=7};return a;}";
	reject (s + "void take(B value){}void f(){A a={x=7};take(a);}", "exact nominal type 'B', found 'A'; equal layout is insufficient");
	reject (s + "B f(A a){return a;}", "exact nominal type 'B', found 'A'");
	reject (s + "void f(){B b=make();}", "exact nominal type 'B', found 'A'");
	foreach (string body in new string[] {"a.x=9;", "a=make();", "A* p=&a;"}) {
		reject (s + "void f(A a){" + body + "}", "parameter storage is read-only");
	}
	reject (s + "struct O{A inner;}void f(O a){a.inner.x=9;}", "parameter storage is read-only");
	reject (s + "void f(){make();}", "bounded");
	reject (s + "int f(){return make();}", "struct call result requires copy initialization");
	reject (s + "bool f(A a){return a==a;}", "whole-struct values");
	check (s + "struct O{int x;property A value{get{return make();}}}");
	foreach (string declaration in new string[] {"extern(C) void f(A a);", "extern(C) A f();", "export(C) void f(A a){}", "export(C) A f(){return make();}"}) {
		reject (s + declaration, "struct function");
	}
	string g = "struct Box<T>{T value;}";
	// Approved milestone-15 open-record batch: exact symbolic signatures.
	check (g + "void f<T>(Box<T> value){}");
	check (g + "Box<T> f<T>(T value){}");
	// The empty result body still rejects when demanded at CFG and later:
	// structural-generics-15/negative.py, open-formal-missing-return.
	reject (g + "void take(Box<u8> value){}void f(){Box<i8> a={value=7};take(a);}", "exact nominal type");
	check (g + "T identity<T>(T value){return value;}void f(){Box<int> a={value=7};identity<Box<int>>(a);}");
	foreach (string capability in new string[] {"Copy", "Move"}) {
		reject ("T f<T>(T a) where T:" + capability + "{return a;}", "unknown generic capability");
	}
}
private void authority() {
	var t = new BuiltinTypes ();
	var s = new StructType ("Future");
	var fields = new GenericArray<SemanticType> ();
	fields.add (t.int_type);
	CopyabilityFields graph = (type) => type == s ? fields : null;
	assert (CopyabilityAuthority.of (s, graph) == Copyability.COPYABLE);
	foreach (SemanticType forbidden in new SemanticType[] {new ClassType ("C"), new HandleType ("R"), new TypeParameterType ("T"), t.pointer_to (t.int_type)}) {
		fields.add (forbidden);
		assert (CopyabilityAuthority.of (s, graph) == Copyability.NOT_COPYABLE);
		bool rejected = false;
		try {
			StructLeafOrder.enumerate (s, graph);
		} catch (StructLeafError e) {
			rejected = true;
		}
		assert (rejected);
		fields.remove_index (1);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-abi/semantic/exact-copy-contracts-bounded-producers", contracts);
	Test.add_func ("/struct-abi/semantic/nominal-readonly-generic-foreign-property-firewalls", negatives);
	Test.add_func ("/struct-abi/semantic/shared-copyability-future-safety", authority);
	return Test.run ();
}
}
