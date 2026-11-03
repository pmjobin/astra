// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
namespace Astra.Tests.GenCapCore {
private void boundary() {
	try {
		CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (sample (GenericOperationKind.SHIFT_RIGHT, "u32")));
		var weak_function = WeakRef (cfg.functions[1]);
		var ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (weak_function.get () == null);
		SsaVerifier.verify (ssa);
		foreach (var f in ssa.functions) {
			assert (!(f.return_type is TypeParameterType));
			foreach (var p in f.parameters) {
				assert (!(p.semantic_type is TypeParameterType));
			}
		}
		assert (!SsaDump.format (ssa).contains ("generic-op"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-cap/ssa/concrete-only-shift-lifetime", boundary);
	return Test.run ();
}

}
