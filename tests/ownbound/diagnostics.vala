// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Cfg;

namespace Astra.Tests.Ownbound {
private void reject(string source, string expected) throws GLib.Error {
	var checked = analyze (source);
	var diagnostic = checked.diagnostic;
	if (diagnostic == null) {
		diagnostic = CfgFlowChecker.check (cfg (source)).diagnostic;
	}
	if (diagnostic == null || !diagnostic.message.contains (expected)) {
		GLib.error ("expected '%s', got '%s' for %s", expected, diagnostic == null ? "accepted" : diagnostic.message, source);
	}
}
private void register_diagnostics() {
	foreach (string type in new string[] {"void*", "int", "bool", "Pair", "Pair*"}) {
		add ("/ownbound/reject/parameter-type/" + type, () => reject ("struct Pair { int n; } void f(owned " + type + " r) { }", "nominal handle type"));
		add ("/ownbound/reject/result-type/" + type, () => reject ("struct Pair { int n; } owned " + type + " f() { return null; }", "nominal handle type"));
	}
	foreach (string argument in new string[] {"r", "raw()", "create(1)"}) {
		add ("/ownbound/reject/implicit/" + argument, () => reject ("void consume(owned Resource p) { } void f() { owned Resource r = create(1); consume(" + argument + "); }", "explicit 'move owner'"));
	}
	foreach (string qualifier in new string[] {"", "borrowed "}) {
		add ("/ownbound/reject/unowned-argument/" + (qualifier == "" ? "raw" : "borrowed"), () => reject ("void consume(owned Resource p) { } void f(" + qualifier + "Resource r) { consume(r); }", "carry no transferable responsibility"));
		add ("/ownbound/reject/unowned-move/" + (qualifier == "" ? "raw" : "borrowed"), () => reject ("void consume(owned Resource p) { } void f(" + qualifier + "Resource r) { consume(move r); }", "must be an owned"));
	}
	add ("/ownbound/reject/cross-handle-argument", () => reject ("void consume(owned Other p) { } void f(owned Resource r) { consume(move r); }", "exact type 'Other'"));
	add ("/ownbound/reject/cross-handle-return", () => reject ("owned Other f(owned Resource r) { return move r; }", "exact type 'Other'"));
	add ("/ownbound/reject/later-borrow", () => reject ("void consume(owned Resource p, int n) { } void f(owned Resource r) { consume(move r, inspect(r)); }", "cannot borrow moved owned value 'r'"));
	add ("/ownbound/reject/overlapping-borrow-transfer", () => reject ("void consume(borrowed Resource view, owned Resource owner) { release owner; inspect(view); } void f(owned Resource r) { consume(r, move r); }", "cannot borrow moved owned value 'r'"));
	add ("/ownbound/reject/pending-borrow-nested-transfer", () => reject ("int consume(owned Resource r) { return 0; } void inspect_two(borrowed Resource r, int n) { inspect(r); } void f(owned Resource r) { inspect_two(r, consume(move r)); }", "cannot borrow moved owned value 'r'"));
	add ("/ownbound/reject/later-null-test", () => reject ("void consume(owned Resource p, bool c) { } void f(owned Resource r) { consume(move r, r == null); }", "use of moved owned value 'r'"));
	add ("/ownbound/reject/later-shortcircuit", () => reject ("void consume(owned Resource p, bool c) { } void f(owned Resource r, bool c) { consume(move r, c && inspect(r) == 1); }", "cannot borrow moved owned value 'r'"));
	add ("/ownbound/reject/double-argument", () => reject ("void consume(owned Resource a, owned Resource b) { } void f(owned Resource r) { consume(move r, move r); }", "use of moved owned value 'r'"));
	foreach (string use in new string[] {"inspect(r);", "release r;", "owned Resource q = move r;"}) {
		add ("/ownbound/reject/after-call/" + use, () => reject ("void consume(owned Resource p) { } void f(owned Resource r) { consume(move r); " + use + " }", "moved owned value 'r'"));
	}
	foreach (string value in new string[] {"r", "raw()", "create(1)", "make()"}) {
		add ("/ownbound/reject/owned-return/" + value, () => reject ("owned Resource make() { return null; } owned Resource f(owned Resource r) { return " + value + "; }", "requires 'return move owner'"));
	}
	foreach (string body in new string[] {"make();", "Resource raw = make();", "inspect(make());", "consume(make());"}) {
		add ("/ownbound/reject/producer/" + body, () => reject ("owned Resource make() { return null; } void consume(owned Resource r) { } void f() { " + body + " }", body.has_prefix ("consume") ? "explicit 'move owner'" : "ownership responsibility"));
	}
	add ("/ownbound/reject/released-return", () => reject ("owned Resource f(owned Resource r) { release r; return move r; }", "use of released owned value 'r'"));
	add ("/ownbound/reject/moved-return", () => reject ("owned Resource f(owned Resource r) { owned Resource q = move r; return move r; }", "use of moved owned value 'r'"));
	add ("/ownbound/reject/maybe-return", () => reject ("owned Resource f(owned Resource r, bool c) { if (c) { release r; } return move r; }", "may no longer own"));
	add ("/ownbound/reject/loop-transfer", () => reject ("void consume(owned Resource p) { } void f(owned Resource r, bool c) { while (c) { consume(move r); } }", "may have been moved"));
	add ("/ownbound/reject/loop-release", () => reject ("void f(owned Resource r, bool c) { while (c) { release r; } }", "may no longer own"));
	add ("/ownbound/replace/live-parameter", () => build ("owned Resource make() { return null; } void f(owned Resource r) { r = make(); }"));
	add ("/ownbound/reject/wrong-result-rearm", () => reject ("owned Other make() { return null; } void f(owned Resource r) { release r; r = make(); }", "expected rearm value of type 'Resource', found 'Other'"));
	add ("/ownbound/reject/missing-return", () => reject ("owned Resource f(owned Resource r, bool c) { if (c) { return move r; } }", "not all paths"));
	add ("/ownbound/reject/empty-return", () => reject ("owned Resource f() { return; }", "return requires a value"));
	add ("/ownbound/reject/export-parameter", () => reject ("export(C) void f(owned Resource r) { }", "C ownership boundaries"));
	add ("/ownbound/reject/export-result", () => reject ("export(C) owned Resource f() { return null; }", "export(C) of resource"));
	add ("/ownbound/reject/extern-parameter", () => reject ("extern(C) void f(owned Resource r);", "C ownership boundaries"));
	add ("/ownbound/reject/duplicate-qualifier", () => reject ("void f(owned borrowed Resource r) { }", "only one ownership qualifier"));
	add ("/ownbound/reject/no-overloads", () => reject ("void f(Resource r) { } void f(owned Resource r) { }", "overloading is not implemented"));
}
}
