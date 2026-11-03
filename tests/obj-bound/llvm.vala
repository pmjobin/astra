// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.ObjectBound {
private void lowering() {
	try {
		foreach (var name in new string[] { "basic", "mutate", "null", "alias", "copy", "forward", "recurse", "method", "struct-method", "constructor", "life", "slice", "vector", "owned", "empty", "null-field", "null-write", "null-method" }) {
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
				foreach (var forbidden in new string[] { "nonnull", "noalias", "readonly", "byval", "sret", "dereferenceable", "nocapture" }) {
					assert (!line.contains (forbidden));
				}
			}
			foreach (var forbidden in new string[] { "llvm.memcpy", "llvm.memmove", "malloc", "calloc", "refcount", "vtable", "typeinfo", "borrow.token" }) {
				assert (!text.contains (forbidden));
			}
			if (name == "basic") {
				assert (text.contains ("define internal fastcc i32 @astra.fn.0(ptr %p0)") && text.contains ("icmp eq ptr %p0, null"));
			}
			if (name == "null") {
				assert (!text.contains ("@llvm.trap"));
			}
			if (name == "method") {
				assert (text.contains ("@astra.class.method.0.0(ptr %p0, ptr %p0)"));
			}
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/llvm/ordinary-nullable-pointer-no-attributes-and-upstream-release", lowering);
	return Test.run ();
}

}
