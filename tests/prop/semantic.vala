// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.PropSemantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("prop", text));
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
	var result = parsed.diagnostic == null ? SemanticAnalyzer.analyze(parsed.unit) : null;
	var diagnostic = parsed.diagnostic ?? result.diagnostic;
	if (diagnostic == null || !diagnostic.message.contains (message)) {
		GLib.error ("expected '%s', got '%s' for %s", message, diagnostic == null ? "accepted" : diagnostic.message, text);
	}
}

private void identities() {
	CheckedProgram? p = check ("struct S{int raw;property int value{get{return this.later();}set(int next){this.other=next;}}property int other{get{return this.raw;}set(int next){this.raw=next;}}int later(){return this.other;}}class C{property int value{get{return 42;}}}int main(){S a={raw=1};S b={raw=2};b.value=42;return b.value+a.raw;}");
	var property = p.structs[0].properties[0];
	assert (property.declaring_type == p.structs[0] && property.ordinal == 0 && property.member_ordinal == 1);
	assert (property != p.classes[0].properties[0] && property.getter != p.classes[0].properties[0].getter);
	assert (property.getter.property_symbol == property && property.setter.property_symbol == property);
	assert (!(property.getter is MethodSymbol) && !(property.setter is MethodSymbol));
	assert (property.getter.kind == CallableKind.PROPERTY_GETTER && property.setter.kind == CallableKind.PROPERTY_SETTER);
	assert (property.getter.implicit_receiver.semantic_type == p.structs[0].receiver_type && property.setter.implicit_receiver.semantic_type == p.structs[0].receiver_type);
	assert (property.getter.parameters.length == 0 && property.setter.parameters.length == 1 && property.setter.parameters[0].name == "next" && property.setter.parameters[0].pointer_contract == PointerParameterContract.UNMANAGED);
	assert (p.properties[0].symbol == property && p.properties[0].getter.symbol == property.getter);
	assert (!p.functions[0].locals[0].address_taken && p.functions[0].locals[1].address_taken);
	var set = p.functions[0].body.statements[2] as CheckedPropertySetStatement;
	assert (set != null && set.setter == property.setter && !(set is CheckedStore));
	var get = ((CheckedBinaryExpression) ((CheckedReturnStatement) p.functions[0].body.statements[3]).expression).left as CheckedPropertyGetExpression;
	assert (get != null && get.getter == property.getter && !(get is CheckedLoadExpression));
	assert (SemanticDump.format (p).contains ("property-get") && SemanticDump.format (p).contains ("property-set"));
	var witness = WeakRef (property);
	var getter_witness = WeakRef (property.getter);
	get = null;
	set = null;
	property = null;
	p = null;
	assert (witness.get () == null && getter_witness.get () == null);
}

private void types() {
	foreach (string type in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "i32", "u32", "f32", "f64", "void*", "i8<16>", "u8<16>", "i16<8>", "u16<8>", "int<4>", "u32<4>", "f32<4>", "f64<2>", "bool<16>"}) {
		var p = check ("class C{property %s p{get{return this.p;}set(%s next){this.p=next;}}}".printf (type, type));
		var property = p.classes[0].properties[0];
		assert (property.semantic_type == property.getter.return_type && property.semantic_type == property.setter.parameters[0].semantic_type);
	}
	foreach (string type in new string[] {"void", "C", "int[]", "int[2]", "int*", "S*"}) {
		reject ("struct S{int x;}class C{property %s p{get{return this.p;}}}".printf (type), "unsupported property value type");
	}
	check ("struct S{int x;}class C{property S p{get{return this.p;}}}");
	reject ("class C{property f64<4> p{get{}}}", "vector shape");
}

private void diagnostics() {
	reject ("class C{property int p{get{return 1;}}}void f(){C c={};c.p[0]=1;}", "not assignment targets");
	reject ("class C{property int p{set(int n){}}}", "requires one getter");
	reject ("class C{property int p{get{}get{}}}", "duplicate getter");
	reject ("class C{property int p{get{}set(int n){}set(int n){}}}", "duplicate setter");
	reject ("class C{property int p{get{return 1;}set(u32 next){}}}", "must exactly match");
	reject ("class C{property int p{get{return true;}}}", "expected return value");
	reject ("class C{property int p{get{return 1;}set(int next){return next;}}}", "void");
	reject ("class C{property int p{get{return 1;}set(int next){next=2;}}}", "parameter");
	reject ("class C{property int p{get{return 1;}set(int next){int n=value;}}}", "unknown name 'value'");
	foreach (string member in new string[] {"int p;", "void p(){}", "property u32 p{get{return 1;}}"}) {
		reject ("class C{" + member + "property int p{get{return 1;}}}", "collision");
		reject ("class C{property int p{get{return 1;}}" + member + "}", "collision");
	}
	foreach (string name in new string[] {"init", "deinit"}) {
		reject ("class C{property int " + name + "{get{return 1;}}}", "reserved");
	}
	foreach (string statement in new string[] {"int n=this.p;", "this.p=2;"}) {
		reject ("class C{int x;init(){this.x=1;" + statement + "}property int p{get{return this.x;}set(int n){this.x=n;}}}", "this.property calls are unsupported in constructors");
	}
	reject ("class C{property int p{get{return 1;}}}void f(){C c={};c.p=2;}", "read-only: missing setter");
	reject ("class C{property int p{get{return 1;}}}void f(){C c={};c.p();}", "unknown method");
	reject ("class C{property int p{get{return 1;}}}void f(){C c={p=2};}", "unknown initializer field");
	reject ("struct S{int x;property int p{get{return this.x;}}}int f(S* s){return s.p;}", "pointer and arbitrary expression");
	check ("class C{int next;property int p{get{return this.next;}set(int next){this.next=next;}}}");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/prop/semantic/identities-callables-receivers-addressability-lifetime", identities);
	Test.add_func ("/prop/semantic/plain-value-type-intersection", types);
	Test.add_func ("/prop/semantic/diagnostics-shadowing-no-implicit-binding", diagnostics);
	return Test.run ();
}

}
