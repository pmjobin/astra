// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Driver;

namespace Astra.Tests.Exec {
private class ForeignWorkspace : Workspace {
	internal string object0;
	internal string object1;

	internal ForeignWorkspace () throws FileError {
		base ();
		object0 = Path.build_filename (directory, "object ; $(false) ' file.o");
		object1 = Path.build_filename (directory, "second object.o");
		assert (FileUtils.symlink (Environment.get_variable ("ASTRA_TEST_C_OBJECT"), object0) == 0);
		assert (FileUtils.symlink (Environment.get_variable ("ASTRA_TEST_C_OBJECT_SECOND"), object1) == 0);
	}

	internal Run compile_c(string text) throws GLib.Error {
		return compile (text, {source, "--link-object", object0, "-o", executable});
	}

	~ForeignWorkspace () {
		FileUtils.unlink (object0);
		FileUtils.unlink (object1);
	}

}

private void c_execute(string name) throws GLib.Error {
	var workspace = new ForeignWorkspace ();
	var result = workspace.compile_c (read ("tests/cabi/fixtures/" + name + ".astra"));
	result.exits (0);
	result.silent ();
	workspace.clean_temporaries ();
	var run = new Run ({workspace.executable}, workspace.directory);
	run.exits (0);
	run.silent ();
}

private void c_link_options() throws GLib.Error {
	var workspace = new ForeignWorkspace ();
	string text = "extern(C) int astra_test_add(int a, int b); extern(C) int astra_test_second(int x); int main() { return astra_test_second(astra_test_add(20, 21)); }";
	var first = workspace.compile (text, {"--link-object", workspace.object0, "--link-object", workspace.object1, workspace.source, "-o", workspace.executable});
	first.exits (0);
	first.silent ();
	new Run ({workspace.executable}).exits (42);
	var second = workspace.compile (text, {"--link-object", Path.get_basename (workspace.object1), workspace.source, "-o", workspace.executable, "--link-object", Path.get_basename (workspace.object0)});
	second.exits (0);
	second.silent ();
	new Run ({workspace.executable}).exits (42);
	workspace.clean_temporaries ();
}

private void c_link_boundary() throws GLib.Error {
	var workspace = new ForeignWorkspace ();
	string source = read ("tests/cabi/fixtures/c-missing-symbol.astra");
	foreach (string mode in new string[] {"--check", "--dump-cabi", "--dump-llvm"}) {
		var result = workspace.compile (source, {mode, workspace.source});
		result.exits (0);
		assert (result.errors == "");
		if (mode == "--check") {
			result.silent ();
		} else {
			assert (result.output.contains ("definitely_missing_symbol"));
		}
	}
	for (int preserve = 0; preserve < 2; preserve++) {
		if (preserve == 1) {
			FileUtils.set_contents (workspace.executable, "preserve me");
		}
		var missing_symbol = workspace.compile_c (source);
		missing_symbol.exits (1);
		assert (missing_symbol.output == "" && missing_symbol.errors.contains ("host linker") && missing_symbol.errors.contains ("definitely_missing_symbol"));
		if (preserve == 1) {
			assert (read (workspace.executable) == "preserve me");
		} else {
			assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
		}
		var missing_object = workspace.compile ("int main() { return 0; }", {workspace.source, "--link-object", "missing object.o", "-o", workspace.executable});
		missing_object.exits (1);
		assert (missing_object.errors.contains ("host linker") && missing_object.errors.contains ("missing object.o"));
		if (preserve == 1) {
			assert (read (workspace.executable) == "preserve me");
		}
		workspace.clean_temporaries ();
	}
	var imported_main = workspace.compile_c ("extern(C) int main();");
	imported_main.exits (1);
	assert (imported_main.errors.contains ("executable requires `int main()`") && !imported_main.errors.contains ("host linker"));
	assert (read (workspace.executable) == "preserve me");
	workspace.clean_temporaries ();
}

private void c_link_argv() throws GLib.Error {
	var workspace = new ForeignWorkspace ();
	try {
		HostLinker.link ("astra temporary.o", "temporary executable", {Environment.get_variable ("ASTRA_TEST_RECORD_LINKER"), workspace.executable}, {workspace.object1, workspace.object0});
		assert_not_reached ();
	} catch (ExecutionError.LINK error) {
		assert (error.message.contains ("exit status 37"));
	}
	string expected = Path.build_filename (Environment.get_current_dir (), "astra temporary.o") + "\n" + workspace.object1 + "\n" + workspace.object0 + "\n-o\n" + Path.build_filename (Environment.get_current_dir (), "temporary executable");
	assert (read (workspace.executable) == expected);
}

private void c_artifact_lifetime() throws GLib.Error {
	var workspace = new ForeignWorkspace ();
	SsaProgram? ssa = build_ssa (read ("tests/cabi/fixtures/c-recursive-native.astra"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var ssa_ref = WeakRef (ssa);
	var foreign_ref = WeakRef (ssa.c_functions[0]);
	var native_ref = WeakRef (ssa.functions[0]);
	var nabi_ref = WeakRef (nabi);
	var cabi_ref = WeakRef (cabi);
	var signature_ref = WeakRef (cabi.functions[0].signature);
	var source_ref = WeakRef (ssa.span.file);
	SsaFunction? entry = ProgramEntry.resolve (ssa);
	LlvmModuleArtifact? artifact = LlvmLowering.lower (ssa, nabi, cabi, entry);
	entry = null;
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && foreign_ref.get () == null && native_ref.get () == null);
	assert (nabi_ref.get () == null && cabi_ref.get () == null && signature_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump ().contains ("declare i32 @astra_test_add(i32, i32)"));
	LlvmTargetMachineArtifact? target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	ExecutableOutput? output = new ExecutableOutput (workspace.executable);
	target.emit_object (artifact, output.object_path);
	var artifact_ref = WeakRef (artifact);
	var target_ref = WeakRef (target);
	artifact = null;
	target = null;
	assert (artifact_ref.get () == null && target_ref.get () == null);
	output.link_and_commit (null, {workspace.object0});
	output = null;
	workspace.clean_temporaries ();
	var run = new Run ({workspace.executable});
	run.exits (0);
	run.silent ();
}

private void register_c_imports() {
	add ("/exec/cabi/basic", () => c_execute ("c-basic"));
	add ("/exec/cabi/void-and-discarded-result", () => c_execute ("c-void"));
	add ("/exec/cabi/argument-and-arithmetic-order", () => c_execute ("c-order"));
	add ("/exec/cabi/shortcircuit", () => c_execute ("c-shortcircuit"));
	add ("/exec/cabi/loops-and-transfers", () => c_execute ("c-loop"));
	add ("/exec/cabi/recursive-native", () => c_execute ("c-recursive-native"));
	add ("/exec/cabi/repeated-object-path-order", c_link_options);
	add ("/exec/cabi/link-boundary-transaction", c_link_boundary);
	add ("/exec/cabi/link-argv", c_link_argv);
	add ("/exec/cabi/artifact-lifetime", c_artifact_lifetime);
	add ("/exec/cabi/missing-object-option", () => cli_error ({"file.astra", "--link-object"}));
	add ("/exec/cabi/empty-object-option", () => cli_error ({"file.astra", "--link-object", ""}));
	add ("/exec/cabi/option-as-object", () => cli_error ({"file.astra", "--link-object", "-o", "out"}));
	add ("/exec/cabi/objects-with-check", () => cli_error ({"--check", "file.astra", "--link-object", "file.o"}));
	add ("/exec/cabi/objects-before-check", () => cli_error ({"--link-object", "file.o", "--check", "file.astra"}));
	add ("/exec/cabi/objects-with-dump", () => cli_error ({"--dump-cabi", "file.astra", "--link-object", "file.o"}));
	add ("/exec/cabi/objects-without-source", () => cli_error ({"--link-object", "file.o"}));
}

}
