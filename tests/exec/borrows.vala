// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Driver;

namespace Astra.Tests.Exec {
private void borrow_object_lifetime() throws GLib.Error {
	var workspace = new Workspace ();
	SsaProgram? ssa = build_ssa (read ("tests/borrow/fixtures/borrow-alias.astra"));
	var structure_ref = WeakRef (ssa.structs[0]);
	var storage_ref = WeakRef (ssa.functions[1].storage[0]);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	SsaFunction? entry = ProgramEntry.resolve (ssa);
	LlvmModuleArtifact? artifact = LlvmLowering.lower (ssa, nabi, cabi, entry);
	entry = null;
	ssa = null;
	nabi = null;
	cabi = null;
	assert (structure_ref.get () == null && storage_ref.get () == null);
	LlvmTargetMachineArtifact? target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	artifact.verify ();
	assert (artifact.dump ().contains ("alloca %astra.struct.0"));
	ExecutableOutput? output = new ExecutableOutput (workspace.executable);
	target.emit_object (artifact, output.object_path);
	string? readelf = Environment.get_variable ("ASTRA_TEST_READELF");
	if (readelf != null) {
		var symbols = new Run ({readelf, "--wide", "--symbols", output.object_path});
		symbols.exits (0);
		assert (Regex.match_simple ("\\bFUNC\\s+LOCAL\\s+DEFAULT\\s+[0-9]+\\s+astra\\.fn\\.0\\b", symbols.output));
		assert (Regex.match_simple ("\\bFUNC\\s+GLOBAL\\s+DEFAULT\\s+[0-9]+\\s+main\\b", symbols.output));
	}
	string? nm = Environment.get_variable ("ASTRA_TEST_NM");
	if (nm != null) {
		var symbols = new Run ({nm, "--undefined-only", output.object_path});
		symbols.exits (0);
		assert (!symbols.output.contains ("malloc") && !symbols.output.contains ("free") && !symbols.output.contains ("memcpy") && !symbols.output.contains ("LLVM"));
	}
	Test.message ("addressable object target %s, data layout %s", target.triple, target.data_layout);
	var artifact_ref = WeakRef (artifact);
	var target_ref = WeakRef (target);
	artifact = null;
	target = null;
	assert (artifact_ref.get () == null && target_ref.get () == null);
	output.link_and_commit ();
	output = null;
	workspace.clean_temporaries ();
	new Run ({workspace.executable}).exits (0);
}

private void register_borrows() {
	foreach (string fixture in new string[] {"basic", "copy", "reassign", "late", "branch", "null", "loop", "scopes", "recursive", "transitive", "alias", "mixed"}) {
		string name = "borrow-" + fixture;
		add ("/exec/borrow/" + name, () => execute (read ("tests/borrow/fixtures/" + name + ".astra")));
	}
	add ("/exec/borrow/object-linkage-lifetime", borrow_object_lifetime);
}

}
