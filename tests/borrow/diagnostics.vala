// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Borrows {
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
	string[,] invalid = {
		{
			"if", "void f(bool c) { Pair* p = null; if (c) { Pair inner = { x = 1, y = 2 }; p = &inner; } }", "borrow from 'inner' cannot be stored in pointer 'p' because 'inner' has a shorter lexical lifetime", "&inner"
		},
		{
			"else", "void f(bool c) { Pair* p = null; if (c) {} else { Pair inner = { x = 1, y = 2 }; p = &inner; } }", "shorter lexical lifetime", "&inner"
		},
		{
			"while", "void f(bool c) { Pair* p = null; while (c) { Pair inner = { x = 1, y = 2 }; p = &inner; break; } }", "shorter lexical lifetime", "&inner"
		},
		{
			"nested-loop", "void f(bool c) { while (c) { Pair* p = null; while (c) { Pair inner = { x = 1, y = 2 }; p = &inner; break; } break; } }", "shorter lexical lifetime", "&inner"
		},
		{
			"copy", "void f(bool c) { Pair* p = null; if (c) { Pair pair = { x = 1, y = 2 }; Pair* inner = &pair; p = inner; } }", "borrow from 'inner' cannot be stored in pointer 'p' because 'inner' has a shorter lexical lifetime", "inner"
		},
		{
			"copy-conservative", "void f(bool c) { Pair pair = { x = 1, y = 2 }; Pair* p = null; if (c) { Pair* inner = &pair; p = inner; } }", "shorter lexical lifetime", "inner"
		},
		{
			"null-copy-conservative", "void f(bool c) { Pair* p = null; if (c) { Pair* inner = null; p = inner; } }", "shorter lexical lifetime", "inner"
		},
		{
			"parameter-copy-conservative", "void f(Pair* parameter) { Pair* p = null; if (true) { Pair* inner = parameter; p = inner; } }", "shorter lexical lifetime", "inner"
		},
		{
			"siblings-via-parent", "void f(bool c) { Pair* p = null; if (c) { Pair inner = { x = 1, y = 2 }; p = &inner; } else { Pair* q = p; } }", "shorter lexical lifetime", "&inner"
		},
		{
			"unreachable", "void f() { Pair* p = null; if (false) { Pair inner = { x = 1, y = 2 }; p = &inner; } }", "shorter lexical lifetime", "&inner"
		},
		{
			"initializer-type", "void f() { Pair pair = { x = 1, y = 2 }; State* p = &pair; }", "expected initializer of type 'State*', found 'Pair*'", "&pair"
		},
		{
			"assignment-type", "void f() { Pair pair = { x = 1, y = 2 }; State* p = null; p = &pair; }", "expected assignment value of type 'State*', found 'Pair*'", "&pair"
		},
		{
			"copy-type", "void f(Pair* parameter) { State* p = parameter; }", "expected initializer of type 'State*', found 'Pair*'", "parameter"
		},
		{
			"c-stored", "extern(C) void consume(void* p); void f() { Pair pair = { x = 1, y = 2 }; Pair* p = &pair; consume(p); }", "expects type 'void*', provided 'Pair*'", "p"
		},
		{
			"opaque-store", "void f() { Pair pair = { x = 1, y = 2 }; void* p = null; p = &pair; }", "expected assignment value of type 'void*', found 'Pair*'", "&pair"
		},
		{
			"opaque-field", "struct Holder { void* p; } void f() { Pair pair = { x = 1, y = 2 }; Holder holder = { p = null }; holder.p = &pair; }", "expected assignment value of type 'void*', found 'Pair*'", "&pair"
		},
		{
			"return", "Pair* f() { Pair pair = { x = 1, y = 2 }; return &pair; }", "typed-pointer function results are unsupported", "Pair*"
		},
		{
			"stored-return", "void* f() { Pair pair = { x = 1, y = 2 }; Pair* p = &pair; return p; }", "expected return value of type 'void*', found 'Pair*'", "p"
		},
		{
			"parameter-assignment", "void f(Pair* p) { Pair pair = { x = 1, y = 2 }; p = &pair; }", "assignment to parameter 'p' is not supported", "p"
		},
		{
			"early-borrow", "void f() { Pair* p = &pair; Pair pair = { x = 1, y = 2 }; }", "address borrow requires a direct local integer, f32, numeric vector, or native struct variable", "&pair"
		}
	};
	for (int i = 0; i < invalid.length[0]; i++) {
		string source = invalid[i, 1];
		string expected = invalid[i, 2];
		string marker = invalid[i, 3];
		add ("/borrow/diagnostic/" + invalid[i, 0], () => reject (source, expected, marker));
	}
}
}
