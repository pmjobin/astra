// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Vapi;

namespace Astra.Tests.TextIoFrontend {
private SemanticResult check(string declaration, bool vapi) {
	var source = Parser.parse (new SourceFile.from_text ("client.astra", (vapi ? "" : declaration) + "int main(){return inspect(4,\"a\\0b\",1.5,\"é\",2.5d,null);}"));
	assert (source.diagnostic == null);
	GenericArray<ForeignDeclarationInput>? inputs = null;
	if (vapi) {
		var parsed = VapiParser.parse (new SourceFile.from_text ("reader.vapi", declaration));
		assert (parsed.diagnostic == null);
		inputs = VapiNormalizer.normalize (parsed.file);
	}
	return SemanticAnalyzer.analyze (source.unit, inputs);
}

private void equivalent() {
	string metadata = "[CCode (text_abi=\"utf8-i32\",cname=\"unfamiliar_reader\",cheader_filename=\"opaque\\\\path\\\".h\")] ";
	var source = check (metadata + "extern(C) int inspect(int tag, borrowed string a, f32 scale, borrowed string b, f64 wide, void* token);", false);
	var vapi = check (metadata + "int inspect(int tag, borrowed string a, float scale, borrowed string b, double wide, void* token);", true);
	if (source.diagnostic != null) {
		GLib.error ("%s", source.diagnostic.format ());
	}
	if (vapi.diagnostic != null) {
		GLib.error ("%s", vapi.diagnostic.format ());
	}
	assert (SemanticDump.format (source.program) == SemanticDump.format (vapi.program));
	var function = source.program.c_functions[0];
	assert (function.metadata.text_abi == CTextAbi.UTF8_I32 && function.external_symbol == "unfamiliar_reader");
	assert (function.parameters[1].semantic_type == source.program.types.string_type && function.parameters[3].semantic_type == source.program.types.string_type);
	assert (function.parameters[1].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	var copy = function.metadata.copy_with_owned_result ();
	assert (copy != function.metadata && copy.text_abi == function.metadata.text_abi && copy.header_at (0).name == "opaque\\path\".h");
}

private void metadata_negatives() {
	string[] entries = {
		"text_abi=\"utf8-i32\",text_abi=\"utf8-i32\"", "text_abi=\"utf8-i32\",text_abi=\"other\"", "text_abi=\"\"", "text_abi=\"utf8-i32\\0\"", "text_abi=\"utf8-\\u0069332\"", "text_abi=1", "unknown=\"x\""
	};
	foreach (string entry in entries) {
		assert (Parser.parse (new SourceFile.from_text ("bad.astra", "[CCode(" + entry + ")] extern(C) int inspect(borrowed string x);")).diagnostic != null);
		assert (VapiParser.parse (new SourceFile.from_text ("bad.vapi", "[CCode(" + entry + ")] int inspect(borrowed string x);")).diagnostic != null);
	}
	assert (VapiParser.parse (new SourceFile.from_text ("bad.vapi", "[CCode(text_abi=\"utf8-i32\",destroy_function=\"free\")] handle H;")).diagnostic != null);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-io/frontend/source-vapi-authority", equivalent);
	Test.add_func ("/text-io/frontend/metadata-rejection", metadata_negatives);
	return Test.run ();
}

}
