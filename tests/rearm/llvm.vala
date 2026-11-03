// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Rearm {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void physical() throws GLib.Error {
	string dump = lower (build (BASIC)).dump ();
	assert (dump.split ("call ptr @resource_create_impl").length == 3);
	assert (dump.split ("call void @resource_destroy_impl").length == 3);
	foreach (string forbidden in new string[] {"alloca", "load ptr", "store ptr", "invoke", "personality", "noalias", "nonnull", "speculatable", "readnone", "readonly", "nounwind", "malloc", "retain", "refcount", "rearm", "armed", "cleanup_rank"}) {
		assert (!dump.contains (forbidden));
	}
}

private void pointer_phi(bool both) throws GLib.Error {
	string dump = lower (build ("void f(bool c) { owned void* a = create(1); release a; if (c) { a = create(2); } " + (both ? "else { a = variant(3); } inspect(a);" : "") + " }")).dump ();
	int phis = 0;
	foreach (string line in dump.split ("\n")) {
		if (line.contains ("phi ptr")) {
			phis++;
			assert (line.contains ("[ null,") != both);
		}
		assert (!line.contains ("phi i1") && !line.contains ("alloca"));
	}
	assert (phis == 1 && dump.contains ("icmp eq ptr %v"));
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (BASIC);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var ssa_ref = WeakRef (ssa.cleanups[0]);
	var cabi_ref = WeakRef (cabi.cleanups[0]);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && cabi_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-rearm-lifetime-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/rearm/llvm/ordinary-calls-no-runtime-state", physical);
	add ("/rearm/llvm/conditional-pointer-phi", () => pointer_phi (false));
	add ("/rearm/llvm/both-arm-pointer-phi", () => pointer_phi (true));
	add ("/rearm/llvm/lifetime-object", lifetime);
	foreach (string name in fixture_names ()) {
		add ("/rearm/llvm/" + name, () => lower (build (read ("rearm-" + name + ".astra"), fixture_declarations ())).verify ());
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
