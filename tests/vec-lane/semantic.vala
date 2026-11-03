// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.VectorLaneSemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("vec-lane.astra", text));
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.program == null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string expected, bool parsing = false) {
	var syntax = Parser.parse (new SourceFile.from_text ("vec-invalid.astra", text));
	if (parsing) {
		if (syntax.unit != null || !syntax.diagnostic.message.contains (expected)) {
			GLib.error ("Expected parse rejection %s for %s", expected, text);
		}
		return;
	}
	if (syntax.unit == null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	string before = SyntaxDump.format (syntax.unit);
	for (int repeat = 0; repeat < 2; repeat++) {
		var result = SemanticAnalyzer.analyze (syntax.unit);
		if (result.program != null || !result.diagnostic.message.contains (expected)) {
			GLib.error ("Expected %s for %s; got %s", expected, text, result.diagnostic == null ? "success" : result.diagnostic.message);
		}
	}
	assert (SyntaxDump.format (syntax.unit) == before);
}

private void types_and_context() {
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int count in new int[] {2, 4, 8, 16}) {
			var types = new BuiltinTypes ();
			if (types.vector_of (types.resolve (element), count) == null) {
				continue;
			}
			string type = "%s<%d>".printf (element, count);
			string literal = element == "bool" ? "true" : element == "f32" ? "1.0" : "1";
			check ("%s f(%s x){%s v=splat(x,%d);v=insert(v,0,%s);return v;}".printf (type, element, type, count, literal));
			check ("%s f(){return splat(%s,%d);}".printf (type, literal, count));
			check ("%s f(%s v){return v[%d];}".printf (element, type, count - 1));
			check ("%s f(bool<%d> m,%s a,%s b){return select(m,a,b);}".printf (type, count, type, type));
		}
	}
	check ("int<4> f(){return splat(1,4);} bool g(){return all(splat(1,4)==f());}");
	check ("u8<16> f(){return splat(255,16);} u8<4> g(u8<4> v){return insert(v,2,255);}");
	check ("u8<16> f(u8<16> v){return splat(1,16)+v;} u8<16> g(u8<16> v){return v+splat(1,16);}");
	check ("bool f(u8<4> v){return 255==v[0] && insert(v,1,255)[1]==255 && shuffle(v,3,2,1,0)[0]==255;} bool g(u8 x){return splat(x,4)[0]==255;}");
	check ("u8<4> f(){return splat(1,4);} bool g(){return f()[0]==1;}");
	reject ("f32<4> f(){return splat(1,4);}", "no implicit element conversion");
	reject ("u8<4> f(int x){return splat(x,4);}", "no implicit element conversion");
	reject ("u8<4> f(){return splat(256,4);}", "out of range for 'u8'");
	foreach (string expression in new string[] {"splat(1,3)", "splat(1,8)", "splat(1.0,8)", "splat(true,32)", "splat(1,99999999999999999999999999)", "splat(null,4)", "splat(splat(1,4),4)"}) {
		reject ("void f(){int<4> v=" + expression + ";}", "supported scalar element and VEC-1 vector shape");
	}
	reject ("void f(){int<4> v=splat(1,0);}", "lane count must be positive");
	reject ("void f(){int<4> v=splat(1,2);}", "exact vector type");
}

private void diagnostics() {
	foreach (string index in new string[] {"i", "1+1", "-1", "foo()", "(1)", "1.0", "1u", "0x1"}) {
		// ARRAY-1 parses general bracket operands, then checks vector ordinals.
		reject ("void f(int<4> v,int i){int x=v[" + index + "];}", index == "1u" || index == "0x1" ? "expected ']'" : "one unsuffixed non-negative decimal integer literal", index == "1u" || index == "0x1");
		foreach (string expression in new string[] {"insert(v," + index + ",1)", "shuffle(v," + index + ",1,2,3)"}) {
			reject ("void f(int<4> v,int i){int x=" + expression + ";}", "one unsuffixed non-negative decimal integer literal", true);
		}
		reject ("void f(){int<4> v=splat(1," + index + ");}", "one unsuffixed positive decimal integer literal", true);
	}
	foreach (string index in new string[] {"4", "999999999999999999999999999999"}) {
		foreach (string expression in new string[] {"v[" + index + "]", "insert(v," + index + ",1)", "shuffle(v,0,1,2," + index + ")"}) {
			reject ("void f(int<4> v){int x=" + expression + ";}", "out of range");
		}
	}
	foreach (string selectors in new string[] {"", ",0,1,2", ",0,1,2,3,0"}) {
		reject ("int<4> f(int<4> v){return shuffle(v" + selectors + ");}", "requires exactly 4 lane selectors");
	}
	check ("int<4> f(int<4> v){return shuffle(v,0,0,2,2);}");
	reject ("int<4> f(int<4> a,int<4> b){return shuffle(a,b,0,1,2,3);}", "decimal integer literal", true);
	reject ("int<2> f(int<4> a){return shuffle(a,0,1,2,3);}", "expected return value");
	reject ("void f(int<4> v){v[2]=1;}", "vector lanes are not assignment targets; use insert()");
	reject ("void f(int<4> v){void* p=&v[2];}", "no storage identity", true);
	reject ("int f(int v){return v[0];}", "requires a vector value");
	reject ("int<4> f(){return insert(1,0,1);}", "requires a vector value");
	reject ("int<4> f(){return shuffle(1,0,1,2,3);}", "requires a vector value");
	reject ("u8<4> f(u8<4> v,int x){return insert(v,0,x);}", "exact element type 'u8'");
	reject ("f32<4> f(f32<4> v){return insert(v,0,1);}", "exact element type 'f32'");
	reject ("int<4> f(int<4> v){return select(true,v,v);}", "select mask must have type bool<N>");
	reject ("int f(){return select(true,1,2);}", "select mask must have type bool<N>");
	reject ("int<4> f(int<4> v){return select(v,v,v);}", "select mask must have type bool<N>");
	reject ("int<4> f(bool<2> m,int<4> v){return select(m,v,v);}", "mask lane count must match");
	foreach (string type in new string[] {"u16<4>", "i16<8>", "int<4>"}) {
		reject ("i16<4> f(bool<4> m,i16<4> a," + type + " b){return select(m,a,b);}", "same exact VectorType");
	}
	foreach (string name in new string[] {"splat", "insert", "shuffle", "select"}) {
		reject ("int " + name + "(){return 0;}", "expected function name", true);
	}
	foreach (string expression in new string[] {"splat(1)", "splat(1,4,4)", "insert(v,1)", "insert(v,1,2,3)", "select(v,v)", "select(v,v,v,v)"}) {
		reject ("void f(int<4> v){int<4> x=" + expression + ";}", "requires exactly", true);
	}
	// Existing source/ABI boundaries remain closed.
	reject ("int<4> f(int<4> v){return insert(v,0,1)/v;}", "integer vector division");
	reject ("void f(int<4> v){void* p=&v;}", "direct local integer, f32, numeric vector, or native struct");
	reject ("class S{int<4> v;}", "vector struct fields are unsupported");
	reject ("int<4> f(){return {1,2,3,4};}", "expected expression", true);
}

private void provenance() {
	string text = "i16<4> f(i16 x,bool<4> m){i16<4> v=splat(x,0004);i16 y=v[002];v=insert(v,01,y);v=shuffle(v,3,2,1,0);return select(m,v,v);}";
	var program = check (text);
	var statements = program.functions[0].body.statements;
	var splat = (CheckedVectorSplatExpression) ((CheckedLocalDeclaration) statements[0]).initializer;
	var extract = (CheckedVectorExtractExpression) ((CheckedLocalDeclaration) statements[1]).initializer;
	var insert = (CheckedVectorInsertExpression) ((CheckedAssignment) statements[2]).expression;
	var shuffle = (CheckedVectorShuffleExpression) ((CheckedAssignment) statements[3]).expression;
	var select = (CheckedVectorSelectExpression) ((CheckedReturnStatement) statements[4]).expression;
	assert (splat.lane_count == 4 && splat.lane_count_span.text () == "0004" && splat.operand.span.text () == "x");
	assert (extract.index.ordinal == 2 && extract.index.span.text () == "002" && extract.vector.span.text () == "v");
	assert (insert.index.ordinal == 1 && insert.index.span.text () == "01" && insert.replacement.span.text () == "y");
	assert (shuffle.selectors.spelling () == "3 2 1 0" && shuffle.selectors.at (0).span.text () == "3");
	assert (select.mask.span.text () == "m" && select.true_value.semantic_type == splat.semantic_type && select.false_value.semantic_type == splat.semantic_type);
	string dump = SemanticDump.format (program);
	foreach (string primitive in new string[] {"splat", "extract", "insert", "shuffle", "select"}) {
		assert (dump.contains ("vector-" + primitive));
	}
	foreach (string property in new string[] {"ordinal", "span"}) {
		assert ((((ObjectClass) typeof (VectorLaneIndex).class_ref ()).find_property (property).flags & ParamFlags.WRITABLE) == 0);
	}
	assert ((((ObjectClass) typeof (VectorLaneSelectors).class_ref ()).find_property ("length").flags & ParamFlags.WRITABLE) == 0);
	var syntax = Parser.parse (new SourceFile.from_text ("postfix", "int f(int<4> v){return -v[2] + (v+v)[1];}"));
	assert (syntax.unit != null);
	assert (SyntaxDump.format (syntax.unit).contains ("(prefix \"-\" (vector-extract"));
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec-lane/semantic/shapes-exact-context", types_and_context);
	Test.add_func ("/vec-lane/semantic/constant-syntax-and-diagnostics", diagnostics);
	Test.add_func ("/vec-lane/semantic/provenance-and-operand-roles", provenance);
	return Test.run ();
}

}
