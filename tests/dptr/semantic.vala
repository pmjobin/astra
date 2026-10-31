// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.DataPointerSemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("dptr.astra", text));
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.program == null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string message, bool parsing = false) {
	var syntax = Parser.parse (new SourceFile.from_text ("dptr.astra", text));
	if (parsing) {
		if (syntax.unit != null || syntax.diagnostic == null) {
			GLib.error ("Expected syntax rejection for %s", text);
		}
		return;
	}
	if (syntax.unit == null) {
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
	var p = check ("struct Pair{int x;} void f(i8* a,u8* b,i16* c,u16* d,int* e,i32* f,u32* g,f32* h,Pair* i,void* j){}");
	var parameters = p.functions[0].symbol.parameters;
	for (int i = 0; i < 9; i++) {
		var type = (TypedPointerType) parameters[i].semantic_type;
		assert (type.kind == TypeKind.TYPED_POINTER && type.is_nullable_pointer_value () && !type.is_ownable_handle_type ());
		assert (p.types.pointer_to (type.pointee) == type && type.pointee.is_typed_data_pointee ());
		for (int j = 0; j < 10; j++) {
			assert ((type == parameters[j].semantic_type) == (i == j || (i == 4 && j == 5) || (i == 5 && j == 4)));
		}
		assert (type.pointee.is_directly_dereferenceable_value_type () == (i != 8));
	}
	assert (parameters[9].semantic_type is RawPointerType && !(parameters[9].semantic_type is TypedPointerType));
	var other = new BuiltinTypes ();
	assert (other.pointer_to (other.i32_type) != parameters[4].semantic_type);
	foreach (string type in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32", "f32"}) {
		check ("bool f(%s* p,%s* q){%s* n=null; n=p; return (p==q) | (null!=p) | (q==null);}".printf (type, type, type));
	}
}

private void places() {
	foreach (string type in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32", "f32"}) {
		var p = check ("%s read(%s* parameter){return *parameter;} void f(){%s x=%s;%s* p=&x;*p=*p;%s y=*p;}".printf (type, type, type, type == "f32" ? "1.0" : "1", type, type));
		var function = p.functions[1];
		assert (function.locals[0].address_taken && !function.locals[1].address_taken && !function.locals[2].address_taken);
		var address = (CheckedAddressOfExpression) ((CheckedLocalDeclaration) function.body.statements[1]).initializer;
		assert (address.local == function.locals[0] && ((TypedPointerType) address.semantic_type).pointee == address.local.semantic_type);
		var store = (CheckedStore) function.body.statements[2];
		var place = (CheckedDereferencePlace) store.target;
		assert (place.semantic_type == function.locals[0].semantic_type && place.pointer.semantic_type == address.semantic_type);
		assert (store.value is CheckedLoadExpression && ((CheckedLoadExpression) store.value).source is CheckedDereferencePlace);
		assert (place.provenance.origin == function.locals[1] && place.provenance.region == function.body.region);
		var read = (CheckedLoadExpression) ((CheckedReturnStatement) p.functions[0].body.statements[0]).expression;
		assert (((CheckedDereferencePlace) read.source).provenance.region == p.functions[0].body.region);
	}
	check ("u8 f(u8* p){return 1+*p*2;} int g(){int x=2;*(&x)=3;return *(&x)*4;}");
	reject ("void f(int<4> v){v[0]=1;}", "vector lanes are not assignment targets");
	var vector = check ("int f(int<4> v){return v[2];}");
	assert (((CheckedReturnStatement) vector.functions[0].body.statements[0]).expression is CheckedVectorExtractExpression);
}

private void regions() {
	var p = check ("void use(int* a,int* b){} void f(int* parameter){int x=1;int* p=&x;if(true){int* q=p;int* r=parameter;use(&x,&x);} }");
	var function = p.functions[1];
	var root = function.body.region;
	var branch = (CheckedIf) function.body.statements[2];
	assert (root.outlives (branch.then_body.region) && !branch.then_body.region.outlives (root));
	var address = BorrowProvenance.for_expression (((CheckedLocalDeclaration) function.body.statements[1]).initializer);
	assert (address.region == root && address.origin == function.locals[0]);
	var copied = BorrowProvenance.for_expression (((CheckedLocalDeclaration) branch.then_body.statements[0]).initializer);
	assert (copied.region == root && copied.outlives (function.locals[2].lexical_region));
	var snapshot = copied.snapshot ();
	assert (snapshot.is_valid () && snapshot.origin == DataPointerOrigin.LOCAL && snapshot.region_ordinal == 0 && snapshot.origin_ordinal == 1);
	var parameter = BorrowProvenance.for_expression (((CheckedLocalDeclaration) branch.then_body.statements[1]).initializer);
	assert (parameter.snapshot ().origin == DataPointerOrigin.PARAMETER && parameter.region == root);
	foreach (string body in new string[] {"if(true){int inner=1;p=&inner;}", "while(false){int inner=1;p=&inner;}", "if(true){int* q=p;p=q;}", "while(false){if(true){int inner=1;p=&inner;}}"}) {
		reject ("void f(){int* p=null;" + body + "}", "shorter lexical lifetime");
	}
	check ("void use(int* p){} void f(){int x=0;use(&x);if(true){int* p=&x;int* q=p;*q=1;}}");
}

private void diagnostics() {
	foreach (string type in new string[] {"bool*", "void**", "int**", "Pair**"}) {
		reject ("struct Pair{int x;} void f(" + type + " p){}", type.contains ("**") ? "depth greater than one" : "bool and resource storage");
	}
	reject ("void f(bool<8>* p){}", "bool-vector pointers are unsupported");
	foreach (string pair in new string[] {"i8,u8", "i16,u16", "int,u32", "f32,int", "Pair,int"}) {
		var t = pair.split (",");
		foreach (string op in new string[] {"==", "!="}) {
			reject ("struct Pair{int x;} bool f(%s* p,%s* q){return p%s q;}".printf (t[0], t[1], op), "matching non-void operands");
		}
		reject ("struct Pair{int x;} void f(%s* p){%s* q=p;}".printf (t[0], t[1]), "expected initializer");
	}
	foreach (string type in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "Pair"}) {
		string pre = "struct Pair{int x;} ";
		reject (pre + type + "* f(){return null;}", "return-lifetime contracts");
		reject (pre + "extern(C) void f(" + type + "* p);", "C ABI yet");
		reject (pre + "export(C) void f(" + type + "* p){}", "C ABI yet");
		reject (pre + "void f(" + type + "* p){if(p){}}", "condition must have type 'bool'");
		foreach (string op in new string[] {"+", "-", "<", "<=", ">", ">=", "&", "|", "^", "<<", ">>"}) {
			reject (pre + "void f(" + type + "* p){int x=p" + op + "1;}", "requires");
		}
		reject (pre + "void f(" + type + "* p){u32 x=p as u32;}", "integer");
		reject (pre + "void f(){" + type + "* p=1 as " + type + "*;}", "integer");
		reject (pre + "void f(" + type + "* p){void* q=p;}", "expected initializer");
		reject (pre + "void f(void* p){" + type + "* q=p;}", "expected initializer");
	}
	reject ("void f(int* p){u8* q=p as u8*;}", "integer");
	foreach (string type in new string[] {"void*", "Pair*", "int"}) {
		reject ("struct Pair{int x;} void f(" + type + " p){int x=*p;}", "dereference requires");
	}
	foreach (string type in new string[] {"int", "f32", "Pair"}) {
		reject ("struct Pair{int x;} void f(" + type + " parameter){void* p=&parameter;}", type == "Pair" ? "by-value struct parameter storage is read-only" : "direct local");
	}
	foreach (string declaration in new string[] {"bool x=true", "void* x=null", "int* x=null"}) {
		reject ("void f(){" + declaration + ";void* p=&x;}", "direct local");
	}
	foreach (string expression in new string[] {"&p.x", "&*p", "&v[2]", "p++"}) {
		reject ("void f(){int x=" + expression + ";}", "", true);
	}
	reject ("void f(int* p){int x=++p;}", "requires an 'int' operand");
	reject ("void f(int* p){int x=p[0];}", "lane extraction requires a vector");
	reject ("void f(int* p){*p=1.0;}", "expected assignment value");
	reject ("void f(){owned int* p=null;}", "supports 'owned'");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dptr/semantic/exact-identity-alias-and-null", identity);
	Test.add_func ("/dptr/semantic/dereference-place-and-addressability", places);
	Test.add_func ("/dptr/borrow/regions-provenance-aliases-and-escapes", regions);
	Test.add_func ("/dptr/semantic/unsupported-operations", diagnostics);
	return Test.run ();
}
}
