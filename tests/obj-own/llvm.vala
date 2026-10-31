// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.ObjectOwn {
private void lowering() {
	try {
		foreach (var name in new string[] { "basic", "consume", "forward", "conditional", "borrow", "borrow-alias", "null", "order", "resource", "method", "constructor", "slice", "vector", "empty", "no-deinit" }) {
			SsaProgram? ssa = build (read (name));
			var declaration = WeakRef (ssa.classes[0]);
			var type = WeakRef (ssa.classes[0].semantic_type);
			var nabi = NativeAbiBuilder.build (ssa);
			var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
			ssa = null;
			assert (declaration.get () == null && type.get () == null);
			artifact.verify ();
			var text = artifact.dump ();
			foreach (var line in text.split ("\n")) {
				if (!line.has_prefix ("define ")) {
					continue;
				}
				foreach (var forbidden in new string[] { "nonnull", "noalias", "readonly", "byval", "sret" }) {
					assert (!line.contains (forbidden));
				}
			}
			foreach (var forbidden in new string[] { "llvm.memcpy", "llvm.memmove", "malloc", "calloc", "realloc", "refcount", "vtable", "owner.active", "alloca i1", "alloca ptr" }) {
				assert (!text.contains (forbidden));
			}
			if (name == "consume") {
				assert (text.contains ("call fastcc void @astra.fn.0(ptr %object0)") && text.contains ("call fastcc void @astra.dtor.0(ptr %p0)") && text.contains ("call fastcc void @astra.dtor.0(ptr null)"));
			}
			if (name == "no-deinit") {
				assert (!text.contains ("@astra.dtor."));
			}
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-own/llvm/original-storage-transfer-cleanup-and-stage-lifetime", lowering);
	return Test.run ();
}
}
