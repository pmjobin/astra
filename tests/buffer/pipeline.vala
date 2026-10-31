// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.BufferPipeline {
private void qualify(string name) {
	try {
		SsaProgram? program = build(name);
		var nabi = NativeAbiBuilder.build(program);
		NativeAbiVerifier.verify(nabi);
		foreach (var cleanup in program.cleanups) {
			if (cleanup.is_buffer) {
				assert(cleanup.buffer_shape.is_valid() && cleanup.external_symbol == "");
			}
		}
		foreach (var function in program.functions) {
			foreach (var group in function.buffer_parameters) {
				assert(group.pair.base_value.semantic_type is RawPointerType && group.pair.length_value.semantic_type is IntegerType);
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaBufferAllocateInstruction) {
						assert(instruction.result == null);
					}
					if (instruction is SsaCallInstruction && ((SsaCallInstruction) instruction).buffer_result != null) {
						assert(instruction.result == null);
					}
				}
			}
		}
		var function = WeakRef(program.functions[0]);
		program = null;
		assert(function.get() == null);
		NativeAbiVerifier.verify(nabi);
	} catch (GLib.Error error) {
		GLib.error("%s: %s", name, error.message);
	}
}
private void fixtures() {
	foreach (string name in new string[] {"param-move", "release", "mixed-call", "empty-field", "basic", "zero", "move", "replace", "borrow", "param", "result", "forward", "field", "field-mixed", "field-move", "deinit", "object-result", "generic-owner", "vector", "integer", "scalars", "cad", "resource-replace", "rearm", "alias", "replace-trap", "field-trap", "deinit-trap", "null-receiver"}) {
		Test.message("fixture %s", name);
		qualify(name);
	}
	try {
		var program = build("param-move");
		bool found = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call == null || call.buffer_arguments.length != 2) {
						continue;
					}
					found = true;
					var first = call.buffer_arguments[0];
					var second = call.buffer_arguments[1];
					call.buffer_arguments[0] = new SsaBufferArgument(first.span, first.parameter, first.pair, second.disarm);
					call.buffer_arguments[1] = new SsaBufferArgument(second.span, second.parameter, second.pair, first.disarm);
				}
			}
		}
		assert(found);
		try {
			SsaVerifier.verify(program);
		} catch (SsaError error) {
			Test.message("swapped source commits: %s", error.message);
			return;
		}
		GLib.error("accepted swapped buffer argument source commits");
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/buffer/pipeline/stage-lifetime-fixtures", fixtures);
	return Test.run();
}
}
