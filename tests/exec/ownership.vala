// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests.Exec {
private void own_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/own/fixtures/owned-resource.vapi"));
	FileUtils.set_contents (workspace.vapi1, "");
	FileUtils.set_contents (workspace.vapi2, "");
	var compiled = workspace.compile_vapi (read ("tests/own/fixtures/own-" + name + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	workspace.clean_temporaries ();
	var run = new Run ({workspace.executable});
	run.silent ();
	if (name == "trap" || name == "null-trap") {
		// The destroyer exits 91 if invoked. A signal proves the earlier
		// abnormal operation was not changed into cleanup followed by trap.
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
	} else {
		run.exits (0);
	}
}
private void own_distinct_contracts() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/own/fixtures/owned-resource.vapi") + "[CCode(cname = \"astra_test_resource_create_other\", destroy_function = \"astra_test_resource_destroy_other\")] void* second(int id);");
	FileUtils.set_contents (workspace.vapi1, "");
	FileUtils.set_contents (workspace.vapi2, "");
	string source = "void scoped() { owned void* a = create_resource(1); owned void* b = second(2); } int main() { resource_reset(); scoped(); if (resource_effect_order() != 821 || resource_destroy_order() != 21 || resource_destroy_count() != 2 || resource_live_count() != 0 || resource_error_count() != 0) { return 1; } return 0; }";
	workspace.compile_vapi (source).exits (0);
	new Run ({workspace.executable}).exits (0);
	workspace.clean_temporaries ();
}
private void move_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/own/fixtures/owned-resource.vapi"));
	FileUtils.set_contents (workspace.vapi1, read ("tests/move/fixtures/move-resource.vapi"));
	FileUtils.set_contents (workspace.vapi2, "");
	var compiled = workspace.compile_vapi (read ("tests/move/fixtures/move-" + name + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	workspace.clean_temporaries ();
	var run = new Run ({workspace.executable});
	run.silent ();
	if (name == "trap") {
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
	} else {
		run.exits (0);
	}
}
private void oborrow_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/own/fixtures/owned-resource.vapi"));
	FileUtils.set_contents (workspace.vapi1, read ("tests/oborrow/fixtures/borrowed-resource.vapi"));
	FileUtils.set_contents (workspace.vapi2, "");
	var compiled = workspace.compile_vapi (read ("tests/oborrow/fixtures/oborrow-" + name + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	var run = new Run ({workspace.executable});
	run.exits (0);
	run.silent ();
	workspace.clean_temporaries ();
}
private void release_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/own/fixtures/owned-resource.vapi"));
	FileUtils.set_contents (workspace.vapi1, read ("tests/oborrow/fixtures/borrowed-resource.vapi") + read ("tests/move/fixtures/move-resource.vapi"));
	FileUtils.set_contents (workspace.vapi2, "");
	var compiled = workspace.compile_vapi (read ("tests/release/fixtures/release-" + name + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	var run = new Run ({workspace.executable});
	run.silent ();
	if (name == "trap") {
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
	} else {
		run.exits (0);
	}
	workspace.clean_temporaries ();
}
private void rearm_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/own/fixtures/owned-resource.vapi"));
	FileUtils.set_contents (workspace.vapi1, read ("tests/oborrow/fixtures/borrowed-resource.vapi") + read ("tests/rearm/fixtures/rearm-resource.vapi"));
	FileUtils.set_contents (workspace.vapi2, "");
	var compiled = workspace.compile_vapi (read ("tests/rearm/fixtures/rearm-" + name + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	var run = new Run ({workspace.executable});
	run.silent ();
	if (name == "trap") {
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
	} else {
		run.exits (0);
	}
	workspace.clean_temporaries ();
}
private void resource_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/resource/fixtures/resource-api.vapi"));
	FileUtils.set_contents (workspace.vapi1, read ("tests/resource/fixtures/resource-types.vapi"));
	FileUtils.set_contents (workspace.vapi2, name == "two-types" ? read ("tests/resource/fixtures/resource-two-types.vapi") : "");
	var compiled = workspace.compile_vapi (read ("tests/resource/fixtures/resource-" + name + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	var run = new Run ({workspace.executable});
	run.exits (0);
	run.silent ();
	workspace.clean_temporaries ();
}
private void ownbound_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, read ("tests/resource/fixtures/resource-api.vapi"));
	FileUtils.set_contents (workspace.vapi1, read ("tests/resource/fixtures/resource-types.vapi"));
	FileUtils.set_contents (workspace.vapi2, read ("tests/ownbound/fixtures/ownbound-extra.vapi"));
	var compiled = workspace.compile_vapi (read ("tests/ownbound/fixtures/ownbound-" + name + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	var run = new Run ({workspace.executable});
	if (name == "trap") {
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
	} else {
		run.exits (0);
	}
	run.silent ();
	workspace.clean_temporaries ();
}
private void register_ownership() {
	foreach (string name in new string[] {"consume", "pass", "null", "release", "move", "borrow", "rearm", "multi", "root-order", "nested", "order", "recurse", "mutual", "result", "terminating", "branches", "loop", "shortcircuit", "borrow-move", "trap"}) {
		add ("/exec/ownbound/" + name, () => ownbound_execute (name));
	}
	foreach (string name in new string[] {"basic", "unmanaged", "borrow", "move", "move-null", "release", "rearm", "mixed", "order", "null", "phi", "loop", "two-types", "extern"}) {
		add ("/exec/resource/" + name, () => resource_execute (name));
	}
	foreach (string name in new string[] {"release", "move", "mixed", "conditional", "both-arms", "both-moved", "both-released", "null", "null-release", "multiple", "move-cycles", "borrow", "order", "branch-order", "effects", "terminating", "terminating-disarmed", "unreachable", "loop", "continue", "move-loop", "move-continue", "mixed-loop", "break", "trap"}) {
		add ("/exec/rearm/" + name, () => rearm_execute (name));
	}
	foreach (string name in new string[] {"basic", "null", "move", "borrow", "loop", "move-loop", "break", "continue", "order", "lifo", "others", "multiple", "contracts", "shortcircuit", "branch", "memory", "unreachable", "conditional", "both-arms", "terminating-arm", "loop-break", "loop-return", "null-conditional", "return", "three-way", "trap"}) {
		add ("/exec/release/" + name, () => release_execute (name));
	}
	foreach (string name in new string[] {"basic", "repeated", "native", "forward", "move", "destination", "null", "loop", "body-loop", "continue", "break", "return", "order", "raw-null", "extern", "control", "conditional", "shortcircuit"}) {
		add ("/exec/oborrow/" + name, () => oborrow_execute (name));
	}
	foreach (string name in new string[] {"basic", "chain", "chain-lifo", "null", "conditional", "both-arms", "return", "break", "continue", "loop", "lifo", "contracts", "terminating-arm", "loop-break", "loop-return", "conditional-break", "mixed", "unreachable", "trap"}) {
		add ("/exec/move/" + name, () => move_execute (name));
	}
	add ("/exec/own/distinct-contracts", own_distinct_contracts);
	foreach (string name in new string[] {"basic", "null", "lifo", "nested", "return", "early-return", "branch", "branch-both", "loop", "continue", "break", "loop-return", "shortcircuit", "mixed", "unreachable", "nested-loop", "fallthrough", "trap", "null-trap"}) {
		add ("/exec/own/" + name, () => own_execute (name));
	}
}
}
