// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private CfgProgram owned_program(int variant = -1) {
	var file = new SourceFile.from_text ("owned-model", "f");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var cleanups = new GenericArray<CfgCleanupContract> ();
	var cleanup = new CfgCleanupContract (variant == 3 ? "" : "destroy", span, variant == 4 ? 1 : 0);
	if (variant != 0) {
		cleanups.add (cleanup);
	}
	if (variant == 5) {
		cleanups.add (new CfgCleanupContract ("destroy", span, 1));
	}
	var imports = new GenericArray<CfgCFunction> ();
	imports.add (new CfgCFunction (span, span, "create", new CForeignMetadata ("create"), ForeignAbi.C, types.raw_pointer_type, new GenericArray<SemanticType> (), 0, cleanup));
	var instructions = new GenericArray<CfgInstruction> ();
	var value = new CfgCallResultValue (span, types.raw_pointer_type);
	instructions.add (new CfgCCallInstruction (span, imports[0], new GenericArray<CfgValue> (), value));
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (new CfgLocalPlace (span, span, "h", types.raw_pointer_type, 0, false, cleanup));
	instructions.add (new CfgInitialize (span, locals[0], value, locals[0]));
	CfgValue operand = variant == 1 ? (CfgValue) new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (1)) : new CfgLoadValue (span, locals[0]);
	var instruction = new CfgCleanupInstruction (span, operand, variant == 6 ? new CfgCleanupContract ("destroy", span, 0) : cleanup);
	instructions.add (instruction);
	if (variant == 2) {
		instructions.add (instruction);
	}
	var block = new CfgBlock (span, 0, instructions, new CfgReturn (span, null));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", types.void_type, 0, new GenericArray<CfgParameter> (), locals, blocks, block));
	return new CfgProgram (span, functions, imports, null, null, cleanups);
}

private void owned_model() {
	try {
		CfgProgram? program = owned_program ();
		CfgVerifier.verify (program);
		assert (CfgDump.format (program).contains ("cleanup"));
		var cleanup_ref = WeakRef (program.cleanups[0]);
		var source_ref = WeakRef (program.span.file);
		program = null;
		assert (cleanup_ref.get () == null && source_ref.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_invalid() {
	for (int variant = 0; variant < 7; variant++) {
		try {
			CfgVerifier.verify (owned_program (variant));
		} catch (CfgError error) {
			Test.message ("malformed cleanup %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed cleanup %d accepted", variant);
	}
}

private CfgProgram move_program(int variant = -1) {
	var program = owned_program ();
	var function = program.functions[0];
	var span = program.span;
	var cleanup = program.cleanups[0];
	var type = function.locals[0].semantic_type;
	var types = new BuiltinTypes ();
	var source = new CfgLocalPlace (span, span, "a", type, 0, false, cleanup);
	var destination = new CfgLocalPlace (span, span, "b", variant == 4 ? types.int_type : type, 1, false, variant == 3 ? null : cleanup);
	function.locals[0] = source;
	function.locals.add (destination);
	var instructions = function.entry.instructions;
	instructions[1] = new CfgInitialize (span, source, ((CfgCCallInstruction) instructions[0]).result, source);
	instructions[2] = new CfgOwnershipTransferInstruction (span, variant == 1 ? new CfgLocalPlace (span, span, "a", type, 0, false, cleanup) : source, variant == 0 ? source : destination, variant == 2 ? new CfgCleanupContract ("destroy", span, 0) : cleanup);
	instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, destination), cleanup));
	instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, source), cleanup));
	if (variant == 5) {
		instructions.add (instructions[2]);
	}
	return program;
}

private void move_model() {
	try {
		CfgProgram? program = move_program ();
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		assert (CfgFlowChecker.check (oborrow_program (8)).diagnostic.message.contains ("cannot borrow moved"));
		assert (CfgDump.format (program).contains ("ownership-transfer (source owner #0"));
		var transfer_ref = WeakRef (program.functions[0].entry.instructions[2]);
		program = null;
		assert (transfer_ref.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void move_invalid() {
	for (int variant = 0; variant < 6; variant++) {
		try {
			CfgVerifier.verify (move_program (variant));
		} catch (CfgError error) {
			Test.message ("malformed move %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed move %d accepted", variant);
	}
}

private CfgProgram oborrow_program(int variant = -1) {
	var program = move_program ();
	var function = program.functions[0];
	var span = program.span;
	var type = function.locals[0].semantic_type;
	var parameters = new GenericArray<CfgParameter> ();
	var parameter = new CfgParameter (span, span, "p", type, 0, variant == 2 ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE);
	parameters.add (parameter);
	var types = new GenericArray<SemanticType> ();
	types.add (type);
	var target = new CfgCFunction (span, span, "inspect", new CForeignMetadata ("inspect"), ForeignAbi.C, function.return_type, types, 1, null, parameters);
	program.c_functions.add (target);
	var owner = variant == 0 ? new CfgLocalPlace (span, span, "a", type, 0, false, program.cleanups[0]) : function.locals[0];
	var borrowed_parameter = variant == 1 ? new CfgParameter (span, span, "p", type, 0, PointerParameterContract.BORROWED_NOESCAPE) : parameter;
	var value = new CfgOwnedBorrowValue (span, owner, borrowed_parameter);
	var event = new CfgOwnedBorrowInstruction (span, value);
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (value);
	var call = new CfgCCallInstruction (span, target, arguments, null);
	function.entry.instructions.insert (2, event);
	function.entry.instructions.insert (3, call);
	if (variant == 3) {
		function.entry.instructions.remove_index (2);
	}
	if (variant == 4) {
		function.entry.instructions.insert (3, event);
	}
	if (variant == 5) {
		function.entry.instructions.insert (3, new CfgCleanupInstruction (span, value, program.cleanups[0]));
	}
	if (variant == 6) {
		function.entry.instructions.insert (4, new CfgCCallInstruction (span, target, arguments, null));
	}
	if (variant == 7) {
		function.entry.instructions.remove_index (3);
	}
	if (variant == 8) {
		var call_instruction = function.entry.instructions[3];
		function.entry.instructions[3] = function.entry.instructions[4];
		function.entry.instructions[4] = call_instruction;
	}
	return program;
}

private void oborrow_model() {
	try {
		CfgProgram? program = oborrow_program ();
		assert (CfgFlowChecker.check (program).diagnostic == null);
		assert (CfgDump.format (program).contains ("borrow-owner #0"));
		var event_ref = WeakRef (program.functions[0].entry.instructions[2]);
		var parameter_ref = WeakRef (program.c_functions[1].parameters[0]);
		program = null;
		assert (event_ref.get () == null && parameter_ref.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void oborrow_invalid() {
	for (int i = 0; i < 8; i++) {
		try {
			CfgVerifier.verify (oborrow_program (i));
		} catch (CfgError error) {
			Test.message ("borrow %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("malformed borrow %d accepted", i);
	}
}

private CfgProgram release_program(int variant = -1) {
	var program = move_program ();
	var function = program.functions[0];
	var owner = function.locals[1];
	var cleanup = program.cleanups[0];
	if (variant == 0) {
		cleanup = new CfgCleanupContract ("destroy", program.span, 0);
	}
	if (variant == 1) {
		owner = new CfgLocalPlace (program.span, program.span, "b", owner.semantic_type, 1, false, cleanup);
	}
	if (variant == 2) {
		cleanup = new CfgCleanupContract ("other_destroy", program.span, 1);
		program.cleanups.add (cleanup);
	}
	if (variant == 4 || variant == 5) {
		var types = new BuiltinTypes ();
		owner = new CfgLocalPlace (program.span, program.span, "raw", variant == 4 ? owner.semantic_type : types.int_type, 2);
		function.locals.add (owner);
		CfgValue value = variant == 4 ? (CfgValue) new CfgNullPointerValue (program.span, owner.semantic_type) : new CfgIntegerValue (program.span, owner.semantic_type, AstraIntValue.from_int64 (1));
		function.entry.instructions.insert (3, new CfgInitialize (program.span, owner, value));
	}
	var event = new CfgOwnershipReleaseInstruction (program.span, owner, cleanup);
	function.entry.instructions.insert (variant == 4 || variant == 5 ? 4 : 3, event);
	if (variant == 3) {
		function.entry.instructions.insert (4, event);
	}
	return program;
}

private void release_model() {
	try {
		CfgProgram? program = release_program ();
		assert (CfgFlowChecker.check (program).diagnostic == null);
		assert (CfgDump.format (program).contains ("ownership-release (owner #1 \"b\") (cleanup #0)"));
		var event_ref = WeakRef (program.functions[0].entry.instructions[3]);
		program = null;
		assert (event_ref.get () == null);
		var borrow = oborrow_program ();
		borrow.functions[0].entry.instructions.insert (3, new CfgOwnershipReleaseInstruction (borrow.span, borrow.functions[0].locals[0], borrow.cleanups[0]));
		assert (CfgFlowChecker.check (borrow).diagnostic.message.contains ("cannot borrow released owned value"));
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void release_invalid() {
	for (int i = 0; i < 6; i++) {
		try {
			CfgVerifier.verify (release_program (i));
		} catch (CfgError error) {
			Test.message ("release %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("malformed release %d accepted", i);
	}
}

private CfgProgram rearm_program(int variant = -1) {
	var program = move_program ();
	var function = program.functions[0];
	var owner = function.locals[0];
	var span = program.span;
	var cleanup = program.cleanups[0];
	var target = program.c_functions[0];
	if (variant == 0) {
		cleanup = new CfgCleanupContract ("destroy", span, 0);
	}
	if (variant == 1) {
		owner = new CfgLocalPlace (span, span, "a", owner.semantic_type, 0, false, cleanup);
	}
	if (variant == 2 || variant == 3 || variant == 4) {
		CfgCleanupContract? other = variant == 3 ? null : cleanup;
		if (variant == 2) {
			other = new CfgCleanupContract ("other_destroy", span, 1);
			program.cleanups.add (other);
		}
		target = new CfgCFunction (span, span, "variant", new CForeignMetadata ("variant"), ForeignAbi.C, owner.semantic_type, new GenericArray<SemanticType> (), 1, other);
		if (variant != 4) {
			program.c_functions.add (target);
		}
	}
	var value = new CfgCallResultValue (span, owner.semantic_type);
	var producer = new CfgCCallInstruction (span, target, new GenericArray<CfgValue> (), value);
	var event = new CfgOwnershipRearmInstruction (span, owner, value, cleanup);
	var instructions = function.entry.instructions;
	instructions.insert (3, producer);
	instructions.insert (4, event);
	if (variant == 5) {
		instructions.insert (5, event);
	}
	if (variant == 6 || variant == 7) {
		instructions.insert (variant == 6 ? 5 : 4, new CfgEvaluateInstruction (span, value, new CfgEvaluatedValue (span, owner.semantic_type)));
	}
	if (variant == 8) {
		instructions.remove_index (4);
	}
	if (variant == 9) {
		instructions[4] = new CfgOwnershipRearmInstruction (span, owner, ((CfgCCallInstruction) instructions[0]).result, cleanup);
	}
	if (variant == 10) {
		instructions.insert (4, new CfgCleanupInstruction (span, new CfgNullPointerValue (span, owner.semantic_type), cleanup));
	}
	if (variant == 11) {
		var raw = new CfgLocalPlace (span, span, "raw", owner.semantic_type, 2);
		function.locals.add (raw);
		instructions[4] = new CfgInitialize (span, raw, value);
	}
	if (variant == 12) {
		var other = new CfgLocalPlace (span, span, "copy", owner.semantic_type, 2, false, cleanup);
		function.locals.add (other);
		instructions.insert (5, new CfgInitialize (span, other, value, other));
	}
	return program;
}

private void rearm_model() {
	try {
		CfgProgram? program = rearm_program ();
		assert (CfgFlowChecker.check (program).diagnostic == null);
		var instructions = program.functions[0].entry.instructions;
		assert (((CfgOwnershipRearmInstruction) instructions[4]).value == ((CfgCCallInstruction) instructions[3]).result);
		assert (CfgDump.format (program).contains ("ownership-rearm") && program.functions[0].locals.length == 2);
		var event_ref = WeakRef (instructions[4]);
		var value_ref = WeakRef (((CfgOwnershipRearmInstruction) instructions[4]).value);
		instructions = null;
		program = null;
		assert (event_ref.get () == null && value_ref.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void rearm_invalid() {
	for (int i = 0; i < 13; i++) {
		try {
			CfgVerifier.verify (rearm_program (i));
		} catch (CfgError error) {
			Test.message ("rearm %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("malformed rearm %d accepted", i);
	}
}

private void register_owned_tests() {
	Test.add_func ("/cfg-standalone/rearm/model-contract-lifetime", rearm_model);
	Test.add_func ("/cfg-standalone/rearm/malformed", rearm_invalid);
	Test.add_func ("/cfg-standalone/release/model-order-lifetime", release_model);
	Test.add_func ("/cfg-standalone/release/malformed", release_invalid);
	Test.add_func ("/cfg-standalone/oborrow/model-lifetime", oborrow_model);
	Test.add_func ("/cfg-standalone/oborrow/malformed", oborrow_invalid);
	Test.add_func ("/cfg-standalone/move/model-lifetime", move_model);
	Test.add_func ("/cfg-standalone/move/malformed", move_invalid);
	Test.add_func ("/cfg-standalone/ownership/model-order-lifetime", owned_model);
	Test.add_func ("/cfg-standalone/ownership/malformed", owned_invalid);
}

}
