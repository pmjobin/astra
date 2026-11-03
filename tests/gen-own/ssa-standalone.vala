// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
namespace Astra.Tests.GenOwnCore {
private void concrete() {
	try {
		foreach (bool resource in new bool[] {false, true}) {
			CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (sample (resource)));
			var weak = WeakRef (cfg.functions[0]);
			var ssa = SsaBuilder.build (cfg);
			cfg = null;
			assert (weak.get () == null);
			SsaVerifier.verify (ssa);
			string dump = SsaDump.format (ssa);
			assert (!dump.contains ("Ownable") && !dump.contains ("type-parameter"));
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/ssa/concrete-ownership-stage-lifetime", concrete);
	return Test.run ();
}

}
