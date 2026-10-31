// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.OwnerBorrow {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}
private void physical() throws GLib.Error {
	string source = "int native(borrowed void* p) { return inspect(p); } void f() { owned void* h = create(1); native(h); inspect(h); }";
	string dump = lower (build (source)).dump ();
	assert (dump.contains ("define internal fastcc i32 @astra.fn.0(ptr %p0)") && dump.contains ("call fastcc i32 @astra.fn.0(ptr %v0)"));
	assert (dump.contains ("declare i32 @inspect(ptr)") && dump.contains ("call i32 @inspect(ptr %v0)"));
	assert (dump.split ("call void @resource_destroy_impl").length == 2);
	assert (dump.contains ("call void @resource_destroy_impl(ptr %v0)") && !dump.contains ("@resource_destroy_impl(ptr null)"));
	foreach (string forbidden in new string[] {"alloca", "load ptr", "store ptr", "noalias", "nonnull", "nocapture", "captures(", "dereferenceable", "readonly", "readnone", "retain", "release", "borrow"}) {
		assert (!dump.contains (forbidden));
	}
	string raw = "int f(void* p) { return inspect(p); }";
	assert (lower (build (raw, "int inspect(void* p);")).dump () == lower (build (raw.replace ("void* p", "borrowed void* p"), "int inspect(borrowed void* p);")).dump ());
	assert (lower (build ("extern(C) int inspect(borrowed void* p); " + raw, "")).dump () == lower (build (raw, "int inspect(borrowed void* p);")).dump ());
}
private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (BASIC);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var ssa_ref = WeakRef (ssa.c_functions[1].parameters[0]);
	var cabi_ref = WeakRef (cabi.functions[1].signature.parameters[0]);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && cabi_ref.get () == null);
	artifact.verify ();
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-oborrow-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.unlink (path) == 0);
}
private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/oborrow/llvm/physical-differential", physical);
	add ("/oborrow/llvm/lifetime-object", lifetime);
	foreach (string name in new string[] {"basic", "native", "forward", "move", "destination", "repeated", "null", "loop", "body-loop", "continue", "break", "return", "order", "raw-null", "extern", "control", "conditional", "shortcircuit"}) {
		add ("/oborrow/llvm/" + name, () => lower (build (read ("oborrow-" + name + ".astra"), fixture_declarations ())).verify ());
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
