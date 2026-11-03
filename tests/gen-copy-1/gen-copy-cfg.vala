// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
namespace Astra.Tests.GenericCopyCore {
private CfgProgram lower() throws CoreError, CfgError {
	CoreProgram? core = CoreGenericMonomorphizer.build (sample ());
	var before = WeakRef (core);
	var definition = WeakRef (core.functions[1]);
	var cfg = CfgBuilder.build (core);
	core = null;
	assert (before.get () == null && definition.get () == null);
	CfgVerifier.verify (cfg);
	return cfg;
}

private void qualify() {
	try {
		var program = lower ();
		assert (program.functions[1].struct_parameters.length == 1 && program.functions[1].struct_result != null && program.functions[1].parameters.length == 1);
		for (int variant = 0; variant < 4; variant++) {
			program = lower ();
			var function = program.functions[1];
			if (variant == 0) {
				function.entry.instructions.remove_index (0);
			}
			if (variant == 1) {
				function.struct_parameters.remove_index (0);
			}
			if (variant == 2) {
				foreach (var instruction in program.functions[0].entry.instructions) {
					if (instruction is CfgStructResultConsume) {
						program.functions[0].entry.instructions.add (instruction);
						break;
					}
				}
			}
			if (variant == 3) {
				function.struct_result = null;
			}
			bool rejected = false;
			try {
				CfgVerifier.verify (program);
			} catch (CfgError error) {
				rejected = true;
			}
			assert (rejected);
		}
		CfgVerifier.verify (lower ());
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int run_cfg(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-copy/cfg/independent-source-and-complete-parameter-producer-contracts", qualify);
	return Test.run ();
}

}
