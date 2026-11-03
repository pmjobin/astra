// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
namespace Astra.Tests.GenOwnCore {
private void concrete() {
	try {
		foreach (bool resource in new bool[] {false, true}) {
			CoreProgram? core = CoreGenericMonomorphizer.build (sample (resource));
			var weak = WeakRef (core.functions[0]);
			var cfg = CfgBuilder.build (core);
			core = null;
			assert (weak.get () == null);
			CfgVerifier.verify (cfg);
			foreach (var f in cfg.functions) {
				assert (OwnershipFlow.analyze (f).diagnostic == null);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void firewall() {
	try {
		CfgBuilder.build (sample ());
	} catch (GLib.Error error) {
		assert (error.message.contains ("before CFG"));
		return;
	}
	GLib.error ("accepted unresolved owned T at CFG");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/cfg/concrete-flow-stage-lifetime", concrete);
	Test.add_func ("/gen-own/cfg/unresolved-owner-firewall", firewall);
	return Test.run ();
}

}
