// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Moves {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}
private void guards() throws GLib.Error {
	string dump = lower (build (BASIC)).dump ();
	assert (dump.split ("call ptr @resource_create_impl").length == 2);
	assert (dump.contains ("%cleanup0.null = icmp eq ptr %v0, null"));
	// LLVM's constant builder folds null == null; the lexical guard and
	// its unreachable physical call block remain present.
	assert (dump.contains ("br i1 true, label %cleanup1.continue, label %cleanup1.call"));
	assert (dump.contains ("call void @resource_destroy_impl(ptr %v0)") && dump.contains ("call void @resource_destroy_impl(ptr null)"));
	foreach (string forbidden in new string[] {"alloca", "load ptr", "store ptr", "invoke", "personality", "noalias", "nonnull", "nocapture", "speculatable", "readnone", "readonly", "nounwind", "malloc", "retain", "release"}) {
		assert (!dump.contains (forbidden));
	}
}
private void pointer_phi() throws GLib.Error {
	string dump = lower (build ("void f(bool c) { owned void* a = create(1); if (c) { owned void* b = move a; } }")).dump ();
	bool found = false;
	foreach (string line in dump.split ("\n")) {
		if (line.contains ("phi ptr") && line.contains ("[ null, %cleanup0.continue ]") && line.contains ("%v")) {
			found = true;
		}
		assert (!line.contains ("phi i1") && !line.contains ("alloca i1"));
	}
	assert (found && dump.contains ("icmp eq ptr %v"));
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
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-move-lifetime-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}
private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/move/llvm/source-null-guards", guards);
	add ("/move/llvm/pointer-phi-physical-predecessor", pointer_phi);
	add ("/move/llvm/lifetime-object", lifetime);
	foreach (string name in new string[] {"basic", "chain", "chain-lifo", "null", "conditional", "both-arms", "return", "break", "continue", "loop", "lifo", "contracts", "terminating-arm", "loop-break", "loop-return", "conditional-break", "mixed", "unreachable", "trap"}) {
		add ("/move/llvm/" + name, () => lower (build (read ("move-" + name + ".astra"), fixture_declarations ())).verify ());
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
