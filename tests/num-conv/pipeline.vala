// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.NumericPipeline {
private void lifetime() {
	try {
		foreach (string name in fixtures ()) {
			SsaProgram? ssa = build (name);
			var function = WeakRef (ssa.functions[0]);
			var nabi = NativeAbiBuilder.build (ssa);
			var cabi = CAbiBuilder.build (ssa, nabi);
			ssa = null;
			assert (function.get () == null);
			NativeAbiVerifier.verify (nabi);
			CAbiVerifier.verify (cabi);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/num-conv/pipeline/destroy-predecessors-all-fixtures", lifetime);
	return Test.run ();
}

}
