// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
namespace Astra.Tests.StructAggSemantic {
private SemanticResult analyze(string source) {
	var parsed = Parser.parse (new SourceFile.from_text ("nested.astra", source));
	assert (parsed.diagnostic == null);
	return SemanticAnalyzer.analyze (parsed.unit);
}

private void positive() {
	var result = analyze ("struct I { int x; f64 gain; } struct O { I inner; } int f(){O o={inner={x=1,gain=0.5}};o.inner.x=42;return o.inner.x;}");
	assert (result.diagnostic == null);
	var program = result.program;
	var body = program.functions[0].body;
	var declaration = (CheckedStructLocalDeclaration) body.statements[0];
	var nested = declaration.initializers[0].initializer;
	assert (nested.semantic_type == program.structs[0].semantic_type && nested.fields[0].field == program.structs[0].fields[0]);
	var field = (CheckedFieldPlace) ((CheckedStore) body.statements[1]).target;
	assert (field.aggregate is CheckedFieldPlace && ((CheckedFieldPlace) field.aggregate).aggregate is CheckedLocalPlace);
	assert (field.field == program.structs[0].fields[0] && field.semantic_type == field.field.semantic_type);
	assert (((CheckedFieldPlace) field.aggregate).field == program.structs[1].fields[0]);
	assert (SemanticDump.format (program).contains ("I::x") && SemanticDump.format (program).contains ("storage-initializer"));
}

private void policy() {
	var types = new BuiltinTypes ();
	foreach (string name in new string[] {"int", "i8", "u8", "i16", "u16", "u32", "f32", "f64", "bool", "void*"}) {
		var type = types.resolve (name);
		assert (NativeFieldTypes.supports (type) && NativeFieldTypes.supports (type, true));
	}
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			if (!VectorType.supports (types.resolve (name), lanes)) {
				continue;
			}
			string shape = "%s<%d>".printf (name, lanes);
			assert (analyze ("struct S{" + shape + " value;}").diagnostic == null);
			assert (analyze ("class C{" + shape + " value;}").diagnostic.message.contains ("vector struct fields are unsupported"));
		}
	}
	assert (analyze ("struct I{int x;}class C{I inner;}").diagnostic == null);
	foreach (string type in new string[] {"void", "int*", "I*", "int[2]", "int[]", "C"}) {
		assert (analyze ("struct I{int x;}class C{}struct S{" + type + " value;}").diagnostic != null);
	}
}

private void invalid() {
	string prefix = "struct I{int x;int y;}struct O{I inner;}int f(){";
	string[,] cases = {
		{
			"O o={inner={x=1}};return 0;}", "missing initializer for field 'inner.y'"
		},
		{
			"O o={inner={x=1,x=2,y=3}};return 0;}", "duplicate initializer for field 'inner.x'"
		},
		{
			"O o={inner={z=1,x=2,y=3}};return 0;}", "unknown initializer field 'inner.z'"
		},
		{
			"O o={inner={x=true,y=3}};return 0;}", "field 'inner.x' expects initializer of type 'int'"
		},
		{
			"O o={inner={x=o.inner.x,y=2}};return 0;}", "unknown name 'o'"
		},
		{
			"O o={inner={x=1,y=2}};return o.inner.z;}", "unknown field 'z'"
		}
	};
	for (int i = 0; i < cases.length[0]; i++) {
		var result = analyze (prefix + cases[i, 0]);
		if (result.diagnostic == null || !result.diagnostic.message.contains (cases[i, 1])) {
			GLib.error ("case %d: %s", i, result.diagnostic == null ? "accepted" : result.diagnostic.message);
		}
	}
	assert (analyze (prefix + "I i={x=1,y=2};O o={inner=i};return 0;}").diagnostic == null);
	foreach (string source in new string[] {"struct A{A self;}", "struct A{B b;}struct B{A a;}", "struct A{B b;}struct B{C c;}struct C{A a;}"}) {
		assert (analyze (source).diagnostic.message.contains ("recursive by-value struct layout"));
	}
	foreach (string body in new string[] {"O o={inner={x=1,y=2}};I i=o.inner;return 0;}", "O o={inner={x=1,y=2}};o.inner=o.inner;return 0;}"}) {
		var result = analyze (prefix + body);
		assert (result.diagnostic == null && result.program.functions[0].body.statements[1] is CheckedStructCopy);
	}
	var lane = Parser.parse (new SourceFile.from_text ("lane.astra", "struct S{i16<8> v;}int f(){S s={v=splat(0,8)};s.v[0]=1;return 0;}"));
	assert (lane.diagnostic == null);
	assert (SemanticAnalyzer.analyze (lane.unit).diagnostic.message.contains ("vector lanes are not assignment targets"));
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-agg/semantic/exact-recursive-places-initializers", positive);
	Test.add_func ("/struct-agg/semantic/field-owner-policy-all-vector-shapes", policy);
	Test.add_func ("/struct-agg/semantic/recursive-diagnostics-copies-cycles-lanes", invalid);
	return Test.run ();
}

}
