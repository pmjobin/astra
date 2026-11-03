// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Cfg;
using Astra.Ssa;
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.Rearm {
private const string OWNED = "owned value 'a' still owns a resource; release or move it before reassignment";
private const string MAY_OWN = "owned value 'a' may still own a resource on another control-flow path";
private void flow_invalid(string body, string message, string operand = "a = create(2);") throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* a = create(1); " + body + " }");
	var result = CfgFlowChecker.check (control);
	if (result.diagnostic == null || result.diagnostic.message != message) {
		GLib.error ("expected %s, got %s", message, result.diagnostic == null ? "success" : result.diagnostic.format ());
	}
	assert (result.diagnostic.span.text () == operand);
	try {
		SsaBuilder.build (control);
		assert_not_reached ();
	} catch (SsaError.INVALID_CFG error) {
		assert (error.message.contains (message));
	}
}

private void register_diagnostics() {
	foreach (string rhs in new string[] {"raw()", "null", "a", "effect()", "a == null", "native()", "raw() == null", "(raw())"}) {
		add ("/rearm/invalid-rhs/" + rhs, () => {
				var result = analyze ("void* native() { return null; } void f() { owned void* a = create(1); release a; a = " + rhs + "; }");
				assert (result.program == null && result.diagnostic.message.contains ("rearming requires a direct foreign owned-result call"));
			});
	}
	add ("/rearm/move-assignment-remains-invalid", () => {
			var checked = analyze ("void f() { owned void* a = create(1); owned void* b = create(2); release a; a = move b; }");
			assert (checked.program == null && checked.diagnostic.message.contains ("rearming requires a direct foreign owned-result call"));
		});
	add ("/rearm/copy-remains-invalid", () => {
			var result = analyze ("void f() { owned void* a = create(1); owned void* b = create(2); release a; a = b; }");
			assert (result.program == null && result.diagnostic.message.contains ("rearming requires a direct foreign owned-result call"));
		});
	add ("/rearm/grouped-direct-call", () => SsaBuilder.build (cfg ("void f() { owned void* a = create(1); release a; a = ((variant(2))); inspect(a); }")));
	add ("/rearm/contract-mismatch", () => {
			var result = analyze ("void f() { owned void* a = create(1); release a; a = second(2); }");
			assert (result.program == null && result.diagnostic.message == "owned value 'a' cannot be rearmed with a different cleanup contract (expected 'resource_destroy_impl', producer uses 'other_destroy')");
		});
	add ("/rearm/owned", () => flow_invalid ("a = create(2);", OWNED));
	add ("/rearm/borrow-keeps-owned", () => flow_invalid ("inspect(a); a = create(2);", OWNED));
	add ("/rearm/owned-released", () => flow_invalid ("if (c) { release a; } a = create(2);", MAY_OWN));
	add ("/rearm/owned-moved", () => flow_invalid ("if (c) { owned void* b = move a; } a = create(2);", MAY_OWN));
	add ("/rearm/three-way", () => flow_invalid ("if (c) { release a; } else { if (c) { owned void* b = move a; } } a = create(2);", MAY_OWN));
	add ("/rearm/null-still-owned", () => flow_invalid ("release a; a = create(0); a = create(2);", OWNED));
	foreach (string tail in new string[] {"", "continue;", "if (c) { release a; }", "if (c) { owned void* b = move a; continue; }", "if (c) { release a; } else { if (c) { owned void* b = move a; } }"}) {
		add ("/rearm/unsafe-backedge/" + (tail == "" ? "no-discharge" : tail), () => flow_invalid ("release a; while (c) { a = create(2); " + tail + " }", MAY_OWN));
	}
	add ("/rearm/use-before", () => flow_invalid ("release a; inspect(a); a = create(2);", "cannot borrow released owned value 'a'", "a"));
	add ("/rearm/producer-argument-before-transition", () => flow_invalid ("release a; a = create(inspect(a));", "cannot borrow released owned value 'a'", "a"));
	foreach (string use in new string[] {"inspect(a);", "if (a == null) { return; }", "release a;", "owned void* b = move a;"}) {
		add ("/rearm/conditional-use/" + use, () => {
				var result = CfgFlowChecker.check (cfg ("void f(bool c) { owned void* a = create(1); release a; if (c) { a = create(2); } " + use + " }"));
				assert (result.diagnostic != null && result.diagnostic.message.contains ("may no longer own its resource"));
			});
	}
}

}
