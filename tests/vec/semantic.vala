// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Syntax;
using Astra.Source;

namespace Astra.Tests.VectorSemantic {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("vec.astra", text));
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

private void identities() {
	var types = new BuiltinTypes ();
	var seen = new GenericArray<VectorType> ();
	foreach (var name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		var element = types.resolve (name);
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (element, lanes);
			bool supported = name == "bool" || name == "i8" || name == "u8" || ((name == "i16" || name == "u16") ? lanes <= 8 : lanes <= 4);
			assert ((vector != null) == supported);
			if (vector == null) {
				continue;
			}
			assert (vector.kind == TypeKind.VECTOR && vector.element_type == element && vector.lane_count == lanes);
			assert (vector == types.vector_of (element, lanes) && vector != element && vector.is_mask == (name == "bool"));
			foreach (var previous in seen) {
				assert (vector != previous);
			}
			seen.add (vector);
			string type = "%s<%d>".printf (name, lanes);
			var program = check (type + " f(" + type + " x){return x;}");
			assert (program.functions[0].symbol.return_type is VectorType);
			assert (program.functions[0].symbol.return_type == program.functions[0].symbol.parameters[0].semantic_type);
		}
	}
	assert (seen.length == 24);
	assert (types.vector_of (types.resolve ("int"), 4) == types.vector_of (types.resolve ("i32"), 4));
	assert (types.vector_of (types.i32_type, 4).display_name () == "int<4>");
	assert (types.vector_of (new BuiltinTypes ().i32_type, 4) == null);
	foreach (int lanes in new int[] {-1, 0, 1, 3, 32, int.MAX}) {
		assert (types.vector_of (types.i8_type, lanes) == null);
	}
	foreach (var type in new SemanticType[] {types.void_type, types.raw_pointer_type, new StructType ("Pair"), new HandleType ("Resource"), types.vector_of (types.i8_type, 4)}) {
		assert (types.vector_of (type, 4) == null);
	}
	foreach (string property in new string[] {"element-type", "lane-count", "is-mask"}) {
		var spec = ((ObjectClass) typeof (VectorType).class_ref ()).find_property (property);
		assert (spec != null && (spec.flags & ParamFlags.WRITABLE) == 0);
	}
}

private void initialization() {
	var program = check ("u8<4> f(){u8<4> v={0,1,254,255};u8<4> x=v;x=v;return x;} f32<4> g(){f32<4> v={0.0,1.0,-0.0,3.14159265};return v;} bool<2> h(){bool<2> v={true,false};return v;}");
	var initial = (CheckedVectorConstructExpression) ((CheckedLocalDeclaration) program.functions[0].body.statements[0]).initializer;
	assert (initial.lanes.length == 4 && initial.semantic_type == program.functions[0].symbol.return_type);
	foreach (var lane in initial.lanes) {
		assert (lane.semantic_type == ((VectorType) initial.semantic_type).element_type && lane is CheckedIntegerExpression);
	}
	var floating = (CheckedVectorConstructExpression) ((CheckedLocalDeclaration) program.functions[1].body.statements[0]).initializer;
	assert (((CheckedFloatExpression) floating.lanes[2]).value.exact_bits == 0x80000000U);
	assert (((CheckedFloatExpression) floating.lanes[3]).value.exact_bits == AstraF32Value.from_decimal ("3.14159265").bits);
	reject ("void f(){u8<4> v={0,1,2};}", "requires exactly 4 lanes, found 3");
	reject ("void f(){u8<4> v={0,1,2,3,4};}", "requires exactly 4 lanes, found 5");
	reject ("void f(){u8<4> v={0,1,254,256};}", "u8");
	reject ("void f(){f32<2> v={1,2.0};}", "lane expects exact type 'f32', found 'int'");
	reject ("void f(){bool<2> v={true,1};}", "lane expects exact type 'bool'");
	reject ("void f(i16 x){u16<2> v={x,x};}", "lane expects exact type 'u16'");
	reject ("void f(){int<2> v={1,v};}", "unknown name 'v'");
	reject ("void f(){int v={1,2};}", "positional initializer requires a vector local type");
	reject ("void f(){int<2> v={x=1,y=2};}", "named field initializer requires a struct local type");
	reject ("void f(){int<2> v=1;}", "expected initializer of type 'int<2>'");
	reject ("void f(int<2> p){int<2> p={1,2};}", "conflicts with parameter");
}

private void operators() {
	foreach (string type in new string[] {"i8<4>", "u8<4>", "i16<8>", "u16<8>", "int<4>", "u32<4>", "f32<4>"}) {
		check (type + " f(" + type + " a," + type + " b){return +(a+b)*(a-b);}");
		string lanes = type.contains ("8>") ? "8" : "4";
		foreach (string op in new string[] {"==", "!=", "<", "<=", ">", ">="}) {
			var program = check ("bool<" + lanes + "> f(" + type + " a," + type + " b){return a" + op + "b;}");
			var expression = ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
			assert (expression is CheckedBinaryExpression && ((VectorType) expression.semantic_type).is_mask && expression.semantic_type == program.functions[0].symbol.return_type);
		}
		reject (type + " f(" + type + " a){return a+1;}", "matching non-void operands");
		reject (type + " f(" + type + " a){return 1+a;}", "matching non-void operands");
	}
	foreach (string type in new string[] {"i8<4>", "i16<4>", "int<4>", "f32<4>"}) {
		check (type + " f(" + type + " a){return -a;}");
	}
	check ("f32<4> f(f32<4> a,f32<4> b){return a/b;}");
	foreach (string type in new string[] {"u8<4>", "u16<4>", "u32<4>"}) {
		reject (type + " f(" + type + " a){return -a;}", "unsigned integer type");
	}
	foreach (string type in new string[] {"i16<8>", "u8<16>"}) {
		foreach (string op in new string[] {"/", "%"}) {
			reject (type + " f(" + type + " a){return a" + op + "a;}", "integer vector division and remainder are unsupported");
		}
	}
	foreach (string type in new string[] {"i16<8>", "u16<4>", "int<4>"}) {
		reject ("i16<4> f(i16<4> a," + type + " b){return a+b;}", "matching non-void operands");
		reject ("void f(i16<4> a," + type + " b){i16<4> v=a;v=b;}", "expected assignment value");
	}
	reject ("void f(int<4> a){int<4> v=a;v=1;}", "expected assignment value");
	reject ("f32<4> f(f32<4> a){return a%a;}", "matching non-void operands");
}

private void masks() {
	check ("bool<4> f(bool<4> a,bool<4> b){return !(a==b)!=b;} bool g(bool<4> a){if(all(a)){return true;} while(any(a)){return false;} return false;}");
	var program = check ("bool f(bool<4> m){return all(m) || any(!m);}");
	var short_circuit = (CheckedShortCircuitExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
	assert (((CheckedVectorReductionExpression) short_circuit.left).operator_kind == VectorReductionOperator.ALL);
	assert (((CheckedVectorReductionExpression) short_circuit.right).operator_kind == VectorReductionOperator.ANY);
	foreach (string op in new string[] {"<", "<=", ">", ">=", "+", "-", "*", "&&", "||"}) {
		reject ("bool<4> f(bool<4> a){return a" + op + "a;}", "operator");
	}
	foreach (string type in new string[] {"bool", "int", "f32", "int<4>"}) {
		foreach (string op in new string[] {"all", "any"}) {
			reject ("bool f(" + type + " a){return " + op + "(a);}", "requires a bool<N> mask");
		}
	}
	reject ("void f(int<4> a){if(a<a){return;}}", "if condition must have type 'bool', found 'bool<4>'");
	reject ("void f(bool<4> a){while(a){return;}}", "while condition must have type 'bool'");
	reject ("bool f(int<4> a){return a==a;}", "bool<4>");
	reject ("bool<4> f(int<4> a){return !a;}", "not supported");
	foreach (string op in new string[] {"+", "-"}) {
		reject ("bool<4> f(bool<4> a){return " + op + "a;}", "unary '" + op + "' is not supported for 'bool<4>'");
	}
}

private void grammar() {
	var syntax = Parser.parse (new SourceFile.from_text ("syntax", "i32<004> f(int<4> a){return a;}"));
	assert (syntax.unit != null && syntax.unit.functions[0].return_type is VectorTypeSyntax);
	assert (SyntaxDump.format (syntax.unit).contains ("i32<004>"));
	check ("struct S{int x;} bool f(S* p,int a,int b){return a<b && p!=null;} void g(){S s={x=1};f(&s,1,2);}");
	foreach (string shape in new string[] {"i8<0>", "i8<1>", "i8<3>", "i8<32>", "i16<16>", "i32<8>", "f32<8>", "bool<32>", "i8<99999999999999999999999>"}) {
		reject (shape + " f(" + shape + " a){return a;}", "unsupported VEC-1 vector shape");
	}
	foreach (string shape in new string[] {"void<4>", "void*<4>", "Pair<4>", "Pair*<4>"}) {
		reject ("struct Pair{int x;} void f(" + shape + " a){}", "vector element must be");
	}
	foreach (string shape in new string[] {"i8<n>", "i8<-4>", "i8<4.0>"}) {
		reject ("void f(" + shape + " a){}", "lane count must be", true);
	}
	reject ("void f(i8<2+2> a){}", "lane expressions are unsupported", true);
	reject ("void f(i8<4><4> a){}", "nested vectors are unsupported", true);
	check ("void f(i8<4>* a){}");
	foreach (string body in new string[] {"int<2> v={};", "int<2> v={1,2,};"}) {
		reject ("void f(){" + body + "}", "trailing commas are unsupported", true);
	}
	foreach (string body in new string[] {"return {1,2};", "int<2> v={1,2};v={3,4};", "f({1,2});"}) {
		reject ("int<2> f(){" + body + "}", "expected expression", true);
	}
	foreach (string keyword in new string[] {"all", "any"}) {
		reject ("int " + keyword + "(){return 0;}", "expected function name", true);
	}
	reject ("class S{int<4> x;}", "vector struct fields are unsupported");
	reject ("void f(){int<4> v={1,2,3,4};void* p=&v;}", "expected initializer of type 'void*', found 'int<4>*'");
	foreach (string declaration in new string[] {"extern(C) int<4> f();", "extern(C) int f(int<4> a);", "export(C) int<4> f(int<4> a){return a;}", "export(C) int f(bool<4> a){return 0;}"}) {
		reject (declaration, "C ABI vectors are not supported yet");
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec/semantic/exact-identities-24-shapes", identities);
	Test.add_func ("/vec/semantic/contextual-initializers", initialization);
	Test.add_func ("/vec/semantic/operators-no-conversions", operators);
	Test.add_func ("/vec/semantic/masks-reductions", masks);
	Test.add_func ("/vec/semantic/grammar-deferrals", grammar);
	return Test.run ();
}

}
