// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.AllocationFailureCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("independent-failure-cfg", "x"), 0, 1);
	var slice = types.slice_of (types.f64_type);
	var cleanup = new CfgCleanupContract.for_buffer (new BufferValueShape (slice, types.raw_pointer_type, types.i32_type), span, 0);
	var cleanups = new GenericArray<CfgCleanupContract> ();
	cleanups.add (cleanup);
	var functions = new GenericArray<CfgFunction> ();
	var zero = new CfgIntegerValue.typed (span, types.int_type, AstraIntegerValue.from_int64 (types.i32_type, 0));
	for (int i = 0; i < 2; i++) {
		var block = new CfgBlock.reserve (span, 0);
		block.complete (span, variant == 3 && i == 0 ? (CfgTerminator) new CfgReturn (span, zero) : new CfgFunctionEnd (span));
		var blocks = new GenericArray<CfgBlock> ();
		blocks.add (block);
		functions.add (new CfgFunction (span, span, "report" + i.to_string (), variant == 3 && i == 0 ? types.int_type : types.void_type, i, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, block));
	}
	var entry = new CfgBlock.reserve (span, 0);
	var success = new CfgBlock.reserve (span, 1);
	var failed = new CfgBlock.reserve (span, 2);
	var count = new CfgEvaluatedValue (span, types.int_type);
	entry.instructions.add (new CfgEvaluateInstruction (span, zero, count));
	var failure = new CfgAllocationFailure (span, functions[0], null);
	var call = new CfgCallInstruction (span, functions[variant == 2 ? 1 : 0], new GenericArray<CfgValue> (), null);
	failure.action = call;
	var allocation = new CfgBufferAllocate (span, variant == 10 ? (CfgValue) zero : count, cleanup, failure);
	var returned = new CfgOwnedReturnValue (span, slice, cleanup, null, allocation.results.owner);
	if (variant == 8) {
		entry.instructions.add (allocation);
	} else {
		success.instructions.add (allocation);
	}
	success.instructions.add (new CfgOwnershipReturnInstruction (span, returned));
	success.complete (span, new CfgOwnershipReturn (span, returned));
	if (variant == 7) {
		entry.instructions.add (call);
	} else if (variant != 1) {
		failed.instructions.add (call);
	}
	if (variant == 11) {
		failed.instructions.insert (0, new CfgCleanupInstruction (span, new CfgNullPointerValue (span, types.raw_pointer_type), cleanup));
	}
	var fallback = variant == 9 ? new CfgAllocationFailure (span, functions[0], null) : failure;
	failed.complete (span, variant == 5 ? (CfgTerminator) new CfgBranch (span, success) : variant == 6 ? (CfgTerminator) new CfgFunctionEnd (span) : variant == 12 ? (CfgTerminator) new CfgBranch (span, failed) : new CfgAllocationFailureTrap (span, fallback));
	entry.complete (span, variant == 4 ? (CfgTerminator) new CfgBranch (span, failed) : new CfgBufferAllocationBranch (span, allocation, success, failed));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (entry);
	blocks.add (success);
	blocks.add (failed);
	functions.add (new CfgFunction (span, span, "make", slice, 2, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, entry, cleanup));
	return new CfgProgram (span, functions, null, null, null, cleanups);
}

private void qualify() {
	try {
		CfgProgram? program = sample ();
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		var graph = WeakRef (program.functions[2]);
		program = null;
		assert (graph.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant <= 12; variant++) {
		bool rejected = false;
		try {
			CfgVerifier.verify (sample (variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/alloc-fail/cfg/independent-cause-publication-and-terminal-region", qualify);
	return Test.run ();
}

}
