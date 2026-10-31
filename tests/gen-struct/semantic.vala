// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Foreign;
namespace Astra.Tests.GenStructSemantic {
private SemanticResult analyze(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("generic-struct.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	return SemanticAnalyzer.analyze (parsed.unit);
}
private CheckedProgram check(string text) {
	var result = analyze (text);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private void reject(string text, string diagnostic) {
	var result = analyze (text);
	if (result.diagnostic == null || !result.diagnostic.message.contains (diagnostic)) {
		GLib.error ("expected %s, found %s", diagnostic, result.diagnostic == null ? "accepted" : result.diagnostic.message);
	}
}
private void identity() {
	var program = check ("struct Box<T>{T value;}struct Tagged<T>{int value;}struct B<T>{T value;}void f(){Box<int> a={value=1};Box<i32> b={value=2};Box<i8> c={value=3};Box<u8> d={value=4};Tagged<i8> e={value=5};Tagged<u8> f={value=6};B<int> g={value=7};Box<int>* p=&a;Box<i32>* q=&b;Box<i8>* s=&c;Box<u8>* u=&d;}");
	assert (program.structs.length == 0 && program.generic_structs.length == 3);
	Object definition = program.generic_structs[0].definition;
	assert (!(definition is StructSymbol) && !(definition is NativeInstanceSymbol));
	var box = program.generic_structs[0];
	var b = program.generic_structs[2];
	assert (box.type_parameters[0].semantic_type != b.type_parameters[0].semantic_type && box.fields[0].semantic_type == box.type_parameters[0].semantic_type);
	assert (box.fields[0].definition == box.definition && box.fields[0].ordinal == 0);
	var locals = program.functions[0].locals;
	assert (locals[0].semantic_type == locals[1].semantic_type && locals[2].semantic_type != locals[3].semantic_type && locals[4].semantic_type != locals[5].semantic_type && locals[0].semantic_type != locals[6].semantic_type);
	assert (locals[7].semantic_type == locals[8].semantic_type && locals[9].semantic_type != locals[10].semantic_type);
	var application = (GenericStructApplicationType) locals[0].semantic_type;
	assert (application.definition == box.definition && application.type_arguments[0] == program.types.int_type && application.field_type (box.fields[0]) == program.types.int_type);
}
private void fields() {
	var program = check ("struct Meta{int tag;f64 scale;}struct Pair<T,U>{T first;U second;}struct Bundle<T>{Pair<T,T> pair;Meta meta;i16<8> samples;bool<4> mask;void* opaque;}T first<T,U>(T a,U b){Pair<T,U> p={first=a,second=b};return p.first;}int f(){Bundle<f64> b={pair={first=1.0,second=2.0},meta={tag=7,scale=0.5},samples=splat(1,8),mask=splat(true,4),opaque=null};return b.meta.tag;}");
	var pair = program.generic_structs[0];
	var bundle = program.generic_structs[1];
	var nested = (GenericStructApplicationType) bundle.fields[0].semantic_type;
	assert (nested.definition == pair.definition && nested.type_arguments[0] == bundle.type_parameters[0].semantic_type && nested.type_arguments[1] == nested.type_arguments[0]);
	var function = program.generic_functions[0];
	var projection = (CheckedGenericStructFieldPlace) ((CheckedLoadExpression) ((CheckedReturnStatement) function.body.statements[1]).expression).source;
	assert (projection.field == pair.fields[0] && projection.semantic_type == function.definition.type_parameters[0].semantic_type);
	var initializer = ((CheckedStructLocalDeclaration) program.functions[0].body.statements[0]).initializers[0];
	assert (initializer.field == bundle.fields[0] && initializer.initializer.fields[0].field == pair.fields[0]);
	assert (SemanticDump.format (program).contains ("generic-field-place") && SemanticDump.format (program).contains ("storage-initializer"));
}
private void matrix() {
	var types = new BuiltinTypes ();
	int count = 0;
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "void*"}) {
		assert (GenericArgumentTypes.supports (types.resolve (name)));
		assert (check ("struct Box<T>{T value;}void f(Box<" + name + ">* p){}").generic_structs.length == 1);
		count++;
	}
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (types.resolve (name), lanes);
			if (vector == null) {
				continue;
			}
			assert (GenericArgumentTypes.supports (vector));
			check ("struct Box<T>{T value;}void f(Box<" + vector.display_name () + ">* p){}");
			count++;
		}
	}
	assert (count == 34);
}
private void negatives() {
	string declarations = "struct Box<T>{T value;}struct Pair<T,U>{T first;U second;}struct S{int value;}class C{}";
	foreach (string argument in new string[] {"void", "C", "int[]", "int[2]", "int*", "S*", "Pair<int,int>*"}) {
		reject (declarations + "void f(Box<" + argument + ">* p){}", "type argument");
	}
	foreach (string argument in new string[] {"S", "Pair<int,int>"}) {
		check (declarations + "void f(Box<" + argument + ">* p){}");
	}
	reject (declarations + "void f(){Pair p={first=1,second=2};}", "requires explicit type arguments");
	reject (declarations + "void f(){Pair<int> p={first=1,second=2};}", "requires exactly 2 type arguments, found 1");
	reject (declarations + "void f(){Pair<int,int,int> p={first=1,second=2};}", "requires exactly 2 type arguments, found 3");
	reject ("struct Bad<T,T>{T value;}", "duplicate type parameter");
	reject ("struct Bad<int>{int value;}", "builtin type name");
	reject ("struct S{int value;}struct Bad<S>{S value;}", "cannot shadow");
	reject ("struct Box<T>{T value;}struct Bad<Box>{Box value;}", "cannot shadow");
	reject ("struct A<T>{T value;}struct A<T,U>{T value;}", "conflicting generic struct");
	foreach (string other in new string[] {"struct A{int value;}", "class A{}"}) {
		reject ("struct A<T>{T value;}" + other, "duplicate");
	}
	reject ("struct Bad<T>{T value;int value;}", "duplicate field");
	reject ("struct Bad<T>{}", "empty struct");
	foreach (string field in new string[] {"void", "int*", "int[]", "int[2]"}) {
		reject ("struct Bad<T>{" + field + " value;}", "unsupported generic struct field");
	}
	reject ("struct Bad<T>{T[] value;}", "signature-derived");
	foreach (string field in new string[] {"T*", "T[2]", "T<4>"}) {
		reject ("struct Bad<T>{" + field + " value;}", "type parameters cannot occur");
	}
	reject (declarations + "void f<T>(T value){Box<T>* p=null;}", "parameterized generic Struct*");
	reject (declarations + "void f<T>(T value){Box<T> b={value=value};void* p=&b;}", "parameterized generic Struct*");
	assert (check (declarations + "void f(){Box<int> a={value=1};Box<int> b=a;}").functions[0].body.statements[1] is CheckedStructCopy);
	assert (check (declarations + "void f(){Box<int> a={value=1};a=a;}").functions[0].body.statements[1] is CheckedStructCopy);
	reject (declarations + "Box<int> f(){return 1;}", "struct boundary requires an initialized exact StructType Place");
	assert (check (declarations + "void f(Box<int> p){}").functions[0].symbol.parameters[0].struct_value_contract != null);
	// Approved M15 replacement: closed copied records are ordinary Class
	// fields; the integer getter still fails its exact record result type.
	check (declarations + "class D{Box<int> value;}");
	reject (declarations + "class D{property Box<int> value{get{return 1;}}}", "struct boundary requires");
	check (declarations + "T id<T>(T x){return x;}void f(){Box<int> a={value=1};id<Box<int>>(a);}");
	reject (declarations + "void f(){Pair<int,f64> p={first=1};}", "missing initializer for field 'second'");
	reject (declarations + "void f(){Pair<int,f64> p={first=1,first=2,second=3.5};}", "duplicate initializer");
	reject (declarations + "void f(){Pair<int,f64> p={first=1,missing=2};}", "unknown initializer field 'missing' in struct 'Pair<int,f64>'");
}
private void resources() {
	var file = new SourceFile.from_text ("foreign-input", "Resource");
	var span = SourceSpan (file, 0, file.length);
	var handles = new GenericArray<ForeignHandleInput> ();
	handles.add (new ForeignHandleInput (span, span, new CForeignCleanupContract ("destroy")));
	foreach (string source in new string[] {"struct Box<T>{T value;}void f(Box<Resource>* p){}", "struct Bad<T>{Resource value;}", "struct Resource<T>{T value;}"}) {
		var parsed = Parser.parse (new SourceFile.from_text ("resource-argument.astra", source));
		assert (parsed.diagnostic == null);
		var result = SemanticAnalyzer.analyze (parsed.unit, null, handles);
		assert (result.program == null && result.diagnostic != null);
		assert (result.diagnostic.message.contains ("GEN1_PLAIN_COPY") || result.diagnostic.message.contains ("unsupported generic struct field") || result.diagnostic.message.contains ("conflicting generic struct"));
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-struct/semantic/exact-identities-nominality-phantom-pointers", identity);
	Test.add_func ("/gen-struct/semantic/parameterized-fields-nested-initializers", fields);
	Test.add_func ("/gen-struct/semantic/complete-34-type-universe", matrix);
	Test.add_func ("/gen-struct/semantic/invalid-unused-definitions-and-uses", negatives);
	Test.add_func ("/gen-struct/semantic/resource-argument-field-and-namespace-rejection", resources);
	return Test.run ();
}
}
