// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
namespace Astra.Tests.GenericBufferCore {
private CfgProgram lower() throws CoreError, CfgError {
	CoreProgram? core = CoreGenericMonomorphizer.build (sample ());
	var graph = WeakRef (core);
	var cfg = CfgBuilder.build (core);
	core = null;
	assert (graph.get () == null);
	CfgVerifier.verify (cfg);
	return cfg;
}

private void qualify() {
	try {
		for (int variant = 0; variant < 2; variant++) {
			var program = lower ();
			var function = program.functions[1];
			bool changed = false;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					if ((variant == 0 && block.instructions[i] is CfgSliceBoundsCheck) || (variant == 1 && block.instructions[i] is CfgInitialize)) {
						block.instructions.remove_index (i);
						changed = true;
						break;
					}
				}
				if (changed) {
					break;
				}
			}
			assert (changed);
			bool rejected = false;
			try {
				CfgVerifier.verify (program);
				if (CfgFlowChecker.check (program).diagnostic != null) {
					rejected = true;
				}
			} catch (CfgError error) {
				Test.message ("variant %d: %s", variant, error.message);
				rejected = true;
			}
			assert (rejected);
		}
		assert (CfgFlowChecker.check (lower ()).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int run_cfg(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-buffer/cfg/independent-bounds-owner-acquisition-and-lifetimes", qualify);
	return Test.run ();
}

}
