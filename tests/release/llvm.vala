// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Release {
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
	string dump = lower (build ("void f(bool c) { owned void* a = create(1); if (c) { release a; } }")).dump ();
	bool found = false;
	foreach (string line in dump.split ("\n")) {
		if (line.contains ("phi ptr") && line.contains ("[ null, %cleanup0.continue ]") && line.contains ("%v")) {
			found = true;
		}
		assert (!line.contains ("phi i1") && !line.contains ("alloca i1"));
	}
	assert (found && dump.contains ("icmp eq ptr %v"));
}

private void three_way() throws GLib.Error {
	string dump = lower (build (THREE_WAY)).dump ();
	int phis = 0;
	foreach (string line in dump.split ("\n")) {
		if (line.contains ("phi ptr")) {
			assert (line.split ("[ null,").length == 3 && line.split ("[").length == 4);
			assert (line.split ("%cleanup").length == 3);
			phis++;
		}
		assert (!line.contains ("phi i1") && !line.contains ("alloca"));
	}
	assert (phis == 1);
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
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-release-lifetime-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

private void continuation(string source, string branch, string expected) throws GLib.Error {
	string dump = lower (build (source)).dump ();
	string block = "";
	bool found = false;
	foreach (string line in dump.split ("\n")) {
		if (line.length > 0 && line[0] != ' ' && line.contains (":")) {
			block = line.split (":")[0];
		}
		if (line.strip () == branch && block != "b0") {
			assert (block == expected);
			found = true;
		}
	}
	assert (found);
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/release/llvm/source-null-guards", guards);
	add ("/release/llvm/pointer-phi-physical-predecessor", pointer_phi);
	add ("/release/llvm/lifetime-object", lifetime);
	add ("/release/llvm/three-way-single-pointer-phi", three_way);
	add ("/release/llvm/before-branch", () => continuation ("void f(bool c) { owned void* a = create(1); release a; if (c) { effect(); } }", "br i1 %p0, label %b1, label %b2", "cleanup0.continue"));
	add ("/release/llvm/before-shortcircuit", () => continuation ("void f(bool c) { owned void* a = create(1); release a; if (c && effect() == 1) { effect(); } }", "br label %b3", "cleanup0.continue"));
	add ("/release/llvm/before-backedge", () => continuation ("void f(bool c) { while (c) { owned void* a = create(1); release a; } }", "br label %b1", "cleanup1.continue"));
	foreach (string name in fixture_names ()) {
		add ("/release/llvm/" + name, () => lower (build (read ("release-" + name + ".astra"), fixture_declarations ())).verify ());
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
