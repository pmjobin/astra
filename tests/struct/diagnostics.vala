// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;

namespace Astra.Tests.Structs {
private void semantic_error(string text, string message, string marker) {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", text));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.program == null && result.diagnostic != null);
	if (result.diagnostic.message != message || result.diagnostic.span.text () != marker) {
		GLib.error ("expected '%s' at '%s', found %s at '%s'", message, marker, result.diagnostic.format (), result.diagnostic.span.text ());
	}
	var repeated = SemanticAnalyzer.analyze (parsed.unit);
	assert (repeated.diagnostic.format () == result.diagnostic.format ());
}

private void register_diagnostics() {
	string[,] invalid = {
		{
			"duplicate-type", "struct P { int x; } struct P { int y; }", "duplicate struct type 'P'", "P"
		},
		{
			"builtin-int", "struct int { int x; }", "struct name 'int' conflicts with builtin type", "int"
		},
		{
			"builtin-bool", "struct bool { int x; }", "struct name 'bool' conflicts with builtin type", "bool"
		},
		{
			"builtin-void", "struct void { int x; }", "struct name 'void' conflicts with builtin type", "void"
		},
		{
			"empty", "struct Empty {}", "empty struct 'Empty' is not supported", "Empty"
		},
		{
			"duplicate-field", "struct P { int x; bool x; }", "duplicate field 'x' in struct 'P'", "x"
		},
		{
			"void-field", "struct P { void x; }", "field type cannot be 'void'", "void"
		},
		{
			"unknown-type", "struct P { Missing x; }", "unknown type 'Missing'", "Missing"
		},
		{
			"recursive-field", "struct P { P p; }", "recursive by-value struct layout: P → P", "P"
		},
		{
			"typed-pointer", "struct P { int* p; }", "typed-pointer struct fields are not supported yet; fields must be 'int', 'bool' or 'void*'", "int*"
		},
		{
			"struct-pointer", "struct P { P* p; }", "typed-pointer struct fields are not supported yet; fields must be 'int', 'bool' or 'void*'", "P*"
		},
		{
			"pointer-depth", "struct P { void** p; }", "pointer depth greater than one is unsupported", "void**"
		},
		{
			"empty-init", "struct P { int x; } int f() { P p = {}; return 0; }", "missing initializer for field 'x'", "}"
		},
		{
			"missing-field", "struct P { int x; int y; } int f() { P p = { x = 1 }; return 0; }", "missing initializer for field 'y'", "}"
		},
		{
			"duplicate-init", "struct P { int x; int y; } int f() { P p = { x = 1, x = 2, y = 3 }; return 0; }", "duplicate initializer for field 'x'", "x"
		},
		{
			"unknown-init", "struct P { int x; } int f() { P p = { z = 1 }; return 0; }", "unknown initializer field 'z' in struct 'P'", "z"
		},
		{
			"int-init-type", "struct P { int x; } int f() { P p = { x = true }; return 0; }", "field 'x' expects initializer of type 'int', found 'bool'", "true"
		},
		{
			"bool-init-type", "struct P { bool x; } int f() { P p = { x = 1 }; return 0; }", "field 'x' expects initializer of type 'bool', found 'int'", "1"
		},
		{
			"ptr-init-type", "struct P { void* x; } int f() { P p = { x = 0 }; return 0; }", "field 'x' expects initializer of type 'void*', found 'int'", "0"
		},
		{
			"self-first", "struct P { int x; int y; } int f() { P p = { x = p.y, y = 1 }; return 0; }", "unknown name 'p'", "p"
		},
		{
			"self-later", "struct P { int x; int y; } int f() { P p = { x = 1, y = p.x }; return 0; }", "unknown name 'p'", "p"
		},
		{
			"scalar-context", "int f() { int x = { value = 1 }; return x; }", "named field initializer requires a struct local type", "{ value = 1 }"
		},
		{
			"scalar-field", "int f() { int x = 1; return x.value; }", "field access requires a local struct variable", "x"
		},
		{
			"nested-scalar-read", "struct P { int x; } int f() { P p = { x = 1 }; return p.x.y; }", "nested field base requires an exact StructType Place", "p.x"
		},
		{
			"nested-scalar-store", "struct P { int x; } int f() { P p = { x = 1 }; p.x.y = 2; return 0; }", "nested field base requires an exact StructType Place", "p.x"
		},
		{
			"parameter-field", "int f(int x) { return x.value; }", "field access requires a local struct variable", "x"
		},
		{
			"unknown-field", "struct P { int x; } int f() { P p = { x = 1 }; return p.z; }", "unknown field 'z' in struct 'P'", "z"
		},
		{
			"field-store-type", "struct P { int x; } int f() { P p = { x = 1 }; p.x = false; return 0; }", "expected assignment value of type 'int', found 'bool'", "false"
		},
		{
			"field-store-unknown", "struct P { int x; } int f() { P p = { x = 1 }; p.z = 2; return 0; }", "unknown field 'z' in struct 'P'", "z"
		},
		{
			"field-store-scalar", "int f() { int p = 0; p.x = 2; return 0; }", "field access requires a local struct variable", "p"
		},
		{
			"whole-return", "struct P { int x; } int f() { P p = { x = 1 }; return p; }", "whole-struct values are not supported yet; access a field", "p"
		},
		{
			"whole-call", "struct P { int x; } int g(int x) { return x; } int f() { P p = { x = 1 }; return g(p); }", "whole-struct values are not supported yet; access a field", "p"
		},
		{
			"whole-equality", "struct P { int x; } int f() { P p = { x = 1 }; if (p == p) { return 1; } return 0; }", "whole-struct values are not supported yet; access a field", "p"
		},
		{
			"whole-inequality", "struct P { int x; } int f() { P p = { x = 1 }; if (p != p) { return 1; } return 0; }", "whole-struct values are not supported yet; access a field", "p"
		},
		{
			"expression-init", "struct P { int x; } int f() { P p = 1; return 0; }", "struct local requires a complete named field initializer", "1"
		},
		{
			"struct-parameter", "struct P{int x;}struct Q{int x;}void f(Q q){}void g(P p){f(p);}", "struct boundary requires exact nominal type 'Q', found 'P'; equal layout is insufficient", "p"
		},
		{
			"struct-result", "struct P{int x;}struct Q{int x;}Q f(P p){return p;}", "struct boundary requires exact nominal type 'Q', found 'P'; equal layout is insufficient", "p"
		},
		{
			"extern-parameter", "struct P { int x; } extern(C) int f(P p);", "struct function parameters are not supported yet (including C boundaries)", "P"
		},
		{
			"extern-result", "struct P { int x; } extern(C) P f();", "struct function results are not supported yet (including C boundaries)", "P"
		},
		{
			"export-parameter", "struct P { int x; } export(C) int f(P p) { return 0; }", "struct function parameters are not supported yet (including C boundaries)", "P"
		},
		{
			"export-result", "struct P { int x; } export(C) P f() {}", "struct function results are not supported yet (including C boundaries)", "P"
		},
		{
			"scope-escape", "struct P { int x; } int f(bool c) { if (c) { P p = { x = 1 }; } return p.x; }", "unknown name 'p'", "p"
		},
		{
			"scope-shadow", "struct P { int x; } int f() { P p = { x = 1 }; if (true) { P p = { x = 2 }; } return 0; }", "duplicate local 'p'", "p"
		},
		{
			"scope-parameter", "struct P { int x; } int f(int p) { P p = { x = 1 }; return 0; }", "local 'p' conflicts with parameter", "p"
		}
	};
	for (int i = 0; i < invalid.length[0]; i++) {
		string text = invalid[i, 1];
		string message = invalid[i, 2];
		string marker = invalid[i, 3];
		add ("/struct/diagnostic/" + invalid[i, 0], () => semantic_error (text, message, marker));
	}
	// STRUCT-COPY-1 supersedes these two whole-storage rejection cases.
	foreach (string text in new string[] {"struct P{int x;}void f(){P p={x=1};P q=p;}", "struct P{int x;}void f(){P p={x=1};p=p;}"}) {
		string source = text;
		add (source.contains ("q=p") ? "/struct/copy/whole-copy" : "/struct/copy/whole-store", () => {
				var parsed = Parser.parse (new SourceFile.from_text ("copy.astra", source));
				var result = SemanticAnalyzer.analyze (parsed.unit);
				assert (result.diagnostic == null && result.program.functions[0].body.statements[1] is CheckedStructCopy);
			});
	}
	string[] malformed = {
		"struct { int x; }", "struct P int x; }", "struct P { int; }", "struct P { int x }", "struct P { int x;", "struct P { int x; };",
		"int f() { struct P { int x; } return 0; }", "int f() { P p = { x = 1, }; }", "int f() { P p = { x 1 }; }",
		"int f() { P p = { x = }; }", "int f() { P p = { x = 1 y = 2 }; }", "int f() { P p = { x = 1 }; return p.; }",
		"int f() { return (p).x; }", "int f() { return f().x; }", "int f() { return { x = 1 }; }", "int f() { P p; }"
	};
	for (int i = 0; i < malformed.length; i++) {
		string text = malformed[i];
		bool observation = i == 12 || i == 13;
		add ("/struct/parser/malformed-%02d".printf (i), () => {
				var source = new SourceFile.from_text ("malformed.astra", text);
				var parsed = Parser.parse (source);
				if (observation) {
					// Approved milestone 15 grammar promotion; exact originals remain
					// semantic negatives and have typed executable counterparts.
					assert (parsed.unit != null && parsed.diagnostic == null);
					var checked = SemanticAnalyzer.analyze (parsed.unit);
					assert (checked.program == null && checked.diagnostic != null);
					assert (checked.diagnostic.message.contains (text.contains ("(p)") ? "unknown name 'p'" : "field"));
					var repeated = SemanticAnalyzer.analyze (parsed.unit);
					assert (checked.diagnostic.format () == repeated.diagnostic.format ());
				} else {
					assert (parsed.unit == null && parsed.diagnostic != null);
					var repeated = Parser.parse (source);
					assert (parsed.diagnostic.format () == repeated.diagnostic.format ());
				}
			});
	}
	add ("/struct/diagnostic/later-declaration-span", () => {
			string text = "struct P { int x; bool x; }";
			var parsed = Parser.parse (new SourceFile.from_text ("duplicate.astra", text));
			var result = SemanticAnalyzer.analyze (parsed.unit);
			assert (result.diagnostic.span.start == text.last_index_of ("x;"));
		});
	foreach (string declaration in new string[] {"P foreign();", "int foreign(P p);"}) {
		string text = declaration;
		add ("/struct/vapi/" + (text.has_prefix ("P") ? "result" : "parameter"), () => {
				var vapi = VapiParser.parse (new SourceFile.from_text ("struct.vapi", text));
				assert (vapi.diagnostic == null);
				var parsed = Parser.parse (new SourceFile.from_text ("struct.astra", "struct P { int x; }"));
				var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file));
				assert (result.diagnostic != null && result.diagnostic.message == "struct types are not supported at C/VAPI function boundaries");
				assert (result.diagnostic.span.text () == "P");
			});
	}
	add ("/struct/vapi/declaration-unsupported", () => {
			var parsed = VapiParser.parse (new SourceFile.from_text ("struct.vapi", "struct P { int x; }"));
			assert (parsed.diagnostic != null && parsed.file == null);
		});
}

}
