// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.SliceSemantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("slice", text));
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
	var parsed = Parser.parse (new SourceFile.from_text ("slice", text));
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
	assert (t.slice_of (t.int_type) == t.slice_of (t.resolve ("i32")));
	assert (t.slice_of (t.i8_type) != t.slice_of (t.u8_type));
	assert (t.slice_of (t.int_type) != t.slice_of (t.u32_type));
	assert (t.slice_of (t.f32_type) != t.slice_of (t.int_type));
	assert (t.slice_of (t.vector_of (t.i16_type, 4)) != t.slice_of (t.vector_of (t.i16_type, 8)));
	assert (t.slice_of (new BuiltinTypes ().int_type) == null);
	int shapes = 0;
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		var element = t.resolve (name);
		var slice = t.slice_of (element);
		assert (slice.kind == TypeKind.SLICE && slice.element_type == element && slice == t.slice_of (element));
		assert (slice.is_lexically_borrowed_value () && !slice.is_nullable_pointer_value () && !slice.is_ownable_handle_type () && !slice.is_typed_data_pointee ());
		check ("void f(%s x){%s[1] a={x};%s[] s=slice(a);s[0]=x;%s y=s[0];}".printf (name, name, name, name));
		for (int lanes = 2; lanes <= 16; lanes *= 2) {
			var vector = t.vector_of (element, lanes);
			if (vector == null) {
				continue;
			}
			shapes++;
			assert (t.slice_of (vector) == t.slice_of (vector));
			string type = vector.display_name ();
			check ("void f(%s v,int i){%s[2] a={v,v};%s[] s=slice(a);s[i]=v;%s x=s[i];}".printf (type, type, type, type));
		}
	}
	assert (shapes == 20);
	foreach (var element in new SemanticType[] {t.bool_type, t.vector_of (t.bool_type, 4), t.raw_pointer_type}) {
		assert (t.slice_of (element) != null);
	}
	foreach (var element in new SemanticType[] {t.pointer_to (t.int_type), new HandleType ("Resource"), t.array_of (t.int_type, 4), t.slice_of (t.int_type), t.void_type}) {
		assert (t.slice_of (element) == null);
	}
	var record = new StructType ("Pair");
	assert (t.slice_of (record) == t.slice_of (record));
	assert (!BufferElementTypes.supports (record));
	var p = check ("void f(){int[4] a={1,2,3,4};i32[2] b={1,2};int[] s=slice(a);i32[] copy=s;copy=slice(b);}");
	assert (p.functions[0].locals[2].semantic_type == p.functions[0].locals[3].semantic_type);
}

private void places() {
	var p = check ("void f(int i){u8[2] a={128,255};u8[] s=slice(a);s[i]=42;u8 x=s[i];i16<8> v=splat(1,8);i16<8>[1] blocks={v};i16<8>[] view=slice(blocks);i16 y=view[0][2];}");
	var f = p.functions[0];
	var construction = (CheckedSliceFromArrayExpression) ((CheckedLocalDeclaration) f.body.statements[1]).initializer;
	assert (construction.local == f.locals[0] && construction.array_type.element_type == p.types.u8_type && construction.start == null && construction.count == null);
	var store = (CheckedStore) f.body.statements[2];
	var place = (CheckedSliceElementPlace) store.target;
	assert (place.semantic_type == p.types.u8_type && place.slice_type == f.locals[1].semantic_type && place.traps_on_invalid && place.index.semantic_type == p.types.int_type);
	var load = (CheckedLoadExpression) ((CheckedLocalDeclaration) f.body.statements[3]).initializer;
	assert (load.source is CheckedSliceElementPlace && load.semantic_type == p.types.u8_type);
	var extract = (CheckedVectorExtractExpression) ((CheckedLocalDeclaration) f.body.statements[7]).initializer;
	assert (extract.vector is CheckedLoadExpression && ((CheckedLoadExpression) extract.vector).source is CheckedSliceElementPlace && extract.vector.semantic_type is VectorType);
	foreach (string start in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
		foreach (string count in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
			check ("void f(%s start,%s count){int[2] a={1,2};int[] s=slice(a,start,count);s[start]=s[count];}".printf (start, count));
		}
	}
	check ("bool f(int i){u8[1] a={255};u8[] s=slice(a);return 255==s[i] && s[i]==255 && 255==slice(a)[i];}");
	check ("void f(){u8[1] a={1};u8[] s=slice(a);int x=42;s[0]=x as u8;}");
	p = check ("int f(int start){int[2] a={1,2};int[] s=slice(a,start,0);return len(s)+len(a);}");
	var sum = (CheckedBinaryExpression) ((CheckedReturnStatement) p.functions[0].body.statements[2]).expression;
	assert (sum.left is CheckedLengthExpression && ((CheckedLengthExpression) sum.left).slice != null && ((CheckedLengthExpression) sum.right).array != null && sum.semantic_type == p.types.int_type);
}

private void borrowing() {
	var p = check ("void f(){int[2] a={1,2};int[] s=slice(a);int[] alias=s;{int[] inner=alias;inner[0]=42;}}");
	var f = p.functions[0];
	var construct = ((CheckedLocalDeclaration) f.body.statements[1]).initializer;
	var copy = ((CheckedLocalDeclaration) f.body.statements[2]).initializer;
	assert (BorrowProvenance.for_expression (construct).origin == f.locals[0]);
	assert (BorrowProvenance.for_expression (copy).origin == f.locals[1]);
	var inner = (CheckedBlockStatement) f.body.statements[3];
	assert (f.locals[0].lexical_region.outlives (inner.region));
	assert (!inner.region.outlives (f.locals[0].lexical_region));
	check ("void f(){int[4] a={1,2,3,4};int[] s=slice(a);{int[] inner=slice(a,1,2);int[] copy=inner;copy[0]=1;}}");
	reject ("void f(){int[1] a={1};int[] outer=slice(a);{int[1] inner={2};outer=slice(inner);}}", "borrow from 'inner' cannot be stored in slice 'outer'");
	reject ("void f(){int[1] a={1};int[] outer=slice(a);{int[] inner=slice(a);outer=inner;}}", "shorter lexical lifetime");
	reject ("void f(){int[1] a={1};int[] outer=slice(a);while(true){int[1] b={2};int[] inner=slice(b);outer=inner;break;}}", "shorter lexical lifetime");
	reject ("void f(){{int[1] a={1};}int[] s=slice(a);}", "direct fixed-array local");
}

private void diagnostics() {
	foreach (string type in new string[] {"int*", "f32*", "i16<4>*", "Pair*"}) {
		reject ("struct Pair{int x;} void f(){" + type + "[] a=null;}", "unsupported slice element");
	}
	check ("struct Pair{int x;} void f(){Pair[1] a={{x=1}};Pair[] view=slice(a);}");
	reject ("struct Pair{int x;} void f(){Pair[] a=null;}", "a slice has no null state");
	foreach (string type in new string[] {"int[][]", "int[]*", "int[][2]"}) {
		reject ("void f(){" + type + " s=null;}", "nested slices");
	}
	reject ("void f(){int[2][] a=null;}", "nested arrays");
	check ("void f(int[] s){}");
	foreach (string type in new string[] {"bool", "bool<4>"}) {
		reject ("void f(){" + type + "[] a=null;}", "no null state");
	}
	reject ("int[] f(){}", "slice results");
	reject ("struct S{int[] s;}", "slice struct fields");
	reject ("void f(){int[] s;}", "initializer");
	reject ("void f(){int[] s=null;}", "no null state");
	foreach (string expression in new string[] {"slice()", "slice(a,1)", "slice(a,0,1,2)", "slice((a))", "slice(s)", "slice(s,0,1)", "slice(p,1)", "slice(p,0,1)", "len()", "len(a,1)", "len(p)", "len(1)", "len(splat(1,4))"}) {
		reject ("void f(int* p){int[2] a={1,2};int[] s=slice(a);int x=len(" + expression + ");}", "");
	}
	foreach (string range in new string[] {"-1,0", "3,0", "0,-1", "1,2", "0,3"}) {
		reject ("void f(){int[2] a={1,2};int[] s=slice(a," + range + ");}", "slice");
	}
	foreach (string value in new string[] {"true", "1.0", "splat(1,4)", "null"}) {
		reject ("void f(){int[2] a={1,2};int[] s=slice(a," + value + ",0);}", "scalar IntegerType");
		reject ("void f(){int[2] a={1,2};int[] s=slice(a,0," + value + ");}", "scalar IntegerType");
		reject ("void f(){int[2] a={1,2};int[] s=slice(a);s[" + value + "]=1;}", "scalar IntegerType");
	}
	foreach (string statement in new string[] {"int[] b=a;", "int[2] b=s;", "bool b=s==s;", "bool b=s!=s;", "bool b=s==null;", "if(s){}", "int* p=s;", "int* p=&s;", "int* p=&s[0];", "int x=s.length;", "int* p=s.data;", "owned int[] o=s;", "release s;", "int[] moved=move s;"}) {
		reject ("void f(){int[2] a={1,2};int[] s=slice(a);" + statement + "}", "");
	}
	reject ("void f(){i8[1] a={1};u8[1] b={1};i8[] s=slice(a);s=slice(b);}", "expected assignment value");
	reject ("void f(){i16<4> v=splat(1,4);i16<4>[1] a={v};i16<4>[] s=slice(a);s[0][2]=1;}", "vector lane assignment targets");
	reject ("void f(int x){u8[1] a={1};u8[] s=slice(a);s[0]=x;}", "expected assignment value");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/slice/semantic/identity-and-supported-shapes", identity);
	Test.add_func ("/slice/semantic/places-length-and-literal-context", places);
	Test.add_func ("/slice/borrow/regions-copies-aliases-and-escapes", borrowing);
	Test.add_func ("/slice/semantic/diagnostics-and-deferrals", diagnostics);
	return Test.run ();
}
}
