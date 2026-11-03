// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.OwnSwapSsa {
private SsaProgram model(int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("independent-exchange-ssa", "x"), 0, 1);
	var shape = new BufferValueShape (t.slice_of (t.f64_type), t.raw_pointer_type, t.i32_type);
	var cleanup = new SsaCleanupContract.for_buffer (shape, s, 0);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	var storage = new GenericArray<SsaBufferStorage> ();
	var places = new GenericArray<SsaBufferPlace> ();
	var body = new SsaBlock (s, 0, 0);
	int ordinal = 0;
	for (int i = 0; i < 2; i++) {
		var slot = new SsaBufferStorage (s, cleanup, i, i);
		storage.add (slot);
		var place = new SsaBufferPlace (s, cleanup, slot);
		places.add (place);
		var count = new SsaIntegerConstant.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, variant == -1 ? 0 : i + 2));
		var allocation = new SsaBufferAllocateInstruction (s, count, cleanup, ordinal);
		ordinal += 2;
		body.instructions.add (allocation);
		var initialization = new SsaBufferWriteInstruction (s, place, allocation.pair);
		initialization.initializes = true;
		body.instructions.add (initialization);
	}
	var left = new SsaBufferSlotCaptureInstruction (s, variant == 1 ? new SsaBufferPlace (s, cleanup, new SsaBufferStorage (s, cleanup, 0, 0)) : places[0]);
	var right = new SsaBufferSlotCaptureInstruction (s, variant == 2 ? new SsaBufferPlace (s, new SsaCleanupContract.for_buffer (shape, s, 0), storage[1]) : places[variant == -2 ? 0 : 1]);
	if (variant == 6) {
		var read = new SsaBufferReadInstruction (s, places[0], ordinal);
		ordinal += 2;
		body.instructions.add (read);
		body.instructions.add (new SsaBufferDeallocateInstruction (s, read.pair, cleanup));
	}
	SsaBufferBorrowInstruction? borrow = null;
	if (variant == 9 || variant == 10) {
		var read = new SsaBufferReadInstruction (s, places[variant - 9], ordinal);
		ordinal += 2;
		body.instructions.add (read);
		borrow = new SsaBufferBorrowInstruction (s, read.pair, ordinal++);
		body.instructions.add (borrow);
	}
	if (variant == 4) {
		body.instructions.add (right);
	}
	if (variant != 3) {
		body.instructions.add (left);
	}
	if (variant == 7) {
		var read = new SsaBufferReadInstruction (s, places[0], ordinal);
		ordinal += 2;
		body.instructions.add (read);
		body.instructions.add (new SsaBufferDeallocateInstruction (s, read.pair, cleanup));
	}
	if (variant != 4) {
		body.instructions.add (right);
	}
	body.instructions.add (new SsaBufferExchangeInstruction (s, left, variant == 5 ? left : right));
	if (variant == 8) {
		body.instructions.add (new SsaBufferSlotCaptureInstruction (s, places[0]));
	}
	if (borrow != null) {
		body.instructions.add (new SsaSliceLengthInstruction (s, t.int_type, borrow.result, ordinal++));
	}
	for (int i = 1; i >= 0; i--) {
		var read = new SsaBufferReadInstruction (s, places[i], ordinal);
		ordinal += 2;
		body.instructions.add (read);
		body.instructions.add (new SsaBufferDeallocateInstruction (s, read.pair, cleanup));
	}
	body.complete (new SsaFunctionEnd (s));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (body);
	var function = new SsaFunction (s, s, "exchange", t.void_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, body);
	foreach (var slot in storage) {
		function.buffer_storage.add (slot);
	}
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	return new SsaProgram (s, functions, null, null, null, cleanups);
}

private void positive() {
	try {
		for (int variant = -2; variant <= 0; variant++) {
			SsaProgram? program = model (variant);
			SsaVerifier.verify (program);
			var function = WeakRef (program.functions[0]);
			program = null;
			assert (function.get () == null);
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void negative() {
	string[] reasons = {
		"storage/cleanup identity", "exact storage origin", "each slot capture", "precede and dominate", "precede and dominate", "initialized live owner", "invalidated before exchange", "orphan", "outlives owner", "outlives owner"
	};
	for (int variant = 1; variant <= reasons.length; variant++) {
		try {
			SsaVerifier.verify (model (variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			assert (error.message.contains (reasons[variant - 1]));
			continue;
		}
		GLib.error ("accepted malformed exchange SSA variant %d", variant);
	}
}

private SsaProgram fields(int variant) throws SsaError {
	var t = new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("independent-field-exchange-ssa", "x"), 0, 1);
	var shape = new BufferValueShape (t.slice_of (t.f64_type), t.raw_pointer_type, t.i32_type);
	var cleanup = new SsaCleanupContract.for_buffer (shape, s, 0);
	var cleanups = new GenericArray<SsaCleanupContract> ();
	cleanups.add (cleanup);
	var c = new SsaClass (s, s, "C", new ClassType ("C"));
	for (int i = 0; i < 2; i++) {
		var field = new SsaStructField (s, s, "field%d".printf (i), c, shape.slice_type, i);
		field.owned_cleanup = cleanup;
		c.fields.add (field);
	}
	var functions = new GenericArray<SsaFunction> ();
	for (int lifecycle = 0; lifecycle < 2; lifecycle++) {
		var receiver = new SsaReceiver (s, new ReceiverType (c.semantic_type, lifecycle == 0 ? ReceiverMode.INITIALIZING : ReceiverMode.LIVE), 0);
		var body = new SsaBlock (s, 0, 0);
		var blocks = new GenericArray<SsaBlock> ();
		blocks.add (body);
		int ordinal = 1;
		for (int n = 0; n < 2; n++) {
			int i = lifecycle == 0 ? n : 1 - n;
			var place = new SsaBufferPlace (s, cleanup, null, new SsaIndirectFieldPlace (s, receiver, c.fields[i]));
			if (lifecycle == 0) {
				if (variant == 6 && n == 1) {
					var a = new SsaBufferSlotCaptureInstruction (s, new SsaBufferPlace (s, cleanup, null, new SsaIndirectFieldPlace (s, receiver, c.fields[0])));
					var b = new SsaBufferSlotCaptureInstruction (s, place);
					body.instructions.add (a);
					body.instructions.add (b);
					body.instructions.add (new SsaBufferExchangeInstruction (s, a, b));
				}
				var allocation = new SsaBufferAllocateInstruction (s, new SsaIntegerConstant.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, i + 2)), cleanup, ordinal);
				ordinal += 2;
				body.instructions.add (allocation);
				var write = new SsaBufferWriteInstruction (s, place, allocation.pair);
				write.initializes = true;
				body.instructions.add (write);
			} else {
				var read = new SsaBufferReadInstruction (s, place, ordinal);
				ordinal += 2;
				body.instructions.add (read);
				body.instructions.add (new SsaBufferDeallocateInstruction (s, read.pair, cleanup));
			}
		}
		body.complete (new SsaFunctionEnd (s));
		if (lifecycle == 0) {
			c.constructor = new SsaConstructor (s, s, c, receiver, 2, t.void_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, body);
			functions.add (c.constructor);
		} else {
			c.destructor = new SsaDestructor (s, s, c, receiver, 3, t.void_type, 1, new GenericArray<SsaFunctionParameter> (), blocks, body);
			functions.add (c.destructor);
		}
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	for (int i = 0; i < 2; i++) {
		parameters.add (new SsaFunctionParameter (s, s, "receiver%d".printf (i), c.semantic_type, i, PointerParameterContract.BORROWED_NOESCAPE));
	}
	var body = new SsaBlock (s, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (body);
	var left_check = new SsaObjectValidateInstruction (s, parameters[0], c.semantic_type, 2);
	var right_check = new SsaObjectValidateInstruction (s, parameters[1], c.semantic_type, 3);
	if (variant != 3) {
		body.instructions.add (left_check);
	}
	var left_field = variant == 1 ? new SsaStructField (s, s, "stale", c, shape.slice_type, 0) : c.fields[0];
	var left_place = new SsaBufferPlace (s, cleanup, null, new SsaIndirectFieldPlace (s, variant == 3 ? (SsaValue) parameters[0] : left_check.result, left_field));
	var left = new SsaBufferSlotCaptureInstruction (s, left_place);
	body.instructions.add (left);
	if (variant != 4) {
		body.instructions.add (right_check);
	}
	var right_place = new SsaBufferPlace (s, cleanup, null, new SsaIndirectFieldPlace (s, variant == 4 ? (SsaValue) parameters[1] : right_check.result, c.fields[variant == 2 ? 0 : 1]));
	int ordinal = 4;
	SsaBufferBorrowInstruction? view = null;
	if (variant == 7 || variant == 8 || variant == 9) {
		var place = variant == 7 ? left_place : variant == 8 ? right_place : new SsaBufferPlace (s, cleanup, null, new SsaIndirectFieldPlace (s, right_check.result, c.fields[0]));
		var read = new SsaBufferReadInstruction (s, place, ordinal);
		ordinal += 2;
		body.instructions.add (read);
		view = new SsaBufferBorrowInstruction (s, read.pair, ordinal++);
		body.instructions.add (view);
	}
	if (variant == 5) {
		var read = new SsaBufferReadInstruction (s, left_place, ordinal);
		ordinal += 2;
		body.instructions.add (read);
		body.instructions.add (new SsaBufferDeallocateInstruction (s, read.pair, cleanup));
	}
	if (variant == 10) {
		var cb = new SsaBlock (s, 0, 0);
		cb.complete (new SsaFunctionEnd (s));
		var cb_blocks = new GenericArray<SsaBlock> ();
		cb_blocks.add (cb);
		var cb_parameters = new GenericArray<SsaFunctionParameter> ();
		cb_parameters.add (new SsaFunctionParameter (s, s, "alias", c.semantic_type, 0, PointerParameterContract.BORROWED_NOESCAPE));
		var callback = new SsaFunction (s, s, "replace_through_alias", t.void_type, 3, cb_parameters, cb_blocks, cb);
		functions.add (callback);
		var arguments = new GenericArray<SsaValue> ();
		arguments.add (parameters[1]);
		body.instructions.add (new SsaCallInstruction (s, null, -1, callback, arguments));
	}
	var right = new SsaBufferSlotCaptureInstruction (s, right_place);
	body.instructions.add (right);
	body.instructions.add (new SsaBufferExchangeInstruction (s, left, right));
	if (view != null) {
		body.instructions.add (new SsaSliceLengthInstruction (s, t.int_type, view.result, ordinal++));
	}
	body.complete (new SsaFunctionEnd (s));
	var function = new SsaFunction (s, s, "exchange", t.void_type, 2, parameters, blocks, body);
	functions.insert (2, function);
	var program = new SsaProgram (s, functions, null, null, null, cleanups);
	program.classes.add (c);
	return program;
}

private void field_models() {
	try {
		SsaVerifier.verify (fields (0));
		SsaVerifier.verify (fields (2));
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
	string[] reasons = {
		"exact program-owned", "", "null-validated", "null-validated", "invalidated before exchange", "definite initialization", "outlives owner", "outlives owner", "outlives owner", "invalidated before exchange"
	};
	for (int variant = 1; variant <= reasons.length; variant++) {
		if (variant == 2) {
			continue;
		}
		try {
			SsaVerifier.verify (fields (variant));
		} catch (SsaError error) {
			Test.message ("field variant %d: %s", variant, error.message);
			assert (error.message.contains (reasons[variant - 1]));
			continue;
		}
		GLib.error ("accepted malformed field exchange %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-swap/ssa/independent-live-empty-self", positive);
	Test.add_func ("/own-swap/ssa/capture-membership-order-cleanup-liveness-borrows", negative);
	Test.add_func ("/own-swap/ssa/independent-field-membership-checks-initialization-aliases", field_models);
	return Test.run ();
}

}
