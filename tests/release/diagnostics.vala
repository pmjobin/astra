// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Release {
private const string RELEASED = "use of released owned value 'a'";
private const string DOUBLE = "owned value 'a' has already been released";
private const string MIXED = "owned value 'a' may no longer own its resource on another control-flow path";
private void flow_invalid(string statements, string message, string operand, int id = 1) throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* a = create(%d); ".printf (id) + statements + " }");
	var result = CfgFlowChecker.check (control);
	assert (result.diagnostic != null && result.diagnostic.message == message);
	assert (result.diagnostic.span.text () == operand);
	try {
		SsaBuilder.build (control);
		assert_not_reached ();
	} catch (SsaError.INVALID_CFG error) {
		assert (error.message.contains (message));
	}
}
private void register_diagnostics() {
	string[] syntax = {
		"release(a);", "release create(1);", "release a == null;", "release a.field;", "release a->field;", "release;", "release a", "a = release a;", "return release a;", "use(release a);", "owned void* b = release a;", "int x = release a;", "if (release a) { return; }"
	};
	for (int i = 0; i < syntax.length; i++) {
		string statement = syntax[i];
		add ("/release/invalid-syntax/%d".printf (i), () => {
				var parsed = Parser.parse (new SourceFile.from_text ("release.astra", "void f() { owned void* a = create(1); " + statement + " }"));
				assert (parsed.unit == null && parsed.diagnostic != null && parsed.diagnostic.message.contains ("release"));
			});
	}
	string[] sources = {
		"void* x = raw(); release x;", "int x = 1; release x;", "bool x = true; release x;", "release p;", "release b;", "release missing;", "Pair pair = { x = 1 }; Pair* x = &pair; release x;", "Pair x = { x = 1 }; release x;", "release create;", "if (true) { owned void* x = create(1); } release x;"
	};
	for (int i = 0; i < sources.length; i++) {
		string source = "struct Pair { int x; } void f(void* p, borrowed void* b) { " + sources[i] + " }";
		add ("/release/invalid-operand/%d".printf (i), () => {
				var result = analyze (source);
				assert (result.program == null && result.diagnostic != null && result.diagnostic.message.contains ("must be an owned void* local"));
			});
	}
	add ("/release/rearm-after-release", () => SsaBuilder.build (cfg ("void f() { owned void* a = create(1); release a; a = create(2); }")));
	string[] escapes = {
		"a = null;", "void* p = a;", "use(a);", "return a;", "owned void* b = a;"
	};
	for (int i = 0; i < escapes.length; i++) {
		string source = "void* f() { owned void* a = create(1); release a; " + escapes[i] + " return null; }";
		add ("/release/invalid-escape-rearm/%d".printf (i), () => {
				var result = analyze (source);
				assert (result.program == null && result.diagnostic.message.contains ("owned local 'a' cannot"));
			});
	}
	add ("/release/double", () => flow_invalid ("release a; release a;", DOUBLE, "release a;"));
	add ("/release/moved-source", () => flow_invalid ("owned void* b = move a; release a;", "cannot release moved owned value 'a'", "release a;"));
	add ("/release/then-move", () => flow_invalid ("release a; owned void* b = move a;", RELEASED, "move a"));
	add ("/release/then-borrow", () => flow_invalid ("release a; inspect(a);", "cannot borrow released owned value 'a'", "a"));
	add ("/release/then-equal", () => flow_invalid ("release a; if (a == null) { return; }", RELEASED, "a"));
	add ("/release/then-not-equal", () => flow_invalid ("release a; if (null != a) { return; }", RELEASED, "a"));
	add ("/release/actual-null-still-released", () => flow_invalid ("if (a != null) { return; } release a; if (a == null) { return; }", RELEASED, "a", 0));
	add ("/release/actual-null-conditional-state", () => flow_invalid ("if (c) { release a; } inspect(a);", MIXED + " and cannot be borrowed", "a", 0));
	add ("/release/conditional-borrow", () => flow_invalid ("if (c) { release a; } inspect(a);", MIXED + " and cannot be borrowed", "a"));
	add ("/release/conditional-move", () => flow_invalid ("if (c) { release a; } owned void* b = move a;", MIXED, "move a"));
	add ("/release/conditional-release", () => flow_invalid ("if (c) { release a; } release a;", MIXED + " and cannot be released", "release a;"));
	add ("/release/conditional-moved-source", () => flow_invalid ("if (c) { owned void* b = move a; } release a;", "owned value 'a' may have been moved on another control-flow path and cannot be released", "release a;"));
	add ("/release/both-arms", () => flow_invalid ("if (c) { release a; } else { release a; } release a;", DOUBLE, "release a;"));
	add ("/release/all-disarmed", () => flow_invalid ("if (c) { release a; } else { owned void* b = move a; } release a;", "owned value 'a' no longer owns a resource on every reachable path and cannot be released", "release a;"));
	add ("/release/three-way", () => flow_invalid ("if (c) { release a; } else { if (c) { owned void* b = move a; } } release a;", MIXED + " and cannot be released", "release a;"));
	foreach (string body in new string[] {"release a;", "release a; continue;", "if (c) { release a; continue; }"}) {
		add ("/release/backedge/" + body, () => flow_invalid ("while (c) { " + body + " }", MIXED + " and cannot be released", "release a;"));
	}
	add ("/release/backedge/header", () => flow_invalid ("while (a != null) { release a; }", MIXED, "a"));
	add ("/release/break-join", () => flow_invalid ("while (c) { release a; break; } inspect(a);", MIXED + " and cannot be borrowed", "a"));
	add ("/release/constant-condition-policy", () => flow_invalid ("if (true) { release a; } release a;", MIXED + " and cannot be released", "release a;"));
}
}
