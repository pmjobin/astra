// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.DotSemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("dot.astra", text));
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.program == null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(owned string text, string expected, bool parsing = false) {
	// Check the expression before unrelated void-return legality.
	if (!parsing && text.has_prefix ("void f")) {
		text = text.replace ("{return ", "{int rejected=");
	}
	var syntax = Parser.parse (new SourceFile.from_text ("invalid.astra", text));
	if (parsing) {
		if (syntax.unit != null || !syntax.diagnostic.message.contains (expected)) {
			GLib.error ("Expected parse rejection %s for %s", expected, text);
		}
		return;
	}
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	string before = SyntaxDump.format (syntax.unit);
	for (int repeat = 0; repeat < 2; repeat++) {
		var result = SemanticAnalyzer.analyze (syntax.unit);
		if (result.program != null || !result.diagnostic.message.contains (expected)) {
			GLib.error ("Expected %s for %s; got %s", expected, text, result.diagnostic == null ? "success" : result.diagnostic.message);
		}
	}
	assert (SyntaxDump.format (syntax.unit) == before);
}

private void matrix() {
	var types = new BuiltinTypes ();
	int cases = 0;
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		var element = types.resolve (name);
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (element, lanes);
			if (vector == null) {
				continue;
			}
			string source = vector.display_name ();
			if (name == "f32") {
				check ("f32 f(%s a,%s b){return dot(a,b);} f32 g(f32 c,%s a,%s b){return mac(c,a,b);}".printf (source, source, source, source));
				cases += 2;
				continue;
			}
			foreach (string dest in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
				string text = "%s f(%s a,%s b){return dot_wrap(a,b,%s);} %s g(%s c,%s a,%s b){return mac_wrap(c,a,b);}".printf (dest, source, source, dest, dest, dest, source, source);
				if (((IntegerType) types.resolve (dest)).bit_width < ((IntegerType) element).bit_width) {
					reject (text, "accumulator width");
					continue;
				}
				check (text);
				cases += 2;
			}
		}
	}
	assert (cases == 164);
	Test.message ("%d exact dot/MAC type and shape combinations", cases);
}

private void provenance() {
	var program = check ("u16 f(i8<16> a,i8<16> b){return dot_wrap(a,b,u16);} f32 g(f32 c,f32<4> a,f32<4> b){return mac(c,a,b);}");
	var dot = (CheckedVectorDotExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
	assert (dot.dot_kind == VectorDotKind.INTEGER_WRAP_DOT && dot.accumulator == null && dot.destination_type == program.types.u16_type);
	assert (dot.source_type == dot.first.semantic_type && dot.source_type == dot.second.semantic_type && dot.span.text () == "dot_wrap(a,b,u16)");
	var mac = (CheckedVectorDotExpression) ((CheckedReturnStatement) program.functions[1].body.statements[0]).expression;
	assert (mac.dot_kind == VectorDotKind.F32_MAC && mac.accumulator.semantic_type == program.types.f32_type && mac.dot_kind.order () == "ascending-lane");
	assert (SemanticDump.format (program).contains ("dot-wrap (source i8<16>) (accumulator u16) (order modular)"));
	check ("bool f(i8<4> a){return dot_wrap(a,a,u16)==65535;} bool g(u16 c,i8<4> a){return mac_wrap(c,a,a)==65535;} i32 h(i8<4> a){return dot_wrap(a,a,int);}");
	// An unadorned integer MAC accumulator has the existing default int
	// type, independently of the expected result. Explicit casts select D.
	check ("u8 f(i8<4> a){return mac_wrap(0 as u8,a,a);}");
	reject ("u8 f(i8<4> a){return mac_wrap(0,a,a);}", "expected return value of type 'u8', found 'int'");
}

private void diagnostics() {
	foreach (string type in new string[] {"i8", "int", "f32", "bool", "bool<4>", "f32<4>"}) {
		reject ("void f(" + type + " a){return dot_wrap(a,a,i32);}", type.contains ("<") ? "requires integer vectors" : "source VectorType");
		reject ("void f(" + type + " a){return mac_wrap(0,a,a);}", type.contains ("<") ? "requires integer vectors" : "source VectorType");
	}
	foreach (string type in new string[] {"i8<4>", "u8<4>", "bool<4>"}) {
		reject ("void f(" + type + " a){return dot(a,a);}", "requires f32 vectors");
		reject ("void f(" + type + " a){return mac(0.0,a,a);}", "requires f32 vectors");
	}
	foreach (string type in new string[] {"u8<4>", "i16<4>", "i8<2>"}) {
		reject ("void f(i8<4> a," + type + " b){return dot_wrap(a,b,int);}", "exact same source VectorType");
		reject ("void f(i8<4> a," + type + " b){return mac_wrap(0,a,b);}", "exact same source VectorType");
	}
	reject ("f32 f(f32<2> a,f32<4> b){return dot(a,b);}", "exact same source VectorType");
	reject ("f32 f(f32 a){return dot(a,a);}", "source VectorType");
	reject ("f32 f(f32<4> a){return mac(0,a,a);}", "requires f32 vectors");
	reject ("void f(i8<4> a){return mac_wrap(0.0,a,a);}", "requires integer vectors");
	reject ("void f(i16<4> a){return mac_wrap(0 as u8,a,a);}", "accumulator width");
	foreach (string dest in new string[] {"bool", "f32", "void*", "i16<4>"}) {
		reject ("void f(i8<4> a){return dot_wrap(a,a," + dest + ");}", "scalar IntegerType");
	}
	reject ("void f(i8<4> a,int d){return dot_wrap(a,a,d);}", "unknown type");
	foreach (string name in new string[] {"dot_sat", "mac_sat", "hsum", "mul_wide", "fma"}) {
		reject ("int f(){return " + name + "();}", "unknown function");
	}
}

private void grammar() {
	foreach (string name in new string[] {"dot_wrap", "mac_wrap", "dot", "mac"}) {
		reject ("int " + name + "(){return 0;}", "expected function name", true);
		reject ("void f(){return " + name + "();}", "expected expression", true);
		reject ("void f(){return " + name + "(a);}", "expected ','", true);
	}
	reject ("void f(){return dot_wrap(a,b);}", "expected ','", true);
	reject ("void f(){return dot_wrap(a,b,1);}", "accumulator type", true);
	reject ("void f(){return dot(a,b,int);}", "expected ')'", true);
	reject ("void f(){return mac(a,b);}", "expected ','", true);
	reject ("void f(){return mac_wrap(c,a,b,int);}", "expected ')'", true);
	var deep = new StringBuilder ("int f(){return ");
	for (int i = 0; i < 256; i++) {
		deep.append ("mac_wrap(");
	}
	deep.append ("0");
	for (int i = 0; i < 256; i++) {
		deep.append (",a,b)");
	}
	reject (deep.str + ";}", "nesting limit", true);
	string text = "i32 f(i8<4> a){return mac_wrap(dot_wrap(a,a,int),a,a);}";
	for (int i = 0; i < text.length; i++) {
		var parsed = Parser.parse (new SourceFile.from_text ("prefix", text.substring (0, i)));
		assert ((parsed.unit == null) != (parsed.diagnostic == null));
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dot/semantic/type-shape-matrix", matrix);
	Test.add_func ("/dot/semantic/provenance-and-literal-boundaries", provenance);
	Test.add_func ("/dot/semantic/invalid-domains", diagnostics);
	Test.add_func ("/dot/semantic/grammar-reservations-depth", grammar);
	return Test.run ();
}

}
