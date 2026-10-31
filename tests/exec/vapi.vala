// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests.Exec {
private class VapiWorkspace : ForeignWorkspace {
	internal string vapi0;
	internal string vapi1;
	internal string vapi2;

	internal VapiWorkspace (bool roundtrip = false) throws FileError {
		base ();
		vapi0 = Path.build_filename (directory, "declarations ; $(false) ' data");
		vapi1 = Path.build_filename (directory, "state declarations.vapi");
		vapi2 = Path.build_filename (directory, "roundtrip.vapi");
		FileUtils.set_contents (vapi0, read ("tests/vapi/fixtures/basic.vapi"));
		FileUtils.set_contents (vapi1, read ("tests/vapi/fixtures/state.vapi"));
		FileUtils.set_contents (vapi2, roundtrip ? read ("tests/vapi/fixtures/roundtrip.vapi") : "");
		if (roundtrip) {
			assert (FileUtils.unlink (object0) == 0);
			assert (FileUtils.symlink (Environment.get_variable ("ASTRA_TEST_CEXPORT_OBJECT_4"), object0) == 0);
		}
	}

	internal Run compile_vapi(string text) throws GLib.Error {
		return compile (text, {"--vapi", vapi0, source, "--vapi", vapi1, "--vapi", vapi2, "--link-object", object0, "-o", executable});
	}

	~VapiWorkspace () {
		FileUtils.unlink (vapi0);
		FileUtils.unlink (vapi1);
		FileUtils.unlink (vapi2);
	}
}

private void vapi_execute(string fixture, bool roundtrip = false) throws GLib.Error {
	var workspace = new VapiWorkspace (roundtrip);
	// The same C object serves the accepted source-extern and VAPI variants.
	// Each fixture checks its result and observable state before returning 0.
	string original = read ("tests/cabi/fixtures/" + (roundtrip ? "cexport-" : "c-") + fixture + ".astra");
	var source_compiled = workspace.compile_c (original);
	source_compiled.exits (0);
	source_compiled.silent ();
	var source_run = new Run ({workspace.executable});
	source_run.exits (0);
	source_run.silent ();
	var vapi_compiled = workspace.compile_vapi (read ("tests/vapi/fixtures/vapi-" + fixture + ".astra"));
	vapi_compiled.exits (0);
	vapi_compiled.silent ();
	var vapi_run = new Run ({workspace.executable});
	vapi_run.exits (0);
	vapi_run.silent ();
	workspace.clean_temporaries ();
}

private void vapi_modes_and_order() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	string text = read ("tests/vapi/fixtures/vapi-order.astra");
	foreach (string mode in new string[] {"--check", "--dump-semantics", "--dump-core", "--dump-cfg", "--dump-ssa", "--dump-nabi", "--dump-cabi", "--dump-llvm"}) {
		var first = workspace.compile (text, {"--vapi", workspace.vapi0, mode, workspace.source, "--vapi", workspace.vapi1});
		var second = workspace.compile (text, {mode, workspace.source, "--vapi", workspace.vapi0, "--vapi", workspace.vapi1});
		var third = workspace.compile (text, {workspace.source, "--vapi", workspace.vapi0, "--vapi", workspace.vapi1, mode});
		first.exits (0);
		second.exits (0);
		third.exits (0);
		assert (first.errors == "" && second.errors == "" && third.errors == "");
		assert (first.output == second.output && first.output == third.output);
		if (mode == "--check") {
			first.silent ();
		} else {
			assert (first.output != "");
		}
	}
	// No extension check, and relative paths with shell punctuation are read directly.
	var compiled = workspace.compile (text, {workspace.source, "--vapi", Path.get_basename (workspace.vapi0), "--vapi", Path.get_basename (workspace.vapi1), "--link-object", workspace.object0, "-o", workspace.executable});
	compiled.exits (0);
	compiled.silent ();
	new Run ({workspace.executable}).exits (0);
	workspace.clean_temporaries ();
}

private void vapi_multiple_objects() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi1, read ("tests/vapi/fixtures/state.vapi") + read ("tests/vapi/fixtures/second.vapi"));
	string text = "int main() { astra_test_reset(); astra_test_record(1); if (astra_test_second(astra_test_add(20, 21)) != 42 || astra_test_state() != 1) { return 1; } return 0; }";
	for (int order = 0; order < 2; order++) {
		var compiled = workspace.compile (text, {"--vapi", order == 0 ? workspace.vapi0 : workspace.vapi1, "--link-object", workspace.object0, workspace.source, "--vapi", order == 0 ? workspace.vapi1 : workspace.vapi0, "--link-object", workspace.object1, "-o", workspace.executable});
		compiled.exits (0);
		compiled.silent ();
		new Run ({workspace.executable}).exits (0);
	}
	// A source extern and export coexist with VAPI imports and both objects.
	FileUtils.set_contents (workspace.vapi1, read ("tests/vapi/fixtures/state.vapi"));
	var mixed = workspace.compile (read ("tests/vapi/fixtures/vapi-mixed.astra"), {workspace.source, "--vapi", workspace.vapi0, "--vapi", workspace.vapi1, "--link-object", workspace.object0, "--link-object", workspace.object1, "-o", workspace.executable});
	mixed.exits (0);
	mixed.silent ();
	new Run ({workspace.executable}).exits (0);
	workspace.clean_temporaries ();
}

private void vapi_link_boundary() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	for (int missing = 0; missing < 2; missing++) {
		string text = read ("tests/vapi/fixtures/" + (missing == 0 ? "vapi-basic" : "vapi-missing-symbol") + ".astra");
		FileUtils.set_contents (workspace.vapi0, read ("tests/vapi/fixtures/" + (missing == 0 ? "basic" : "missing-symbol") + ".vapi"));
		foreach (string mode in new string[] {"--check", "--dump-cabi", "--dump-llvm"}) {
			var checked = workspace.compile (text, {mode, workspace.source, "--vapi", workspace.vapi0});
			checked.exits (0);
			assert (checked.errors == "");
		}
		for (int preserve = 0; preserve < 2; preserve++) {
			FileUtils.unlink (workspace.executable);
			if (preserve == 1) {
				FileUtils.set_contents (workspace.executable, "preserve VAPI output");
			}
			string[] options = {
				workspace.source, "--vapi", workspace.vapi0, "-o", workspace.executable
			};
			// Omit the real implementation in the first case; even a supplied
			// companion cannot satisfy the deliberately missing symbol in the second.
			if (missing == 1) {
				options += "--link-object";
				options += workspace.object0;
			}
			var compiled = workspace.compile (text, options);
			compiled.exits (1);
			assert (compiled.output == "" && compiled.errors.contains ("host linker"));
			assert (compiled.errors.contains (missing == 0 ? "astra_test_add" : "definitely_missing_symbol"));
			if (preserve == 1) {
				assert (read (workspace.executable) == "preserve VAPI output");
			} else {
				assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
			}
			workspace.clean_temporaries ();
		}
	}
}

private void vapi_input_failures() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.executable, "preserve input failure");
	foreach (string mode in new string[] {"--check", "--dump-semantics", "--dump-core", "--dump-cfg", "--dump-ssa", "--dump-nabi", "--dump-cabi", "--dump-llvm", "compile"}) {
		string[] options = mode == "compile" ? new string[] {
			workspace.source, "-o", workspace.executable
		} : new string[] {
			mode, workspace.source
		};
		options += "--vapi";
		options += workspace.vapi0;
		options += "--vapi";
		options += workspace.vapi1;
		// A valid first input never allows downstream output after a bad second input.
		FileUtils.set_contents (workspace.vapi1, read ("tests/vapi/fixtures/malformed.vapi"));
		var malformed = workspace.compile ("int main() { return unknown(); }", options);
		malformed.exits (1);
		assert (malformed.output == "" && malformed.errors == workspace.vapi1 + ":2:1: error: expected ';' after VAPI function declaration\n");
		FileUtils.set_contents (workspace.vapi1, read ("tests/vapi/fixtures/invalid-bool.vapi"));
		var invalid = workspace.compile ("int main() { return unknown(); }", options);
		invalid.exits (1);
		assert (invalid.output == "" && invalid.errors == workspace.vapi1 + ":1:1: error: C result type must be 'int', 'void*' or 'void'; foreign bool is unsupported\n");
		assert (read (workspace.executable) == "preserve input failure");
	}
	FileUtils.unlink (workspace.vapi1);
	var unreadable = workspace.compile ("int main() { return 0; }", {"--check", workspace.source, "--vapi", workspace.vapi1});
	unreadable.exits (1);
	assert (unreadable.output == "" && unreadable.errors == workspace.vapi1 + ": error: cannot read VAPI file\n");
	// Copy complete byte allocations, including malformed UTF-8 and NUL.
	foreach (string fixture in new string[] {"invalid-utf8", "embedded-nul"}) {
		string bytes;
		size_t length;
		FileUtils.get_contents ("tests/frontend/fixtures/" + fixture + ".astra", out bytes, out length);
		FileUtils.set_contents (workspace.vapi1, bytes, (ssize_t) length);
		var invalid = workspace.compile ("int main() { return 0; }", {"--check", workspace.source, "--vapi", workspace.vapi1});
		invalid.exits (1);
		assert (invalid.output == "" && invalid.errors.has_prefix (workspace.vapi1 + ":"));
		assert (invalid.errors.contains (fixture == "invalid-utf8" ? "invalid UTF-8 encoding" : "unexpected NUL byte"));
	}
	var duplicate = workspace.compile ("int main() { return 0; }", {"--check", workspace.source, "--vapi", workspace.vapi0, "--vapi", workspace.vapi0});
	duplicate.exits (1);
	assert (duplicate.output == "" && duplicate.errors == workspace.vapi0 + ":2:5: error: duplicate function 'astra_test_add'; overloading is not implemented\n");
	assert (read (workspace.executable) == "preserve input failure");
	workspace.clean_temporaries ();
}

private void register_vapi() {
	register_vapi_metadata ();
	add ("/exec/vapi/basic-differential", () => vapi_execute ("basic"));
	add ("/exec/vapi/effect-order-differential", () => vapi_execute ("order"));
	add ("/exec/vapi/shortcircuit-differential", () => vapi_execute ("shortcircuit"));
	add ("/exec/vapi/loop-differential", () => vapi_execute ("loop"));
	add ("/exec/vapi/recursion-differential", () => vapi_execute ("recursive-native"));
	add ("/exec/vapi/roundtrip-differential", () => vapi_execute ("roundtrip", true));
	add ("/exec/vapi/modes-order-paths", vapi_modes_and_order);
	add ("/exec/vapi/multiple-objects-mixed", vapi_multiple_objects);
	add ("/exec/vapi/link-boundary", vapi_link_boundary);
	add ("/exec/vapi/input-failures", vapi_input_failures);
	add ("/exec/vapi/missing-path", () => cli_error ({"--vapi"}));
	add ("/exec/vapi/empty-path", () => cli_error ({"--vapi", ""}));
	add ("/exec/vapi/option-as-path", () => cli_error ({"--vapi", "--check"}));
	add ("/exec/vapi/missing-source", () => cli_error ({"--vapi", "input.vapi"}));
	add ("/exec/vapi/help-compilation", () => cli_error ({"--help", "--vapi", "input.vapi"}));
	add ("/exec/vapi/parse-input", () => cli_error ({"--parse", "file.astra", "--vapi", "input.vapi"}));
	add ("/exec/vapi/syntax-input", () => cli_error ({"--dump-syntax", "file.astra", "--vapi", "input.vapi"}));
	add ("/exec/vapi/input-before-syntax", () => cli_error ({"--vapi", "input.vapi", "--dump-syntax", "file.astra"}));
	add ("/exec/vapi/duplicate-mode", () => cli_error ({"--check", "--dump-cabi", "file.astra"}));
	add ("/exec/vapi/output-with-check", () => cli_error ({"--check", "file.astra", "--vapi", "input.vapi", "-o", "out"}));
}
}
