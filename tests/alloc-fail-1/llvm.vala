// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.AllocationFailure {
private void lifetime() {
	try {
		SsaProgram? ssa = build (SOURCE);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
		var source = WeakRef (ssa.span.file);
		var graph = WeakRef (ssa);
		var plans = WeakRef (native);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		assert (source.get () == null && graph.get () == null && plans.get () == null);
		artifact.verify ();
		new LlvmTargetMachineArtifact ().configure (artifact);
		artifact.verify ();
		string ir = artifact.dump ();
		assert (ir.contains ("@calloc") && ir.contains ("@free") && ir.contains ("nobuiltin") && ir.contains ("@llvm.trap") && ir.contains ("unreachable"));
		foreach (string forbidden in new string[] {"noalias", "@malloc", "byval", "sret", "allocsize", "allockind"}) {
			assert (!ir.contains (forbidden));
		}
		// LLVM arithmetic intrinsics have their ordinary attributes. The
		// application action has none of their purity/termination promises.
		foreach (string line in ir.split ("\n")) {
			if (line.contains ("@output(")) {
				assert (!line.contains (" #") && !line.contains ("noreturn") && !line.contains ("memory("));
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
// Existing internal target-layout seam, never a source element admission.
private LlvmModuleArtifact physical(string mode) throws LlvmError {
	var artifact = new LlvmModuleArtifact ();
	var i32 = CApi.int32_type_in_context (artifact.context);
	var type = CApi.function_type (i32, null, 0, 0);
	var function = CApi.add_function (artifact.module, "main", type);
	var entry = CApi.append_basic_block_in_context (artifact.context, function, "entry");
	var failure = CApi.append_basic_block_in_context (artifact.context, function, "allocator.null.action");
	var state = new LlvmBlockState (entry);
	var failed = new LlvmBlockState (failure);
	var builder = CApi.create_builder_in_context (artifact.context);
	CApi.position_builder_at_end (builder, entry);
	var scalars = new LlvmScalarLowering (artifact, new LlvmTypeMapper (artifact.context), builder, function);
	var allocation = new LlvmBufferAllocation (artifact, builder, function, scalars);
	var element = CApi.array_type (CApi.int_type_in_context (artifact.context, 8), ((uint64) 1) << 60);
	int64 count = mode == "empty" ? 0 : mode == "negative" ? -1 : mode == "unsigned" ? 32 : 8;
	allocation.allocate (CApi.const_int (i32, (uint64) count, 1), element, "record", state, true, failed);
	CApi.build_ret (builder, CApi.const_int (i32, 0, 0));
	CApi.position_builder_at_end (builder, failure);
	var action_type = CApi.function_type (CApi.void_type_in_context (artifact.context), null, 0, 0);
	var action = CApi.add_function (artifact.module, "unexpected_failure_action", action_type);
	CApi.build_call (builder, action_type, action, null, 0, "");
	scalars.emit_trap ();
	CApi.dispose_builder (builder);
	new LlvmTargetMachineArtifact ().configure (artifact);
	artifact.verify ();
	return artifact;
}
int main(string[] args) {
	if (args.length == 3 && args[1] == "--physical") {
		try {
			stdout.puts (physical (args[2]).dump ());
			return 0;
		} catch (GLib.Error error) {
			stderr.printf ("%s\n", error.message);
			return 1;
		}
	}
	Test.init (ref args);
	Test.add_func ("/alloc-fail/llvm/lifetimes-attributes-and-fatal-fallback", lifetime);
	return Test.run ();
}
}
