// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Vapi;

namespace Astra.Tests.VapiFrontend {
private void borrowed_grammar() {
	var result = VapiParser.parse (new SourceFile.from_text ("borrowed.vapi", "[CCode(cname = \"inspect\", cheader_filename = \"missing.h\", destroy_function = \"destroy\")] void* create(borrowed void* p);"));
	assert (result.diagnostic == null);
	var parameter = result.file.functions[0].parameters[0];
	assert (parameter.borrowed_keyword.kind == VapiTokenKind.BORROWED && parameter.type_name.spelling () == "void*");
	assert (parameter.span.text () == "borrowed void* p");
	foreach (string spelling in new string[] {"int", "bool", "Pair", "Pair*"}) {
		var invalid_type = VapiParser.parse (new SourceFile.from_text ("invalid-type.vapi", "int inspect(borrowed " + spelling + " p);"));
		assert (invalid_type.diagnostic == null);
		assert (invalid_type.file.functions[0].parameters[0].type_name.spelling () == spelling);
		assert (invalid_type.file.functions[0].parameters[0].borrowed_keyword != null);
	}
	assert (VapiParser.parse (new SourceFile.from_text ("result.vapi", "borrowed void* f();")).diagnostic != null);
}
private void grammar() {
	string text = "// é\r\nint add(int a, /* ignored */ int b);\rvoid reset();\nint identity(int value); // eof";
	var parsed = VapiParser.parse (new SourceFile.from_text ("declarations.data", text));
	assert (parsed.diagnostic == null && parsed.file.functions.length == 3);
	var function = parsed.file.functions[0];
	assert (function.name.spelling () == "add" && function.return_type.identifier.spelling () == "int");
	assert (function.span.text () == "int add(int a, /* ignored */ int b);");
	assert (function.parameters.length == 2 && function.parameters[1].span.text () == "int b");
	int line;
	int column;
	function.name.span.file.locate (function.name.span.start, out line, out column);
	assert (line == 2 && column == 5);
	parsed.file.functions[1].name.span.file.locate (parsed.file.functions[1].name.span.start, out line, out column);
	assert (line == 3 && column == 6);
	assert (parsed.file.functions[1].parameters.length == 0);
	assert (parsed.file.eof.kind == VapiTokenKind.EOF && parsed.file.eof.span.start == text.length);
	// Types are identifier syntax; foreign normalization decides legality.
	assert (VapiParser.parse (new SourceFile.from_text ("types.vapi", "bool f(void x, Unknown y);")).diagnostic == null);
	assert (VapiParser.parse (new SourceFile.from_text ("empty.vapi", "")).file.functions.length == 0);
	assert (VapiParser.parse (new SourceFile.from_text ("comments.vapi", "/* outer /* ends here */ // eof")).file.functions.length == 0);
}

private void lexer_lifetime() {
	SourceFile? source = new SourceFile.from_text ("tokens.vapi", "_int f2(int _x);\t\v\f");
	var source_ref = WeakRef (source);
	VapiLexer? lexer = new VapiLexer (source);
	var lexer_ref = WeakRef (lexer);
	VapiToken? token = lexer.next_token ();
	assert (token.kind == VapiTokenKind.IDENTIFIER && token.spelling () == "_int");
	VapiTokenKind[] expected = {
		VapiTokenKind.IDENTIFIER, VapiTokenKind.OPEN_PAREN, VapiTokenKind.IDENTIFIER, VapiTokenKind.IDENTIFIER, VapiTokenKind.CLOSE_PAREN, VapiTokenKind.SEMICOLON, VapiTokenKind.EOF
	};
	foreach (var kind in expected) {
		assert (lexer.next_token ().kind == kind);
	}
	lexer = null;
	source = null;
	assert (lexer_ref.get () == null && source_ref.get () != null && token.spelling () == "_int");
	token = null;
	assert (source_ref.get () == null);
}

private void reject(string text, int line, int column, string message) {
	for (int attempt = 0; attempt < 2; attempt++) {
		var result = VapiParser.parse (new SourceFile.from_text ("invalid.vapi", text));
		assert (result.file == null && result.diagnostic != null);
		string expected = "invalid.vapi:%d:%d: error: %s".printf (line, column, message);
		if (result.diagnostic.format () != expected) {
			GLib.error ("Expected %s; got %s", expected, result.diagnostic.format ());
		}
	}
}

private void malformed() {
	reject ("int ();", 1, 5, "expected VAPI function name");
	reject ("int f;", 1, 6, "expected '(' after VAPI function name");
	reject ("int f(int x;", 1, 12, "expected ')' after VAPI parameters");
	reject ("int f(int);", 1, 10, "expected VAPI parameter name");
	reject ("int f(int x,);", 1, 13, "expected VAPI parameter type name");
	reject ("int f(,);", 1, 7, "expected VAPI parameter type name");
	reject ("int f()\n", 2, 1, "expected ';' after VAPI function declaration");
	reject (";", 1, 1, "expected VAPI function return type name");
	reject ("int f() {}", 1, 9, "unexpected VAPI character '{'");
	reject ("int f(...);", 1, 7, "unexpected VAPI character '.'");
	reject ("int f(int x, ...);", 1, 14, "unexpected VAPI character '.'");
	reject ("void* * ();", 1, 9, "expected VAPI function name");
	reject ("// comment\n@", 2, 1, "unexpected VAPI character '@'");
	reject ("// é\r\n/* unfinished", 2, 1, "unterminated VAPI block comment");
	reject ("/*", 1, 1, "unterminated VAPI block comment");
	reject ("int café();", 1, 8, "non-ASCII character is not supported outside VAPI comments or strings");
	foreach (string text in new string[] {"extern(C) int f();", "export(C) int f();", "export int f();"}) {
		reject (text, 1, 1, "VAPI declarations are implicit C imports; extern/export syntax is not supported");
	}
}

private void metadata() {
	string text = "[CCode (\n\tcname = \"real.add$é\", // comment\r\n\tcheader_filename = \"foo/bar.h,other\"\n)]\nint add(int a, int b);\n[CCode (cheader_filename = \"missing\")] void reset();\nint plain();";
	var parsed = VapiParser.parse (new SourceFile.from_text ("metadata.vapi", text));
	assert (parsed.diagnostic == null && parsed.file.functions.length == 3);
	var function = parsed.file.functions[0];
	assert (function.name.spelling () == "add" && function.span.text ().has_prefix ("[CCode"));
	var attribute = function.metadata;
	assert (attribute.entries.length == 2 && attribute.span.text ().has_suffix (")]"));
	var entry = attribute.entries[0];
	assert (entry.key.spelling () == "cname" && entry.value.kind == VapiTokenKind.STRING);
	assert (entry.value.spelling () == "\"real.add$é\"" && entry.value.string_value == "real.add$é");
	assert (entry.span.text () == "cname = \"real.add$é\"");
	assert (attribute.entries[1].key.spelling () == "cheader_filename" && attribute.entries[1].value.string_value == "foo/bar.h,other");
	int line;
	int column;
	attribute.entries[1].value.span.file.locate (attribute.entries[1].value.span.start, out line, out column);
	assert (line == 3 && column == 21);
	assert (parsed.file.functions[1].metadata.entries.length == 1 && parsed.file.functions[2].metadata == null);
	assert (VapiParser.parse (new SourceFile.from_text ("reverse.vapi", "[CCode (cheader_filename = \"h\", cname = \"f\")] int local();")).diagnostic == null);
}

private void strings() {
	string literal = "\"quote\\\" slash\\\\ n\\n r\\r t\\t é😀 /*string*/\"";
	VapiLexer? lexer = new VapiLexer (new SourceFile.from_text ("strings.vapi", literal));
	var token = lexer.next_token ();
	assert (lexer.next_token ().kind == VapiTokenKind.EOF && lexer.diagnostic == null);
	lexer = null;
	assert (token.spelling () == literal && token.string_value == "quote\" slash\\ n\n r\r t\t é😀 /*string*/");
	assert (new VapiLexer (new SourceFile.from_text ("empty.vapi", "\"\"")).next_token ().string_value == "");
	foreach (string text in new string[] {"\"", "\"abc", "\"abc\\", "\"abc\n\"", "\"abc\r\""}) {
		reject (text, 1, 1, "unterminated VAPI string literal");
	}
	foreach (string escape in new string[] {"q", "0", "x00", "u0000", "v", "é"}) {
		reject ("\"a\\" + escape + "\"", 1, 3, "invalid VAPI string escape");
	}
	for (int mode = 0; mode < 2; mode++) {
		uint8[] bytes = {
			'[', 'C', 'C', 'o', 'd', 'e', ' ', '(', 'c', 'n', 'a', 'm', 'e', '=', '"', mode == 0 ? (uint8) 0 : (uint8) 0xff, '"', ')', ']'
		};
		var result = VapiParser.parse (new SourceFile ("string-bytes.vapi", (owned) bytes));
		assert (result.file == null && result.diagnostic.format () == "string-bytes.vapi:1:16: error: " + (mode == 0 ? "unexpected NUL byte" : "invalid UTF-8 encoding"));
	}
}

private void metadata_errors() {
	reject ("[Foo (cname = \"f\")] int f();", 1, 2, "unknown VAPI attribute 'Foo'");
	reject ("[ccode (cname = \"f\")] int f();", 1, 2, "unknown VAPI attribute 'ccode'");
	reject ("[ (cname = \"f\")] int f();", 1, 3, "expected VAPI attribute name");
	reject ("[CCode] int f();", 1, 7, "expected '(' after CCode");
	reject ("[CCode ()] int f();", 1, 9, "expected VAPI metadata key");
	reject ("[CCode (= \"f\")] int f();", 1, 9, "expected VAPI metadata key");
	foreach (string key in new string[] {"cnamee", "header", "ownership", "array_length", "whatever", "CName", "library", "pkg_config"}) {
		reject ("[CCode (" + key + " = \"f\")] int f();", 1, 9, "unknown VAPI metadata key '" + key + "'");
	}
	foreach (string key in new string[] {"cname", "cheader_filename"}) {
		reject ("[CCode (" + key + " = \"first\",\n  " + key + " = \"second\")] int f();", 2, 3, "duplicate VAPI metadata key '" + key + "'");
		reject ("[CCode (" + key + " = \"\")] int f();", 1, 12 + key.length, "VAPI metadata '" + key + "' must be nonempty");
	}
	reject ("[CCode (cname \"f\")] int f();", 1, 15, "expected '=' after VAPI metadata key");
	reject ("[CCode (cname = f)] int f();", 1, 17, "expected VAPI metadata string literal");
	reject ("[CCode (cname = \"f\",)] int f();", 1, 21, "expected VAPI metadata key");
	reject ("[CCode (cname = \"f\"] int f();", 1, 20, "expected ')' after VAPI metadata");
	reject ("[CCode (cname = \"f\") int f();", 1, 22, "expected ']' after CCode attribute");
	reject ("[CCode (cname = \"f\")]", 1, 22, "expected VAPI function return type name");
	reject ("[CCode (cname = \"f\")][CCode (cname = \"g\")] int f();", 1, 22, "expected VAPI function return type name");
	reject ("[CCode (cname = \"unfinished", 1, 17, "unterminated VAPI string literal");
}

private void encoding() {
	for (int mode = 0; mode < 2; mode++) {
		uint8[] bytes = {
			'/', '/', '\n', mode == 0 ? (uint8) 0xff : (uint8) 0
		};
		var result = VapiParser.parse (new SourceFile ("bytes.vapi", (owned) bytes));
		assert (result.file == null && result.diagnostic != null);
		assert (result.diagnostic.format () == "bytes.vapi:2:1: error: " + (mode == 0 ? "invalid UTF-8 encoding" : "unexpected NUL byte"));
	}
	uint8[] truncated = {
		'/', '*', 0xe2, 0x82
	};
	var result = VapiParser.parse (new SourceFile ("truncated.vapi", (owned) truncated));
	assert (result.diagnostic.format () == "truncated.vapi:1:3: error: invalid UTF-8 encoding");
}

private void pointers() {
	foreach (string spelling in new string[] {"void*", "void *", "void /* ignored */ *", "int*", "bool*", "void**", "void***"}) {
		var parsed = VapiParser.parse (new SourceFile.from_text ("pointer.vapi", "// é\n" + spelling + " f(" + spelling + " p);"));
		assert (parsed.diagnostic == null);
		var type = parsed.file.functions[0].return_type;
		assert (type.span.text () == spelling && type.stars.length > 0);
		assert (type.spelling () == parsed.file.functions[0].parameters[0].type_name.spelling ());
		assert (type.stars[0].kind == VapiTokenKind.STAR && type.stars[0].spelling () == "*");
	}
	reject ("void* f(* p);", 1, 9, "expected VAPI parameter type name");
	reject ("void* f(void*);", 1, 14, "expected VAPI parameter name");
	reject ("void (*f)();", 1, 6, "expected VAPI function name");
	reject ("void* f(void p*);", 1, 15, "expected ')' after VAPI parameters");
}

private void owned_results() {
	string declaration = "[CCode(cname = \"factory\", cheader_filename = \"resource.h\", destroy_function = \"physical.destroy\")] void /* trivia */ * create(int id);";
	var parsed = VapiParser.parse (new SourceFile.from_text ("owned.vapi", declaration));
	assert (parsed.diagnostic == null && parsed.file.functions[0].metadata.entries.length == 3);
	assert (parsed.file.functions[0].metadata.entries[2].value.string_value == "physical.destroy");
	foreach (string type in new string[] {"int", "void", "bool", "Pair", "Pair*", "void**"}) {
		var invalid = VapiParser.parse (new SourceFile.from_text ("owned.vapi", "[CCode(destroy_function = \"destroy\")] " + type + " create();"));
		assert (invalid.file == null && invalid.diagnostic.message == "VAPI destroy_function requires exactly a 'void*' result");
	}
	foreach (string metadata in new string[] {"destroy_function = \"\"", "destroy_function = \"a\", destroy_function = \"b\"", "destroy_function = 7", "destroy_function = destroy"}) {
		var invalid = VapiParser.parse (new SourceFile.from_text ("owned.vapi", "[CCode(" + metadata + ")] void* create();"));
		assert (invalid.file == null && invalid.diagnostic != null);
	}
}

private void handles() {
	string text = "[CCode(destroy_function = \"destroy\", cheader_filename = \"missing.h\")] handle Resource; owned Resource create(); int inspect(borrowed Resource r);";
	var parsed = VapiParser.parse (new SourceFile.from_text ("handles.vapi", text));
	assert (parsed.diagnostic == null && parsed.file.handles.length == 1 && parsed.file.functions.length == 2);
	var handle = parsed.file.handles[0];
	assert (handle.name.spelling () == "Resource" && handle.keyword.kind == VapiTokenKind.HANDLE && handle.semicolon.kind == VapiTokenKind.SEMICOLON);
	assert (handle.name.span.text () == "Resource" && handle.span.text ().has_prefix ("[CCode"));
	assert (handle.metadata.entries.length == 2);
	assert (parsed.file.functions[0].owned_keyword.kind == VapiTokenKind.OWNED);
	assert (parsed.file.functions[0].span.text () == "owned Resource create();");
	assert (parsed.file.functions[1].parameters[0].borrowed_keyword.kind == VapiTokenKind.BORROWED);
}
private void malformed_handles() {
	foreach (string text in new string[] {"handle Resource;", "[CCode(cheader_filename = \"missing.h\")] handle Resource;", "[CCode(destroy_function = \"\")] handle Resource;", "[CCode(destroy_function = \"d\", cname = \"R\")] handle Resource;", "[CCode(destroy_function = \"d\", destroy_function = \"d\")] handle Resource;", "[CCode(destroy_function = \"d\")] handle;", "[CCode(destroy_function = \"d\")] handle Resource", "[CCode(destroy_function = \"d\")] handle Resource();", "[CCode(destroy_function = \"d\")] handle Resource*;", "owned Resource;", "owned borrowed Resource f();", "Resource f(owned Resource r);"}) {
		var parsed = VapiParser.parse (new SourceFile.from_text ("invalid-handle.vapi", text));
		assert (parsed.file == null && parsed.diagnostic != null);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vapi-frontend/handle-grammar-metadata", handles);
	Test.add_func ("/vapi-frontend/malformed-handles", malformed_handles);
	Test.add_func ("/vapi-frontend/borrowed-grammar", borrowed_grammar);
	Test.add_func ("/vapi-frontend/owned-results", owned_results);
	Test.add_func ("/vapi-frontend/grammar-comments-locations", grammar);
	Test.add_func ("/vapi-frontend/lexer-lifetime", lexer_lifetime);
	Test.add_func ("/vapi-frontend/malformed", malformed);
	Test.add_func ("/vapi-frontend/pointer-syntax", pointers);
	Test.add_func ("/vapi-frontend/encoding", encoding);
	Test.add_func ("/vapi-frontend/metadata-syntax-provenance", metadata);
	Test.add_func ("/vapi-frontend/string-literals", strings);
	Test.add_func ("/vapi-frontend/metadata-diagnostics", metadata_errors);
	return Test.run ();
}
}
