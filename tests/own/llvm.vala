// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Ownership {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void guards() throws GLib.Error {
	string dump = lower (build ("int f() { owned void* a = create(1); owned void* b = create(2); return 7; }")).dump ();
	assert (dump.split ("declare void @resource_destroy_impl(ptr)").length == 2);
	assert (dump.split ("call void @resource_destroy_impl(ptr").length == 3);
	assert (dump.contains ("%cleanup0.null = icmp eq ptr %v1, null") && dump.contains ("%cleanup1.null = icmp eq ptr %v0, null"));
	assert (dump.contains ("br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call"));
	foreach (string forbidden in new string[] {"alloca ptr", "load ptr", "store ptr", "invoke", "personality", "noalias", "nonnull", "nocapture", "speculatable", "readnone", "readonly", "nounwind", "malloc", "retain", "release"}) {
		assert (!dump.contains (forbidden));
	}
}

private void predecessors(string name) throws GLib.Error {
	string source = name == "break" ? "int f(bool stop) { int n = 0; while (n < 2) { owned void* h = create_resource(1); n = n + 1; if (stop) { break; } } return n; }" : read ("own-" + name + ".astra");
	string dump = lower (build (source, read ("owned-resource.vapi"))).dump ();
	bool found = false;
	foreach (string line in dump.split ("\n")) {
		if (line.contains ("phi i32") && line.contains ("%cleanup") && line.contains (".continue")) {
			found = true;
		}
	}
	assert (found);
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (BASIC);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var ssa_ref = WeakRef (ssa.cleanups[0]);
	var cabi_ref = WeakRef (cabi.cleanups[0]);
	var source_ref = WeakRef (ssa.cleanups[0].symbol_span.file);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && cabi_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-owned-lifetime-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR));
	assert (FileUtils.unlink (path) == 0);
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/own/llvm/chained-guards", guards);
	foreach (string name in new string[] {"branch", "branch-both", "loop", "continue", "break", "nested-loop"}) {
		add ("/own/llvm/predecessors/" + name, () => predecessors (name));
	}
	add ("/own/llvm/lifetime-object", lifetime);
	foreach (string name in new string[] {"basic", "null", "lifo", "nested", "return", "early-return", "loop-return", "shortcircuit", "mixed", "unreachable", "fallthrough", "trap", "null-trap"}) {
		add ("/own/llvm/" + name, () => lower (build (read ("own-" + name + ".astra"), read ("owned-resource.vapi"))).verify ());
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
