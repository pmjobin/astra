// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;
namespace Astra.Tests.OwningCfg {
private CfgProgram model(BuiltinTypes? supplied = null) throws CfgError {
	var t = supplied ?? new BuiltinTypes ();
	var s = SourceSpan (new SourceFile.from_text ("independent-owning-cfg", "x"), 0, 1);
	var definition = OwningShape.definition (t, s);
	var local = new CfgLocalPlace (s, s, "owner", definition.semantic_type, 0);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (local);
	var scratch = new CfgEnumSlot (s, definition, 0);
	var owner = new CfgEnumSlot (s, definition, 1, local);
	var instructions = new GenericArray<CfgInstruction> ();
	instructions.add (new CfgEnumConstruct (s, scratch, definition.variant (1), new GenericArray<CfgEnumFieldInput> ()));
	instructions.add (new CfgEnumCopy (s, owner, scratch, true, EnumUse.MOVE));
	instructions.add (new CfgEnumDrop (s, owner));
	var entry = new CfgBlock.reserve (s, 0);
	foreach (var instruction in instructions) {
		entry.instructions.add (instruction);
	}
	entry.complete (s, new CfgReturn (s, new CfgIntegerValue.typed (s, t.int_type, AstraIntegerValue.from_int64 (t.i32_type, 0))));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (entry);
	var function = new CfgFunction (s, s, "probe", t.int_type, 0, new GenericArray<CfgParameter> (), locals, blocks, entry);
	function.enum_slots.add (scratch);
	function.enum_slots.add (owner);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	var program = new CfgProgram (s, functions);
	program.enums.add (definition);
	return program;
}

private void contracts() {
	try {
		CfgProgram? program = model ();
		CfgVerifier.verify (program);
		var function = program.functions[0];
		var instructions = function.entry.instructions;
		var transfer = (CfgEnumCopy) instructions[1];
		var cleanup = instructions[2];
		for (int mutation = 0; mutation < 5; mutation++) {
			if (mutation == 0) {
				instructions[1] = new CfgEnumCopy (transfer.span, transfer.destination, transfer.source);
			}
			if (mutation == 1) {
				instructions.remove_index (2);
			}
			if (mutation == 2) {
				instructions.add (new CfgEnumDrop (transfer.span, transfer.destination));
			}
			if (mutation == 3) {
				instructions.add (new CfgEnumCopy (transfer.span, transfer.source, transfer.destination, true, EnumUse.MOVE));
			}
			if (mutation == 4) {
				instructions[1] = new CfgEnumCommit (transfer.span, transfer.destination);
			}
			bool rejected = false;
			try {
				CfgVerifier.verify (program);
			} catch (CfgError error) {
				Test.message ("owning CFG mutation %d: %s", mutation, error.message);
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
			CfgVerifier.verify (program);
		}
		var view = new CfgEnumSlot (transfer.span, transfer.destination.definition, 2);
		view.inspection_root = transfer.destination;
		function.enum_slots.add (view);
		var inspection = new CfgEnumCopy (transfer.span, view, transfer.destination, true, EnumUse.INSPECT);
		var end = new CfgEnumEndInspection (transfer.span, view);
		instructions.insert (2, inspection);
		instructions.insert (3, end);
		CfgVerifier.verify (program);
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
				instructions.insert (4, new CfgEnumEndInspection (transfer.span, view));
			}
			bool rejected = false;
			try {
				CfgVerifier.verify (program);
			} catch (CfgError error) {
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
			CfgVerifier.verify (program);
		}
		var parallel = new CfgEnumSlot (transfer.span, transfer.destination.definition, 3);
		parallel.inspection_root = transfer.destination;
		function.enum_slots.add (parallel);
		var parallel_inspection = new CfgEnumCopy (transfer.span, parallel, transfer.destination, true, EnumUse.INSPECT);
		var parallel_end = new CfgEnumEndInspection (transfer.span, parallel);
		instructions.insert (3, parallel_inspection);
		instructions.insert (5, parallel_end);
		CfgVerifier.verify (program);
		var t = new BuiltinTypes ();
		var stale_read = new CfgEvaluateInstruction (transfer.span, new CfgEnumTag (transfer.span, t.int_type, view), new CfgEvaluatedValue (transfer.span, t.int_type));
		instructions.insert (5, stale_read);
		bool stale_rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("ended inspection with another loan active: %s", error.message);
			stale_rejected = true;
		}
		assert (stale_rejected);
		instructions.remove_index (5);
		CfgVerifier.verify (program);
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
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void nonnull_authority() {
	try {
		for (int mutation = 0; mutation < 4; mutation++) {
			var types = new BuiltinTypes ();
			var program = model (types);
			var span = program.span;
			var function = program.functions[0];
			CfgParameter? parameter = null;
			CfgStructField? field = null;
			if (mutation == 1) {
				parameter = new CfgParameter (span, span, "value", types.int_type, 0);
				function.parameters.add (parameter);
			}
			if (mutation == 3) {
				var record = new CfgStruct (span, span, "Copied", new StructType ("Copied"));
				field = new CfgStructField (span, span, "value", record, types.int_type, 0);
				record.fields.add (field);
				program.structs.add (record);
			}
			CfgVerifier.verify (program);
			if (mutation == 0) {
				function.mark_nonnull_result ();
			}
			if (mutation == 1) {
				parameter.mark_nonnull ();
			}
			if (mutation == 2) {
				function.locals[0].mark_nonnull ();
			}
			if (mutation == 3) {
				field.mark_nonnull ();
			}
			bool rejected = false;
			try {
				CfgVerifier.verify (program);
			} catch (CfgError error) {
				rejected = true;
				Test.message ("%s", error.message);
			}
			assert (rejected);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum-own/cfg/independent-empty-owner-mutations", contracts);
	Test.add_func ("/enum-own/cfg/reject-forged-nonnull-authority", nonnull_authority);
	return Test.run ();
}

}
