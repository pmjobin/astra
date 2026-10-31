// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Cfg;

namespace Astra.Tests.Resource {
private void reject(string source, string expected, string declarations = TYPES + API) throws GLib.Error {
	var result = analyze (source, declarations);
	string? message = result.diagnostic == null ? null : result.diagnostic.message;
	if (message == null) {
		var flow = CfgFlowChecker.check (cfg (source, declarations));
		message = flow.diagnostic == null ? null : flow.diagnostic.message;
	}
	if (message == null || !message.contains (expected)) {
		GLib.error ("Expected rejection containing '%s'; got '%s' for %s", expected, message ?? "accepted", source);
	}
}
private void register_diagnostics() {
	string[] nominal = {
		"void f() { Resource r = raw_other(); }",
		"void f() { Resource r = raw(); Other q = r; }",
		"void f() { Other q = raw_other(); inspect(q); }",
		"bool f(Resource r, Other q) { return r == q; }",
		"void f() { owned Resource r = other(); }",
		"void f() { owned Other r = other(); owned Resource q = move r; }",
		"void f() { owned Resource r = create(1); release r; r = other(); }",
		"int f(borrowed Resource r) { return other_inspect(r); }",
		"void f() { owned Resource r = create(1); other_inspect(r); }"
	};
	for (int i = 0; i < nominal.length; i++) {
		string source = nominal[i];
		add ("/resource/reject/nominal/" + i.to_string (), () => reject (source, "Other"));
	}
	string[] erased = {
		"void f() { Resource r = raw_pointer(); }", "void f() { void* p = raw(); }",
		"int f() { Resource r = raw(); return pointer(r); }", "int f(void* p) { return inspect(p); }",
		"bool f(Resource r, void* p) { return r == p; }", "void f() { Resource r = raw(); r = raw_pointer(); }"
	};
	for (int i = 0; i < erased.length; i++) {
		string source = erased[i];
		add ("/resource/reject/void-pointer/" + i.to_string (), () => reject (source, "void*"));
	}
	string[] noescape = {
		"void f(borrowed Resource r) { Resource q = r; }", "void f(borrowed Resource r) { Resource q = null; q = r; }",
		"Resource f(borrowed Resource r) { return r; }", "int f(borrowed Resource r) { return unmanaged(r); }"
	};
	for (int i = 0; i < noescape.length; i++) {
		string source = noescape[i];
		add ("/resource/reject/noescape/" + i.to_string (), () => reject (source, "cannot be stored, returned, or forwarded"));
	}
	string[] leaks = {
		"void f() { create(1); }", "void f() { Resource r = create(1); }", "Resource f() { return create(1); }", "void f() { inspect(create(1)); }"
	};
	for (int i = 0; i < leaks.length; i++) {
		string source = leaks[i];
		add ("/resource/reject/owned-result/" + i.to_string (), () => reject (source, "ownership responsibility"));
	}
	add ("/resource/reject/owner-decay", () => reject ("void f() { owned Resource r = create(1); unmanaged(r); }", "cannot be copied"));
	add ("/resource/reject/owner-copy", () => reject ("void f() { owned Resource r = create(1); Resource q = r; }", "cannot be copied"));
	foreach (string discharge in new string[] {"release r;", "owned Resource q = move r;", "if (c) { release r; }", "if (c) { owned Resource q = move r; }"}) {
		string source = "void f(bool c) { owned Resource r = create(1); " + discharge + " inspect(r); }";
		add ("/resource/reject/disarmed-borrow/" + (discharge.has_prefix ("if") ? "mixed-" : "") + (discharge.contains ("release") ? "released" : "moved"), () => reject (source, "owned value 'r'"));
	}
	foreach (string operation in new string[] {"+", "-", "*", "/", "%", "<", "<=", ">", ">="}) {
		add ("/resource/reject/operator/" + operation.replace ("/", "divide"), () => reject ("void f() { Resource r = raw(); bool b = r " + operation + " r; }", "requires an 'int' operand"));
	}
	add ("/resource/reject/truthiness", () => reject ("void f() { Resource r = raw(); if (r) { } }", "condition must have type 'bool'"));
	add ("/resource/reject/arrow", () => reject ("void f(Resource r) { int n = r->field; }", "native struct pointer local or parameter"));
	add ("/resource/reject/dereference", () => reject ("void f() { Resource r = raw(); int n = *r; }", "dereference requires a typed pointer"));
	add ("/resource/reject/address", () => reject ("void f() { Resource r = raw(); void* p = &r; }", "direct local integer, f32, numeric vector, or native struct variable"));
	add ("/resource/reject/pointer", () => reject ("void f(Resource* r) { }", "pointee"));
	add ("/resource/reject/array", () => reject ("void f(Resource[2] r) { }", "unsupported array element type"));
	add ("/resource/reject/slice", () => reject ("void f(Resource[] r) { }", "unsupported slice element type"));
	add ("/resource/reject/field", () => reject ("struct Holder { Resource r; }", "resource-valued struct fields"));
	add ("/resource/reject/export-parameter", () => reject ("export(C) int f(Resource r) { return 0; }", "export(C) of resource"));
	add ("/resource/reject/export-result", () => reject ("export(C) Resource f() { return null; }", "export(C) of resource"));
	add ("/resource/native-owned-result", () => assert (analyze ("owned Resource f() { return null; }").diagnostic == null));
	add ("/resource/native-owned-parameter", () => assert (analyze ("void f(owned Resource r) { }").diagnostic == null));
	add ("/resource/reject/borrowed-local", () => reject ("void f() { borrowed Resource r = raw(); }", "borrowed"));
	add ("/resource/reject/source-handle", () => reject ("handle Resource;", "expected '('"));
	add ("/resource/reject/struct-collision", () => reject ("struct Resource { int id; }", "conflicts with imported handle"));
	add ("/resource/reject/duplicate-handle", () => reject ("", "conflicts with an existing type", TYPES + TYPES));
	foreach (string name in new string[] {"int", "bool", "void"}) {
		add ("/resource/reject/builtin/" + name, () => reject ("", "conflicts with an existing type", "[CCode(destroy_function = \"destroy\")] handle " + name + ";"));
	}
	foreach (string type in new string[] {"int", "void", "void*", "bool"}) {
		add ("/resource/reject/owned-result-type/" + type, () => reject ("", "requires a nominal handle type", "owned " + type + " f();"));
	}
	add ("/resource/reject/function-destroy", () => reject ("", "destroy_function", TYPES + "[CCode(destroy_function = \"destroy\")] owned Resource f();"));
	add ("/resource/replace/live-local", () => { var flow = CfgFlowChecker.check (cfg ("void f() { owned Resource r = create(1); r = again(2); }"));
		                                         assert (flow.diagnostic == null);
	});
	add ("/resource/replace/mixed-live-local", () => { var flow = CfgFlowChecker.check (cfg ("void f(bool c) { owned Resource r = create(1); if (c) { release r; } r = again(2); }"));
		                                               assert (flow.diagnostic == null);
	});
}
}
