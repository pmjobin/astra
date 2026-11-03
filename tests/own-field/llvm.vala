// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.OwnedFieldPipeline {
private void lowering() {
	try {
		foreach (var name in new string[] { "basic", "multi", "replace", "null", "result", "generic", "deinit-replace", "reentrant" }) {
			SsaProgram? ssa = build (name);
			var witness = WeakRef (ssa.classes[0]);
			var nabi = NativeAbiBuilder.build (ssa);
			var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
			ssa = null;
			assert (witness.get () == null);
			artifact.verify ();
			var text = artifact.dump ();
			assert (text.contains ("define internal fastcc void @astra.dtor.0(ptr %this)") && text.contains ("call void @of_release(ptr"));
			foreach (var forbidden in new string[] { "llvm.memcpy", "llvm.memmove", "malloc", "calloc", "realloc", "alloca i1", "alloca ptr", "sret", "byval", "noalias", "OwnedField" }) {
				assert (!text.contains (forbidden));
			}
			if (name == "result") {
				assert (text.contains ("ptr %result.storage") && text.contains ("ret ptr %result.storage"));
			}
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/llvm/physical-handles-direct-release-and-stage-lifetime", lowering);
	return Test.run ();
}

}
