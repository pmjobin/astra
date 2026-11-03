// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
namespace Astra.Tests.StructCopySemantic {
private SemanticResult analyze(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("copy.astra", text));
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

private void reject(string text, string message) {
	var result = analyze (text);
	if (result.diagnostic == null || !result.diagnostic.message.contains (message)) {
		GLib.error ("expected %s, found %s", message, result.diagnostic == null ? "accepted" : result.diagnostic.message);
	}
}

private void authority() {
	var types = new BuiltinTypes ();
	int count = 0;
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "i32", "u32", "f32", "f64", "void*"}) {
		assert (CopyabilityAuthority.of (types.resolve (name), (type) => null) == Copyability.COPYABLE);
	}
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (types.resolve (name), lanes);
			if (vector == null) {
				continue;
			}
			assert (CopyabilityAuthority.of (vector, (type) => null) == Copyability.COPYABLE);
			count++;
		}
	}
	assert (count == 24);
	var negative = new GenericArray<SemanticType> ();
	negative.add (types.void_type);
	negative.add (new HandleType ("Resource"));
	negative.add (new ClassType ("C"));
	negative.add (types.pointer_to (types.int_type));
	negative.add (types.array_of (types.int_type, 2));
	negative.add (types.slice_of (types.int_type));
	negative.add (new TypeParameterType ("T"));
	negative.add (new VectorType (types.f64_type, 4));
	assert (CopyabilityAuthority.of (types.vector_of (types.f64_type, 2), (type) => null) == Copyability.COPYABLE);
	foreach (var type in negative) {
		assert (CopyabilityAuthority.of (type, (t) => null) == Copyability.NOT_COPYABLE);
	}
	var inner = new StructType ("Inner");
	var outer = new StructType ("Outer");
	var inner_fields = new GenericArray<SemanticType> ();
	inner_fields.add (types.f64_type);
	var outer_fields = new GenericArray<SemanticType> ();
	outer_fields.add (inner);
	outer_fields.add (inner);
	CopyabilityFields graph = (type) => type == inner ? inner_fields : type == outer ? outer_fields : null;
	assert (CopyabilityAuthority.of (outer, graph) == Copyability.COPYABLE);
	inner_fields.add (negative[1]);
	assert (CopyabilityAuthority.of (outer, graph) == Copyability.NOT_COPYABLE);
	inner_fields.remove_index (1);
	inner_fields.add (outer);
	assert (CopyabilityAuthority.of (outer, graph) == Copyability.NOT_COPYABLE);
	assert (CopyabilityAuthority.of (new StructType ("Missing"), graph) == Copyability.NOT_COPYABLE);
}

private void contexts() {
	var program = check ("struct I{int x;}struct O{I a;I b;}void f(){O a={a={x=1},b={x=2}};O b=a;I c=b.a;b.b=c;b.a=b.b;O* p=&b;*p=a;O d=*p;*p=*p;}");
	var body = program.functions[0].body;
	var copy = (CheckedStructCopy)body.statements[1];
	assert (copy.initializes_destination && copy.copyability == Copyability.COPYABLE && copy.destination is CheckedLocalPlace && copy.source is CheckedLocalPlace);
	assert (copy.semantic_type == program.structs[1].semantic_type && copy.source.semantic_type == copy.destination.semantic_type);
	assert (((CheckedStructCopy)body.statements[2]).source is CheckedFieldPlace);
	assert (((CheckedStructCopy)body.statements[4]).destination is CheckedFieldPlace);
	assert (((CheckedStructCopy)body.statements[6]).destination is CheckedDereferencePlace);
	assert (((CheckedStructCopy)body.statements[7]).source is CheckedDereferencePlace);
	string dump = SemanticDump.format (program);
	assert (dump.contains ("struct-copy") && dump.contains ("snapshot-before-write") && !dump.contains ("StructValue"));
	var generic = check ("struct Box<T>{T value;}void f(){Box<int> a={value=1};Box<i32> b=a;b=a;}");
	var g = (CheckedStructCopy)generic.functions[0].body.statements[1];
	assert (g.semantic_type == generic.functions[0].locals[0].semantic_type && !g.semantic_type.is_parameterized ());
}

private void negatives() {
	string ordinary = "struct A{int x;}struct B{int x;}";
	reject (ordinary + "void f(){A a={x=1};B b=a;}", "exact nominal type 'B', found 'A'");
	reject (ordinary + "void f(){A a={x=1};B b={x=2};a=b;}", "exact nominal type 'A', found 'B'");
	reject (ordinary + "void f(){A a=a;}", "initialized local Place");
	reject (ordinary + "void f(){if(true){A a={x=1};}A b=a;}", "initialized local Place");
	reject (ordinary + "int f(){A a={x=1};return a;}", "whole-struct values");
	reject (ordinary + "void g(int x){}void f(){A a={x=1};g(a);}", "whole-struct values");
	reject (ordinary + "void f(){A a={x=1};if(a==a){}}", "whole-struct values");
	assert (check (ordinary + "void f(A a){}").functions[0].symbol.parameters[0].struct_value_contract != null);
	assert (check (ordinary + "A f(A a){return a;}").functions[0].body.statements[0] is CheckedStructReturn);
	reject (ordinary + "struct O{int dummy;property A value{get{return 1;}}}", "struct boundary requires");
	string generic = "struct Box<T>{T value;}struct Other<T>{T value;}struct Tagged<T>{int value;}";
	reject (generic + "void f(){Box<i8> a={value=1};Box<u8> b=a;}", "exact nominal type");
	reject (generic + "void f(){Box<int> a={value=1};Other<int> b=a;}", "exact nominal type");
	reject (generic + "void f(){Tagged<i8> a={value=1};Tagged<u8> b=a;}", "exact nominal type");
	check (generic + "void f<T>(T value){Box<T> a={value=value};Box<T> b=a;}");
	check (generic + "T identity<T>(T x){return x;}void f(){Box<int> a={value=1};identity<Box<int>>(a);}");
	foreach (string capability in new string[] {"Copy", "Move"}) {
		reject ("T f<T>(T x) where T:" + capability + " {return x;}", "unknown generic capability");
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-copy/semantic/one-recursive-authority-24-vectors-negative-cycle", authority);
	Test.add_func ("/struct-copy/semantic/dedicated-copy-contexts-exact-places", contexts);
	Test.add_func ("/struct-copy/semantic/nominality-storage-generic-abi-exclusions", negatives);
	return Test.run ();
}

}
