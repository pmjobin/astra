// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Constants {
private SemanticResult analyze(string source) {
	var parsed = Parser.parse (new SourceFile.from_text ("constant.astra", source));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	return SemanticAnalyzer.analyze (parsed.unit);
}

private CheckedProgram check(string source) {
	var result = analyze (source);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string source, string message) {
	string? previous = null;
	for (int repeat = 0; repeat < 2; repeat++) {
		var parsed = Parser.parse (new SourceFile.from_text ("constant.astra", source));
		SemanticResult? result = parsed.diagnostic == null ? SemanticAnalyzer.analyze(parsed.unit) : null;
		var diagnostic = parsed.diagnostic ?? result.diagnostic;
		if (diagnostic == null || !diagnostic.message.contains (message)) {
			GLib.error ("expected %s for %s; got %s", message, source, diagnostic == null ? "accepted" : diagnostic.format ());
		}
		assert (previous == null || previous == diagnostic.format ());
		previous = diagnostic.format ();
	}
}

private void types() {
	foreach (string type in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "i32", "u32", "f32", "f64"}) {
		string literal = type == "bool" ? "true" : type.has_prefix ("f") ? "1.25" : "1";
		var program = check ("const " + type + " TOP=" + literal + "; void f(){const " + type + " LOCAL=TOP; " + type + " x=LOCAL;}");
		assert (program.constants[0].semantic_type == program.types.resolve (type));
		assert (program.functions[0].locals.length == 1 && program.functions[0].locals[0].ordinal == 0);
		assert (program.constants[0].region == null);
	}
	var p = check ("const I=1; const A=1.25; const B=1.25f; const C=1.25d; const f64 D=1.0000000000000002; const E=1.0000000000000002f as f64; const F=1.0000000596046448d as f32; const G=(1.0000000596046448f as f64); const i32 ALIAS=I;");
	assert (p.constants[0].semantic_type == p.types.i32_type && p.types.int_type == p.types.i32_type);
	assert (p.constants[1].semantic_type == p.types.f32_type && p.constants[2].semantic_type == p.types.f32_type && p.constants[3].semantic_type == p.types.f64_type);
	assert (p.constants[4].value.floating.exact_bits == 0x3ff0000000000001UL);
	assert (p.constants[5].value.floating.exact_bits == 0x3ff0000000000000UL);
	assert (p.constants[6].value.floating.exact_bits == 0x3f800000U);
	assert (p.constants[7].value.floating.exact_bits == 0x3ff0000020000000UL);
	reject ("const ONE=1; void f(){u8 x=ONE;}", "initializer of type 'u8'");
	reject ("const f64 X=1.0f;", "found 'f32'");
	reject ("const X=1.0d; const f32 Y=X;", "found 'f64'");
	check ("const ONE=1; void f(){u8 x=ONE as u8;}");
	check ("T id<T>(T x){const N=2;return x;} int f(){const N=1;return id(N);}");
	reject ("T f<T>(T x){const T C=x;return x;}", "unsupported constant type 'T'");
	reject ("T f<T>(T x){const C=x;return x;}", "nonconstant dependency");
	foreach (string type in new string[] {"void", "void*", "int*", "int[]", "int[1]", "int<4>", "bool<4>", "S", "Box<int>", "C"}) {
		reject ("struct S{int x;} struct Box<T>{T x;} class C{int x;} const " + type + " X=1;", "unsupported constant type");
	}
	reject ("const int[X] X=1;", "unsupported constant type");
	reject ("struct Box<T>{T x;} const Box<int[X]> X=1;", "unsupported constant type");
	reject ("struct Box<T>{T x;} const X=1 as Box<int[X]>;", "expected expression");
}

private void integer_steps() {
	var p = check ("const u8 W=(255+1)/2;const i8 S=(127+1)/2;const i8 Q=-128/-1;const i8 R=-128%-1;const i8 SHIFT=(-128)>>7;const u32 HIGH=4294967295>>31;const MOD=(-1 as u8);const B=(true^false)&!false;");
	int64[] expected = {
		0, -64, -128, 0, -1, 1, 255
	};
	for (int i = 0; i < expected.length; i++) {
		assert (p.constants[i].value.integer.mathematical_value == expected[i]);
	}
	assert (p.constants[7].value.boolean);
}

private void scopes() {
	check ("const RESULT=LATER+LATER;const LATER=21; int f(){const L=RESULT; if(true){const A=L; int x=A;} if(false){const A=2;} return L;}");
	check ("int f(){return 1;const C=2;}");
	reject ("int f(){return 1;const C=1/0;}", "division by zero");
	reject ("void f(){if(false){const C=1/0;}}", "division by zero");
	reject ("void f(){const X=X;}", "unknown name 'X'");
	reject ("void f(){const X=Y;const Y=1;}", "unknown name 'Y'");
	reject ("void f(){if(true){const X=1;}int a=X;}", "unknown name 'X'");
	reject ("void f(int X){const X=1;}", "conflicts");
	reject ("const X=1;void f(int X){}", "conflicts");
	reject ("const X=1;void f(){int X=2;}", "duplicate local");
	reject ("void f(){const X=1;if(true){const X=2;}}", "conflicts");
	reject ("const X=1;const X=2;", "duplicate constant");
	reject ("const f=1;int f(){return 1;}", "duplicate constant or callable");
	reject ("extern(C) int f();const f=1;", "duplicate constant or callable");
	reject ("void f(){const f=1;}", "conflicts");
	reject ("const A=B;const B=C;const C=A;", "dependency cycle");
	reject ("const A=false && A;", "dependency cycle");
	reject ("const A=false && B;const B=A;", "dependency cycle");
	var text = new StringBuilder ();
	for (int i = 0; i < 5000; i++) {
		text.append ("const C%d=C%d+1;\n".printf (i, i + 1));
	}
	text.append ("const C5000=0;");
	var p = check (text.str);
	assert (p.constants[0].value.integer.mathematical_value == 5000);
	text.append ("const BAD=BAD;");
	reject (text.str, "dependency cycle");
	check ("const C=42;");
}

private void eligibility() {
	check ("const SAFE=false && ((1/0)==0);const ALSO=true || ((1<<32)==0);const CAST=false && ((1e1000d as int)==0);");
	reject ("const X=false && missing;", "unknown name");
	reject ("const X=false && 1;", "requires");
	reject ("bool pure(){return true;}const X=false && pure();", "unsupported constant expression");
	reject ("bool sqrt(){return true;}const X=sqrt();", "unsupported constant expression");
	reject ("const X=false && BAD;const BAD=(1/0)==0;", "division by zero");
	foreach (string expr in new string[] {"x", "x+1"}) {
		reject ("void f(int x){const C=" + expr + ";}", "nonconstant dependency");
	}
	reject ("void f(){int x=1;const C=x;}", "nonconstant dependency");
	foreach (string expr in new string[] {"null", "new int[1]", "&x", "*p", "a[0]", "x.field", "move x", "x.method()", "len(x)"}) {
		reject ("void f(){const C=" + expr + ";}", "unsupported constant expression");
	}
	foreach (string decl in new string[] {"const C;", "const C=;", "const int C;"}) {
		reject (decl, "requires an initializer");
	}
	foreach (string decl in new string[] {"const var C=1;", "const owned int C=1;", "const borrowed int C=1;"}) {
		reject (decl, "ownership qualifiers");
	}
	reject ("const A=1,B=2;", "one name");
	reject ("struct S{const int X=1;}", "reserved keyword");
	reject ("int const(){return 1;}", "reserved keyword");
	check ("int Const(){return 1;}int CONST(){return Const();}");
	reject ("const X=1;void f(){X=2;}", "not mutable storage");
	reject ("const X=1;void f(){int* p=&X;}", "no storage or address");
	reject ("const X=1;void f(){release X;}", "owned void* local");
	reject ("const X=1;void f(){var y=move X;}", "owned");
	foreach (string expr in new string[] {"1/0", "1%0", "1<<32", "1>>-1", "1e1000d as int", "(0.0d/0.0d) as u8", "256.0d as u8", "-1.0f as u32"}) {
		reject ("const BAD=" + expr + ";", "invalid evaluated");
	}
	check ("int f(int n){return 1/n;}int c(f64 n){return n as int;}");
}

private void extents() {
	check ("const u8 N=1;void f(){int[N] a={1};const M=N+1;int[M] b={1,2};int[1+1] c={1,2};}");
	foreach (string type in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32"}) {
		check ("void f(){const " + type + " N=1;int[N] a={1};}");
	}
	var source = new StringBuilder ("void f(){const u32 N=1024;int[N] a={");
	for (int i = 0; i < 1024; i++) {
		source.append (i == 0 ? "1" : ",1");
	}
	source.append ("};}");
	check (source.str);
	foreach (string bound in new string[] {"0", "-1", "1025", "1.0", "true", "1/0", "x", "missing"}) {
		reject ("void f(int x){int[" + bound + "] a={1};}", "1..1024");
	}
	reject ("void f(){const N=2;int[N] a={1};}", "exactly 2 elements");
	reject ("void f(){const u8 N=2;var a=new int[N];}", "count requires int/i32");
	check ("void f(){const N=2;var a=new int[N];}");
}

private int values() {
	var source = new StringBuilder ();
	string? line;
	while ((line = stdin.read_line ()) != null) {
		source.append (line);
		source.append_c ('\n');
	}
	var p = check (source.str);
	foreach (var symbol in p.constants) {
		var v = symbol.value;
		stdout.printf ("%s %s %s\n", symbol.name, v.semantic_type.display_name (), v.integer != null ? v.integer.to_string () : v.floating != null ? v.floating.to_string () : v.boolean ? "true" : "false");
	}
	return 0;
}

int main(string[] args) {
	if (args.length == 2 && args[1] == "--values") {
		return values ();
	}
	Test.init (ref args);
	Test.add_func ("/const/types-context-suffixes", types);
	Test.add_func ("/const/integer-intermediate-steps", integer_steps);
	Test.add_func ("/const/scopes-graph-memoization", scopes);
	Test.add_func ("/const/eligibility-lazy-traps", eligibility);
	Test.add_func ("/const/array-extents", extents);
	return Test.run ();
}

}
