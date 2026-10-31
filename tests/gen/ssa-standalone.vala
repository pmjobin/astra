// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.Semantic;
namespace Astra.Tests.GenCore {
private void boundary() {
	try {
		CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (sample ()));
		var witness = WeakRef (cfg.functions[1]);
		var ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (witness.get () == null);
		SsaVerifier.verify (ssa);
		foreach (var f in ssa.functions) {
			assert (!(f.return_type is TypeParameterType));
			foreach (var p in f.parameters) {
				assert (!(p.semantic_type is TypeParameterType));
			}
		}
		assert (ssa.functions[8].return_type is F64Type);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen/ssa/concrete-scalar-f64-vector-stage-lifetime", boundary);
	return Test.run ();
}
}
