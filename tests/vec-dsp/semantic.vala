// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.DspSemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("dsp.astra", text));
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
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		var element = types.resolve (name);
		foreach (int lanes in new int[] {1, 2, 4, 8, 16}) {
			var vector = lanes == 1 ? null : types.vector_of (element, lanes);
			if (lanes != 1 && vector == null) {
				continue;
			}
			string source = lanes == 1 ? name : vector.display_name ();
			if (element is IntegerType) {
				foreach (string op in new string[] {"sat_add", "sat_sub"}) {
					check ("%s f(%s a,%s b){return %s(a,b);}".printf (source, source, source, op));
					cases++;
				}
			}
			if (vector == null) {
				continue;
			}
			foreach (string op in new string[] {"interleave_low", "interleave_high"}) {
				check ("%s f(%s a,%s b){return %s(a,b);}".printf (source, source, source, op));
				cases++;
			}
			if (!(element is IntegerType)) {
				continue;
			}
			foreach (string dest in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
				var d = (IntegerType) types.resolve (dest);
				bool widen = d.bit_width > ((IntegerType) element).bit_width;
				bool pack = d.bit_width < ((IntegerType) element).bit_width;
				var output = types.vector_of (d, widen ? lanes / 2 : lanes * 2);
				if ((!widen && !pack) || output == null) {
					continue;
				}
				foreach (string op in widen ? new string[] {"widen_low", "widen_high"} : new string[] {"pack_wrap", "pack_sat"}) {
					check ("%s f(%s a,%s b){return %s(a,%s%s);}".printf (output.display_name (), source, source, op, widen ? "" : "b,", dest));
					cases++;
				}
			}
		}
	}
	assert (cases > 150);
	Test.message ("%d exact DSP type/shape combinations", cases);
}

private void literals_and_provenance() {
	var program = check ("u8 f(){return sat_add(250,10);} int g(){return sat_add(1,2);} u16<8> h(i8<16> a){return widen_high(a,u16);}");
	var sat = (CheckedDspExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
	assert (sat.source_type == program.types.u8_type && sat.first.semantic_type == sat.second.semantic_type);
	assert (((CheckedIntegerExpression) sat.first).value.mathematical_value == 250 && ((CheckedIntegerExpression) sat.second).value.mathematical_value == 10);
	var widen = (CheckedDspExpression) ((CheckedReturnStatement) program.functions[2].body.statements[0]).expression;
	assert (widen.primitive_kind == DspPrimitiveKind.WIDEN_HIGH && widen.destination_element == program.types.u16_type && widen.second == null);
	assert (widen.span.text () == "widen_high(a,u16)" && widen.first.span.text () == "a");
	check ("u8 f(u8 x){return sat_add(10,x);} bool g(u8 x){return sat_sub(250,x)==250;} u8 h(u8 x){return sat_add(sat_sub(250,10),x);}");
	check ("bool f(i8<16> v){return widen_low(v,u16)[0]==65535;} bool g(u16<8> v){return pack_sat(v,v,i8)[0]==127;}");
	check ("i32 f(int a,i32 b){return sat_sub(a,b);}");
	reject ("u8 f(){return sat_add(256,1);}", "out of range for 'u8'");
	reject ("u8 f(){return sat_sub(0,-1);}", "unsigned integer type");
	reject ("i16 f(i8 a){return sat_add(a,1);}", "matching types");
	assert (SemanticDump.format (program).contains ("vector-widen-high (from i8<16>) (to u16<8>)"));
}

private void diagnostics() {
	foreach (string op in new string[] {"sat_add", "sat_sub"}) {
		foreach (string type in new string[] {"bool", "f32", "bool<8>", "f32<4>"}) {
			reject ("%s f(%s a,%s b){return %s(a,b);}".printf (type, type, type, op), "saturation requires");
		}
		foreach (string type in new string[] {"u8", "i16", "i8<8>"}) {
			reject ("i8 f(i8 a,%s b){return %s(a,b);}".printf (type, op), "matching types");
		}
	}
	foreach (string op in new string[] {"widen_low", "widen_high"}) {
		reject ("i8<4> f(i8<8> a){return " + op + "(a,u8);}", "strictly wider");
		reject ("i8<4> f(i16<8> a){return " + op + "(a,i8);}", "strictly wider");
		reject ("void f(i8<2> a){return " + op + "(a,i16);}", "unsupported DSP result");
		reject ("void f(i8<16> a){return " + op + "(a,i32);}", "unsupported DSP result");
		foreach (string type in new string[] {"f32<4>", "bool<8>", "i8"}) {
			reject ("void f(" + type + " a){return " + op + "(a,i16);}", "integer VectorType");
		}
	}
	foreach (string op in new string[] {"pack_wrap", "pack_sat"}) {
		reject ("void f(i16<4> a,u16<4> b){return " + op + "(a,b,i8);}", "matching types");
		reject ("void f(i16<4> a,i16<2> b){return " + op + "(a,b,i8);}", "matching types");
		reject ("void f(i8<4> a){return " + op + "(a,a,u8);}", "strictly narrower");
		reject ("void f(i8<2> a){return " + op + "(a,a,i16);}", "strictly narrower");
		reject ("void f(i8<16> a){return " + op + "(a,a,i8);}", "unsupported DSP result");
		foreach (string type in new string[] {"f32<4>", "bool<8>", "i16"}) {
			reject ("void f(" + type + " a){return " + op + "(a,a,i8);}", "integer VectorType");
		}
	}
	foreach (string dest in new string[] {"bool", "f32", "void*", "i16<4>"}) {
		reject ("void f(i8<8> a){return widen_low(a," + dest + ");}", "scalar IntegerType");
	}
	reject ("void f(i8<8> a,int destination){return widen_low(a,destination);}", "unknown type");
	foreach (string op in new string[] {"interleave_low", "interleave_high"}) {
		reject ("i8 f(i8 a){return " + op + "(a,a);}", "same VectorType");
		reject ("void f(i8<8> a,u8<8> b){return " + op + "(a,b);}", "matching types");
		reject ("void f(i8<8> a,i8<4> b){return " + op + "(a,b);}", "matching types");
	}
}

private void grammar() {
	foreach (string op in new string[] {"sat_add", "sat_sub", "widen_low", "widen_high", "pack_wrap", "pack_sat", "interleave_low", "interleave_high"}) {
		reject ("int " + op + "(){return 0;}", "expected function name", true);
		reject ("void f(){return " + op + "();}", "expected expression", true);
		reject ("void f(){return " + op + "(a);}", "expected ','", true);
	}
	reject ("void f(){return widen_low(a,12);}", "destination element type", true);
	reject ("void f(){return widen_high(a,i16+1);}", "expected ')'", true);
	reject ("void f(){return pack_sat(a,b);}", "expected ','", true);
	reject ("void f(){return sat_add(a,b,c);}", "expected ')'", true);
	reject ("void f(){return interleave_high(a,b,c);}", "expected ')'", true);
	reject ("int f(int a){return sat_cast(a,u8);}", "unknown function");
	var deep = new StringBuilder ("int f(){return ");
	for (int i = 0; i < 256; i++) {
		deep.append ("sat_add(1,");
	}
	deep.append ("2");
	for (int i = 0; i < 256; i++) {
		deep.append (")");
	}
	reject (deep.str + ";}", "nesting limit", true);
	string text = "u8<16> f(i16<8> a){return pack_sat(a,widen_low(splat(1 as i8,16),i16),u8);}";
	for (int i = 0; i < text.length; i++) {
		var parsed = Parser.parse (new SourceFile.from_text ("prefix", text.substring (0, i)));
		assert ((parsed.unit == null) != (parsed.diagnostic == null));
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dsp/semantic/all-type-shapes", matrix);
	Test.add_func ("/dsp/semantic/literals-provenance", literals_and_provenance);
	Test.add_func ("/dsp/semantic/diagnostics", diagnostics);
	Test.add_func ("/dsp/semantic/grammar-reservations-depth", grammar);
	return Test.run ();
}

}
