// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;

namespace Astra.Tests.TypedPointers {
private const string DECLARATIONS = "struct Pair { int x; int y; } struct State { int x; } ";

private void reject(string text, string expected, string marker) {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", DECLARATIONS + text));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic == null || !result.diagnostic.message.contains (expected) || result.diagnostic.span.text () != marker) {
		GLib.error ("expected %s at %s; found %s", expected, marker, result.diagnostic == null ? "accepted" : result.diagnostic.format ());
	}
	assert (result.program == null);
	assert (SemanticAnalyzer.analyze (parsed.unit).diagnostic.format () == result.diagnostic.format ());
}

private void register_diagnostics() {
	add ("/tptr/now-valid/initialize-borrow", () => { check (DECLARATIONS + "void f() { Pair p = { x = 1, y = 2 }; Pair* q = &p; }");
	});
	add ("/tptr/now-valid/assign-borrow", () => { check (DECLARATIONS + "void f() { Pair p = { x = 1, y = 2 }; Pair* q = null; q = &p; }");
	});
	add ("/tptr/now-valid/compare-borrow", () => { check (DECLARATIONS + "bool f() { Pair p = { x = 1, y = 2 }; return &p == null; }");
	});
	add ("/tptr/now-valid/wrapped-borrow", () => { check (DECLARATIONS + "void use(Pair* p) {} void f() { Pair p = { x = 1, y = 2 }; use((&p)); }");
	});
	string[,] invalid = {
		{
			"result", "Pair* f() { return null; }", "typed-pointer function results are unsupported; escaping pointers require return-lifetime contracts", "Pair*"
		},
		{
			"result-recursive", "Pair* f(Pair* p) { return f(p); }", "typed-pointer function results are unsupported", "Pair*"
		},
		{
			"depth-two", "void f(Pair** p) {}", "pointer depth greater than one is unsupported", "Pair**"
		},
		{
			"depth-three", "void f(Pair*** p) {}", "pointer depth greater than one is unsupported", "Pair***"
		},
		{
			"depth-void", "void f(void** p) {}", "pointer depth greater than one is unsupported", "void**"
		},
		{
			"bool-pointer", "void f(bool* p) {}", "typed pointer pointee must be an integer, f32, numeric vector, or native struct; bool and resource storage are unsupported", "bool*"
		},
		{
			"unknown-pointer", "void f(Missing* p) {}", "unknown type 'Missing'", "Missing*"
		},
		{
			"pointer-field", "struct Holder { Pair* p; }", "typed-pointer struct fields are not supported", "Pair*"
		},
		{
			"return-borrow-void", "void f() { Pair p = { x = 1, y = 2 }; return &p; }", "cannot return a value from a 'void' function", "&p"
		},
		{
			"return-borrow-wrapped", "void f() { Pair p = { x = 1, y = 2 }; return (&p); }", "cannot return a value from a 'void' function", "(&p)"
		},
		{
			"return-borrow", "void* f() { Pair p = { x = 1, y = 2 }; return &p; }", "expected return value of type 'void*', found 'Pair*'", "&p"
		},
		{
			"borrow-void", "void use(void* p) {} void f() { Pair p = { x = 1, y = 2 }; use(&p); }", "expects type 'void*', provided 'Pair*'", "&p"
		},
		{
			"borrow-wrong-pointee", "void use(State* p) {} void f() { Pair p = { x = 1, y = 2 }; use(&p); }", "expects type 'State*', provided 'Pair*'", "&p"
		},
		{
			"borrow-c", "extern(C) void use(void* p); void f() { Pair p = { x = 1, y = 2 }; use(&p); }", "expects type 'void*', provided 'Pair*'", "&p"
		},
		{
			"borrow-scalar", "void use(Pair* p) {} void f() { int n = 1; use(&n); }", "expects type 'Pair*', provided 'int*'", "&n"
		},
		{
			"borrow-bool", "void use(Pair* p) {} void f() { bool n = true; use(&n); }", "address borrow requires a direct local integer, f32, numeric vector, or native struct variable", "&n"
		},
		{
			"borrow-opaque", "void use(Pair* p) {} void f() { void* n = null; use(&n); }", "address borrow requires a direct local integer, f32, numeric vector, or native struct variable", "&n"
		},
		{
			"borrow-pointer-local", "void use(Pair* p) {} void f() { Pair* n = null; use(&n); }", "address borrow requires a direct local integer, f32, numeric vector, or native struct variable", "&n"
		},
		{
			"borrow-parameter", "void use(Pair* p) {} void f(Pair* n) { use(&n); }", "address borrow requires a direct local integer, f32, numeric vector, or native struct variable", "&n"
		},
		{
			"borrow-self-initializer", "int use(Pair* p) { return 1; } void f() { Pair n = { x = use(&n), y = 2 }; }", "address borrow requires a direct local integer, f32, numeric vector, or native struct variable", "&n"
		},
		{
			"borrow-out-of-scope", "void use(Pair* p) {} void f() { if (true) { Pair n = { x = 1, y = 2 }; } use(&n); }", "address borrow requires a direct local integer, f32, numeric vector, or native struct variable", "&n"
		},
		{
			"native-conversion", "void use(State* p) {} void f(Pair* p) { use(p); }", "expects type 'State*', provided 'Pair*'", "p"
		},
		{
			"typed-to-opaque", "void f(Pair* p) { void* q = p; }", "expected initializer of type 'void*', found 'Pair*'", "p"
		},
		{
			"opaque-to-typed", "void f(void* p) { Pair* q = p; }", "expected initializer of type 'Pair*', found 'void*'", "p"
		},
		{
			"opaque-null-variable", "void f() { void* p = null; Pair* q = p; }", "expected initializer of type 'Pair*', found 'void*'", "p"
		},
		{
			"c-escape", "extern(C) void use(void* p); void f(Pair* p) { use(p); }", "expects type 'void*', provided 'Pair*'", "p"
		},
		{
			"import-parameter", "extern(C) void use(Pair* p);", "typed native struct pointers are not supported by the C ABI yet", "Pair*"
		},
		{
			"import-result", "extern(C) Pair* use();", "typed native struct pointers are not supported by the C ABI yet", "Pair*"
		},
		{
			"export-parameter", "export(C) void use(Pair* p) {}", "typed native struct pointers are not supported by the C ABI yet", "Pair*"
		},
		{
			"export-result", "export(C) Pair* use() { return null; }", "typed native struct pointers are not supported by the C ABI yet", "Pair*"
		},
		{
			"compare-different", "bool f(Pair* p, State* q) { return p == q; }", "requires matching non-void operands, found 'Pair*' and 'State*'", "=="
		},
		{
			"compare-opaque", "bool f(Pair* p, void* q) { return p != q; }", "requires matching non-void operands, found 'Pair*' and 'void*'", "!="
		},
		{
			"compare-integer", "bool f(Pair* p) { return p == 0; }", "requires matching non-void operands, found 'Pair*' and 'int'", "=="
		},
		{
			"compare-bool", "bool f(Pair* p) { return p == false; }", "requires matching non-void operands, found 'Pair*' and 'bool'", "=="
		},
		{
			"truthiness", "void f(Pair* p) { if (p) {} }", "if condition must have type 'bool', found 'Pair*'", "p"
		},
		{
			"while-truthiness", "void f(Pair* p) { while (p) {} }", "while condition must have type 'bool', found 'Pair*'", "p"
		},
		{
			"not-pointer", "bool f(Pair* p) { return !p; }", "requires a 'bool' operand, found 'Pair*'", "p"
		},
		{
			"unknown-field", "int f(Pair* p) { return p->missing; }", "unknown field 'missing' in struct 'Pair'", "missing"
		},
		{
			"nested-scalar-field", "int f(Pair* p) { return p->x.y; }", "nested field base requires an exact StructType Place", "p->x"
		},
		{
			"void-indirect", "int f(void* p) { return p->x; }", "indirect field access requires a native struct pointer", "p"
		},
		{
			"struct-indirect", "int f() { Pair p = { x = 1, y = 2 }; return p->x; }", "indirect field access requires a native struct pointer", "p"
		},
		{
			"scalar-indirect", "int f(int p) { return p->x; }", "indirect field access requires a native struct pointer", "p"
		},
		{
			"direct-pointer", "int f(Pair* p) { return p.x; }", "field access requires a local struct variable", "p"
		},
		{
			"store-type", "void f(Pair* p) { p->x = true; }", "expected assignment value of type 'int', found 'bool'", "true"
		},
		{
			"unknown-base", "int f() { return p->x; }", "unknown name 'p'", "p"
		},
		{
			"null-integer", "void f() { Pair* p = 0; }", "expected initializer of type 'Pair*', found 'int'", "0"
		}
	};
	for (int i = 0; i < invalid.length[0]; i++) {
		string text = invalid[i, 1];
		string expected = invalid[i, 2];
		string marker = invalid[i, 3];
		add ("/tptr/diagnostic/" + invalid[i, 0], () => reject (text, expected, marker));
	}
	foreach (string operation in new string[] {"+", "-", "*", "/", "%", "<", "<=", ">", ">="}) {
		string op = operation;
		add ("/tptr/operator/" + op.replace ("/", "divide"), () => reject ("int f(Pair* p, Pair* q) { return p " + op + " q; }", "requires an 'int' operand, found 'Pair*'", "p"));
	}
	string[] malformed = {
		"int f() { return &(p); }", "int f() { return &p.x; }", "int f() { return &p->x; }", "int f() { return &&p; }",
		"int f() { return &; }", "int f() { return &42; }", "int f() { return p->; }",
		"int f() { p-> = 1; }", "int f() { return p->x..y; }", "int f() { return p->x->y; }",
		"int f() { return (&p)->x; }", "int f() { return f()->x; }", "int f() { return (p)->x; }",
		"int f() { return p - > x; }", "int f() { return p->x(); }", "int f() { return true | ; }",
		"int f() { return (Pair*)p; }", "void (*f)(Pair* p);", "int f() { return &f(); }"
	};
	for (int i = 0; i < malformed.length; i++) {
		string text = malformed[i];
		add ("/tptr/parser/malformed-%02d".printf (i), () => {
				var source = new SourceFile.from_text ("malformed", text);
				var first = Parser.parse (source);
				assert (first.unit == null && first.diagnostic != null);
				assert (first.diagnostic.format () == Parser.parse (source).diagnostic.format ());
			});
	}
	foreach (string declaration in new string[] {"Pair* use();", "void use(Pair* p);", "void use(Pair** p);"}) {
		string text = declaration;
		add ("/tptr/vapi/" + text, () => {
				var parsed = VapiParser.parse (new SourceFile.from_text ("typed.vapi", text));
				assert (parsed.diagnostic == null);
				foreach (string source in new string[] {"", DECLARATIONS}) {
					var native = Parser.parse (new SourceFile.from_text ("native", source));
					var result = SemanticAnalyzer.analyze (native.unit, VapiNormalizer.normalize (parsed.file));
					assert (result.program == null && result.diagnostic.message == "unsupported foreign pointer type; C/VAPI supports only 'void*'");
					assert (result.diagnostic.span.file == parsed.file.span.file);
				}
			});
	}
}

}
