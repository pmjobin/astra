// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Driver;

namespace Astra.Tests.Exec {
private class ExportWorkspace : ForeignWorkspace {
	internal ExportWorkspace (int variant) throws FileError {
		base ();
		assert (FileUtils.unlink (object0) == 0);
		assert (FileUtils.symlink (Environment.get_variable ("ASTRA_TEST_CEXPORT_OBJECT_%d".printf (variant)), object0) == 0);
	}
}

private void export_execute(string fixture, int variant, bool trap = false) throws GLib.Error {
	var workspace = new ExportWorkspace (variant);
	var compiled = workspace.compile_c (read ("tests/cabi/fixtures/" + fixture + ".astra"));
	compiled.exits (0);
	compiled.silent ();
	workspace.clean_temporaries ();
	var run = new Run ({workspace.executable});
	if (trap) {
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
		Test.message ("C ingress trap did not return normally; signal %d is not part of the contract", (int) Process.term_sig (run.status));
	} else {
		run.exits (0);
		run.silent ();
	}
}

private void export_object_lifetime() throws GLib.Error {
	var workspace = new ExportWorkspace (4);
	SsaProgram? ssa = build_ssa (read ("tests/cabi/fixtures/cexport-roundtrip.astra"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var ssa_ref = WeakRef (ssa);
	var native_ref = WeakRef (ssa.functions[0]);
	var metadata_ref = WeakRef (ssa.c_exports[0]);
	var nabi_ref = WeakRef (nabi);
	var cabi_ref = WeakRef (cabi);
	var export_ref = WeakRef (cabi.exports[0]);
	var source_ref = WeakRef (ssa.span.file);
	SsaFunction? entry = ProgramEntry.resolve (ssa);
	LlvmModuleArtifact? artifact = LlvmLowering.lower (ssa, nabi, cabi, entry);
	entry = null;
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && native_ref.get () == null && metadata_ref.get () == null && nabi_ref.get () == null);
	assert (cabi_ref.get () == null && export_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	LlvmTargetMachineArtifact? target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	string ir = artifact.dump ();
	assert (ir.contains ("define internal fastcc i32 @astra.fn.0()") && ir.contains ("define i32 @astra_export_roundtrip()") && ir.contains ("define i32 @main()"));
	ExecutableOutput? output = new ExecutableOutput (workspace.executable);
	target.emit_object (artifact, output.object_path);
	string? readelf = Environment.get_variable ("ASTRA_TEST_READELF");
	if (readelf != null) {
		var symbols = new Run ({readelf, "--wide", "--symbols", output.object_path});
		symbols.exits (0);
		assert (Regex.match_simple ("\\bFUNC\\s+LOCAL\\s+DEFAULT\\s+[0-9]+\\s+astra\\.fn\\.0\\b", symbols.output));
		assert (Regex.match_simple ("\\bFUNC\\s+GLOBAL\\s+DEFAULT\\s+[0-9]+\\s+astra_export_roundtrip\\b", symbols.output));
		assert (Regex.match_simple ("\\bFUNC\\s+GLOBAL\\s+DEFAULT\\s+[0-9]+\\s+main\\b", symbols.output));
		Test.message ("export object symbol audit:\n%s", symbols.output);
	}
	string? nm = Environment.get_variable ("ASTRA_TEST_NM");
	if (nm != null) {
		var symbols = new Run ({nm, output.object_path});
		symbols.exits (0);
		assert (Regex.match_simple ("(?m)^[0-9a-fA-F]+ t astra\\.fn\\.0$", symbols.output));
		assert (Regex.match_simple ("(?m)^[0-9a-fA-F]+ T astra_export_roundtrip$", symbols.output));
		var caller = new Run ({nm, "--undefined-only", workspace.object0});
		caller.exits (0);
		assert (caller.output.contains ("U astra_export_roundtrip") && !caller.output.contains ("astra.fn."));
		Test.message ("C companion unresolved symbol audit:\n%s", caller.output);
	}
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

private void exported_main_policy() throws GLib.Error {
	var workspace = new Workspace ();
	string source = read ("tests/cabi/fixtures/cexport-main.astra");
	foreach (string mode in new string[] {"--check", "--dump-cabi", "--dump-llvm"}) {
		var stage = workspace.compile (source, {mode, workspace.source});
		stage.exits (0);
		assert (stage.errors == "");
		if (mode == "--check") {
			stage.silent ();
		}
	}
	for (int preserve = 0; preserve < 2; preserve++) {
		if (preserve == 1) {
			FileUtils.set_contents (workspace.executable, "preserve exported main output");
		}
		var compiled = workspace.compile (source);
		compiled.exits (1);
		assert (compiled.output == "" && compiled.errors.contains ("C export symbol `main` conflicts with the executable entry wrapper"));
		assert (!compiled.errors.contains ("host linker") && !compiled.errors.contains ("internal LLVM"));
		if (preserve == 1) {
			assert (read (workspace.executable) == "preserve exported main output");
		} else {
			assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
		}
		workspace.clean_temporaries ();
	}
	// Direct backend callers also cannot create a second platform main.
	var ssa = build_ssa (source);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	try {
		LlvmLowering.lower (ssa, nabi, cabi, ssa.functions[0]);
		assert_not_reached ();
	} catch (LlvmError.INVALID_INPUT error) {
		assert (error.message.contains ("conflicts with the executable entry wrapper"));
	}
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	artifact.entry_function = artifact.c_exports[0].native_target;
	artifact.entry_type = CApi.global_value_type (artifact.entry_function);
	try {
		artifact.configure_executable (new LlvmTargetMachineArtifact ());
		assert_not_reached ();
	} catch (LlvmError.INVALID_INPUT error) {
		assert (error.message.contains ("conflicts with the executable entry wrapper"));
	}
	assert (!artifact.dump ().contains ("@main.1"));
}

private void export_link_transaction() throws GLib.Error {
	var workspace = new ExportWorkspace (1);
	string source = read ("tests/cabi/fixtures/cexport-basic.astra");
	for (int preserve = 0; preserve < 2; preserve++) {
		if (preserve == 1) {
			FileUtils.set_contents (workspace.executable, "preserve export output");
		}
		var missing = workspace.compile (source);
		missing.exits (1);
		assert (missing.errors.contains ("host linker") && missing.errors.contains ("c_call_astra_add"));
		if (preserve == 1) {
			assert (read (workspace.executable) == "preserve export output");
		} else {
			assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
		}
		workspace.clean_temporaries ();
	}
	var success = workspace.compile_c (source);
	success.exits (0);
	success.silent ();
	new Run ({workspace.executable}).exits (0);
	workspace.clean_temporaries ();
}

private void register_c_exports() {
	add ("/exec/cexport/basic", () => export_execute ("cexport-basic", 1));
	add ("/exec/cexport/void", () => export_execute ("cexport-void", 2));
	add ("/exec/cexport/native-call", () => export_execute ("cexport-native-call", 1));
	add ("/exec/cexport/recursion", () => export_execute ("cexport-recursive", 3));
	add ("/exec/cexport/roundtrip-and-c-observed-order", () => export_execute ("cexport-roundtrip", 4));
	add ("/exec/cexport/shortcircuit-effects", () => export_execute ("cexport-shortcircuit", 5));
	add ("/exec/cexport/wrapping-loops-break-continue", () => export_execute ("cexport-body", 6));
	add ("/exec/cexport/trap", () => export_execute ("cexport-trap", 7, true));
	add ("/exec/cexport/object-audit-lifetime-and-link", export_object_lifetime);
	add ("/exec/cexport/main-collision", exported_main_policy);
	add ("/exec/cexport/link-transaction", export_link_transaction);
}
}
