// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Objects {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void lowering() throws GLib.Error {
	string basic = lower (build (read ("basic"))).dump ();
	assert (basic.contains ("%astra.class.0 = type { i32 }"));
	assert (basic.contains ("define internal fastcc void @astra.class.method.0.0(ptr %this, i32 %p0)"));
	assert (basic.contains ("call fastcc void @astra.class.method.0.0(ptr %object0, i32 2)"));
	assert (basic.contains ("icmp eq ptr %object0, null") && basic.contains ("@llvm.trap") && !basic.contains ("icmp eq ptr %this, null"));
	assert (basic.split ("alloca").length == 2);
	foreach (string forbidden in new string[] {"memcpy", "memmove", "vtable", "vptr", "typeinfo", "noalias", "readonly", "refcount", "descriptor", "malloc", "free("}) {
		assert (!basic.contains (forbidden));
	}
	string empty = lower (build (read ("empty"))).dump ();
	assert (empty.contains ("%astra.class.0 = type { i8 }") && empty.contains ("%astra.class.1 = type { i8 }"));
	assert (empty.split ("alloca").length == 5 && empty.contains ("icmp eq ptr %object0, %object1"));
	string slice = lower (build (read ("slice"))).dump ();
	assert (slice.contains ("@astra.class.method.0.0(ptr %this, ptr %p0.base, i32 %p0.length)"));
	string owned = lower (build (read ("owned"))).dump ();
	assert (owned.contains ("define internal fastcc ptr @astra.class.method.0.1(ptr %this, ptr %p0.base, i32 %p0.length, ptr %p1)"));
}

private void lifetime() throws GLib.Error {
	foreach (string fixture in new string[] {"basic", "empty", "nested-construction", "method"}) {
		SsaProgram? ssa = build (read (fixture));
		var declaration = WeakRef (ssa.classes[0]);
		var storage = WeakRef (ssa.functions[0].object_storage[0]);
		var artifact = lower (ssa);
		ssa = null;
		assert (declaration.get () == null && storage.get () == null);
		artifact.verify ();
		var directory = DirUtils.make_tmp ("astra-object-XXXXXX");
		var machine = new LlvmTargetMachineArtifact ();
		machine.configure (artifact);
		machine.emit_object (artifact, directory + "/object.o");
		assert (FileUtils.test (directory + "/object.o", FileTest.IS_REGULAR));
		FileUtils.unlink (directory + "/object.o");
		DirUtils.remove (directory);
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/object/llvm/layout-anchor-reference-identity-guards-direct-methods", lowering);
	add ("/object/llvm/stage-lifetime-and-machine-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
