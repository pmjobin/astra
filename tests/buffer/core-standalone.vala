// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.BufferCore {
private CoreProgram sample(int variant = 0) {
	var t = new BuiltinTypes();
	var span = SourceSpan(new SourceFile.from_text("buffer-core", "x"), 0, 1);
	var slice = variant == 1 ? new SliceType(new ClassType("C")) : t.slice_of(t.f64_type);
	var shape = new BufferValueShape(slice, t.raw_pointer_type, (IntegerType) (variant == 2 ? t.u32_type : t.int_type));
	var cleanup = new CoreCleanupContract.for_buffer(shape, span, 0);
	var cleanups = new GenericArray<CoreCleanupContract>();
	cleanups.add(cleanup);
	CoreValue count = variant == 3 ? (CoreValue) new CoreBooleanValue(span, t.bool_type, BooleanLiteral.TRUE) : new CoreIntegerValue.typed(span, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, variant == 4 ? -1 : 3));
	var allocation = new CoreOwnedBufferAllocate(span, slice, count, cleanup);
	var body = new CoreBlock(span, new GenericArray<CoreStatement>());
	body.statements.add(new CoreOwnershipReturn(span, slice, cleanup, null, variant == 5 ? null : (CoreValue) allocation));
	var function = new CoreFunction(span, span, "make", slice, new GenericArray<CoreParameter>(), new GenericArray<CoreLocalPlace>(), body, variant == 6 ? null : cleanup);
	var functions = new GenericArray<CoreFunction>();
	functions.add(function);
	return new CoreProgram(span, functions, null, null, null, cleanups);
}

private void positive() {
	try {
		CoreProgram? program = sample();
		CoreVerifier.verify(program);
		string dump = CoreDump.format(program);
		assert(dump.contains("owned-buffer-allocate") && !dump.contains("calloc") && !dump.contains("free"));
		var function = WeakRef(program.functions[0]);
		program = null;
		assert(function.get() == null);
	} catch (CoreError error) {
		GLib.error("%s", error.message);
	}
}

private void negative() {
	for (int variant = 1; variant <= 6; variant++) {
		try {
			CoreVerifier.verify(sample(variant));
		} catch (CoreError error) {
			Test.message("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed Core buffer %d", variant);
	}
}

private CoreProgram local_flow(int variant = 0) {
	var t = new BuiltinTypes();
	var s = SourceSpan(new SourceFile.from_text("buffer-core-owner", "x"), 0, 1);
	var shape = new BufferValueShape(t.slice_of(t.f64_type), t.raw_pointer_type, (IntegerType) t.int_type);
	var cleanup = new CoreCleanupContract.for_buffer(shape, s, 0);
	var cleanups = new GenericArray<CoreCleanupContract>();
	cleanups.add(cleanup);
	var parameters = new GenericArray<CoreParameter>();
	parameters.add(new CoreParameter(s, s, "view", shape.slice_type, 0, PointerParameterContract.BORROWED_NOESCAPE));
	var use = new CoreFunction(s, s, "use", t.void_type, parameters, new GenericArray<CoreLocalPlace>(), new CoreBlock(s, new GenericArray<CoreStatement>()));
	var body = new CoreBlock(s, new GenericArray<CoreStatement>());
	var locals = new GenericArray<CoreLocalPlace>();
	locals.add(new CoreLocalPlace(s, s, "a", shape.slice_type, 0));
	locals.add(new CoreLocalPlace(s, s, "b", shape.slice_type, 1));
	var a = new CoreOwnedLocal(s, locals[0], cleanup, body);
	var b = new CoreOwnedLocal(s, locals[1], cleanup, body);
	var count = new CoreIntegerValue.typed(s, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, 3));
	var allocation = new CoreOwnedBufferAllocate(s, shape.slice_type, count, cleanup);
	body.statements.add(new CoreInitialize(s, a.place, allocation, a));
	var args = new GenericArray<CoreValue>();
	args.add(variant == 3 ? (CoreValue) new CoreOwnedBufferAllocate(s, shape.slice_type, count, cleanup) : new CoreOwnedBufferBorrow(s, a, parameters[0]));
	body.statements.add(new CoreCallStatement(s, use, args));
	if (variant == 1 || variant == 2) {
		body.statements.add(new CoreInitialize(s, b.place, variant == 1 ? (CoreValue) new CoreLoadValue(s, a.place) : new CoreOwnedBufferBorrow(s, a, null), b));
	} else {
		body.statements.add(new CoreOwnershipTransfer(s, a, b, cleanup));
	}
	body.statements.add(new CoreOwnershipRearm(s, a, variant == 4 ? allocation : new CoreOwnedBufferAllocate(s, shape.slice_type, count, cleanup), cleanup));
	var function = new CoreFunction(s, s, "flow", t.void_type, new GenericArray<CoreParameter>(), locals, body);
	if (variant != 5) {
		function.owned_locals.add(a);
	}
	function.owned_locals.add(b);
	var functions = new GenericArray<CoreFunction>();
	functions.add(use);
	functions.add(function);
	return new CoreProgram(s, functions, null, null, null, cleanups);
}

private void ownership() {
	try {
		CoreVerifier.verify(local_flow());
	} catch (CoreError error) {
		GLib.error("%s", error.message);
	}
	for (int variant = 1; variant <= 5; variant++) {
		try {
			CoreVerifier.verify(local_flow(variant));
		} catch (CoreError error) {
			Test.message("owner variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed Core owner %d", variant);
	}
}

private CoreProgram fields(int variant = 0) {
	var t = new BuiltinTypes();
	var s = SourceSpan(new SourceFile.from_text("buffer-core-fields", "C"), 0, 1);
	var shape = new BufferValueShape(t.slice_of(t.f64_type), t.raw_pointer_type, (IntegerType) t.int_type);
	var cleanup = new CoreCleanupContract.for_buffer(shape, s, 0);
	var cleanups = new GenericArray<CoreCleanupContract>();
	cleanups.add(cleanup);
	var c = new CoreClass(s, s, "C", new ClassType("C"));
	for (int i = 0; i < 3; i++) {
		var field = new CoreStructField(s, s, "buffer" + i.to_string(), c, shape.slice_type, i);
		field.owned_cleanup = cleanup;
		c.fields.add(field);
	}
	var receiver = new CoreReceiver(s, new ReceiverType(c.semantic_type, ReceiverMode.INITIALIZING));
	var body = new CoreBlock(s, new GenericArray<CoreStatement>());
	var ctor = new CoreConstructor(s, s, c, receiver, 3, t.void_type, new GenericArray<CoreParameter>(), new GenericArray<CoreLocalPlace>(), body);
	c.constructor = ctor;
	for (int i = 0; i < 3; i++) {
		if (variant == 1 && i == 0) {
			continue;
		}
		var place = new CoreIndirectFieldPlace(s, new CoreReceiverValue(s, receiver), c.fields[i]);
		var count = new CoreIntegerValue.typed(s, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, 3));
		var allocation = new CoreOwnedBufferAllocate(s, shape.slice_type, count, cleanup);
		body.statements.add(new CoreOwnedFieldTransfer(s, place, cleanup, null, allocation, variant != 5));
		if (variant == 2 && i == 0) {
			body.statements.add(new CoreOwnedFieldTransfer(s, place, cleanup, null, new CoreOwnedBufferAllocate(s, shape.slice_type, count, cleanup), true));
		}
	}
	var live = new CoreReceiver(s, new ReceiverType(c.semantic_type));
	var dbody = new CoreBlock(s, new GenericArray<CoreStatement>());
	var dtor = new CoreDestructor(s, s, c, live, 4, t.void_type, new GenericArray<CoreParameter>(), new GenericArray<CoreLocalPlace>(), dbody);
	c.destructor = dtor;
	for (int i = 2; i >= 0; i--) {
		if (variant == 3 && i == 0) {
			continue;
		}
		dtor.field_cleanups.add(new CoreOwnedFieldCleanup(s, c.fields[variant == 4 ? 2 - i : i], cleanup));
	}
	var functions = new GenericArray<CoreFunction>();
	functions.add(ctor);
	functions.add(dtor);
	var program = new CoreProgram(s, functions, null, null, null, cleanups);
	program.classes.add(c);
	return program;
}

private void field_cleanup() {
	try {
		CoreVerifier.verify(fields());
	} catch (CoreError error) {
		GLib.error("%s", error.message);
	}
	for (int variant = 1; variant <= 5; variant++) {
		try {
			CoreVerifier.verify(fields(variant));
		} catch (CoreError error) {
			Test.message("field variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed Core buffer field %d", variant);
	}
}

int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/buffer/core/independent-neutral-allocation-owner-result", positive);
	Test.add_func("/buffer/core/reject-element-count-shape-and-responsibility", negative);
	Test.add_func("/buffer/core/independent-owner-borrow-move-rearm", ownership);
	Test.add_func("/buffer/core/independent-field-initialization-and-cleanup", field_cleanup);
	return Test.run();
}

}
