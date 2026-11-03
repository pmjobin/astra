// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
namespace Astra.Tests.GenericBufferCore {
private SsaProgram lower() throws CoreError, CfgError, SsaError {
	CoreProgram? core = CoreGenericMonomorphizer.build (sample ());
	var core_graph = WeakRef (core);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_graph.get () == null);
	var cfg_graph = WeakRef (cfg);
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_graph.get () == null);
	SsaVerifier.verify (result);
	return result;
}

private void qualify() {
	try {
		for (int variant = 0; variant < 4; variant++) {
			var program = lower ();
			var function = program.functions[1];
			bool changed = false;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					var write = instruction as SsaBufferWriteInstruction;
					if (variant == 0 && instruction is SsaSliceBoundsCheck) {
						block.instructions.remove_index (i);
						changed = true;
						break;
					}
					if (variant == 1 && write != null && write.pair.is_empty) {
						block.instructions.remove_index (i);
						changed = true;
						break;
					}
					if (variant == 2 && write != null && !write.pair.is_empty) {
						var partial = new SsaBufferPair (write.span, write.pair.shape, write.pair.base_value, new SsaIntegerConstant.typed (write.span, write.pair.shape.length_type, Astra.Semantic.AstraIntegerValue.from_int64 (write.pair.shape.length_type, 0)));
						block.instructions[i] = new SsaBufferWriteInstruction (write.span, write.place, partial);
						changed = true;
						break;
					}
				}
				if (variant == 3 && block.terminator is SsaBufferReturn) {
					var returned = (SsaBufferReturn) block.terminator;
					block.instructions.add (new SsaBufferDeallocateInstruction (returned.span, returned.pair, returned.cleanup));
					changed = true;
				}
				if (changed) {
					break;
				}
			}
			assert (changed);
			bool rejected = false;
			try {
				SsaVerifier.verify (program);
			} catch (SsaError error) {
				Test.message ("variant %d: %s", variant, error.message);
				rejected = true;
			}
			assert (rejected);
		}
		SsaVerifier.verify (lower ());
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int run_ssa(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-buffer/ssa/independent-bounds-complete-owner-groups-and-disarming", qualify);
	return Test.run ();
}

}
