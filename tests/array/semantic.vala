// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.ArraySemantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("array", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	string syntax = SyntaxDump.format (parsed.unit);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	assert (syntax == SyntaxDump.format (parsed.unit));
	return result.program;
}

private void reject(string text, string message) {
	var parsed = Parser.parse (new SourceFile.from_text ("array", text));
	if (parsed.diagnostic != null) {
		if (!parsed.diagnostic.message.contains (message)) {
			GLib.error ("expected %s: %s", message, parsed.diagnostic.format ());
		}
		return;
	}
	string syntax = SyntaxDump.format (parsed.unit);
	string? previous = null;
	for (int i = 0; i < 2; i++) {
		var result = SemanticAnalyzer.analyze (parsed.unit);
		if (result.diagnostic == null || !result.diagnostic.message.contains (message)) {
			GLib.error ("expected %s for %s; got %s", message, text, result.diagnostic == null ? "accepted" : result.diagnostic.format ());
		}
		assert (previous == null || previous == result.diagnostic.format ());
		previous = result.diagnostic.format ();
	}
	assert (syntax == SyntaxDump.format (parsed.unit));
}

private void identity() {
	var t = new BuiltinTypes ();
	assert (t.array_of (t.int_type, 16) == t.array_of (t.resolve ("i32"), 16));
	assert (t.array_of (t.i8_type, 4) != t.array_of (t.u8_type, 4));
	assert (t.array_of (t.i16_type, 4) != t.array_of (t.i16_type, 8));
	assert (t.array_of (t.int_type, 4) != t.array_of (t.f32_type, 4));
	assert (t.array_of (t.vector_of (t.i16_type, 4), 4) != t.array_of (t.i16_type, 4));
	assert (t.array_of (new BuiltinTypes ().int_type, 4) == null);
	int shapes = 0;
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		var element = t.resolve (name);
		foreach (int length in new int[] {1, 4, 1024}) {
			var array = t.array_of (element, length);
			assert (array.kind == TypeKind.ARRAY && array.element_type == element && array.length == length && array == t.array_of (element, length));
			assert (!array.is_typed_data_pointee () && !array.is_directly_dereferenceable_value_type () && !array.is_nullable_pointer_value ());
		}
		for (int n = 2; n <= 16; n *= 2) {
			var vector = t.vector_of (element, n);
			if (vector == null) {
				continue;
			}
			shapes++;
			var array = t.array_of (vector, 2);
			assert (array == t.array_of (vector, 2));
			string type = vector.display_name ();
			check ("void f(%s v,int i){%s[2] a={v,v};a[i]=v;%s x=a[i];}".printf (type, type, type));
		}
	}
	assert (shapes == 20);
	foreach (var type in new SemanticType[] {t.bool_type, t.vector_of (t.bool_type, 4), t.pointer_to (t.int_type), new HandleType ("Resource"), t.array_of (t.int_type, 4), t.void_type}) {
		assert (t.array_of (type, 4) == null);
	}
	var record = new StructType ("Pair");
	assert (t.array_of (record, 4) == t.array_of (record, 4));
	assert (!BufferElementTypes.supports (record));
	assert (t.array_of (t.int_type, 0) == null && t.array_of (t.int_type, 1025) == null);
	var p = check ("void f(){int[1] a={1};i32[1] b={2};}");
	assert (p.functions[0].locals[0].semantic_type == p.functions[0].locals[1].semantic_type);
}

private void places() {
	var p = check ("void f(int i){u8[2] a={128,255};a[i]=42;u8 x=a[i];i16<4> v=splat(1,4);i16<4>[1] blocks={v};i16 y=blocks[0][2];}");
	var f = p.functions[0];
	var array = (CheckedArrayLocalDeclaration) f.body.statements[0];
	assert (array.elements.length == 2 && array.elements[0].semantic_type == p.types.u8_type);
	var store = (CheckedStore) f.body.statements[1];
	var place = (CheckedArrayElementPlace) store.target;
	assert (place.local == array.local && place.array_type == array.local.semantic_type && place.index.semantic_type == p.types.int_type && place.traps_on_invalid);
	var load = (CheckedLoadExpression) ((CheckedLocalDeclaration) f.body.statements[2]).initializer;
	assert (load.source is CheckedArrayElementPlace && load.semantic_type == p.types.u8_type);
	var extract = (CheckedVectorExtractExpression) ((CheckedLocalDeclaration) f.body.statements[5]).initializer;
	assert (extract.vector is CheckedLoadExpression && ((CheckedLoadExpression) extract.vector).source is CheckedArrayElementPlace && extract.vector.semantic_type is VectorType);
	foreach (string type in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32"}) {
		check ("void f(%s i){int[2] a={1,2};a[i]=a[i]+1;}".printf (type));
	}
	check ("bool f(int i){u8[1] a={255};return 255==a[i] && a[i]==255;}");
	check ("void f(){u8[1] a={1};int x=42;a[0]=x as u8;}");
}

private void diagnostics() {
	foreach (string length in new string[] {"0", "1025", "9999999999999999999999999999999999999"}) {
		reject ("void f(){int[" + length + "] a={1};}", "1..1024");
	}
	foreach (string length in new string[] {"-1", "1+1", "n", "1.0", "1u8"}) {
		reject ("void f(int n){int[" + length + "] a={1};}", "");
	}
	foreach (string type in new string[] {"bool", "bool<4>", "int*", "f32*", "i16<4>*", "Pair*"}) {
		reject ("struct Pair{int x;} void f(){" + type + "[1] a={1};}", "unsupported array element");
	}
	check ("struct Pair{int x;} void f(){Pair[1] a={{x=1}};}");
	reject ("struct Pair{int x;} void f(){Pair[1] a={1};}", "struct boundary requires an initialized exact StructType Place");
	reject ("void f(){int[4][4] a={1};}", "nested arrays");
	reject ("void f(){int[4]* a=null;}", "array pointers");
	reject ("void f(int[4] a){}", "array parameters");
	reject ("int[4] f(){}", "array results");
	reject ("struct S{int[4] a;}", "array struct fields");
	reject ("void f(){int[2] a;}", "initializer");
	reject ("void f(){int[2] a={1};}", "exactly 2 elements, found 1");
	reject ("void f(){int[2] a={1,2,3};}", "exactly 2 elements, found 3");
	reject ("void f(){int[2] a={1,2,};}", "trailing commas");
	reject ("void f(){int[2] a={a[0],2};}", "unknown name 'a'");
	reject ("void f(){u8[1] a={256};}", "range");
	reject ("void f(){f32[1] a={1};}", "initializer of type 'f32'");
	reject ("void f(){i16<4>[1] a={{1,2,3,4}};}", "");
	foreach (string body in new string[] {"return a;", "use(a);", "int[2] b=a;", "a=a;", "bool b=a==a;", "int* p=a;", "int* p=&a;", "int* p=&a[0];"}) {
		reject ("void use(int* p){} int f(){int[2] a={1,2};" + body + "}", "");
	}
	foreach (string index in new string[] {"-1", "2", "(2)"}) {
		reject ("void f(){int[2] a={1,2};int x=a[" + index + "];}", "outside [0, 2)");
	}
	foreach (string index in new string[] {"true", "1.0", "splat(1,4)", "null"}) {
		reject ("void f(){int[2] a={1,2};a[" + index + "]=3;}", "scalar IntegerType");
	}
	reject ("void f(int i){i16<4> v=splat(1,4);i16 x=v[i];}", "dynamic indexing is unsupported");
	reject ("void f(){i16<4> v=splat(1,4);v[2]=1;}", "vector lanes are not assignment targets");
	reject ("void f(int i){i16<4> v=splat(1,4);i16<4>[1] a={v};a[i][2]=1;}", "vector lane assignment targets");
	reject ("void f(int i){u8[1] a={1};a[0]=i;}", "expected assignment value");
	reject ("void f(int* p){int x=p[0];}", "lane extraction requires a vector");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/array/semantic/identity-and-supported-shapes", identity);
	Test.add_func ("/array/semantic/places-and-literal-context", places);
	Test.add_func ("/array/semantic/diagnostics-and-deferrals", diagnostics);
	return Test.run ();
}

}
