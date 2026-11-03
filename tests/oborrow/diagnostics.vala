// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.OwnerBorrow {
private void semantic_invalid(string source, string message, string declarations = VAPI) {
	var result = analyze (source, declarations);
	if (result.diagnostic == null || !result.diagnostic.message.contains (message)) {
		GLib.error ("expected '%s', got '%s' for %s", message, result.diagnostic == null ? "success" : result.diagnostic.message, source);
	}
}

private void flow_case(string statements, string? message) throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* h = create(1); " + statements + " }");
	var result = CfgFlowChecker.check (control);
	if (message == null) {
		assert (result.diagnostic == null);
		SsaBuilder.build (control);
	} else {
		assert (result.diagnostic != null && result.diagnostic.message == message && result.diagnostic.span.text () == "h");
		try {
			SsaBuilder.build (control);
			assert_not_reached ();
		} catch (SsaError.INVALID_CFG error) {
			assert (error.message.contains (message));
		}
	}
}

private void register_diagnostics() {
	foreach (string source in new string[] {"borrowed void* f() {}", "void f() { borrowed void* p = null; }", "struct Holder { borrowed void* p; }", "extern(C) borrowed void* f();", "void f(borrowed borrowed void* p) {}"}) {
		add ("/oborrow/grammar/" + source, () => {
				var result = Parser.parse (new SourceFile.from_text ("invalid.astra", source));
				assert (result.diagnostic != null && result.diagnostic.message.contains ("'borrowed' is supported only"));
			});
	}
	foreach (string type in new string[] {"int", "bool", "Pair", "Pair*", "void", "void**"}) {
		if (type == "Pair*") {
			add ("/oborrow/type/native/" + type, () => {
					build ("struct Pair{int x;}int read(borrowed Pair* p){return p->x;}int f(){Pair p={x=42};return read(&p);}");
					semantic_invalid ("struct Pair{int x;}void unmanaged_pair(Pair* p){}void f(borrowed Pair* p){unmanaged_pair(p);}", "cannot be stored, returned, or forwarded");
				});
		} else if (type == "Pair") {
			add ("/oborrow/type/native/" + type, () => {
					var result = analyze ("struct Pair { int x; } void f(borrowed Pair p) {}");
					assert (result.diagnostic == null && result.program != null);
				});
		} else {
			add ("/oborrow/type/native/" + type, () => semantic_invalid ("struct Pair { int x; } void f(borrowed " + type + " p) {}", type == "void**" ? "pointer depth greater than one" : "requires exactly 'void*'"));
		}
		add ("/oborrow/type/extern/" + type, () => semantic_invalid ("struct Pair { int x; } extern(C) void f(borrowed " + type + " p);", "requires exactly 'void*'"));
		add ("/oborrow/type/vapi/" + type, () => semantic_invalid ("", "requires exactly 'void*'", "int inspect(borrowed " + type + " p);"));
	}
	add ("/oborrow/export", () => semantic_invalid ("export(C) int f(borrowed void* p) { return 0; }", "unsupported on export(C)"));
	string[] captures = {
		"void* q = p;", "void* q = null; q = p;", "Holder h = { handle = p };", "Holder h = { handle = null }; h.handle = p;", "Holder h = { handle = null }; Holder* ptr = &h; ptr->handle = p;", "out->handle = p;", "return p;", "use(p);", "native_raw(p);", "owned void* h = p;", "void* q = (p);", "if (p == null) { use(p); }", "while (p != null) { void* q = p; }", "if (false && native_raw(p) != 0) { return null; }"
	};
	for (int i = 0; i < captures.length; i++) {
		string source = "struct Holder { void* handle; } int native_raw(void* q) { return 0; } void* f(borrowed void* p, Holder* out) { " + captures[i] + " return null; }";
		add ("/oborrow/noescape/%d".printf (i), () => semantic_invalid (source, "borrowed parameter 'p' cannot be stored, returned, or forwarded to an unmanaged parameter"));
	}
	add ("/oborrow/no-move-parameter", () => semantic_invalid ("void f(borrowed void* p) { owned void* h = move p; }", "must be an owned void* local"));
	add ("/oborrow/no-inline-acquisition", () => semantic_invalid ("void f() { inspect(create(1)); }", "foreign result carries ownership responsibility"));
	add ("/oborrow/no-general-conversion", () => semantic_invalid ("void f() { owned void* h = create(1); void* raw = h; }", "owned local 'h' cannot"));
	add ("/oborrow/no-owner-raw-call", () => semantic_invalid ("void f() { owned void* h = create(1); use(h); }", "owned local 'h' cannot"));
	string moved = "cannot borrow moved owned value 'h'";
	string maybe = "owned value 'h' may have been moved on another control-flow path and cannot be borrowed";
	add ("/oborrow/flow/moved", () => flow_case ("owned void* next = move h; inspect(h);", moved));
	add ("/oborrow/flow/maybe", () => flow_case ("if (c) { owned void* next = move h; } inspect(h);", maybe));
	add ("/oborrow/flow/backedge", () => flow_case ("while (c) { inspect(h); owned void* next = move h; }", maybe));
	add ("/oborrow/flow/backedge-continue", () => flow_case ("while (c) { inspect(h); owned void* next = move h; continue; }", maybe));
	add ("/oborrow/flow/terminating-arm", () => flow_case ("if (c) { owned void* next = move h; return; } inspect(h);", null));
	add ("/oborrow/flow/repeated-loop", () => flow_case ("while (c) { inspect(h); inspect(h); } inspect(h);", null));
	add ("/oborrow/flow/before-move", () => flow_case ("inspect(h); if (c) { owned void* next = move h; inspect(next); }", null));
	add ("/oborrow/forward-raw-null-comparison", () => {
			build ("int inner(borrowed void* p) { return inspect(p); } int outer(borrowed void* p, void* q) { if (p == q || p != null) { return inner((p)); } return inspect(null); } void f(void* p) { outer(p, null); inspect(raw()); }");
		});
}

}
