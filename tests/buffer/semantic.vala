// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.BufferSemantic {
private SemanticResult analyze(string source) {
	var parsed = Parser.parse(new SourceFile.from_text("buffer", source));
	if (parsed.diagnostic != null) {
		GLib.error("%s", parsed.diagnostic.format());
	}
	return SemanticAnalyzer.analyze(parsed.unit);
}

private void eligible() {
	var t = new BuiltinTypes();
	foreach (var type in new SemanticType[] {t.bool_type, t.i8_type, t.u8_type, t.i16_type, t.u16_type, t.int_type, t.u32_type, t.f32_type, t.f64_type, t.raw_pointer_type}) {
		assert(BufferElementTypes.fixed_storage(type) && BufferElementTypes.trivial_destruction(type) && BufferElementTypes.defined_zero(type) && BufferElementTypes.supports(type));
		assert(t.slice_of(type) == t.slice_of(type));
		string spelling = type.display_name();
		var result = analyze("void f(int count){owned " + spelling + "[] values=new " + spelling + "[count];}");
		assert(result.diagnostic == null);
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = t.vector_of(type, lanes);
			if (vector == null) {
				continue;
			}
			assert(BufferElementTypes.supports(vector));
			spelling = vector.display_name();
			assert(analyze("void f(int n){owned " + spelling + "[] v=new " + spelling + "[n];}").diagnostic == null);
		}
	}
	foreach (var type in new SemanticType[] {t.void_type, t.pointer_to(t.int_type), t.pointer_to(t.f64_type), new HandleType("R"), new ClassType("C"), new StructType("S"), t.slice_of(t.int_type), t.array_of(t.int_type, 3)}) {
		assert(!BufferElementTypes.supports(type));
	}
}

private void identity() {
	var result = analyze("void use(f64[] values){} owned f64[] make(int n){return new f64[n];} void f(){owned f64[] a=make(3);use(a);owned f64[] b=move a;a=new f64[4];}");
	assert(result.diagnostic == null);
	var program = result.program;
	var canonical = program.types.slice_of(program.types.f64_type);
	assert(program.functions[0].symbol.parameters[0].semantic_type == canonical && program.functions[0].symbol.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert(program.functions[1].symbol.return_type == canonical && program.functions[1].symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER);
	assert(program.functions[2].locals[0].semantic_type == canonical && program.functions[2].locals[0].is_buffer_owner);
	assert(!SemanticDump.format(program).contains("calloc"));
}

private void invalid() {
	assert(analyze("struct S{int x;}void f(){owned S[] a=new S[2];}").diagnostic == null);
	foreach (string source in new string[] {
			"void f(){f64[] a=new f64[2];}",
			"void f(){owned f64[] a=new f64[2];owned f64[] b=a;}",
			"void f(){owned f64[] a=new f64[2];f64[] b=a;}",
			"void f(){owned f64[] a=new f64[-1];}",
			"void f(u32 n){owned f64[] a=new f64[n];}",
			"void f(){owned f64[] a=new f64[true];}",
			"void f(){owned int*[] a=new int*[2];}",
			"class C{}void f(){owned C[] a=new C[2];}",
			"void f<T>(int n){owned T[] a=new T[n];}",
			"class C{owned f64[] a;}",
			"class C{owned f64[] a;init(){}}",
			"class C{owned f64[] a;init(){this.a=new f64[2];this.a=new f64[3];}}",
			"class C{owned f64[] a;init(){int n=len(this.a);this.a=new f64[n];}}",
			"class C{property owned f64[] values { get { return new f64[2]; } }}"
		}) {
		var parsed = Parser.parse(new SourceFile.from_text("buffer-invalid", source));
		if (parsed.diagnostic != null) {
			continue;
		}
		var checked = SemanticAnalyzer.analyze(parsed.unit);
		if (checked.diagnostic == null) {
			GLib.error("accepted invalid buffer: %s", source);
		}
	}
}

int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/buffer/semantic/structural-element-authority", eligible);
	Test.add_func("/buffer/semantic/same-slice-identity-with-owner-contract", identity);
	Test.add_func("/buffer/semantic/rejected-elements-and-owner-consumers", invalid);
	return Test.run();
}

}
