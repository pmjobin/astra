// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests.Exec {
private Run compile_metadata(VapiWorkspace workspace, string source) throws GLib.Error {
	return workspace.compile (source, {workspace.source, "--vapi", workspace.vapi0, "--vapi", workspace.vapi1, "--vapi", workspace.vapi2, "--link-object", workspace.object0, "--link-object", Environment.get_variable ("ASTRA_TEST_VAPI_OBJECT"), "-o", workspace.executable});
}

private void metadata_execute(string fixture, bool roundtrip = false) throws GLib.Error {
	var workspace = new VapiWorkspace (roundtrip);
	FileUtils.set_contents (workspace.vapi0, read ("tests/vapi/fixtures/aliases.vapi"));
	FileUtils.set_contents (workspace.vapi1, read ("tests/vapi/fixtures/state-aliases.vapi"));
	FileUtils.set_contents (workspace.vapi2, roundtrip ? read ("tests/vapi/fixtures/roundtrip-aliases.vapi") : "");
	string source = fixture == "int" ? "int main() { return add(20, 22); }" : fixture == "void-discard" ? "int main() { record(9); reset(); if (state() != 0) { return 1; } record(4); if (state() != 4) { return 2; } return 0; }" : alias_source (read ("tests/vapi/fixtures/vapi-" + fixture + ".astra"));
	var compiled = compile_metadata (workspace, source);
	compiled.exits (0);
	compiled.silent ();
	var run = new Run ({workspace.executable});
	run.exits (fixture == "int" ? 42 : 0);
	run.silent ();
	workspace.clean_temporaries ();
}

private void metadata_header_boundary() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	string source = "int main() { return local(); }";
	string declaration = "[CCode (cname = \"c_value\")] int local();";
	string? previous_llvm = null;
	for (int header = 0; header < 2; header++) {
		FileUtils.set_contents (workspace.vapi0, header == 0 ? declaration : declaration.replace (")]", ", cheader_filename = \"this/header/does/not/exist.h\")]"));
		foreach (string mode in new string[] {"--check", "--dump-cabi", "--dump-llvm"}) {
			var checked = workspace.compile (source, {mode, workspace.source, "--vapi", workspace.vapi0});
			checked.exits (0);
			assert (checked.errors == "");
			if (mode == "--dump-cabi") {
				assert (checked.output.contains ("(name \"local\")\n\t\t(symbol \"c_value\")"));
				assert (checked.output.contains ("(headers") == (header == 1));
			}
			if (mode == "--dump-llvm") {
				assert (previous_llvm == null || previous_llvm == checked.output);
				previous_llvm = checked.output;
			}
		}
		var compiled = compile_metadata (workspace, source);
		compiled.exits (0);
		compiled.silent ();
		new Run ({workspace.executable}).exits (42);
	}
	// The header does not supply the implementation or infer any linker input.
	var unlinked = workspace.compile (source, {workspace.source, "--vapi", workspace.vapi0, "-o", workspace.executable});
	unlinked.exits (1);
	assert (unlinked.errors.contains ("host linker") && unlinked.errors.contains ("c_value"));
	new Run ({workspace.executable}).exits (42);
	// Also exercise the header-only/default external-symbol normalization.
	FileUtils.set_contents (workspace.vapi0, read ("tests/vapi/fixtures/header-only.vapi"));
	foreach (string mode in new string[] {"--check", "--dump-cabi", "--dump-llvm"}) {
		workspace.compile ("int main() { return c_value(); }", {mode, workspace.source, "--vapi", workspace.vapi0}).exits (0);
	}
	compile_metadata (workspace, "int main() { return c_value(); }").exits (0);
	new Run ({workspace.executable}).exits (42);
	workspace.clean_temporaries ();
}

private void metadata_missing_symbol() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, "[CCode (cname = \"definitely_missing_physical_symbol\", cheader_filename = \"missing.h\")] int friendly();");
	string source = "int main() { return friendly(); }";
	foreach (string mode in new string[] {"--check", "--dump-semantics", "--dump-cabi", "--dump-llvm"}) {
		var checked = workspace.compile (source, {mode, workspace.source, "--vapi", workspace.vapi0});
		checked.exits (0);
		assert (checked.errors == "");
		if (mode != "--check") {
			assert (checked.output.contains ("definitely_missing_physical_symbol"));
		}
		if (mode == "--dump-llvm") {
			assert (!checked.output.contains ("friendly") && checked.output.contains ("call i32 @definitely_missing_physical_symbol()"));
		}
	}
	for (int preserve = 0; preserve < 2; preserve++) {
		if (preserve == 1) {
			FileUtils.set_contents (workspace.executable, "preserved");
		}
		var compiled = compile_metadata (workspace, source);
		compiled.exits (1);
		assert (compiled.output == "" && compiled.errors.contains ("host linker") && compiled.errors.contains ("definitely_missing_physical_symbol") && !compiled.errors.contains ("friendly"));
		if (preserve == 1) {
			assert (read (workspace.executable) == "preserved");
		} else {
			assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
		}
		workspace.clean_temporaries ();
	}
}

private void metadata_cli_errors() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.executable, "preserved");
	FileUtils.set_contents (workspace.vapi0, read ("tests/vapi/fixtures/invalid-metadata.vapi"));
	foreach (string mode in new string[] {"--check", "--dump-semantics", "--dump-core", "--dump-cfg", "--dump-ssa", "--dump-nabi", "--dump-cabi", "--dump-llvm", "compile"}) {
		string[] options = mode == "compile" ? new string[] {
			workspace.source, "-o", workspace.executable
		} : new string[] {
			mode, workspace.source
		};
		options += "--vapi";
		options += workspace.vapi0;
		var rejected = workspace.compile ("int main() { return unknown(); }", options);
		rejected.exits (1);
		assert (rejected.output == "" && rejected.errors == workspace.vapi0 + ":3:2: error: duplicate VAPI metadata key 'cname'\n");
		assert (read (workspace.executable) == "preserved");
	}
	FileUtils.set_contents (workspace.vapi0, "[CCode (cname = \"physical\")] int alpha();");
	FileUtils.set_contents (workspace.vapi1, "[CCode (cname = \"physical\")] int beta();");
	foreach (string mode in new string[] {"--check", "--dump-cabi", "--dump-llvm", "compile"}) {
		string[] options = mode == "compile" ? new string[] {
			workspace.source, "-o", workspace.executable
		} : new string[] {
			mode, workspace.source
		};
		options += "--vapi";
		options += workspace.vapi0;
		options += "--vapi";
		options += workspace.vapi1;
		var rejected = workspace.compile ("int main() { return alpha() + beta(); }", options);
		rejected.exits (1);
		assert (rejected.output == "" && rejected.errors == workspace.vapi1 + ":1:17: error: C external symbol 'physical' is declared more than once\n");
		assert (read (workspace.executable) == "preserved");
	}
	workspace.clean_temporaries ();
}

private void register_vapi_metadata() {
	add ("/exec/vapi-metadata/int-42", () => metadata_execute ("int"));
	add ("/exec/vapi-metadata/void-discard-effects", () => metadata_execute ("void-discard"));
	add ("/exec/vapi-metadata/basic", () => metadata_execute ("basic"));
	add ("/exec/vapi-metadata/order", () => metadata_execute ("order"));
	add ("/exec/vapi-metadata/shortcircuit", () => metadata_execute ("shortcircuit"));
	add ("/exec/vapi-metadata/loop", () => metadata_execute ("loop"));
	add ("/exec/vapi-metadata/recursion", () => metadata_execute ("recursive-native"));
	add ("/exec/vapi-metadata/roundtrip", () => metadata_execute ("roundtrip", true));
	add ("/exec/vapi-metadata/header-boundary-differential", metadata_header_boundary);
	add ("/exec/vapi-metadata/missing-physical-symbol", metadata_missing_symbol);
	add ("/exec/vapi-metadata/cli-diagnostics", metadata_cli_errors);
}

}
