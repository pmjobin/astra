// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Moves {
private void parse_invalid(string statement) {
	var parsed = Parser.parse (new SourceFile.from_text ("move.astra", "void f() { owned void* a = create(1); " + statement + " }"));
	assert (parsed.unit == null && parsed.diagnostic != null);
	assert (parsed.diagnostic.message.contains ("move"));
}

private void semantic_invalid(string text, string message) {
	var result = analyze (text);
	assert (result.program == null && result.diagnostic != null && result.diagnostic.message.contains (message));
}

private void flow_invalid(string statements, bool maybe, string operand) throws GLib.Error {
	var control = cfg ("void f(bool condition) { owned void* a = create(1); " + statements + " }");
	var result = CfgFlowChecker.check (control);
	assert (result.diagnostic != null);
	assert (result.diagnostic.message == (maybe ? "owned value 'a' may have been moved on another control-flow path" : "use of moved owned value 'a'"));
	assert (result.diagnostic.span.text () == operand);
	try {
		SsaBuilder.build (control);
		assert_not_reached ();
	} catch (SsaError.INVALID_CFG error) {
		assert (error.message.contains (result.diagnostic.message));
	}
}

private void register_diagnostics() {
	string[] syntax = {
		"void* p = move a;", "move a == null;", "int x = move a;", "owned void* b = (move a);", "owned void* b = move create(1);", "owned void* b = move (a);", "owned void* b = move a == null;", "owned void* b = move a.field;", "a = move a;", "if (true && move a) { return; }", "owned void* b = move;"
	};
	for (int i = 0; i < syntax.length; i++) {
		string statement = syntax[i];
		if (i == 0 || i == 2 || i == 7) {
			string message = i == 7 ? "moving ownership out of an owned field" : "requires a fresh 'owned void*' local destination";
			add ("/move/invalid-syntax/%d".printf (i), () => semantic_invalid ("void f() { owned void* a = create(1); " + statement + " }", message));
		} else if (i == 8) {
			add ("/move/invalid-assignment/legacy-pointer", () => semantic_invalid ("void f() { owned void* a = create(1); a = move a; }", "rearming requires a direct foreign owned-result call"));
		} else {
			add ("/move/invalid-syntax/%d".printf (i), () => parse_invalid (statement));
		}
	}
	foreach (string statement in new string[] {"use(move a);", "return move a;", "owned void* b = create(move a);"}) {
		add ("/move/invalid-boundary-contract/" + statement, () => semantic_invalid ("void* f() { owned void* a = create(1); " + statement + " return null; }", "move requires"));
	}
	string[] sources = {
		"void* raw = raw(); owned void* b = move raw;", "int x = 1; owned void* b = move x;", "owned void* b = move p;", "owned void* b = move missing;", "Pair pair = { x = 1 }; Pair* q = &pair; owned void* b = move q;"
	};
	for (int i = 0; i < sources.length; i++) {
		string text = "struct Pair { int x; } void f(void* p) { " + sources[i] + " }";
		add ("/move/invalid-source/%d".printf (i), () => semantic_invalid (text, "must be an owned void* local"));
	}
	add ("/move/rearm-moved-source", () => SsaBuilder.build (cfg ("void f() { owned void* a = create(1); owned void* b = move a; a = create(2); }")));
	string[] escapes = {
		"void* p = a;", "use(a);", "return a;", "owned void* c = a;", "a = null;"
	};
	for (int i = 0; i < escapes.length; i++) {
		string text = "void* f() { owned void* a = create(1); owned void* b = move a; " + escapes[i] + " return null; }";
		add ("/move/escape-after-move/%d".printf (i), () => semantic_invalid (text, "owned local 'a' cannot"));
	}
	add ("/move/destination-type", () => semantic_invalid ("void f() { owned void* a = create(1); owned int b = move a; }", "only on local 'void*'"));
	add ("/move/destination-escape", () => semantic_invalid ("void f() { owned void* a = create(1); owned void* b = move a; use(b); }", "owned local 'b' cannot"));
	add ("/move/double-move", () => flow_invalid ("owned void* b = move a; owned void* c = move a;", false, "move a"));
	add ("/move/use-after-move/equal", () => flow_invalid ("owned void* b = move a; if (a == null) { return; }", false, "a"));
	add ("/move/use-after-move/not-equal", () => flow_invalid ("owned void* b = move a; if (null != a) { return; }", false, "a"));
	add ("/move/maybe/move", () => flow_invalid ("if (condition) { owned void* b = move a; } owned void* c = move a;", true, "move a"));
	add ("/move/maybe/read", () => flow_invalid ("if (condition) { owned void* b = move a; } if (a == null) { return; }", true, "a"));
	add ("/move/both-arms/read", () => flow_invalid ("if (condition) { owned void* b = move a; } else { owned void* c = move a; } if (a == null) { return; }", false, "a"));
	add ("/move/backedge/fallthrough", () => flow_invalid ("while (condition) { owned void* b = move a; }", true, "move a"));
	add ("/move/backedge/continue", () => flow_invalid ("while (condition) { owned void* b = move a; continue; }", true, "move a"));
	add ("/move/backedge/conditional-continue", () => flow_invalid ("while (condition) { if (condition) { owned void* b = move a; continue; } }", true, "move a"));
	add ("/move/backedge/header-read", () => flow_invalid ("while (a != null) { owned void* b = move a; continue; }", true, "a"));
	// Short-circuit expansion reserves later CFG blocks for the read.
	// Stable block order diagnoses the body move first; both require OWNED.
	add ("/move/backedge/short-circuit-read", () => flow_invalid ("while (a != null && condition) { owned void* b = move a; continue; }", true, "move a"));
	add ("/move/break/maybe-read", () => flow_invalid ("while (condition) { owned void* b = move a; break; } if (a == null) { return; }", true, "a"));
	add ("/move/null-is-still-moved", () => flow_invalid ("if (a == null) { owned void* b = move a; if (a == null) { return; } }", false, "a"));
}

}
