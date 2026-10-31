// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.VectorMemorySemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("vecmem.astra", text));
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	string before = SyntaxDump.format (syntax.unit);
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	assert (before == SyntaxDump.format (syntax.unit));
	return result.program;
}

private void reject(string text, string message, bool parse = false) {
	var syntax = Parser.parse (new SourceFile.from_text ("vecmem.astra", text));
	if (parse) {
		assert (syntax.unit == null && syntax.diagnostic.message.contains (message));
		return;
	}
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	string before = SyntaxDump.format (syntax.unit);
	string? previous = null;
	for (int i = 0; i < 2; i++) {
		var result = SemanticAnalyzer.analyze (syntax.unit);
		if (result.program != null || !result.diagnostic.message.contains (message)) {
			GLib.error ("Expected %s for %s; got %s", message, text, result.diagnostic == null ? "accepted" : result.diagnostic.format ());
		}
		assert (previous == null || previous == result.diagnostic.format ());
		previous = result.diagnostic.format ();
	}
	assert (SyntaxDump.format (syntax.unit) == before);
}

private void identity() {
	var types = new BuiltinTypes ();
	var pointers = new GenericArray<TypedPointerType> ();
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		for (int lanes = 2; lanes <= 16; lanes *= 2) {
			var type = types.vector_of (types.resolve (element), lanes);
			if (type == null) {
				continue;
			}
			var pointer = types.pointer_to (type);
			assert (type.is_typed_data_pointee () && type.is_directly_dereferenceable_value_type ());
			assert (pointer.pointee == type && pointer == types.pointer_to (type) && pointer.kind == TypeKind.TYPED_POINTER);
			assert (pointer.is_nullable_pointer_value () && !pointer.is_ownable_handle_type ());
			foreach (var prior in pointers) {
				assert (prior != pointer);
			}
			pointers.add (pointer);
			string name = type.display_name ();
			var p = check ("bool f(%s* p,%s* q){%s* n=null;n=p;return (p==q)|(null!=p)|(q==null)|(n!=q);}".printf (name, name, name));
			assert (p.functions[0].symbol.parameters[0].semantic_type == p.functions[0].symbol.parameters[1].semantic_type);
		}
	}
	assert (pointers.length == 20);
	for (int lanes = 2; lanes <= 4; lanes *= 2) {
		var p = check ("void f(int<%d>* p,i32<%d>* q){int<%d>* r=q;}".printf (lanes, lanes, lanes));
		assert (p.functions[0].symbol.parameters[0].semantic_type == p.functions[0].symbol.parameters[1].semantic_type);
		assert (types.pointer_to (types.vector_of (types.int_type, lanes)) == types.pointer_to (types.vector_of (types.resolve ("i32"), lanes)));
	}
	var syntax = Parser.parse (new SourceFile.from_text ("syntax", "void f(i16 < 008 > /*shape*/ * p){}"));
	var pointer_syntax = (PointerTypeSyntax) syntax.unit.functions[0].parameters[0].type_name;
	assert (pointer_syntax.pointee is VectorTypeSyntax && pointer_syntax.spelling () == "i16<008>*");
	check ("void f(i16 < 008 > /*shape*/ * p){}");
}

private void places() {
	var p = check ("i16<8> read(i16<8>* parameter){return *parameter;} void f(){i16<8> x=splat(1,8);i16<8>* p=&x;*p=*p;i16<8> y=*p;i16 z=(*p)[2];*p=insert(*p,2,42);}");
	var f = p.functions[1];
	assert (f.locals[0].address_taken && !f.locals[1].address_taken && !f.locals[2].address_taken);
	var address = (CheckedAddressOfExpression) ((CheckedLocalDeclaration) f.body.statements[1]).initializer;
	assert (address.local == f.locals[0] && ((TypedPointerType) address.semantic_type).pointee == address.local.semantic_type);
	var store = (CheckedStore) f.body.statements[2];
	assert (store.target is CheckedDereferencePlace && store.target.semantic_type is VectorType);
	assert (store.value is CheckedLoadExpression && ((CheckedLoadExpression) store.value).source is CheckedDereferencePlace);
	var extract = (CheckedVectorExtractExpression) ((CheckedLocalDeclaration) f.body.statements[4]).initializer;
	assert (extract.vector is CheckedLoadExpression && ((CheckedLoadExpression) extract.vector).source is CheckedDereferencePlace);
	var load = (CheckedLoadExpression) ((CheckedReturnStatement) p.functions[0].body.statements[0]).expression;
	assert (((CheckedDereferencePlace) load.source).provenance.region == p.functions[0].body.region);
	check ("bool f(u8<16>* p){return 255==(*p)[0] && (*p)[0]==255;} bool g(){u8<16> v=splat(255,16);return (*(&v))[0]==255;}");
	check ("bool f(i16<8>* p){*p=splat(42,8);return all(*p==splat(42,8));}");
}

private void regions() {
	var p = check ("void use(f32<4>* a,f32<4>* b){} void f(f32<4>* parameter){f32<4> x=splat(1.0,4);f32<4>* p=&x;if(true){f32<4>* q=p;f32<4>* r=parameter;use(&x,&x);*q=*r;} }");
	var f = p.functions[1];
	var root = f.body.region;
	var branch = (CheckedIf) f.body.statements[2];
	assert (root.outlives (branch.then_body.region) && !branch.then_body.region.outlives (root));
	var address = BorrowProvenance.for_expression (((CheckedLocalDeclaration) f.body.statements[1]).initializer);
	assert (address.region == root && address.origin == f.locals[0]);
	var copied = BorrowProvenance.for_expression (((CheckedLocalDeclaration) branch.then_body.statements[0]).initializer);
	assert (copied.region == root && copied.outlives (f.locals[2].lexical_region));
	assert (copied.snapshot ().origin == DataPointerOrigin.LOCAL && copied.snapshot ().origin_ordinal == 1);
	var parameter = BorrowProvenance.for_expression (((CheckedLocalDeclaration) branch.then_body.statements[1]).initializer);
	assert (parameter.snapshot ().origin == DataPointerOrigin.PARAMETER && parameter.region == root);
	foreach (string body in new string[] {"if(true){i16<8> inner=splat(1,8);p=&inner;}", "while(false){i16<8> inner=splat(1,8);p=&inner;}", "if(true){i16<8>* q=p;p=q;}"}) {
		reject ("void f(){i16<8>* p=null;" + body + "}", "shorter lexical lifetime");
	}
	check ("void use(i16<8>* p){} void f(){i16<8> x=splat(0,8);use(&x);if(true){i16<8>* p=&x;i16<8>* q=p;*q=splat(1,8);}}");
}

private void diagnostics() {
	for (int n = 2; n <= 16; n *= 2) {
		reject ("void f(bool<%d>* p){}".printf (n), "bool-vector pointers are unsupported");
		reject ("void f(){bool<%d> m=splat(true,%d);void* p=&m;}".printf (n, n), "direct local");
	}
	foreach (string pair in new string[] {"i8<16>,u8<16>", "i16<8>,u16<8>", "int<4>,u32<4>", "i16<4>,i16<8>", "i32<4>,f32<4>"}) {
		var t = pair.split (",");
		foreach (string op in new string[] {"==", "!="}) {
			reject ("bool f(%s* p,%s* q){return p%s q;}".printf (t[0], t[1], op), "matching non-void operands");
		}
		reject ("void f(%s* p){%s* q=p;}".printf (t[0], t[1]), "expected initializer");
	}
	foreach (string t in new string[] {"i8<16>", "i16<8>", "f32<4>"}) {
		reject (t + "* f(){return null;}", "return-lifetime contracts");
		reject ("extern(C) void f(" + t + "* p);", "typed data pointers are not supported by the C ABI yet");
		reject ("export(C) void f(" + t + "* p){}", "typed data pointers are not supported by the C ABI yet");
		reject ("void f(" + t + "** p){}", "depth greater than one");
		reject ("void f(" + t + "* p){if(p){}}", "condition must have type 'bool'");
		foreach (string op in new string[] {"+", "-", "<", "<=", ">", ">="}) {
			reject ("void f(" + t + "* p){int x=p" + op + "1;}", "requires");
		}
		foreach (string index in new string[] {"0", "1"}) {
			reject ("void f(" + t + "* p){" + t + " v=p[" + index + "];}", "lane extraction requires a vector");
		}
		reject ("void f(" + t + "* p){int x=++p;}", "requires an 'int' operand");
		reject ("void f(" + t + "* p){p++;}", "", true);
		reject ("void f(" + t + " p){void* q=&p;}", "direct local");
		reject ("void f(" + t + "* p){void* q=p as void*;}", "integer");
	}
	reject ("void f(i8<16>* p){u8<16>* q=p as u8<16>*;}", "integer");
	reject ("void f(f32<4>* p){int<4>* q=p as int<4>*;}", "integer");
	reject ("void f(i16<8>* p,i8<8> v){*p=v;}", "expected assignment value");
	check ("void f(i16<8>* p,i8<8> v){*p=v as i16<8>;}");
	reject ("void f(i16<8>* p){(*p)[3]=42;}", "vector lanes are not assignment targets; use insert()");
	foreach (string operand in new string[] {"*p", "v[2]", "s.x", "(v)"}) {
		reject ("void f(){void* q=&" + operand + ";}", "", true);
	}
	reject ("class S{f32<4> v;}", "vector struct fields are unsupported");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vecmem/semantic/all-shapes-exact-identity-syntax-null-equality", identity);
	Test.add_func ("/vecmem/semantic/generic-places-and-value-extraction", places);
	Test.add_func ("/vecmem/borrow/regions-stored-call-bound-aliases-escapes", regions);
	Test.add_func ("/vecmem/semantic/deferrals-and-exact-store-types", diagnostics);
	return Test.run ();
}
}
