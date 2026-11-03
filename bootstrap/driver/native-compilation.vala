// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Backend.LLVM;

namespace Astra.Driver {
public class NativeCompilation : Object {
	public static void emit(LlvmModuleArtifact artifact, string output_path, LinkInput[]? link_inputs = null, int optimization_level = 0, bool object_only = false, bool entry_object = false, string? selected_target = null) throws LlvmError, ExecutionError {
		var target = new LlvmTargetMachineArtifact (optimization_level, selected_target);
		if (object_only && !entry_object) {
			target.configure (artifact);
		} else {
			artifact.configure_executable (target);
		}
		var output = new ExecutableOutput (output_path);
		target.emit_object (artifact, output.object_path);
		if (object_only) {
			output.commit_object ();
		} else {
			output.link_and_commit (null, null, link_inputs);
		}
	}

}
}
