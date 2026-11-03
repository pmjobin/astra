// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.BufferSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var t = new BuiltinTypes();
	var span = SourceSpan(new SourceFile.from_text("buffer-ssa", "x"), 0, 1);
	var slice = variant == 1 ? new SliceType(new ClassType("C")) : t.slice_of(t.f64_type);
	var shape = new BufferValueShape(slice, t.raw_pointer_type, (IntegerType) (variant == 2 ? t.u32_type : t.int_type));
	var cleanup = new SsaCleanupContract.for_buffer(shape, span, 0);
	var cleanups = new GenericArray<SsaCleanupContract>();
	cleanups.add(cleanup);
	SsaValue count = variant == 3 ? (SsaValue) new SsaBooleanConstant(span, t.bool_type, BooleanLiteral.TRUE) : new SsaIntegerConstant.typed(span, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, variant == 4 ? -1 : 3));
	var allocation = new SsaBufferAllocateInstruction(span, count, cleanup, 0);
	var block = new SsaBlock(span, 0, 0);
	block.instructions.add(allocation);
	var slot = new SsaBufferStorage(span, cleanup, 0, 0);
	var place = new SsaBufferPlace(span, cleanup, slot);
	var initialization = new SsaBufferWriteInstruction(span, place, allocation.pair);
	initialization.initializes = true;
	if (variant != 5 && variant != 14) {
		block.instructions.add(initialization);
	}
	if (variant == 6) {
		block.instructions.add(new SsaBufferWriteInstruction(span, place, allocation.pair));
	}
	var read = new SsaBufferReadInstruction(span, place, 2);
	block.instructions.add(read);
	SsaBufferStorage? destination = null;
	if (variant == 15) {
		// A different read can destroy the captured allocation before a later
		// transfer. Pair identity alone cannot prove the capture stays live.
		var dying = new SsaBufferReadInstruction(span, place, 4);
		block.instructions.add(dying);
		block.instructions.add(new SsaBufferDeallocateInstruction(span, dying.pair, cleanup));
		block.instructions.add(new SsaBufferWriteInstruction(span, place, new SsaBufferPair.empty(span, shape)));
		destination = new SsaBufferStorage(span, cleanup, 1, 1);
		var target = new SsaBufferPlace(span, cleanup, destination);
		var transfer = new SsaBufferWriteInstruction(span, target, read.pair);
		transfer.initializes = true;
		block.instructions.add(transfer);
		var installed = new SsaBufferReadInstruction(span, target, 6);
		block.instructions.add(installed);
		block.instructions.add(new SsaBufferDeallocateInstruction(span, installed.pair, cleanup));
	}
	var pair = variant == 7 ? new SsaBufferPair(span, shape, read.pair.base_value, allocation.pair.length_value) : variant == 8 ? new SsaBufferPair(span, shape, new SsaNullPointerConstant(span, t.raw_pointer_type), new SsaIntegerConstant.typed(span, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, 1))) : read.pair;
	if (variant != 10 && variant != 12 && variant != 15) {
		block.instructions.add(new SsaBufferDeallocateInstruction(span, pair, cleanup));
	}
	if (variant == 11) {
		var second = new SsaBufferReadInstruction(span, place, 4);
		block.instructions.add(second);
		block.instructions.add(new SsaBufferDeallocateInstruction(span, second.pair, cleanup));
	}
	if (variant == 12) {
		block.instructions.add(new SsaBufferWriteInstruction(span, place, new SsaBufferPair.empty(span, shape)));
	}
	if (variant == 13) {
		block.instructions.add(new SsaBufferBorrowInstruction(span, read.pair, 4));
	}
	if (variant == 14) {
		block.instructions.add(initialization);
	}
	if (variant == 9) {
		block.instructions.add(new SsaBufferDeallocateInstruction(span, pair, cleanup));
	}
	block.complete(new SsaFunctionEnd(span));
	var blocks = new GenericArray<SsaBlock>();
	blocks.add(block);
	var function = new SsaFunction(span, span, "run", t.void_type, 0, new GenericArray<SsaFunctionParameter>(), blocks, block);
	function.buffer_storage.add(slot);
	if (destination != null) {
		function.buffer_storage.add(destination);
	}
	var functions = new GenericArray<SsaFunction>();
	functions.add(function);
	return new SsaProgram(span, functions, null, null, null, cleanups);
}

private void positive() {
	try {
		SsaProgram? program = sample();
		SsaVerifier.verify(program);
		assert(SsaDump.format(program).contains("PTR+I32"));
		var function = WeakRef(program.functions[0]);
		program = null;
		assert(function.get() == null);
	} catch (SsaError error) {
		GLib.error("%s", error.message);
	}
}

private void negative() {
	for (int variant = 1; variant <= 15; variant++) {
		try {
			SsaVerifier.verify(sample(variant));
		} catch (SsaError error) {
			Test.message("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed SSA buffer %d", variant);
	}
}

private SsaProgram fields(int variant = 0) throws SsaError {
	var t = new BuiltinTypes();
	var s = SourceSpan(new SourceFile.from_text("buffer-field-ssa", "C"), 0, 1);
	var r = new HandleType("R");
	var resource = new SsaCleanupContract("release", s, 0);
	var shape = new BufferValueShape(t.slice_of(t.f64_type), t.raw_pointer_type, (IntegerType) t.int_type);
	var buffer = new SsaCleanupContract.for_buffer(shape, s, 1);
	var cleanups = new GenericArray<SsaCleanupContract>();
	cleanups.add(resource);
	cleanups.add(buffer);
	var handles = new GenericArray<SsaHandle>();
	handles.add(new SsaHandle(s, s, r, resource, null, 0));
	var c = new SsaClass(s, s, "C", new ClassType("C"));
	for (int i = 0; i < 4; i++) {
		var field = new SsaStructField(s, s, "field" + i.to_string(), c, i % 2 == 0 ? (SemanticType) r : shape.slice_type, i);
		field.owned_cleanup = i % 2 == 0 ? resource : buffer;
		c.fields.add(field);
	}
	var receiver = new SsaReceiver(s, new ReceiverType(c.semantic_type, ReceiverMode.INITIALIZING), 0);
	var body = new SsaBlock(s, 0, 0);
	var blocks = new GenericArray<SsaBlock>();
	blocks.add(body);
	int ordinal = 1;
	foreach (var field in c.fields) {
		var place = new SsaIndirectFieldPlace(s, receiver, field);
		if (field.semantic_type is HandleType) {
			body.instructions.add(new SsaInitializeInstruction(s, place, new SsaNullPointerConstant(s, r)));
			continue;
		}
		var count = new SsaIntegerConstant.typed(s, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, 3));
		var allocation = new SsaBufferAllocateInstruction(s, count, buffer, ordinal);
		ordinal += 2;
		body.instructions.add(allocation);
		var write = new SsaBufferWriteInstruction(s, new SsaBufferPlace(s, buffer, null, place), allocation.pair);
		write.initializes = true;
		body.instructions.add(write);
	}
	body.complete(new SsaFunctionEnd(s));
	var ctor = new SsaConstructor(s, s, c, receiver, 4, t.void_type, 0, new GenericArray<SsaFunctionParameter>(), blocks, body);
	c.constructor = ctor;
	var live = new SsaReceiver(s, new ReceiverType(c.semantic_type), 0);
	var dbody = new SsaBlock(s, 0, 0);
	var dblocks = new GenericArray<SsaBlock>();
	dblocks.add(dbody);
	ordinal = 1;
	for (int i = 3; i >= 0; i--) {
		if (variant == 1 && i == 1) {
			continue;
		}
		var field = c.fields[variant == 2 ? 3 - i : i];
		var place = new SsaIndirectFieldPlace(s, live, field);
		if (field.semantic_type is HandleType) {
			var load = new SsaLoadInstruction(s, place, ordinal++);
			dbody.instructions.add(load);
			dbody.instructions.add(new SsaCleanupInstruction(s, load.result, resource));
		} else {
			var read = new SsaBufferReadInstruction(s, new SsaBufferPlace(s, buffer, null, place), ordinal);
			ordinal += 2;
			dbody.instructions.add(read);
			dbody.instructions.add(new SsaBufferDeallocateInstruction(s, read.pair, variant == 3 ? resource : buffer));
		}
	}
	dbody.complete(new SsaFunctionEnd(s));
	var dtor = new SsaDestructor(s, s, c, live, 5, t.void_type, 1, new GenericArray<SsaFunctionParameter>(), dblocks, dbody);
	c.destructor = dtor;
	var functions = new GenericArray<SsaFunction>();
	functions.add(ctor);
	functions.add(dtor);
	var program = new SsaProgram(s, functions, null, null, null, cleanups, handles);
	program.classes.add(c);
	return program;
}

private void mixed_fields() {
	try {
		SsaVerifier.verify(fields());
	} catch (SsaError error) {
		GLib.error("%s", error.message);
	}
	for (int variant = 1; variant <= 3; variant++) {
		try {
			SsaVerifier.verify(fields(variant));
		} catch (SsaError error) {
			Test.message("mixed field variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed mixed field cleanup %d", variant);
	}
}

int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/buffer/ssa/independent-ptr-i32-memory-and-cleanup", positive);
	Test.add_func("/buffer/ssa/reject-half-mismatched-copied-or-unowned-groups", negative);
	Test.add_func("/buffer/ssa/independent-mixed-field-cleanup", mixed_fields);
	return Test.run();
}

}
