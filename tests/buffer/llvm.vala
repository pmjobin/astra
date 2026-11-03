// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.BufferPipeline {
private void lowering() {
	try {
		foreach (string name in new string[] {"basic", "zero", "move", "replace", "borrow", "param", "result", "forward", "field", "field-mixed", "deinit", "object-result", "generic-owner", "vector", "scalars", "cad"}) {
			SsaProgram? program = build(name);
			var function = WeakRef(program.functions[0]);
			var nabi = NativeAbiBuilder.build(program);
			var artifact = LlvmLowering.lower(program, nabi, CAbiBuilder.build(program, nabi));
			program = null;
			assert(function.get() == null);
			artifact.verify();
			string text = artifact.dump();
			assert(artifact.requires_hosted_buffers && text.contains("@calloc") && text.contains("@free") && text.contains("llvm.umul.with.overflow.i64") && text.contains("nobuiltin"));
			foreach (string forbidden in new string[] {"llvm.memcpy", "llvm.memmove", "realloc", "alloca i1", "byval", "personality", "landingpad", "invoke "}) {
				assert(!text.contains(forbidden));
			}
			if (name == "result") {
				assert(text.contains("define internal fastcc { ptr, i32 }") && text.contains("extractvalue { ptr, i32 } %buffer.call"));
			}
			var target = new LlvmTargetMachineArtifact();
			target.configure(artifact);
			artifact.verify();
		}
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}

private void targets() {
	try {
		LlvmBufferAllocation.qualify("x86_64-pc-linux-gnu");
	} catch (LlvmError error) {
		GLib.error("%s", error.message);
	}
	foreach (string triple in new string[] {"aarch64-unknown-linux-gnu", "x86_64-pc-windows-msvc", "x86_64-unknown-none", "x86_64-unknown-linux-gnux32", "x86_64-unknown-linux-musl"}) {
		try {
			LlvmBufferAllocation.qualify(triple);
		} catch (LlvmError error) {
			assert(error.message.contains("owned runtime-array allocator is not qualified"));
			continue;
		}
		GLib.error("accepted unqualified allocator target %s", triple);
	}
}

private LlvmModuleArtifact overflow_artifact() throws LlvmError {
	// Physical-stage adversarial layout, never admitted as an Astra element.
	// The ordinary domain max (INT_MAX * 16) cannot overflow hosted size_t.
	var artifact = new LlvmModuleArtifact();
	var i32 = CApi.int32_type_in_context(artifact.context);
	var type = CApi.function_type(i32, null, 0, 0);
	var function = CApi.add_function(artifact.module, "main", type);
	var entry = CApi.append_basic_block_in_context(artifact.context, function, "entry");
	var state = new LlvmBlockState(entry);
	var builder = CApi.create_builder_in_context(artifact.context);
	CApi.position_builder_at_end(builder, entry);
	var scalars = new LlvmScalarLowering(artifact, new LlvmTypeMapper(artifact.context), builder, function);
	var allocator = new LlvmBufferAllocation(artifact, builder, function, scalars);
	allocator.allocate(CApi.const_int(i32, 2147483647, 0), CApi.array_type(i32, ((uint64) 1) << 36), "overflow", state);
	CApi.build_ret(builder, CApi.const_int(i32, 1, 0));
	CApi.dispose_builder(builder);
	var target = new LlvmTargetMachineArtifact();
	target.configure(artifact);
	artifact.verify();
	return artifact;
}

private void overflow() {
	try {
		string text = overflow_artifact().dump();
		assert(text.contains("llvm.umul.with.overflow.i64") && text.contains("overflow.size.trap") && text.contains("[68719476736 x i32]"));
	} catch (LlvmError error) {
		GLib.error("%s", error.message);
	}
}

int main(string[] args) {
	if (args.length == 2 && args[1] == "--dump-overflow") {
		try {
			stdout.puts(overflow_artifact().dump());
			return 0;
		} catch (LlvmError error) {
			stderr.puts(error.message);
			return 1;
		}
	}
	Test.init(ref args);
	Test.add_func("/buffer/llvm/allocation-zero-checks-cleanup-and-stage-lifetime", lowering);
	Test.add_func("/buffer/llvm/hosted-target-gate", targets);
	Test.add_func("/buffer/llvm/independent-checked-byte-size-overflow", overflow);
	return Test.run();
}

}
