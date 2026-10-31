// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Driver;

namespace Astra.Tests.Exec {
private void pointer_execute(string name) throws GLib.Error {
	var workspace = new VapiWorkspace ();
	bool exported = name == "ptr-cexport" || name == "ptr-roundtrip";
	FileUtils.set_contents (workspace.vapi0, read ("tests/ptr/fixtures/pointer-alias.vapi"));
	FileUtils.set_contents (workspace.vapi1, exported ? read ("tests/ptr/fixtures/pointer-roundtrip.vapi") : "");
	string object_path = Environment.get_variable (exported ? "ASTRA_TEST_PTR_EXPORT_OBJECT" : "ASTRA_TEST_PTR_OBJECT");
	var compiled = workspace.compile (read ("tests/ptr/fixtures/" + name + ".astra"), {workspace.source, "--vapi", workspace.vapi0, "--vapi", workspace.vapi1, "--link-object", object_path, "-o", workspace.executable});
	compiled.exits (0);
	compiled.silent ();
	var run = new Run ({workspace.executable});
	run.exits (0);
	run.silent ();
	if (exported && Environment.get_variable ("ASTRA_TEST_NM") != null) {
		var symbols = new Run ({Environment.get_variable ("ASTRA_TEST_NM"), "-g", workspace.executable});
		symbols.exits (0);
		assert (symbols.output.contains (" T astra_export_echo_ptr") && !symbols.output.contains ("astra.fn."));
		var all = new Run ({Environment.get_variable ("ASTRA_TEST_NM"), "-a", workspace.executable});
		all.exits (0);
		assert (all.output.contains (" t astra.fn.0"));
	}
	workspace.clean_temporaries ();
}

private void pointer_source_extern() throws GLib.Error {
	var workspace = new Workspace ();
	string text = "extern(C) void* astra_test_handle_a(); extern(C) int astra_test_is_handle_a(void* p); int main() { if (astra_test_is_handle_a(astra_test_handle_a()) == 0) { return 1; } return 0; }";
	workspace.compile (text, {workspace.source, "--link-object", Environment.get_variable ("ASTRA_TEST_PTR_OBJECT"), "-o", workspace.executable}).exits (0);
	new Run ({workspace.executable}).exits (0);
	workspace.clean_temporaries ();
}

private void pointer_unresolved() throws GLib.Error {
	var workspace = new VapiWorkspace ();
	FileUtils.set_contents (workspace.vapi0, "[CCode (cname = \"astra_missing_pointer\", cheader_filename = \"nonexistent/pointer_api.h\")] void* missing();");
	string source = "int main() { if (missing() == null) { return 0; } return 1; }";
	foreach (string mode in new string[] {"--check", "--dump-core", "--dump-cfg", "--dump-ssa", "--dump-nabi", "--dump-cabi", "--dump-llvm"}) {
		workspace.compile (source, {mode, workspace.source, "--vapi", workspace.vapi0}).exits (0);
	}
	FileUtils.set_contents (workspace.executable, "preserved");
	var compiled = workspace.compile (source, {workspace.source, "--vapi", workspace.vapi0, "-o", workspace.executable});
	compiled.exits (1);
	assert (compiled.errors.contains ("astra_missing_pointer") && compiled.errors.contains ("host linker"));
	assert (read (workspace.executable) == "preserved");
	workspace.clean_temporaries ();
}

private void pointer_object_lifetime() throws GLib.Error {
	var workspace = new Workspace ();
	SsaProgram? ssa = build_ssa ("extern(C) void* astra_test_handle_a(); extern(C) void* astra_test_pointer_roundtrip(void* p); export(C) void* astra_export_echo_ptr(void* p) { return p; } int main() { void* a = astra_test_handle_a(); if (astra_test_pointer_roundtrip(a) != a) { return 1; } if (astra_test_pointer_roundtrip(null) != null) { return 2; } return 0; }");
	var ssa_ref = WeakRef (ssa);
	var pointer_ref = WeakRef (ssa.functions[0].return_type);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	SsaFunction? entry = ProgramEntry.resolve (ssa);
	LlvmModuleArtifact? artifact = LlvmLowering.lower (ssa, nabi, cabi, entry);
	entry = null;
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && pointer_ref.get () == null);
	LlvmTargetMachineArtifact? target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	string ir = artifact.dump ();
	assert (ir.contains ("define internal fastcc ptr @astra.fn.0(ptr") && ir.contains ("define ptr @astra_export_echo_ptr(ptr"));
	assert (!ir.contains ("ptrtoint") && !ir.contains ("inttoptr"));
	Test.message ("pointer target: %s; data layout: %s\n%s", target.triple, target.data_layout, ir);
	ExecutableOutput? output = new ExecutableOutput (workspace.executable);
	target.emit_object (artifact, output.object_path);
	string? readelf = Environment.get_variable ("ASTRA_TEST_READELF");
	if (readelf != null) {
		var symbols = new Run ({readelf, "--wide", "--symbols", output.object_path});
		symbols.exits (0);
		assert (Regex.match_simple ("\\bFUNC\\s+LOCAL\\s+DEFAULT\\s+[0-9]+\\s+astra\\.fn\\.0\\b", symbols.output));
		assert (Regex.match_simple ("\\bFUNC\\s+GLOBAL\\s+DEFAULT\\s+[0-9]+\\s+astra_export_echo_ptr\\b", symbols.output));
		Test.message ("pointer object symbols:\n%s", symbols.output);
	}
	string? nm = Environment.get_variable ("ASTRA_TEST_NM");
	if (nm != null) {
		var symbols = new Run ({nm, "--undefined-only", output.object_path});
		symbols.exits (0);
		assert (symbols.output.contains ("U astra_test_handle_a") && symbols.output.contains ("U astra_test_pointer_roundtrip"));
		var caller = new Run ({nm, "--undefined-only", Environment.get_variable ("ASTRA_TEST_PTR_EXPORT_OBJECT")});
		caller.exits (0);
		assert (caller.output.contains ("U astra_export_echo_ptr") && !caller.output.contains ("astra.fn."));
		Test.message ("pointer object imports:\n%sC caller imports:\n%s", symbols.output, caller.output);
	}
	var artifact_ref = WeakRef (artifact);
	var target_ref = WeakRef (target);
	artifact = null;
	target = null;
	assert (artifact_ref.get () == null && target_ref.get () == null);
	output.link_and_commit (null, {Environment.get_variable ("ASTRA_TEST_PTR_EXPORT_OBJECT")});
	output = null;
	workspace.clean_temporaries ();
	new Run ({workspace.executable}).exits (0);
}

private void register_pointers() {
	foreach (string fixture in new string[] {"ptr-native", "ptr-null", "ptr-merge", "ptr-cimport", "ptr-cexport", "ptr-roundtrip", "ptr-shortcircuit"}) {
		string name = fixture;
		add ("/exec/pointers/" + name, () => pointer_execute (name));
	}
	add ("/exec/pointers/source-extern", pointer_source_extern);
	add ("/exec/pointers/object-linkage-lifetime", pointer_object_lifetime);
	add ("/exec/pointers/check-versus-link", pointer_unresolved);
}
}
