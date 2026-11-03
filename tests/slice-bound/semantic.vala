// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.SliceBoundSemantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("slice-bound", text));
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
	var parsed = Parser.parse (new SourceFile.from_text ("slice-bound", text));
	if (parsed.diagnostic != null) {
		assert (parsed.diagnostic.message.contains (message));
		return;
	}
	string syntax = SyntaxDump.format (parsed.unit);
	string? previous = null;
	for (int i = 0; i < 2; i++) {
		var result = SemanticAnalyzer.analyze (parsed.unit);
		if (result.diagnostic == null || !result.diagnostic.message.contains (message)) {
			GLib.error ("expected %s for %s, got %s", message, text, result.diagnostic == null ? "accepted" : result.diagnostic.format ());
		}
		assert (previous == null || previous == result.diagnostic.format ());
		previous = result.diagnostic.format ();
	}
	assert (syntax == SyntaxDump.format (parsed.unit));
}

private void identity() {
	var t = new BuiltinTypes ();
	int shapes = 0;
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		foreach (int lanes in new int[] {0, 2, 4, 8, 16}) {
			if (lanes != 0 && t.vector_of (t.resolve (element), lanes) == null) {
				continue;
			}
			string type = lanes == 0 ? element : "%s<%d>".printf (element, lanes);
			var p = check ("void f(borrowed %s[] s,%s value){%s[] local=s;local[0]=value;s[0]=local[0];g(local);} void g(borrowed %s[] s){int n=len(s);}".printf (type, type, type, type));
			var f = p.functions[0];
			var parameter = f.symbol.parameters[0];
			assert (parameter.semantic_type is SliceType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && parameter.ordinal == 0);
			assert (parameter.semantic_type == f.locals[0].semantic_type && parameter.semantic_type == p.functions[1].symbol.parameters[0].semantic_type);
			var reference = ((CheckedLocalDeclaration) f.body.statements[0]).initializer;
			var proof = BorrowProvenance.for_expression (reference);
			assert (proof.origin == parameter && proof.region == f.body.region && proof.region.ordinal == 0);
			assert (proof.snapshot ().origin == DataPointerOrigin.PARAMETER && proof.outlives (f.locals[0].lexical_region));
			var place = (CheckedSliceElementPlace) ((CheckedStore) f.body.statements[2]).target;
			assert (place.provenance.origin == parameter && place.semantic_type == ((SliceType) parameter.semantic_type).element_type);
			shapes++;
		}
	}
	assert (shapes == 27);
	var p = check ("void f(borrowed int[] s){g(s);} void g(borrowed i32[] s){} void h(){int[4] a={1,2,3,4};i32[1] b={1};f(slice(a));f(slice(b));}");
	assert (p.functions[0].symbol.parameters[0].semantic_type == p.functions[1].symbol.parameters[0].semantic_type);
	check ("bool f(borrowed u8[] s,int i){s[i]=255;return 255==s[i] && s[i]==255 && 255==(s)[i];}");
	check ("void f(borrowed int[] s){int[] a=s;{int[] b=s;b[0]=a[0];}}");
}

private void diagnostics() {
	foreach (string type in new string[] {"bool", "bool<4>", "void*"}) {
		check ("void f(borrowed " + type + "[] s){}");
	}
	check ("void f(int[] s){}");
	check ("void f(owned int[] s){}");
	reject ("int[] f(borrowed int[] s){return s;}", "slice results");
	reject ("borrowed int[] f(borrowed int[] s){return s;}", "borrowed");
	reject ("extern(C) void f(borrowed int[] s);", "slice parameters are unsupported at C boundaries");
	reject ("export(C) void f(borrowed int[] s){}", "borrowed parameters are unsupported on export(C)");
	foreach (string type in new string[] {"int*", "S*"}) {
		reject ("struct S{int x;} void f(borrowed " + type + "[] s){}", "unsupported slice element");
	}
	check ("struct S{int x;} void f(borrowed S[] s){s[0].x=1;}");
	foreach (string type in new string[] {"int[][]", "int[]*", "int[][2]"}) {
		reject ("void f(borrowed " + type + " s){}", "nested slices");
	}
	reject ("void f(borrowed int[] s){} void g(){int[1] a={1};f(a);}", "whole-array values");
	reject ("void f(borrowed int[] s){} void g(int* p){f(p);}", "argument");
	reject ("void f(borrowed int[] s){} void g(){f(null);}", "no null state");
	foreach (string pair in new string[] {"i8 u8", "int u32", "f32 int", "i16<4> i16<8>"}) {
		var types = pair.split (" ");
		reject ("void f(borrowed %s[] s){} void g(borrowed %s[] s){f(s);}".printf (types[0], types[1]), "argument");
	}
	reject ("void f(borrowed int[] s){int[] outer=s;{int[] inner=s;outer=inner;}}", "shorter lexical lifetime");
	reject ("void f(borrowed int[] s){int[] outer=s;{int[1] a={1};outer=slice(a);}}", "shorter lexical lifetime");
	foreach (string body in new string[] {"int* p=s;", "int[] a=slice(s);", "int* p=&s;", "int* p=&s[0];", "owned int[] a=s;", "release s;", "int[] a=move s;", "bool same=s==s;"}) {
		reject ("void f(borrowed int[] s){" + body + "}", "");
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice-bound/semantic/exact-types-mutable-places-provenance", identity);
	Test.add_func ("/slice-bound/semantic/contracts-escapes-and-deferrals", diagnostics);
	return Test.run ();
}

}
