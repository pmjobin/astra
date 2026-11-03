// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Driver;

namespace Astra.Tests.Exec {
private void struct_execute(string name, bool trap = false) throws GLib.Error {
	var workspace = new Workspace ();
	string text = read ("tests/struct/fixtures/" + name + ".astra");
	var compiled = workspace.compile (text, {workspace.source, "--link-object", Environment.get_variable ("ASTRA_TEST_C_OBJECT"), "--link-object", Environment.get_variable ("ASTRA_TEST_PTR_OBJECT"), "-o", workspace.executable});
	compiled.exits (0);
	compiled.silent ();
	workspace.clean_temporaries ();
	var run = new Run ({workspace.executable}, workspace.directory);
	run.silent ();
	if (trap) {
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
		Test.message ("later struct initializer traps (host signal %d)", (int) Process.term_sig (run.status));
	} else {
		run.exits (0);
	}
	workspace.clean_temporaries ();
}

private void struct_object_lifetime() throws GLib.Error {
	var workspace = new Workspace ();
	SsaProgram? ssa = build_ssa (read ("tests/struct/fixtures/struct-pointer.astra"));
	var ssa_ref = WeakRef (ssa);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	SsaFunction? entry = ProgramEntry.resolve (ssa);
	LlvmModuleArtifact? artifact = LlvmLowering.lower (ssa, nabi, cabi, entry);
	entry = null;
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null);
	LlvmTargetMachineArtifact? target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	artifact.verify ();
	string ir = artifact.dump ();
	assert (!ir.contains ("alloca") && !ir.contains ("extractvalue") && !ir.contains ("insertvalue") && !ir.contains (" = type "));
	Test.message ("struct scalarization target: %s; data layout: %s", target.triple, target.data_layout);
	ExecutableOutput? output = new ExecutableOutput (workspace.executable);
	target.emit_object (artifact, output.object_path);
	string? readelf = Environment.get_variable ("ASTRA_TEST_READELF");
	if (readelf != null) {
		var symbols = new Run ({readelf, "--wide", "--symbols", output.object_path});
		symbols.exits (0);
		assert (Regex.match_simple ("\\bFUNC\\s+LOCAL\\s+DEFAULT\\s+[0-9]+\\s+astra\\.fn\\.0\\b", symbols.output));
		assert (Regex.match_simple ("\\bFUNC\\s+GLOBAL\\s+DEFAULT\\s+[0-9]+\\s+main\\b", symbols.output));
		Test.message ("struct object symbols:\n%s", symbols.output);
	}
	string? nm = Environment.get_variable ("ASTRA_TEST_NM");
	if (nm != null) {
		var symbols = new Run ({nm, "--undefined-only", output.object_path});
		symbols.exits (0);
		assert (symbols.output.contains ("U astra_test_handle_a") && symbols.output.contains ("U astra_test_guarded_handle_a"));
		assert (!symbols.output.contains ("malloc") && !symbols.output.contains ("free"));
		Test.message ("struct object imports:\n%s", symbols.output);
	}
	var artifact_ref = WeakRef (artifact);
	var target_ref = WeakRef (target);
	artifact = null;
	target = null;
	assert (artifact_ref.get () == null && target_ref.get () == null);
	output.link_and_commit (null, {Environment.get_variable ("ASTRA_TEST_PTR_OBJECT")});
	output = null;
	workspace.clean_temporaries ();
	new Run ({workspace.executable}).exits (0);
}

private void register_structs() {
	foreach (string fixture in new string[] {"struct-basic", "struct-order", "struct-branch", "struct-loop", "struct-pointer", "struct-scope"}) {
		string name = fixture;
		add ("/exec/structs/" + name, () => struct_execute (name));
	}
	add ("/exec/structs/later-initializer-trap", () => struct_execute ("struct-trap", true));
	add ("/exec/structs/object-linkage-lifetime", struct_object_lifetime);
}

}
