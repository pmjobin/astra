// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Ssa;

namespace Astra.Tests.SsaStandalone {
private SsaProgram owned_program(int variant = -1) throws SsaError {
	var file = new SourceFile.from_text ("owned-model", "f");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var cleanups = new GenericArray<SsaCleanupContract> ();
	var cleanup = new SsaCleanupContract (variant == 3 ? "" : "destroy", span, variant == 4 ? 1 : 0);
	if (variant != 0) {
		cleanups.add (cleanup);
	}
	if (variant == 5) {
		cleanups.add (new SsaCleanupContract ("destroy", span, 1));
	}
	var imports = new GenericArray<SsaCFunction> ();
	imports.add (new SsaCFunction (span, span, "create", new CForeignMetadata ("create"), ForeignAbi.C, types.raw_pointer_type, new GenericArray<SemanticType> (), 0, cleanup));
	var block = new SsaBlock (span, 0, 0);
	var call = new SsaCCallInstruction (span, types.raw_pointer_type, 0, imports[0], new GenericArray<SsaValue> ());
	block.instructions.add (call);
	SsaValue value = variant == 1 ? (SsaValue) new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (1)) : call.result;
	var instruction = new SsaCleanupInstruction (span, value, variant == 6 ? new SsaCleanupContract ("destroy", span, 0) : cleanup);
	block.instructions.add (instruction);
	if (variant == 2) {
		block.instructions.add (instruction);
	}
	block.complete (new SsaReturn (span, null));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", types.void_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, block));
	return new SsaProgram (span, functions, imports, null, null, cleanups);
}

private void owned_model() {
	try {
		SsaProgram? program = owned_program ();
		SsaVerifier.verify (program);
		assert (SsaDump.format (program).contains ("cleanup"));
		var cleanup_ref = WeakRef (program.cleanups[0]);
		var source_ref = WeakRef (program.span.file);
		program = null;
		assert (cleanup_ref.get () == null && source_ref.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_invalid() {
	for (int variant = 0; variant < 7; variant++) {
		try {
			SsaVerifier.verify (owned_program (variant));
		} catch (SsaError error) {
			Test.message ("malformed cleanup %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed cleanup %d accepted", variant);
	}
}

private void moved_source_null() {
	try {
		var program = owned_program ();
		var block = program.functions[0].entry;
		block.instructions.add (new SsaCleanupInstruction (program.span, new SsaNullPointerConstant (program.span, program.c_functions[0].return_type), program.cleanups[0]));
		SsaVerifier.verify (program);
		assert (SsaDump.format (program).contains ("cleanup (null : void*) via #0"));
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void normalized_borrow() {
	try {
		SsaProgram? program = owned_program ();
		var span = program.span;
		var type = program.c_functions[0].return_type;
		var parameters = new GenericArray<SsaFunctionParameter> ();
		parameters.add (new SsaFunctionParameter (span, span, "p", type, 0, PointerParameterContract.BORROWED_NOESCAPE));
		var types = new GenericArray<SemanticType> ();
		types.add (type);
		var target = new SsaCFunction (span, span, "inspect", new CForeignMetadata ("inspect"), ForeignAbi.C, program.functions[0].return_type, types, 1, null, parameters);
		program.c_functions.add (target);
		var block = program.functions[0].entry;
		var value = block.instructions[0].result;
		var arguments = new GenericArray<SsaValue> ();
		arguments.add (value);
		block.instructions.insert (1, new SsaCCallInstruction (span, null, -1, target, arguments));
		SsaVerifier.verify (program);
		assert (((SsaCCallInstruction) block.instructions[1]).arguments[0] == ((SsaCleanupInstruction) block.instructions[2]).value);
		assert (block.instructions.length == 3 && program.functions[0].storage.length == 0);
		assert (SsaDump.format (program).contains ("borrowed-noescape") && !SsaDump.format (program).contains ("borrow-owner"));
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private SsaProgram borrowed_parameter_program(int variant = -1) throws SsaError {
	var file = new SourceFile.from_text ("borrowed-native", "borrowed void* p");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var parameter = new SsaFunctionParameter (span, span, "p", variant == 2 ? types.int_type : types.raw_pointer_type, 0, variant == 3 ? (PointerParameterContract) 99 : PointerParameterContract.BORROWED_NOESCAPE);
	parameters.add (parameter);
	var imported_parameters = new GenericArray<SsaFunctionParameter> ();
	imported_parameters.add (new SsaFunctionParameter (span, span, "q", types.raw_pointer_type, 0, variant == 1 ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE));
	var parameter_types = new GenericArray<SemanticType> ();
	parameter_types.add (types.raw_pointer_type);
	var imports = new GenericArray<SsaCFunction> ();
	var target = new SsaCFunction (span, span, "inspect", new CForeignMetadata ("inspect"), ForeignAbi.C, types.void_type, parameter_types, 0, null, imported_parameters);
	imports.add (target);
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (parameter);
	var block = new SsaBlock (span, 0, 0);
	block.instructions.add (new SsaCCallInstruction (span, null, -1, target, arguments));
	block.complete (new SsaReturn (span, variant == 0 ? (SsaValue) parameter : new SsaNullPointerConstant (span, types.raw_pointer_type)));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", types.raw_pointer_type, 0, parameters, blocks, block));
	return new SsaProgram (span, functions, imports);
}

private void borrowed_parameter_contract() {
	try {
		SsaVerifier.verify (borrowed_parameter_program ());
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
	for (int i = 0; i < 4; i++) {
		try {
			SsaVerifier.verify (borrowed_parameter_program (i));
		} catch (SsaError error) {
			Test.message ("native borrow %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("escaping native SSA parameter %d accepted", i);
	}
}

private void normalized_release() {
	try {
		var program = owned_program ();
		var source = new SourceFile.from_text ("release.astra", "release h;");
		var span = SourceSpan (source, 0, source.length);
		var block = program.functions[0].entry;
		block.instructions[1] = new SsaCleanupInstruction (span, block.instructions[0].result, program.cleanups[0]);
		block.instructions.add (new SsaCleanupInstruction (program.span, new SsaNullPointerConstant (span, program.c_functions[0].return_type), program.cleanups[0]));
		SsaVerifier.verify (program);
		assert (((SsaCleanupInstruction) block.instructions[1]).value == block.instructions[0].result);
		assert (block.instructions[1].span.text () == "release h;" && ((SsaCleanupInstruction) block.instructions[2]).value is SsaNullPointerConstant);
		assert (block.instructions[1].result == null && block.instructions[2].result == null && program.functions[0].storage.length == 0);
		assert (!SsaDump.format (program).contains ("ownership-release"));
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void normalized_rearm() {
	try {
		SsaProgram? program = owned_program ();
		var block = program.functions[0].entry;
		var producer = new SsaCCallInstruction (program.span, program.c_functions[0].return_type, 1, program.c_functions[0], new GenericArray<SsaValue> ());
		block.instructions.add (producer);
		block.instructions.add (new SsaCleanupInstruction (program.span, producer.result, program.cleanups[0]));
		SsaVerifier.verify (program);
		assert (((SsaCleanupInstruction) block.instructions[1]).value == block.instructions[0].result);
		assert (((SsaCleanupInstruction) block.instructions[3]).value == block.instructions[2].result);
		assert (block.instructions.length == 4 && program.functions[0].storage.length == 0 && !SsaDump.format (program).contains ("rearm"));
		var producer_ref = WeakRef (producer);
		producer = null;
		block = null;
		program = null;
		assert (producer_ref.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void register_owned_tests() {
	Test.add_func ("/ssa-standalone/rearm/normalized-pointer-lifetime", normalized_rearm);
	Test.add_func ("/ssa-standalone/release/normalized-cleanup-null", normalized_release);
	Test.add_func ("/ssa-standalone/oborrow/native-contract", borrowed_parameter_contract);
	Test.add_func ("/ssa-standalone/oborrow/normalized-pointer", normalized_borrow);
	Test.add_func ("/ssa-standalone/move/normalized-null-cleanup", moved_source_null);
	Test.add_func ("/ssa-standalone/ownership/model-order-lifetime", owned_model);
	Test.add_func ("/ssa-standalone/ownership/malformed", owned_invalid);
}

}
