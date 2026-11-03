// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Ownbound {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void physical() throws GLib.Error {
	string dump = lower (build (BASIC)).dump ();
	assert (dump.contains ("define internal fastcc ptr @astra.fn.0(ptr %p0)"));
	assert (dump.contains ("ret ptr %p0") && dump.contains ("call fastcc ptr @astra.fn.0(ptr %v0)"));
	assert (dump.contains ("call void @destroy(ptr null)"));
	foreach (string forbidden in new string[] {"alloca", "ptrtoint", "inttoptr", "load ptr", "store ptr", "Resource", "Other", "Device", "descriptor", "type_tag", "malloc", "retain", "refcount"}) {
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
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-ownbound-lifetime-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/ownbound/llvm/ptr-no-runtime-descriptor", physical);
	add ("/ownbound/llvm/lifetime-object", lifetime);
	foreach (string name in fixture_names ()) {
		add ("/ownbound/llvm/" + name, () => lower (build (read (name + ".astra"), fixture_declarations (name))).verify ());
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
