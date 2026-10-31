// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.Semantic;
namespace Astra.Tests.GenStructCore {
private void boundary() {
	try {
		foreach (bool addressed in new bool[] {false, true}) {
			CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (sample (addressed)));
			var witness = WeakRef (cfg.structs[0]);
			var ssa = SsaBuilder.build (cfg);
			cfg = null;
			assert (witness.get () == null);
			SsaVerifier.verify (ssa);
			assert (ssa.functions[0].storage.length == (addressed ? 1 : 0));
			if (!addressed) {
				assert (ssa.structs.length == 0);
			}
			for (int f = 1; f < ssa.functions.length; f++) {
				assert (ssa.functions[f].storage.length == 0);
			}
			int vectors = 0;
			foreach (var function in ssa.functions) {
				assert (!function.return_type.is_struct_storage () && !(function.return_type is TypeParameterType));
				if (function.return_type is VectorType) {
					vectors++;
				}
				foreach (var block in function.blocks) {
					foreach (var parameter in block.parameters) {
						assert (!parameter.semantic_type.is_struct_storage () && !(parameter.semantic_type is TypeParameterType));
					}
				}
			}
			assert (vectors == 2);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-struct/ssa/scalar-vector-mask-nested-promotion-addressability-lifetime", boundary);
	return Test.run ();
}
}
