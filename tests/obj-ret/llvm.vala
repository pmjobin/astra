// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.ObjectResult {
private void lowering() {
	try {
		foreach (var name in new string[] { "basic", "null", "param", "forward", "recursive", "method", "vector", "slice", "owned", "empty" }) {
			SsaProgram? ssa = build (read (name));
			var witness = WeakRef (ssa.classes[0]);
			var nabi = NativeAbiBuilder.build (ssa);
			var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
			ssa = null;
			assert (witness.get () == null);
			artifact.verify ();
			var text = artifact.dump ();
			assert (text.contains ("ptr %result.storage"));
			foreach (var forbidden in new string[] { "llvm.memcpy", "llvm.memmove", "malloc", "calloc", "realloc", "alloca i1", "alloca ptr", "sret", "byval", "noalias" }) {
				assert (!text.contains (forbidden));
			}
			if (name == "basic") {
				assert (text.contains ("ret ptr %result.storage") && text.contains ("@astra.ctor.0(ptr %result.storage, i32 %p0)"));
			}
			if (name == "param") {
				assert (text.contains ("ret ptr %p0") && text.contains ("@astra.dtor.0(ptr null)"));
			}
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/llvm/direct-storage-pointer-transfer-and-stage-lifetime", lowering);
	return Test.run ();
}
}
