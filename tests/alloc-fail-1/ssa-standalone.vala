// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.AllocationFailureSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("independent-failure-ssa", "x"), 0, 1);
	var slice = types.slice_of (types.f64_type);
	var cleanup = new SsaCleanupContract.for_buffer (new BufferValueShape (slice, types.raw_pointer_type, types.i32_type), span, 0);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	var functions = new GenericArray<SsaFunction> ();
	var zero = new SsaIntegerConstant.typed (span, types.int_type, AstraIntegerValue.from_int64 (types.i32_type, 0));
	for (int i = 0; i < 2; i++) {
		var block = new SsaBlock (span, 0, 0);
		block.complete (variant == 3 && i == 0 ? (SsaTerminator) new SsaReturn (span, zero) : new SsaFunctionEnd (span));
		var blocks = new GenericArray<SsaBlock> ();
		blocks.add (block);
		functions.add (new SsaFunction (span, span, "report" + i.to_string (), variant == 3 && i == 0 ? types.int_type : types.void_type, i, new GenericArray<SsaFunctionParameter> (), blocks, block));
	}
	var entry = new SsaBlock (span, 0, 0);
	var success = new SsaBlock (span, 1, 1);
	var failed = new SsaBlock (span, 2, 2);
	var failure = new SsaAllocationFailure (span, functions[0], null);
	var call = new SsaCallInstruction (span, null, -1, functions[variant == 2 ? 1 : 0], new GenericArray<SsaValue> ());
	failure.action = call;
	var allocation = new SsaBufferAllocateInstruction (span, zero, cleanup, 0, failure);
	if (variant == 8) {
		entry.instructions.add (allocation);
	} else {
		success.instructions.add (allocation);
	}
	var pair = variant == 10 ? new SsaBufferPair (span, cleanup.buffer_shape, new SsaNullPointerConstant (span, types.raw_pointer_type), new SsaIntegerConstant.typed (span, types.int_type, AstraIntegerValue.from_int64 (types.i32_type, 2))) : allocation.pair;
	success.complete (new SsaBufferReturn (span, pair, cleanup));
	if (variant == 7) {
		entry.instructions.add (call);
	} else if (variant != 1) {
		failed.instructions.add (call);
	}
	if (variant == 11) {
		failed.instructions.insert (0, new SsaBufferDeallocateInstruction (span, new SsaBufferPair.empty (span, cleanup.buffer_shape), cleanup));
	}
	var fallback = variant == 9 ? new SsaAllocationFailure (span, functions[0], null) : failure;
	failed.complete (variant == 5 ? (SsaTerminator) new SsaBranch (span, new SsaEdge (success, new GenericArray<SsaValue> ())) : variant == 6 ? (SsaTerminator) new SsaFunctionEnd (span) : variant == 12 ? (SsaTerminator) new SsaBranch (span, new SsaEdge (failed, new GenericArray<SsaValue> ())) : new SsaAllocationFailureTrap (span, fallback));
	entry.complete (variant == 4 ? (SsaTerminator) new SsaBranch (span, new SsaEdge (failed, new GenericArray<SsaValue> ())) : new SsaBufferAllocationBranch (span, allocation, new SsaEdge (success, new GenericArray<SsaValue> ()), new SsaEdge (failed, new GenericArray<SsaValue> ())));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (entry);
	blocks.add (success);
	blocks.add (failed);
	functions.add (new SsaFunction (span, span, "make", slice, 2, new GenericArray<SsaFunctionParameter> (), blocks, entry, cleanup));
	return new SsaProgram (span, functions, null, null, null, cleanups);
}

private void qualify() {
	try {
		SsaProgram? program = sample ();
		SsaVerifier.verify (program);
		var graph = WeakRef (program.functions[2]);
		program = null;
		assert (graph.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant <= 12; variant++) {
		bool rejected = false;
		try {
			SsaVerifier.verify (sample (variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/alloc-fail/ssa/independent-cause-pairs-and-terminal-region", qualify);
	return Test.run ();
}

}
