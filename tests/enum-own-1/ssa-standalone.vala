// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
namespace Astra.Tests.OwningSsa {
private SsaProgram model(BuiltinTypes? supplied = null) throws SsaError {
	var t = supplied ?? new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("independent-owning-ssa", "x"), 0, 1);
	var definition = OwningShape.definition (t, s);
	var scratch = new SsaEnumSlot (s, definition, 0);
	var owner = new SsaEnumSlot (s, definition, 1, 0);
	var entry = new SsaBlock (s, 0, 0);
	entry.instructions.add (new SsaEnumConstruct (s, scratch, definition.variant (1), new GenericArray<SsaEnumFieldInput> ()));
	entry.instructions.add (new SsaEnumCopy (s, owner, scratch, true, EnumUse.MOVE));
	entry.instructions.add (new SsaEnumDrop (s, owner));
	entry.complete (new SsaReturn (s, new SsaIntegerConstant.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 0))));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (entry);
	var function = new SsaFunction (s, s, "probe", t.int_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, entry);
	function.enum_slots.add (scratch);
	function.enum_slots.add (owner);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	var program = new SsaProgram (s, functions);
	program.enums.add (definition);
	return program;
}

private void contracts() {
	try {
		SsaProgram? program = model ();
		SsaVerifier.verify (program);
		var function = program.functions[0];
		var instructions = function.entry.instructions;
		var transfer = (SsaEnumCopy) instructions[1];
		var cleanup = instructions[2];
		for (int mutation = 0; mutation < 5; mutation++) {
			if (mutation == 0) {
				instructions[1] = new SsaEnumCopy (transfer.span, transfer.destination, transfer.source);
			}
			if (mutation == 1) {
				instructions.remove_index (2);
			}
			if (mutation == 2) {
				instructions.add (new SsaEnumDrop (transfer.span, transfer.destination));
			}
			if (mutation == 3) {
				instructions.add (new SsaEnumCopy (transfer.span, transfer.source, transfer.destination, true, EnumUse.MOVE));
			}
			if (mutation == 4) {
				instructions[1] = new SsaEnumCommit (transfer.span, transfer.destination);
			}
			bool rejected = false;
			try {
				SsaVerifier.verify (program);
			} catch (SsaError error) {
				Test.message ("owning SSA mutation %d: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			while (instructions.length > 3) {
				instructions.remove_index (instructions.length - 1);
			}
			if (instructions.length < 3) {
				instructions.add (cleanup);
			}
			instructions[1] = transfer;
			SsaVerifier.verify (program);
		}
		var view = new SsaEnumSlot (transfer.span, transfer.destination.definition, 2);
		view.inspection_root = transfer.destination;
		function.enum_slots.add (view);
		var inspection = new SsaEnumCopy (transfer.span, view, transfer.destination, true, EnumUse.INSPECT);
		var end = new SsaEnumEndInspection (transfer.span, view);
		instructions.insert (2, inspection);
		instructions.insert (3, end);
		SsaVerifier.verify (program);
		for (int mutation = 0; mutation < 4; mutation++) {
			if (mutation == 0) {
				view.inspection_root = transfer.source;
			}
			if (mutation == 1) {
				instructions.remove_index (3);
			}
			if (mutation == 2) {
				instructions[3] = cleanup;
				instructions[4] = end;
			}
			if (mutation == 3) {
				instructions.insert (4, new SsaEnumEndInspection (transfer.span, view));
			}
			bool rejected = false;
			try {
				SsaVerifier.verify (program);
			} catch (SsaError error) {
				Test.message ("independent inspection mutation %d: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			view.inspection_root = transfer.destination;
			while (instructions.length > 5) {
				instructions.remove_index (instructions.length - 1);
			}
			if (instructions.length < 5) {
				instructions.add (cleanup);
			}
			instructions[3] = end;
			instructions[4] = cleanup;
			SsaVerifier.verify (program);
		}
		var parallel = new SsaEnumSlot (transfer.span, transfer.destination.definition, 3);
		parallel.inspection_root = transfer.destination;
		function.enum_slots.add (parallel);
		var parallel_inspection = new SsaEnumCopy (transfer.span, parallel, transfer.destination, true, EnumUse.INSPECT);
		var parallel_end = new SsaEnumEndInspection (transfer.span, parallel);
		instructions.insert (3, parallel_inspection);
		instructions.insert (5, parallel_end);
		SsaVerifier.verify (program);
		var t = new BuiltinTypes ();
		var stale_read = new SsaEnumTagInstruction (transfer.span, t.int_type, view, 0);
		instructions.insert (5, stale_read);
		bool stale_rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("ended inspection with another loan active: %s", error.message);
			stale_rejected = true;
		}
		assert (stale_rejected);
		instructions.remove_index (5);
		SsaVerifier.verify (program);
		var weak = WeakRef (function);
		function = null;
		parallel = null;
		parallel_inspection = null;
		parallel_end = null;
		stale_read = null;
		view = null;
		inspection = null;
		end = null;
		transfer = null;
		cleanup = null;
		instructions = null;
		program = null;
		assert (weak.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void metadata_authority() {
	try {
		for (int mutation = 0; mutation < 6; mutation++) {
			var types = new BuiltinTypes ();
			var program = model (types);
			var span = program.span;
			var function = program.functions[0];
			SsaFunctionParameter? parameter = null;
			SsaStructField? field = null;
			if (mutation == 1) {
				parameter = new SsaFunctionParameter (span, span, "value", types.int_type, 0);
				function.parameters.add (parameter);
			}
			if (mutation == 2) {
				var record = new SsaStruct (span, span, "Copied", new StructType ("Copied"));
				field = new SsaStructField (span, span, "value", record, types.int_type, 0);
				record.fields.add (field);
				program.structs.add (record);
			}
			SsaVerifier.verify (program);
			if (mutation == 0) {
				function.mark_nonnull_result ();
			}
			if (mutation == 1) {
				parameter.mark_nonnull ();
			}
			if (mutation == 2) {
				field.mark_nonnull ();
			}
			if (mutation == 3) {
				var cleanup = new SsaCleanupInstruction (span, new SsaNullPointerConstant (span, types.raw_pointer_type), new SsaCleanupContract ("destroy", span, 0));
				function.retain_cleanup_effect (cleanup, function.entry);
			}
			if (mutation == 4) {
				var local = new SsaAddressableLocal (span, span, "value", types.int_type, 0, 0);
				var load = new SsaLoadInstruction (span, new SsaLocalMemoryPlace (span, local), 0, new VolatileAccessContract (types.int_type));
				function.retain_volatile_effect (load, function.entry);
			}
			if (mutation == 5) {
				function.retain_nonnull_use (new SsaNonNullUse (span, new SsaNullPointerConstant (span, types.raw_pointer_type), 0, function.entry, 0));
			}
			bool rejected = false;
			try {
				SsaVerifier.verify (program);
			} catch (SsaError error) {
				rejected = true;
				Test.message ("%s", error.message);
			}
			assert (rejected);
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void record_buffer_authority() {
	try {
		var types = new BuiltinTypes ();
		var program = model (types);
		var function = program.functions[0];
		var span = program.span;
		var slice = new SliceType (types.int_type);
		var buffer_shape = new BufferValueShape (slice, types.raw_pointer_type, types.i32_type);
		var cleanup = new SsaCleanupContract.for_buffer (buffer_shape, span, 0);
		program.cleanups.add (cleanup);
		var record = new SsaStruct (span, span, "Record", new StructType ("Record"));
		program.structs.add (record);
		var field = new SsaStructField (span, span, "data", record, slice, 0);
		field.owned_cleanup = cleanup;
		record.fields.add (field);
		var path = new StructLeafPath ({0}, slice);
		var paths = new GenericArray<StructLeafPath> ();
		paths.add (new StructBufferLeafPath (path, buffer_shape, 0));
		paths.add (new StructBufferLeafPath (path, buffer_shape, 1));
		var shape = new StructValueShape ((StructType) record.semantic_type, paths, StructValueMode.MOVE_VALUE, true);
		var group = new StructBoundaryGroup (0, 0, shape);
		function.struct_parameters.add (group);
		function.parameters.add (new SsaFunctionParameter (span, span, "base", types.raw_pointer_type, 0));
		function.parameters.add (new SsaFunctionParameter (span, span, "length", types.i32_type, 1));
		var values = new GenericArray<SsaValue> ();
		values.add (function.parameters[0]);
		values.add (function.parameters[1]);
		var pair = new SsaBufferPair (span, buffer_shape, values[0], values[1]);
		var storage = new SsaBufferStorage (span, cleanup, 0, 0);
		storage.record_type = record;
		storage.record_path = path;
		storage.record_rank = 0;
		storage.record_source_ordinal = 0;
		function.buffer_storage.add (storage);
		var acquisition = new SsaStructBoundaryAcquire (span, record, 0, shape, values, new GenericArray<SsaHeapOwner> (), group, null);
		acquisition.add_buffer (storage, pair);
		var place = new SsaBufferPlace (span, cleanup, storage);
		var write = new SsaBufferWriteInstruction (span, place, pair);
		write.initializes = true;
		write.record_boundary = acquisition;
		function.entry.instructions.insert (0, acquisition);
		function.entry.instructions.insert (1, write);
		var read = new SsaBufferReadInstruction (span, place, 2);
		function.entry.instructions.add (read);
		function.entry.instructions.add (new SsaBufferDeallocateInstruction (span, read.pair, cleanup));
		SsaVerifier.verify (program);
		storage.record_rank = 1;
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		storage.record_rank = 0;
		SsaVerifier.verify (program);
		acquisition.buffer_pairs.remove_index (0);
		rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		acquisition.buffer_pairs.add (pair);
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum-own/ssa/independent-empty-owner-mutations", contracts);
	Test.add_func ("/enum-own/ssa/reject-forged-metadata-and-erased-effects", metadata_authority);
	Test.add_func ("/enum-own/ssa/independent-record-buffer-boundary", record_buffer_authority);
	return Test.run ();
}

}
