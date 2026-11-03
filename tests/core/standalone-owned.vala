// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
private CoreProgram owned_program(int variant = -1) {
	var file = new SourceFile.from_text ("owned-model", "f");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var cleanups = new GenericArray<CoreCleanupContract> ();
	var cleanup = new CoreCleanupContract (variant == 10 ? "" : "destroy", span, 0);
	cleanups.add (cleanup);
	var imports = new GenericArray<CoreCFunction> ();
	imports.add (new CoreCFunction (span, span, "create", new CForeignMetadata ("create"), ForeignAbi.C, types.raw_pointer_type, new GenericArray<SemanticType> (), 0, variant == 2 ? null : cleanup));
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (new CoreLocalPlace (span, span, "h", variant == 4 ? types.int_type : types.raw_pointer_type, 0));
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var scope = variant == 0 ? new CoreBlock (span, new GenericArray<CoreStatement> ()) : body;
	var owner = new CoreOwnedLocal (span, locals[0], variant == 3 ? new CoreCleanupContract ("destroy", span, 0) : cleanup, scope);
	var function = new CoreFunction (span, span, "f", variant == 7 ? types.raw_pointer_type : types.void_type, new GenericArray<CoreParameter> (), locals, body);
	function.owned_locals.add (owner);
	if (variant == 5) {
		function.owned_locals.add (owner);
	}
	var producer = new CoreCCallValue (span, types.raw_pointer_type, imports[0], new GenericArray<CoreValue> ());
	body.statements.add (new CoreInitialize (span, locals[0], producer, variant == 1 ? null : owner));
	if (variant == 6) {
		body.statements.add (new CoreStore (span, locals[0], new CoreNullPointerValue (span, types.raw_pointer_type)));
	}
	if (variant == 8) {
		body.statements.add (new CoreCCallStatement (span, imports[0], new GenericArray<CoreValue> ()));
	}
	if (variant == 9) {
		var other = new CoreLocalPlace (span, span, "raw", types.raw_pointer_type, 1);
		locals.add (other);
		body.statements.add (new CoreInitialize (span, other, new CoreLoadValue (span, locals[0])));
	}
	body.statements.add (new CoreReturn (span, variant == 7 ? new CoreLoadValue (span, locals[0]) : null));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	return new CoreProgram (span, functions, imports, null, null, cleanups);
}

private void owned_model() {
	try {
		CoreProgram? program = owned_program ();
		CoreVerifier.verify (program);
		assert (CoreDump.format (program).contains ("owned-initialize"));
		assert (program.functions[0].locals[0].is_promotable ());
		var contract_ref = WeakRef (program.cleanups[0]);
		var owner_ref = WeakRef (program.functions[0].owned_locals[0]);
		var scope_ref = WeakRef (program.functions[0].body);
		program = null;
		assert (contract_ref.get () == null && owner_ref.get () == null && scope_ref.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_invalid() {
	for (int variant = 0; variant < 11; variant++) {
		try {
			CoreVerifier.verify (owned_program (variant));
		} catch (CoreError error) {
			Test.message ("malformed owner %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed owner %d accepted", variant);
	}
}

private CoreProgram move_program(int variant = -1) {
	var program = owned_program ();
	var function = program.functions[0];
	var source = function.owned_locals[0];
	var types = new BuiltinTypes ();
	var place = new CoreLocalPlace (program.span, program.span, "destination", variant == 4 ? types.int_type : source.place.semantic_type, 1);
	function.locals.add (place);
	var destination = new CoreOwnedLocal (program.span, place, source.cleanup, function.body);
	if (variant != 7) {
		function.owned_locals.add (destination);
	}
	var transfer = new CoreOwnershipTransfer (program.span, variant == 2 ? new CoreOwnedLocal (program.span, source.place, source.cleanup, function.body) : source, variant == 0 ? source : destination, variant == 1 ? new CoreCleanupContract ("destroy", program.span, 0) : source.cleanup);
	function.body.statements.insert (variant == 3 ? 0 : 1, transfer);
	if (variant == 5) {
		function.body.statements.insert (2, transfer);
	}
	if (variant == 6) {
		function.body.statements.insert (2, new CoreInitialize (program.span, place, new CoreLoadValue (program.span, source.place)));
	}
	return program;
}

private void move_model() {
	try {
		CoreProgram? program = move_program ();
		CoreVerifier.verify (program);
		var transfer_ref = WeakRef (program.functions[0].body.statements[1]);
		assert (CoreDump.format (program).contains ("ownership-transfer (source owner #0"));
		program = null;
		assert (transfer_ref.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void move_invalid() {
	for (int variant = 0; variant < 8; variant++) {
		try {
			CoreVerifier.verify (move_program (variant));
		} catch (CoreError error) {
			Test.message ("malformed move %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed move %d accepted", variant);
	}
}

private CoreProgram oborrow_program(int variant = -1) {
	var program = owned_program ();
	var function = program.functions[0];
	var span = program.span;
	var owner = function.owned_locals[0];
	var type = owner.place.semantic_type;
	var parameters = new GenericArray<CoreParameter> ();
	var parameter = new CoreParameter (span, span, "p", type, 0, variant == 6 ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE);
	parameters.add (parameter);
	var types = new GenericArray<SemanticType> ();
	types.add (type);
	var target = new CoreCFunction (span, span, "inspect", new CForeignMetadata ("inspect"), ForeignAbi.C, function.return_type, types, 1, null, parameters);
	program.c_functions.add (target);
	var borrowed_owner = variant == 0 ? new CoreOwnedLocal (span, owner.place, owner.cleanup, function.body) : owner;
	var borrowed_parameter = variant == 1 ? new CoreParameter (span, span, "p", type, 0, PointerParameterContract.BORROWED_NOESCAPE) : parameter;
	CoreValue value = new CoreOwnedBorrowValue (span, borrowed_owner, borrowed_parameter);
	if (variant == 3) {
		value = new CoreLoadValue (span, owner.place);
	}
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (value);
	CoreStatement use = new CoreCCallStatement (span, target, arguments);
	if (variant == 2) {
		var local = new CoreLocalPlace (span, span, "raw", type, 1);
		function.locals.add (local);
		use = new CoreInitialize (span, local, value);
	}
	if (variant == 4 || variant == 5) {
		var input = new CoreParameter (span, span, "input", type, 0, PointerParameterContract.BORROWED_NOESCAPE);
		function.parameters.add (input);
		if (variant == 4) {
			var local = new CoreLocalPlace (span, span, "raw", type, 1);
			function.locals.add (local);
			use = new CoreInitialize (span, local, new CoreParameterValue (span, input));
		} else {
			use = new CoreReturn (span, new CoreParameterValue (span, input));
		}
	}
	function.body.statements.insert (variant == 7 ? 0 : 1, use);
	return program;
}

private void oborrow_model() {
	try {
		CoreProgram? program = oborrow_program ();
		CoreVerifier.verify (program);
		assert (CoreDump.format (program).contains ("borrow-owner #0"));
		var value_ref = WeakRef (((CoreCCallStatement) program.functions[0].body.statements[1]).arguments[0]);
		var parameter_ref = WeakRef (program.c_functions[1].parameters[0]);
		program = null;
		assert (value_ref.get () == null && parameter_ref.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void oborrow_invalid() {
	for (int i = 0; i < 8; i++) {
		try {
			CoreVerifier.verify (oborrow_program (i));
		} catch (CoreError error) {
			Test.message ("borrow %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("malformed borrow %d accepted", i);
	}
}

private CoreProgram release_program(int variant = -1) {
	var program = owned_program (variant == 4 ? 4 : -1);
	var function = program.functions[0];
	var owner = function.owned_locals[0];
	var cleanup = program.cleanups[0];
	if (variant == 0) {
		cleanup = new CoreCleanupContract ("destroy", program.span, 0);
	}
	if (variant == 1) {
		owner = new CoreOwnedLocal (program.span, owner.place, cleanup, function.body);
	}
	if (variant == 3) {
		cleanup = new CoreCleanupContract ("other_destroy", program.span, 1);
		program.cleanups.add (cleanup);
	}
	if (variant == 5) {
		owner = new CoreOwnedLocal (program.span, new CoreLocalPlace (program.span, program.span, "h", owner.place.semantic_type, 0), cleanup, function.body);
	}
	function.body.statements.insert (variant == 2 ? 0 : 1, new CoreOwnershipRelease (program.span, owner, cleanup));
	return program;
}

private void release_model() {
	try {
		CoreProgram? program = release_program ();
		CoreVerifier.verify (program);
		assert (CoreDump.format (program).contains ("ownership-release (owner #0 \"h\") (cleanup #0)"));
		var event_ref = WeakRef (program.functions[0].body.statements[1]);
		var owner_ref = WeakRef (program.functions[0].owned_locals[0]);
		program = null;
		assert (event_ref.get () == null && owner_ref.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void release_invalid() {
	for (int i = 0; i < 6; i++) {
		try {
			CoreVerifier.verify (release_program (i));
		} catch (CoreError error) {
			Test.message ("release %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("malformed release %d accepted", i);
	}
}

private CoreProgram rearm_program(int variant = -1) {
	var program = owned_program ();
	var function = program.functions[0];
	var owner = function.owned_locals[0];
	var span = program.span;
	var cleanup = owner.cleanup;
	var target = program.c_functions[0];
	if (variant == 0) {
		cleanup = new CoreCleanupContract ("destroy", span, 0);
	}
	if (variant == 1) {
		owner = new CoreOwnedLocal (span, owner.place, cleanup, function.body);
	}
	if (variant == 3 || variant == 4 || variant == 5) {
		CoreCleanupContract? other = variant == 4 ? null : cleanup;
		if (variant == 3) {
			other = new CoreCleanupContract ("other_destroy", span, 1);
			program.cleanups.add (other);
		}
		target = new CoreCFunction (span, span, "variant", new CForeignMetadata ("variant"), ForeignAbi.C, owner.place.semantic_type, new GenericArray<SemanticType> (), 1, other);
		if (variant != 5) {
			program.c_functions.add (target);
		}
	}
	if (variant == 6) {
		owner = new CoreOwnedLocal (span, new CoreLocalPlace (span, span, "h", owner.place.semantic_type, 0), cleanup, function.body);
	}
	function.body.statements.insert (1, new CoreOwnershipRelease (span, function.owned_locals[0], function.owned_locals[0].cleanup));
	var call = new CoreCCallValue (span, owner.place.semantic_type, target, new GenericArray<CoreValue> ());
	function.body.statements.insert (variant == 2 ? 0 : 2, new CoreOwnershipRearm (span, owner, call, cleanup));
	return program;
}

private void rearm_model() {
	try {
		CoreProgram? program = rearm_program ();
		CoreVerifier.verify (program);
		assert (program.functions[0].owned_locals.length == 1 && CoreDump.format (program).contains ("ownership-rearm"));
		var event_ref = WeakRef (program.functions[0].body.statements[2]);
		var call_ref = WeakRef (((CoreOwnershipRearm) program.functions[0].body.statements[2]).producer);
		program = null;
		assert (event_ref.get () == null && call_ref.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void rearm_invalid() {
	for (int i = 0; i < 7; i++) {
		try {
			CoreVerifier.verify (rearm_program (i));
		} catch (CoreError error) {
			Test.message ("rearm %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("malformed rearm %d accepted", i);
	}
}

private void register_owned_tests() {
	Test.add_func ("/core-standalone/rearm/model-contract-lifetime", rearm_model);
	Test.add_func ("/core-standalone/rearm/malformed", rearm_invalid);
	Test.add_func ("/core-standalone/release/model-lifetime", release_model);
	Test.add_func ("/core-standalone/release/malformed", release_invalid);
	Test.add_func ("/core-standalone/oborrow/model-lifetime", oborrow_model);
	Test.add_func ("/core-standalone/oborrow/malformed", oborrow_invalid);
	Test.add_func ("/core-standalone/move/model-lifetime", move_model);
	Test.add_func ("/core-standalone/move/malformed", move_invalid);
	Test.add_func ("/core-standalone/ownership/model-lifetime", owned_model);
	Test.add_func ("/core-standalone/ownership/malformed", owned_invalid);
}

}
