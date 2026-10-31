// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Backend.LLVM;
using Astra.NativeAbi;
using Astra.Driver;

namespace Astra.Tests.Exec {
private void entry_policy() throws GLib.Error {
	string[] texts = {
		"int f() { return 0; }", "void main() { return; }", "bool main() { return true; }", "int main(int x) { return x; }"
	};
	string[] reasons = {
		"no source function named main", "main must return int", "main must return int", "main must have zero parameters or one borrowed string[] parameter"
	};
	for (int i = 0; i < texts.length; i++) {
		var workspace = new Workspace ();
		var compiled = workspace.compile (texts[i]);
		compiled.exits (1);
		assert (compiled.output == "");
		string prefix = i == 0 ? "astrac: error: " : "%s:1:%d: error: ".printf (workspace.source, i == 3 ? 5 : 6);
		assert (compiled.errors == prefix + (i == 0 ? "executable requires `int main()`; " : "executable requires `int main()` or `int main(string[] args)`; ") + reasons[i] + "\n");
		assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
		foreach (string mode in new string[] {"--parse", "--dump-syntax", "--check", "--dump-semantics", "--dump-core", "--dump-cfg", "--dump-ssa", "--dump-nabi", "--dump-llvm"}) {
			var result = workspace.compile (texts[i], {mode, workspace.source});
			result.exits (0);
			assert (result.errors == "");
			if (mode == "--check" || mode == "--parse") {
				result.silent ();
			} else {
				assert (result.output != "");
			}
			if (mode == "--dump-llvm") {
				assert (!result.output.contains ("target triple") && !result.output.contains ("target datalayout") && !result.output.contains ("@main("));
			}
		}
		workspace.clean_temporaries ();
	}
}

private void option_order() throws GLib.Error {
	var workspace = new Workspace ();
	string text = read ("tests/exec/fixtures/exit-42.astra");
	var first = workspace.compile (text, {"-o", workspace.executable, workspace.source});
	first.exits (0);
	first.silent ();
	new Run ({workspace.executable}).exits (42);
	var default_output = workspace.compile (text, {workspace.source});
	default_output.exits (0);
	default_output.silent ();
	new Run ({Path.build_filename (workspace.directory, "a.out")}).exits (42);
	FileUtils.unlink (workspace.source);
	workspace.source = Path.build_filename (workspace.directory, "-input.astra");
	var positional = workspace.compile (text, {"-o", workspace.executable, "--", "-input.astra"});
	positional.exits (0);
	positional.silent ();
	new Run ({workspace.executable}).exits (42);
	workspace.clean_temporaries ();
}

private void cli_error(string[] args, string diagnostic = "astrac: error:") throws GLib.Error {
	var workspace = new Workspace ();
	var result = workspace.compile ("int main() { return 0; }", args);
	result.exits (2);
	assert (result.output == "" && result.errors.contains (diagnostic));
	assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
	workspace.clean_temporaries ();
}

private void symlink_parent() throws GLib.Error {
	var workspace = new Workspace ();
	string real = Path.build_filename (workspace.directory, "real");
	string leaf = Path.build_filename (real, "leaf");
	string link = Path.build_filename (workspace.directory, "link");
	assert (DirUtils.create_with_parents (leaf, 0700) == 0);
	assert (FileUtils.symlink (leaf, link) == 0);
	workspace.executable = Path.build_filename (real, "program");
	var result = workspace.compile ("int main() { return 42; }", {workspace.source, "-o", Path.build_filename (link, "..", "program")});
	result.exits (0);
	result.silent ();
	new Run ({workspace.executable}).exits (42);
	assert (!FileUtils.test (Path.build_filename (workspace.directory, "program"), FileTest.EXISTS));
	FileUtils.unlink (workspace.executable);
	FileUtils.unlink (link);
	assert (DirUtils.remove (leaf) == 0 && DirUtils.remove (real) == 0);
	workspace.clean_temporaries ();
}

private void output_preservation() throws GLib.Error {
	var workspace = new Workspace ();
	FileUtils.set_contents (workspace.executable, "existing output\n");
	foreach (string source in new string[] {"int main() { return 0 }", "int main() { return false; }", "int main() {}", "int f() { return 0; }"}) {
		var result = workspace.compile (source);
		result.exits (1);
		assert (result.output == "" && result.errors.contains ("error:"));
		assert (read (workspace.executable) == "existing output\n");
		workspace.clean_temporaries ();
	}
	var success = workspace.compile ("int main() { return 42; }");
	success.exits (0);
	success.silent ();
	new Run ({workspace.executable}).exits (42);
	workspace.clean_temporaries ();
}

private void link_failures() throws GLib.Error {
	var workspace = new Workspace ();
	FileUtils.set_contents (workspace.executable, "preserve me");
	var target = new LlvmTargetMachineArtifact ();
	var artifact = lower_entry ();
	artifact.configure_executable (target);
	foreach (string driver in new string[] {Environment.get_variable ("ASTRA_TEST_LINK_FAILURE"), Path.build_filename (workspace.directory, "absent driver")}) {
		try {
			var output = new ExecutableOutput (workspace.executable);
			target.emit_object (artifact, output.object_path);
			output.link_and_commit ({driver});
			assert_not_reached ();
		} catch (ExecutionError.LINK error) {
			assert (error.message.contains ("host linker"));
			if (driver == Environment.get_variable ("ASTRA_TEST_LINK_FAILURE")) {
				assert (error.message.contains ("exit status 37") && error.message.contains ("linker fixture stderr") && error.message.contains ("linker fixture stdout"));
			} else {
				assert (error.message.contains ("cannot start"));
			}
		}
		assert (read (workspace.executable) == "preserve me");
		workspace.clean_temporaries ();
	}
	// Real object generation is independent of wrapper insertion and linking.
	var library = build_ssa ("int f() { return 0; }");
	var module = LlvmLowering.lower (library, NativeAbiBuilder.build (library), Astra.CAbi.CAbiBuilder.build (library, Astra.NativeAbi.NativeAbiBuilder.build (library)));
	target.configure (module);
	assert (!module.dump ().contains ("@main("));
	try {
		var output = new ExecutableOutput (workspace.executable);
		target.emit_object (module, output.object_path);
		output.link_and_commit ();
		assert_not_reached ();
	} catch (ExecutionError.LINK error) {
		assert (error.message.contains ("host linker") && error.message.contains ("main"));
	}
	assert (read (workspace.executable) == "preserve me");
	workspace.clean_temporaries ();
}

private void output_failures() throws GLib.Error {
	var workspace = new Workspace ();
	try {
		new ExecutableOutput (Path.build_filename (workspace.directory, "missing", "program"));
		assert_not_reached ();
	} catch (ExecutionError.OUTPUT error) {
		assert (error.message.contains ("cannot create temporary output"));
	}
	assert (DirUtils.create (workspace.executable, 0700) == 0);
	var result = workspace.compile ("int main() { return 0; }");
	result.exits (1);
	assert (result.output == "" && result.errors.contains ("cannot publish executable"));
	assert (FileUtils.test (workspace.executable, FileTest.IS_DIR));
	workspace.clean_temporaries ();
	assert (DirUtils.remove (workspace.executable) == 0);
}

private void format_inspection() throws GLib.Error {
	string? readelf = Environment.get_variable ("ASTRA_TEST_READELF");
	if (readelf == null) {
		Test.skip ("optional readelf is unavailable");
		return;
	}
	var workspace = new Workspace ();
	ExecutableOutput? output = new ExecutableOutput (workspace.executable);
	var artifact = lower_entry ();
	var target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	target.emit_object (artifact, output.object_path);
	var object_info = new Run ({readelf, "-h", "-s", output.object_path});
	object_info.exits (0);
	assert (object_info.errors == "" && object_info.output.contains ("REL (Relocatable file)"));
	bool local = false;
	bool launch = false;
	foreach (string line in object_info.output.split ("\n")) {
		if (line.contains ("astra.fn.1")) {
			assert (line.contains ("LOCAL") && line.contains ("FUNC"));
			local = true;
		}
		if (line.has_suffix (" main")) {
			assert (line.contains ("GLOBAL") && line.contains ("FUNC"));
			launch = true;
		}
	}
	assert (local && launch);
	Test.message ("object inspection:\n%s", object_info.output);
	var compiler_info = new Run ({readelf, "-h", Environment.get_variable ("ASTRA_TEST_COMPILER")});
	compiler_info.exits (0);
	foreach (string line in compiler_info.output.split ("\n")) {
		if (line.contains ("Machine:") || line.contains ("Class:") || line.contains ("Data:")) {
			assert (object_info.output.contains (line));
			Test.message ("host object %s", line.strip ());
		}
	}
	output.link_and_commit ();
	output = null;
	workspace.clean_temporaries ();
	var executable_info = new Run ({readelf, "-h", workspace.executable});
	executable_info.exits (0);
	Test.message ("executable inspection:\n%s", executable_info.output);
	assert (executable_info.output.contains ("Position-Independent Executable file") || executable_info.output.contains ("EXEC (Executable file)"));
	new Run ({workspace.executable}).exits (0);
}

private void register_driver() {
	add ("/exec/driver/entry-stage-policy", entry_policy);
	add ("/exec/driver/options-spaces-punctuation", option_order);
	add ("/exec/driver/symlink-parent", symlink_parent);
	add ("/exec/driver/output-preservation", output_preservation);
	add ("/exec/driver/link-failures", link_failures);
	add ("/exec/driver/output-failures", output_failures);
	add ("/exec/driver/object-executable-format", format_inspection);
	add ("/exec/cli/missing-output", () => cli_error ({"file.astra", "-o"}));
	add ("/exec/cli/empty-output", () => cli_error ({"file.astra", "-o", ""}));
	add ("/exec/cli/duplicate-output", () => cli_error ({"-o", "one", "file.astra", "-o", "two"}));
	add ("/exec/cli/duplicate-sources", () => cli_error ({"one.astra", "./one.astra"}));
	add ("/exec/cli/output-without-source", () => cli_error ({"-o", "one"}));
	add ("/exec/cli/output-with-dump", () => cli_error ({"--dump-llvm", "one.astra", "-o", "one"}));
	add ("/exec/cli/target-unsupported", () => cli_error ({"--target", "some-target", "one.astra"}, "astrac: unsupported target 'some-target'; supported selections are"));
	add ("/exec/cli/run-unsupported", () => cli_error ({"--run", "one.astra"}));
}
}
