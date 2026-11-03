// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Sources {
private void lifetimes() {
	try {
		foreach (string name in fixtures ()) {
			GenericArray<Witness> sources;
			CheckedProgram? checked = fixture (name, out sources);
			var checked_function = WeakRef (checked.functions[0]);
			CoreProgram? core = CoreBuilder.build (checked);
			checked = null;
			assert (checked_function.get () == null);
			CoreVerifier.verify (core);
			core = CoreGenericMonomorphizer.build (core);
			var core_function = WeakRef (core.functions[0]);
			CfgProgram? cfg = CfgBuilder.build (core);
			core = null;
			assert (core_function.get () == null);
			CfgVerifier.verify (cfg);
			assert (CfgFlowChecker.check (cfg).diagnostic == null);
			var cfg_function = WeakRef (cfg.functions[0]);
			SsaProgram? ssa = SsaBuilder.build (cfg);
			cfg = null;
			assert (cfg_function.get () == null);
			SsaVerifier.verify (ssa);
			var ssa_function = WeakRef (ssa.functions[0]);
			NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
			CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
			ssa = null;
			assert (ssa_function.get () == null);
			NativeAbiVerifier.verify (nabi);
			CAbiVerifier.verify (cabi);
			nabi = null;
			cabi = null;
			foreach (var source in sources) {
				assert (source.get () == null);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/pipeline/independent-verification-after-every-predecessor-dies", lifetimes);
	return Test.run ();
}

}
