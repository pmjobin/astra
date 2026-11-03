// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.NumericSemantic {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("numeric.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", text));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.diagnostic != null && result.program == null);
	Test.message ("%s", result.diagnostic.message);
}

private void pairs() {
	foreach (string integer in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32"}) {
		foreach (string floating in new string[] {"f32", "f64"}) {
			foreach (bool to_float in new bool[] {false, true}) {
				string source = to_float ? integer : floating;
				string destination = to_float ? floating : integer;
				var checked = check ("%s f(%s x){return x as %s;}".printf (destination, source, destination));
				var conversion = (CheckedNumericConversionExpression) ((CheckedReturnStatement) checked.functions[0].body.statements[0]).expression;
				assert (conversion.source_type == checked.types.resolve (source) && conversion.destination_type == checked.types.resolve (destination));
				assert (conversion.conversion_kind.accepts (conversion.source_type, conversion.destination_type, conversion.policy));
				assert (conversion.span.text () == "x as " + destination && conversion.operand.span.text () == "x");
				assert (conversion.conversion_kind.traps () != to_float);
				if (integer == "i32") {
					assert (SemanticDump.format (checked).contains ("int)") && !SemanticDump.format (checked).contains ("i32"));
				}
				reject ("%s f(%s x){return x;}".printf (destination, source));
			}
		}
	}
}

private void literals() {
	foreach (string suffix in new string[] {"f", "F", "d", "D"}) {
		string type = suffix.down () == "f" ? "f32" : "f64";
		foreach (string spelling in new string[] {"1.0000000000000002", "1.0e10", "1e-10", "-1.25", "+0.0", "-0.0"}) {
			var checked = check (type + " f(){return " + spelling + suffix + ";}");
			var value = (CheckedFloatExpression) ((CheckedReturnStatement) checked.functions[0].body.statements[0]).expression;
			assert (value.semantic_type == checked.types.resolve (type));
			if (spelling == "1.0000000000000002") {
				assert (value.value.exact_bits == (type == "f32" ? 0x3f800000UL : 0x3ff0000000000001UL));
			}
			if (spelling == "-0.0") {
				assert (value.value.exact_bits == value.value.format.sign_mask ());
			}
			assert (value.span.text () == spelling + suffix);
		}
	}
	foreach (string bad in new string[] {"1f", "1d", "1.0ff", "1.0dd", "1.0fd", "1.0df", "1.0f32", "1.0f64", "1.0m", "1.0h", "1.0q", "1e-f", "1e+d", "0x1.0p0d"}) {
		var parsed = Parser.parse (new SourceFile.from_text ("invalid", "void f(){f32 x=" + bad + ";}"));
		assert (parsed.unit == null && parsed.diagnostic != null);
	}
	reject ("f64 f(){return 1.0f;}");
	reject ("f32 f(){return 1.0d;}");
	reject ("void f(){f64 x=1.0F;}");
	reject ("void f(){f32 x=1.0D;}");
	check ("f64 f(){return 1.0f as f64;} f32 g(){return 1.0d as f32;}");
	var defaults = check ("f64 context(){return 1.0000000000000002;} f64 boundary(){return 1.0000000000000002 as f64;}");
	var direct = (CheckedFloatExpression) ((CheckedReturnStatement) defaults.functions[0].body.statements[0]).expression;
	var wide = (CheckedFloatConversionExpression) ((CheckedReturnStatement) defaults.functions[1].body.statements[0]).expression;
	assert (direct.value.exact_bits == 0x3ff0000000000001UL);
	assert (wide.source_type == defaults.types.f32_type && ((CheckedFloatExpression) wide.operand).value.exact_bits == 0x3f800000UL);
}

private void excluded() {
	foreach (string type in new string[] {"bool", "void*", "f32*", "int<4>", "f32<4>", "bool<4>"}) {
		foreach (string scalar in new string[] {"int", "f32", "f64"}) {
			reject ("void f(" + type + " x){" + scalar + " y=x as " + scalar + ";}");
			reject ("void f(" + scalar + " x){" + type + " y=x as " + type + ";}");
		}
	}
	reject ("void f(){int x=true as int;}");
	reject ("void f(){bool x=1 as bool;}");
	reject ("void f(){bool x=1.0f as bool;}");
	reject ("struct S{int x;} void f(){S s={x=1};f64 x=s as f64;}");
	reject ("struct S{int x;} void f(f64 x){S s=x as S;}");
	reject ("f64 f<T>(T x) where T : Numeric {return x as f64;}");
	reject ("T f<T>(f64 x) where T : Numeric {return x as T;}");
	reject ("extern(C) void consume(f32 x); void f(int x){consume(x);}");
	reject ("extern(C) void consume(f64 x); void f(int x){consume(x);}");
	check ("extern(C) void consume(f64 x); void f(int x){consume(x as f64);}");
}

int main(string[] args) {
	if (args.length == 2 && args[1] == "--literals") {
		string? spelling;
		while ((spelling = stdin.read_line ()) != null) {
			string type = spelling[spelling.length - 1].tolower () == 'd' ? "f64" : "f32";
			var checked = check (type + " f(){return " + spelling + ";}");
			var value = (CheckedFloatExpression) ((CheckedReturnStatement) checked.functions[0].body.statements[0]).expression;
			stdout.printf ("%s %s\n", value.semantic_type.display_name (), value.value.to_string ());
		}
		return 0;
	}
	Test.init (ref args);
	Test.add_func ("/num-conv/semantic/all-pairs-canonical-types-no-implicit", pairs);
	Test.add_func ("/num-conv/semantic/suffix-grammar-exact-types-context-defaults", literals);
	Test.add_func ("/num-conv/semantic/excluded-domains-generics-cabi", excluded);
	return Test.run ();
}

}
