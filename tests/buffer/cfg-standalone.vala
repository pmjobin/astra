// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.BufferCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var t = new BuiltinTypes();
	var span = SourceSpan(new SourceFile.from_text("buffer-cfg", "x"), 0, 1);
	var slice = variant == 1 ? new SliceType(new ClassType("C")) : t.slice_of(t.f64_type);
	var shape = new BufferValueShape(slice, t.raw_pointer_type, (IntegerType) (variant == 2 ? t.u32_type : t.int_type));
	var cleanup = new CfgCleanupContract.for_buffer(shape, span, 0);
	var cleanups = new GenericArray<CfgCleanupContract>();
	cleanups.add(cleanup);
	CfgValue count = variant == 3 ? (CfgValue) new CfgBooleanValue(span, t.bool_type, BooleanLiteral.TRUE) : new CfgIntegerValue.typed(span, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, variant == 4 ? -1 : 3));
	var allocation = new CfgBufferAllocate(span, count, cleanup);
	var block = new CfgBlock.reserve(span, 0);
	block.instructions.add(allocation);
	var returned = new CfgOwnedReturnValue(span, slice, cleanup, null, allocation.results.owner);
	if (variant != 5) {
		block.instructions.add(new CfgOwnershipReturnInstruction(span, returned));
	}
	block.complete(span, new CfgOwnershipReturn(span, returned));
	var blocks = new GenericArray<CfgBlock>();
	blocks.add(block);
	var function = new CfgFunction(span, span, "make", slice, 0, new GenericArray<CfgParameter>(), new GenericArray<CfgLocalPlace>(), blocks, block, variant == 6 ? null : cleanup);
	var functions = new GenericArray<CfgFunction>();
	functions.add(function);
	return new CfgProgram(span, functions, null, null, null, cleanups);
}
private void positive() {
	try {
		CfgProgram? program = sample();
		CfgVerifier.verify(program);
		assert(CfgFlowChecker.check(program).diagnostic == null);
		assert(CfgDump.format(program).contains("empty=null+0"));
		var function = WeakRef(program.functions[0]);
		program = null;
		assert(function.get() == null);
	} catch (CfgError error) {
		GLib.error("%s", error.message);
	}
}
private void negative() {
	for (int variant = 1; variant <= 6; variant++) {
		try {
			CfgVerifier.verify(sample(variant));
		} catch (CfgError error) {
			Test.message("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed CFG buffer %d", variant);
	}
}
private CfgProgram fields(int variant = 0) throws CfgError {
	var t = new BuiltinTypes();
	var s = SourceSpan(new SourceFile.from_text("buffer-cfg-fields", "C"), 0, 1);
	var shape = new BufferValueShape(t.slice_of(t.f64_type), t.raw_pointer_type, (IntegerType) t.int_type);
	var cleanup = new CfgCleanupContract.for_buffer(shape, s, 0);
	var cleanups = new GenericArray<CfgCleanupContract>();
	cleanups.add(cleanup);
	var c = new CfgClass(s, s, "C", new ClassType("C"));
	for (int i = 0; i < 3; i++) {
		var field = new CfgStructField(s, s, "buffer" + i.to_string(), c, shape.slice_type, i);
		field.owned_cleanup = cleanup;
		c.fields.add(field);
	}
	var receiver = new CfgReceiver(s, new ReceiverType(c.semantic_type, ReceiverMode.INITIALIZING));
	var body = new CfgBlock.reserve(s, 0);
	var blocks = new GenericArray<CfgBlock>();
	blocks.add(body);
	var count = new CfgIntegerValue.typed(s, t.int_type, AstraIntegerValue.from_int64((IntegerType) t.int_type, 3));
	for (int i = 0; i < 3; i++) {
		var allocation = new CfgBufferAllocate(s, count, cleanup);
		body.instructions.add(allocation);
		var capture = new CfgResourceCapture(s, allocation.results.owner, null, cleanup);
		body.instructions.add(capture);
		body.instructions.add(new CfgInitialize(s, new CfgIndirectFieldPlace(s, new CfgReceiverValue(s, receiver), c.fields[i]), capture.result));
	}
	body.complete(s, new CfgFunctionEnd(s));
	var ctor = new CfgConstructor(s, s, c, receiver, 3, t.void_type, 0, new GenericArray<CfgParameter>(), new GenericArray<CfgLocalPlace>(), blocks, body);
	c.constructor = ctor;
	var live = new CfgReceiver(s, new ReceiverType(c.semantic_type));
	var dbody = new CfgBlock.reserve(s, 0);
	var dblocks = new GenericArray<CfgBlock>();
	dblocks.add(dbody);
	var destination = new CfgIndirectFieldPlace(s, new CfgReceiverValue(s, live), c.fields[0]);
	var view = new CfgEvaluatedValue(s, shape.slice_type);
	dbody.instructions.add(new CfgEvaluateInstruction(s, new CfgLoadValue(s, destination), view));
	var length = new CfgEvaluateInstruction(s, new CfgSliceLengthValue(s, t.int_type, view), new CfgEvaluatedValue(s, t.int_type));
	if (variant != 6) {
		dbody.instructions.add(length);
	}
	var old = new CfgCleanupInstruction(s, new CfgLoadValue(s, destination), cleanup);
	if (variant == 1) {
		dbody.instructions.add(old);
	}
	var incoming = new CfgBufferAllocate(s, count, cleanup);
	dbody.instructions.add(incoming);
	var capture = new CfgResourceCapture(s, incoming.results.owner, null, cleanup);
	dbody.instructions.add(capture);
	if (variant != 1 && variant != 2) {
		dbody.instructions.add(old);
	}
	dbody.instructions.add(new CfgStore(s, destination, capture.result));
	if (variant == 6) {
		dbody.instructions.add(length);
	}
	if (variant == 5) {
		dbody.instructions.add(new CfgStore(s, destination, capture.result));
	}
	for (int i = 2; i >= 0; i--) {
		if (variant == 3 && i == 0) {
			continue;
		}
		var place = new CfgIndirectFieldPlace(s, new CfgReceiverValue(s, live), c.fields[variant == 4 ? 2 - i : i]);
		dbody.instructions.add(new CfgCleanupInstruction(s, new CfgLoadValue(s, place), cleanup));
	}
	dbody.complete(s, new CfgFunctionEnd(s));
	var dtor = new CfgDestructor(s, s, c, live, 4, t.void_type, 1, new GenericArray<CfgParameter>(), new GenericArray<CfgLocalPlace>(), dblocks, dbody);
	c.destructor = dtor;
	var functions = new GenericArray<CfgFunction>();
	functions.add(ctor);
	functions.add(dtor);
	var program = new CfgProgram(s, functions, null, null, null, cleanups);
	program.classes.add(c);
	return program;
}
private void field_cleanup() {
	try {
		var program = fields();
		CfgVerifier.verify(program);
		assert(CfgFlowChecker.check(program).diagnostic == null);
	} catch (CfgError error) {
		GLib.error("%s", error.message);
	}
	for (int variant = 1; variant <= 6; variant++) {
		try {
			CfgVerifier.verify(fields(variant));
		} catch (CfgError error) {
			Test.message("field variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed CFG buffer field %d", variant);
	}
}
int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/buffer/cfg/independent-allocation-and-complete-owner-result", positive);
	Test.add_func("/buffer/cfg/reject-element-count-shape-and-incomplete-transfer", negative);
	Test.add_func("/buffer/cfg/independent-field-replacement-and-cleanup-order", field_cleanup);
	return Test.run();
}
}
