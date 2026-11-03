// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.F64Semantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("f64.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string message) {
	var parsed = Parser.parse (new SourceFile.from_text ("bad-f64.astra", text));
	assert (parsed.unit != null);
	var before = SyntaxDump.format (parsed.unit);
	for (int i = 0; i < 2; i++) {
		var result = SemanticAnalyzer.analyze (parsed.unit);
		if (result.program != null || !result.diagnostic.message.contains (message)) {
			GLib.error ("expected %s for %s; got %s", message, text, result.diagnostic == null ? "success" : result.diagnostic.message);
		}
	}
	assert (SyntaxDump.format (parsed.unit) == before);
}

private void exact_context() {
	var types = new BuiltinTypes ();
	assert (types.resolve ("f64") == types.f64_type && types.f64_type != (SemanticType) types.f32_type);
	assert (types.f64_type.format == BinaryFloatFormat.BINARY64 && types.f32_type.format == BinaryFloatFormat.BINARY32);
	foreach (string alias in new string[] {"double", "float64", "real"}) {
		assert (types.resolve (alias) == null);
	}
	// WIDE-1 added a distinct integer identity, never a floating alias.
	assert (types.resolve ("i64") == types.i64_type && types.resolve ("i64") != (SemanticType) types.f64_type);
	var program = check ("f64 wide(){return 1.0000000000000002;} f32 small(){return 1.0000000000000002;} f64 zero(){return -0.0;} f64 explicit(){return 1.0000000000000002 as f64;}");
	var wide = (CheckedFloatExpression) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
	var small = (CheckedFloatExpression) ((CheckedReturnStatement) program.functions[1].body.statements[0]).expression;
	var zero = (CheckedFloatExpression) ((CheckedReturnStatement) program.functions[2].body.statements[0]).expression;
	var conversion = (CheckedFloatConversionExpression) ((CheckedReturnStatement) program.functions[3].body.statements[0]).expression;
	assert (wide.value.exact_bits == 0x3ff0000000000001UL && wide.value.format == BinaryFloatFormat.BINARY64 && wide.span.text () == "1.0000000000000002");
	assert (small.value.exact_bits == 0x3f800000U && small.value.format == BinaryFloatFormat.BINARY32);
	assert (zero.value.exact_bits == 0x8000000000000000UL && zero.span.text () == "-0.0");
	assert (conversion.source_type is F32Type && conversion.destination_type is F64Type && conversion.conversion_kind == FloatConversionKind.FLOAT_WIDEN);
	assert (((CheckedFloatExpression) conversion.operand).value.exact_bits == 0x3f800000U);
	assert (SemanticDump.format (program).contains ("(float-convert (from f32) (to f64) (mode widen-exact)"));
	check ("class C{f64 x;f64 get(){return this.x;}} bool f(borrowed C c){return 1.0==c.get() && c.get()==1.0;}");
	check ("struct S{f64 x;} bool f(f64 x,f64* p,borrowed f64[] s){S v={x=1.0};f64[2] a={1.0,2.0};return 1.0==x && 1.0==*p && 1.0==s[0] && 1.0==a[0] && 1.0==v.x;}");
}

private void diagnostics() {
	reject ("struct f64{int x;}", "conflicts with builtin type");
	foreach (string op in new string[] {"+", "-", "*", "/", "==", "!=", "<", "<=", ">", ">="}) {
		reject ("void f(f32 a,f64 b){bool unused=true; f64 x=a" + op + "b;}", "requires matching non-void operands");
		reject ("void f(int a,f64 b){f64 x=b" + op + "a;}", "requires matching non-void operands");
	}
	foreach (string a in new string[] {"f32", "f64"}) {
		string b = a == "f32" ? "f64" : "f32";
		reject ("void f(" + a + " a){" + b + " b=a;}", "expected initializer of type");
		reject ("void f(" + a + " a){} void g(" + b + " b){f(b);}", "expects type");
	}
	foreach (string integer in new string[] {"int", "u32"}) {
		check ("f64 f(" + integer + " x){return x as f64;}");
		check (integer + " f(f64 x){return x as " + integer + ";}");
	}
	// CABI-FP-1 qualifies exact C double transport with a C companion.
	foreach (string declaration in new string[] {"extern(C) f64 f();", "extern(C) int f(f64 x);", "export(C) f64 f(){return 1.0;}", "export(C) int f(f64 x){return 0;}"}) {
		check (declaration);
	}
	check ("f64<2> f(f64<2> x){return x;}");
	foreach (string vector in new string[] {"f64<4>", "f64<8>", "f64<16>"}) {
		reject (vector + " f(" + vector + " x){return x;}", "unsupported VEC-1 vector shape");
	}
	reject ("f64 f(f64 x){return x%1.0;}", "not supported for f64");
	reject ("f64 f(){return 1;}", "type 'f64'");
	reject ("f64 f(f64 x){return x as f64;}", "unsupported integer conversion source");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f64/semantic/context-format-provenance-no-double-rounding", exact_context);
	Test.add_func ("/f64/semantic/diagnostics-deferred-capabilities", diagnostics);
	return Test.run ();
}

}
