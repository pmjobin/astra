// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
namespace Astra.Tests.GenericSliceCore {
private SsaProgram lower() throws CoreError, CfgError, SsaError {
	CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (sample ()));
	var before = WeakRef (cfg);
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (before.get () == null);
	SsaVerifier.verify (result);
	return result;
}

private void qualify() {
	try {
		var program = lower ();
		assert (program.functions[1].storage.length == 0 && program.functions[1].struct_parameters.length == 1);
		for (int variant = 0; variant < 4; variant++) {
			program = lower ();
			var function = program.functions[1];
			if (variant == 0) {
				function.struct_parameters.remove_index (0);
			}
			if (variant == 1) {
				function.struct_result = null;
			}
			if (variant == 2) {
				program.functions.remove_index (1);
			}
			if (variant == 3) {
				bool removed = false;
				foreach (var block in function.blocks) {
					for (int i = 0; i < block.instructions.length; i++) {
						if (block.instructions[i] is SsaSliceBoundsCheck) {
							block.instructions.remove_index (i);
							removed = true;
							break;
						}
					}
					if (removed) {
						break;
					}
				}
				assert (removed);
			}
			bool rejected = false;
			try {
				SsaVerifier.verify (program);
			} catch (SsaError error) {
				rejected = true;
			}
			assert (rejected);
		}
		SsaVerifier.verify (lower ());
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-slice/ssa/independent-erasure-scalarization-and-exact-boundary-groups", qualify);
	return Test.run ();
}

}
