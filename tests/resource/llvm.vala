// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Resource {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void physical() throws GLib.Error {
	string dump = lower (build ("Resource empty(Resource r) { return null; } Resource choose(bool c) { Resource q = null; if (c) { q = raw(); } return q; }" + BASIC)).dump ();
	assert (dump.contains ("define internal fastcc ptr @astra.fn.0(ptr %p0)"));
	assert (dump.contains ("phi ptr") && dump.contains ("[ null,"));
	assert (dump.contains ("call ptr @create") && dump.contains ("call void @destroy(ptr") && dump.contains ("icmp eq ptr"));
	foreach (string forbidden in new string[] {"alloca", "ptrtoint", "inttoptr", "load ptr", "store ptr", "Resource", "Other", "Device", "vtable", "descriptor", "type_tag", "malloc", "retain", "refcount"}) {
		assert (!dump.contains (forbidden));
	}
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (BASIC);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var type_ref = WeakRef (ssa.handles[0].semantic_type);
	var handle_ref = WeakRef (ssa.handles[0]);
	var cleanup_ref = WeakRef (cabi.cleanups[0]);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (type_ref.get () == null && handle_ref.get () == null && cleanup_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-resource-lifetime-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/resource/llvm/ptr-no-runtime-descriptor", physical);
	add ("/resource/llvm/lifetime-object", lifetime);
	foreach (string name in fixture_names ()) {
		add ("/resource/llvm/" + name, () => lower (build (read (name + ".astra"), fixture_declarations (name))).verify ());
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
