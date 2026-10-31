// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
namespace Astra.Tests.CAbiFp {
private void declarations() throws GLib.Error {
	check (fixture ("cabi-fp-mixed"));
	var types = new BuiltinTypes ();
	assert (types.resolve ("float") == null && types.resolve ("double") == null && types.resolve ("f64") == types.f64_type);
	foreach (string source in new string[] {"extern(C) void consume(f64 x);", "extern(C) f64 produce();", "extern(C) f64 echo(f64 x);", "export(C) void consume(f64 x){}", "export(C) f64 produce(){return 1.0;}", "export(C) f64 echo(f64 x){return x;}"}) {
		check (source);
	}
	var program = check ("f64 native(f64 x){return echo_double(x);}", "[CCode(cname=\"c_echo\",cheader_filename=\"double.h\")] double echo_double(double value);");
	var symbol = program.c_functions[0];
	assert (symbol is CFunctionSymbol && symbol.domain == CallableDomain.C && symbol.abi == ForeignAbi.C);
	assert (symbol.return_type is F64Type && symbol.return_type == symbol.parameters[0].semantic_type && symbol.return_type == program.functions[0].symbol.return_type);
	assert (symbol.external_symbol == "c_echo" && symbol.name == "echo_double" && symbol.span.file.path == "double.vapi");
	assert (symbol.parameters[0].span.text ().contains ("double value") && symbol.metadata.header_at (0).name == "double.h");
	var narrow = check ("f32 native(f32 x){return echo_float(x);}", "[CCode(cname=\"c_echo32\")] float echo_float(float value);");
	assert (narrow.c_functions[0].return_type is F32Type && narrow.c_functions[0].return_type == narrow.functions[0].symbol.return_type && narrow.c_functions[0].abi == ForeignAbi.C);
	assert (narrow.c_functions[0].parameters[0].span.text ().contains ("float value"));
	assert (SemanticDump.format (program).contains ("f64"));
}
private void reject(string source, string expected, string declarations = "") {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", source));
	assert (parsed.unit != null);
	var vapi = VapiParser.parse (new SourceFile.from_text ("invalid.vapi", declarations));
	assert (vapi.file != null);
	var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file));
	if (result.program != null || !result.diagnostic.message.contains (expected)) {
		GLib.error ("Expected %s for %s / %s, got %s", expected, source, declarations, result.diagnostic == null ? "success" : result.diagnostic.message);
	}
}
private void exact_types() throws GLib.Error {
	foreach (string type in new string[] {"f32", "int", "u32", "bool", "void*"}) {
		reject ("extern(C) f64 echo(f64 x); f64 call(" + type + " x){return echo(x);}", "expects type");
		reject ("f64 call(" + type + " x){return echo(x);}", "expects type", "double echo(double x);");
	}
	reject ("extern(C) f64 echo(f64 x); f32 call(f64 x){return echo(x);}", "expected return value");
	reject ("extern(C) f64 echo(f64 x); void call(f64 x){f32 y=echo(x);}", "expected initializer");
	reject ("extern(C) f64 echo(f64 x); void small(f32 x){} void call(f64 x){small(echo(x));}", "expects type");
	reject ("float native(float x){return x;}", "unknown type");
	reject ("extern(C) f32 echo(f32* x);", "typed data pointers");
	reject ("", "unsupported foreign pointer", "float echo(float* x);");
	foreach (string type in new string[] {"f64", "int", "u32", "bool", "void*"}) {
		reject ("extern(C) f32 echo(f32 x); f32 call(" + type + " x){return echo(x);}", "expects type");
		reject ("f32 call(" + type + " x){return echo(x);}", "expects type", "float echo(float x);");
	}
	reject ("extern(C) f32 echo(f32 x); f64 call(f32 x){return echo(x);}", "expected return value");
	reject ("double native(double x){return x;}", "unknown type");
	reject ("extern(C) double echo(double x);", "unknown type");
	reject ("extern(C) f64 echo(f64* x);", "typed data pointers");
	reject ("", "unsupported foreign pointer", "double echo(double* x);");
	reject ("struct Lab{f64 x;} extern(C) Lab echo(Lab x);", "C boundaries");
	reject ("", "unknown type", "long_double echo(long_double x);");
	// CABI-FP-1 qualifies both scalar widths.
	foreach (string source in new string[] {"extern(C) f32 small();", "extern(C) void small(f32 x);", "export(C) f32 small(){return 1.0;}"}) {
		check (source);
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/cabi-fp/semantic/direct-export-vapi-one-type-provenance", declarations);
	add ("/cabi-fp/semantic/exact-types-no-promotion-deferred", exact_types);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
