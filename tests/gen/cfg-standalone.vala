// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Semantic;
namespace Astra.Tests.GenCore {
private void boundary() {
	try {
		bool rejected = false;
		try {
			CfgBuilder.build (sample ());
		} catch (CfgError error) {
			rejected = error.message.contains ("before CFG");
		}
		assert (rejected);
		CoreProgram? core = CoreGenericMonomorphizer.build (sample ());
		var witness = WeakRef (core.functions[1]);
		var cfg = CfgBuilder.build (core);
		core = null;
		assert (witness.get () == null);
		CfgVerifier.verify (cfg);
		foreach (var f in cfg.functions) {
			assert (!(f.return_type is TypeParameterType));
			foreach (var p in f.parameters) {
				assert (!(p.semantic_type is TypeParameterType));
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen/cfg/concrete-only-firewall-stage-lifetime", boundary);
	return Test.run ();
}

}
