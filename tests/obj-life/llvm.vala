// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Lifecycle {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}
private void storage_authority() {
	try {
		foreach (var name in new string[] { "alias", "null-rebind", "rebind", "return", "order", "loop", "empty", "slice", "owned" }) {
			SsaProgram? ssa = build (read (name));
			var witness = WeakRef (ssa.classes[0].constructor);
			var storage = WeakRef (null);
			foreach (var function in ssa.functions) {
				if (function.object_storage.length > 0) {
					storage.set (function.object_storage[0]);
					break;
				}
			}
			var artifact = lower (ssa);
			ssa = null;
			assert (witness.get () == null && storage.get () == null);
			artifact.verify ();
			var text = artifact.dump ();
			assert (text.contains ("define internal fastcc void @astra.ctor.0(ptr %this") && text.contains ("define internal fastcc void @astra.dtor.0(ptr %this)"));
			assert (text.contains ("call fastcc void @astra.dtor.0(ptr %object0)"));
			foreach (var forbidden in new string[] { "landingpad", "personality", "invoke ", "atexit", "malloc", "calloc", "refcount", "vtable", "typeinfo", "llvm.memcpy", "llvm.memmove", "icmp eq ptr %this, null", "define internal fastcc ptr @astra.ctor" }) {
				assert (!text.contains (forbidden));
			}
			if (name == "alias" || name == "null-rebind") {
				assert (text.split ("alloca %astra.class.").length == 2 && text.split ("call fastcc void @astra.dtor.").length == (name == "alias" ? 3 : 2));
			}
			if (name == "empty") {
				assert (text.contains ("%astra.class.0 = type { i8 }") && text.index_of ("@astra.dtor.0(ptr %object1)") < text.index_of ("@astra.dtor.0(ptr %object0)"));
			}
			var directory = DirUtils.make_tmp ("astra-lifecycle-XXXXXX");
			var machine = new LlvmTargetMachineArtifact ();
			machine.configure (artifact);
			machine.emit_object (artifact, directory + "/lifecycle.o");
			assert (FileUtils.test (directory + "/lifecycle.o", FileTest.IS_REGULAR));
			FileUtils.unlink (directory + "/lifecycle.o");
			DirUtils.remove (directory);
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/llvm/direct-void-lifecycle-storage-targets-and-stage-release", storage_authority);
	return Test.run ();
}
}
