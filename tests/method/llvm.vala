// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Methods {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void signatures() throws GLib.Error {
	string basic = lower (build (read ("basic"))).dump ();
	assert (basic.contains ("define internal fastcc void @astra.method.0.0(ptr %this, i32 %p0)"));
	assert (basic.contains ("define internal fastcc i32 @astra.method.0.1(ptr %this)"));
	assert (basic.contains ("call fastcc void @astra.method.0.0(ptr %storage0, i32 2)"));
	assert (basic.contains ("ptr %this, i32 0, i32 0") && basic.contains ("load i32") && basic.contains ("store i32"));
	foreach (string forbidden in new string[] {"memcpy", "vtable", "vptr", "typeinfo", "noalias", "readonly", "nonnull", "icmp eq ptr"}) {
		assert (!basic.contains (forbidden));
	}
	assert (basic.split ("alloca").length == 2);
	string alias = lower (build (read ("alias"))).dump ();
	assert (alias.contains ("icmp eq ptr %p0, null") && !alias.contains ("icmp eq ptr %this, null"));
	string slice = lower (build (read ("slice"))).dump ();
	assert (slice.contains ("@astra.method.0.0(ptr %this, ptr %p0.base, i32 %p0.length)"));
	string vector = lower (build (read ("vector"))).dump ();
	assert (vector.contains ("@astra.method.0.3(ptr %this, <8 x i16> %p0)"));
	assert (vector.contains ("define internal fastcc <4 x float> @astra.method.0.2(ptr %this, <4 x float> %p0)"));
	string owned = lower (build (read ("owned"))).dump ();
	assert (owned.contains ("define internal fastcc ptr @astra.method.0.1(ptr %this, ptr %p0.base, i32 %p0.length, ptr %p1)"));
	assert (!owned.contains ("noalias") && !owned.contains ("method.descriptor"));
}

private void entry() throws GLib.Error {
	var ssa = build ("struct S { int x; int main () { return 42; } }");
	var nabi = NativeAbiBuilder.build (ssa);
	try {
		LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi), ssa.functions[0]);
	} catch (LlvmError error) {
		assert (error.message.contains ("entry error"));
		return;
	}
	GLib.error ("method accepted as a program entry without a receiver");
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("recursive"));
	var method = WeakRef (ssa.structs[0].methods[0]);
	var receiver = WeakRef (ssa.structs[0].methods[0].receiver);
	var type = WeakRef (ssa.structs[0].methods[0].receiver.contract);
	var artifact = lower (ssa);
	ssa = null;
	assert (method.get () == null && receiver.get () == null && type.get () == null);
	artifact.verify ();
	var directory = DirUtils.make_tmp ("astra-method-object-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/method.o");
	assert (FileUtils.test (directory + "/method.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/method.o");
	DirUtils.remove (directory);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/method/llvm/internal-direct-receiver-first-signatures-and-storage", signatures);
	add ("/method/llvm/stage-lifetime-and-object", lifetime);
	add ("/method/llvm/reject-method-as-entry", entry);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
