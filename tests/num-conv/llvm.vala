// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.NumericPipeline {
private void lowering() {
	try {
		foreach (string name in fixtures ()) {
			SsaProgram? ssa = build (name);
			var function = WeakRef (ssa.functions[0]);
			var nabi = NativeAbiBuilder.build (ssa);
			var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
			ssa = null;
			assert (function.get () == null);
			artifact.verify ();
			string text = artifact.dump ();
			if (name.has_prefix ("int-")) {
				assert (text.contains ("sitofp") && text.contains ("uitofp") && !text.contains ("llvm.trap"));
			}
			if (name.has_suffix ("-int")) {
				assert (text.contains ("fptosi") && text.contains ("fptoui") && text.contains ("fcmp ogt") && text.contains ("fcmp olt") && text.contains ("llvm.trap") && text.contains (".valid:"));
			}
			if (name == "literals") {
				assert (text.contains ("0x3FF0000000000001"));
			}
			foreach (string forbidden in new string[] {" fast ", " nsz ", " nnan ", " ninf ", " contract ", "llvm.fma", "personality", "landingpad"}) {
				assert (!text.contains (forbidden));
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/num-conv/llvm/exact-opcodes-guards-stage-lifetime", lowering);
	return Test.run ();
}
}
