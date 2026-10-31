// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.ParamBorrow {
private void lifetime() {
	try {
		foreach (string name in fixtures ()) {
			CoreProgram? core = CoreBuilder.build (fixture (name));
			CfgProgram? cfg = CfgBuilder.build (core);
			core = null;
			SsaProgram? ssa = SsaBuilder.build (cfg);
			cfg = null;
			var function = WeakRef (ssa.functions[0]);
			var file = WeakRef (ssa.span.file);
			NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
			CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
			var artifact = LlvmLowering.lower (ssa, nabi, cabi);
			ssa = null;
			nabi = null;
			cabi = null;
			assert (function.get () == null && file.get () == null);
			artifact.verify ();
			foreach (var line in artifact.dump ().split ("\n")) {
				if (!line.has_prefix ("define ")) {
					continue;
				}
				foreach (var forbidden in new string[] { "noalias", "readonly", "nocapture", "nonnull" }) {
					assert (!line.contains (forbidden));
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/param-borrow/llvm/destroy-all-predecessors-no-borrow-attributes", lifetime);
	return Test.run ();
}
}
