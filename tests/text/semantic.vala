// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.TextSemantic {
private SemanticResult analyze(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("text.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	return SemanticAnalyzer.analyze (parsed.unit);
}
private void contracts() {
	var result = analyze ("const A=\"a\\0b\"; const string B=A; const N=B.byte_length; const E=A==\"a\\u0000b\"; bool f(string a, borrowed string b){var copy=a;return copy==b;} string g(){return B;}");
	assert (result.diagnostic == null);
	var p = result.program;
	assert (p.constants[0].semantic_type == p.types.string_type && p.constants[1].value.text.hex () == "610062");
	assert (p.constants[2].value.integer.mathematical_value == 3 && p.constants[3].value.boolean);
	assert (p.functions[0].symbol.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && p.functions[0].symbol.parameters[1].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (p.functions[1].symbol.result_contract == ResultOwnershipContract.STATIC_TEXT);
	assert (!GenericArgumentTypes.supports (p.types.string_type));
	assert (BuiltinTypes.is_builtin_name ("string") && p.types.resolve ("string") == p.types.string_type);
}
private void lifetimes() {
	string[] accepted = {
		"string f(bool c){var r=\"a\";if(c){r=\"b\";}return r;}",
		"string f(string p){var x=\"a\";var copy=x;x=p;return copy;}",
		"string f(string p){var x=p;x=\"static\";return x;}",
		"string f(string p,bool c){var x=\"a\";while(c){var copy=x;x=p;x=copy;break;}return x;}",
		"string f(bool c){var r=\"a\";while(c){r=\"b\";break;}return r;}",
		"string f(){var r=\"\";{var inner=\"static\";r=inner;}return r;}",
		"bool eq(string a,string b){return a==b;} bool f(string p){var copy=p;return eq(copy,p);}",
		"string f(bool c){if(c){return g(false);}return \"a\";} string g(bool c){if(c){return f(false);}return \"b\";}",
		"int string(int byte_length){return byte_length;} int f(){var null_value=null;return string(1);}"
	};
	foreach (string source in accepted) {
		var result = analyze (source);
		if (result.diagnostic != null) {
			GLib.error ("%s", result.diagnostic.format ());
		}
	}
	string[] escapes = {
		"string f(string p){return p;}",
		"string f(string p){var q=p;return q;}",
		"string f(string p,bool c){var q=\"a\";if(c){q=p;}return q;}",
		"string f(string p,bool c){var q=\"a\";while(c){q=p;break;}return q;}",
		"string f(string p){return g(p);} string g(string p){return p;}",
		"string f(string p){return p;} int main(){var x=f(\"literal\");return 0;}"
	};
	foreach (string source in escapes) {
		var result = analyze (source);
		assert (result.diagnostic != null && result.diagnostic.message.contains ("borrowed text cannot escape"));
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text/semantic/canonical-type-constants-contracts", contracts);
	Test.add_func ("/text/semantic/backing-origin-joins-recursion", lifetimes);
	return Test.run ();
}
}
