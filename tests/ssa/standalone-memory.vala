// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SsaStandalone {
private SsaProgram memory_program(int variant = -1) throws SsaError {
	var file = new SourceFile.from_text ("standalone-memory", "Pair Other x ready handle storage p");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var structure = new SsaStruct (span, span, "Pair", new StructType ("Pair"));
	structure.fields.add (new SsaStructField (span, span, "x", structure, types.int_type, 0));
	structure.fields.add (new SsaStructField (span, span, "ready", structure, types.bool_type, 1));
	structure.fields.add (new SsaStructField (span, span, "handle", structure, types.raw_pointer_type, 2));
	var other = new SsaStruct (span, span, "Other", new StructType ("Other"));
	other.fields.add (new SsaStructField (span, span, "x", other, types.int_type, 0));
	var pointer_type = types.pointer_to (structure.semantic_type);
	var parameter = new SsaFunctionParameter (span, span, "p", pointer_type, 0);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (parameter);
	var storage = new SsaAddressableLocal (span, span, "storage", structure.semantic_type, 0, variant == 17 ? -1 : 0, structure);
	var x = new SsaDirectFieldPlace (span, storage, structure.fields[0]);
	var ready = new SsaDirectFieldPlace (span, storage, structure.fields[1]);
	var handle = new SsaDirectFieldPlace (span, storage, structure.fields[2]);
	var one = new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (1));
	var boolean = new SsaBooleanConstant (span, types.bool_type, BooleanLiteral.TRUE);
	var null_pointer = new SsaNullPointerConstant (span, types.raw_pointer_type);
	var address = new SsaAddressOfInstruction (span, pointer_type, 1, storage);
	var indirect = new SsaIndirectFieldPlace (span, parameter, structure.fields[0]);
	var direct_load = new SsaLoadInstruction (span, x, 2);
	var indirect_load = new SsaLoadInstruction (span, new SsaIndirectFieldPlace (span, address.result, structure.fields[0]), 3);
	var block = new SsaBlock (span, 0, 0);
	block.instructions.add (new SsaInitializeInstruction (span, x, one));
	block.instructions.add (new SsaInitializeInstruction (span, ready, boolean));
	block.instructions.add (new SsaInitializeInstruction (span, handle, null_pointer));
	block.instructions.add (address);
	block.instructions.add (new SsaStoreInstruction (span, indirect, one));
	block.instructions.add (new SsaStoreInstruction (span, x, one));
	block.instructions.add (direct_load);
	block.instructions.add (indirect_load);
	block.instructions.add (new SsaLoadInstruction (span, new SsaIndirectFieldPlace (span, parameter, structure.fields[1]), 4));
	block.instructions.add (new SsaLoadInstruction (span, new SsaIndirectFieldPlace (span, parameter, structure.fields[2]), 5));
	var sum = new SsaBinaryInstruction (span, types.int_type, 6, BinaryOperator.ADD, direct_load.result, indirect_load.result);
	block.instructions.add (sum);
	block.complete (new SsaReturn (span, sum.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var function = new SsaFunction (span, span, "f", variant == 22 ? (SemanticType) pointer_type : types.int_type, 0, parameters, blocks, block);
	function.storage.add (storage);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	var structs = new GenericArray<SsaStruct> ();
	structs.add (structure);
	structs.add (other);
	switch (variant) {
	case 0:
		function.storage.add (storage);
		break;
	case 1:
		structs.add (structure);
		break;
	case 2:
		structs.remove_index (0);
		break;
	case 3:
		block.instructions[5] = new SsaStoreInstruction (span, new SsaDirectFieldPlace (span, storage, other.fields[0]), one);
		break;
	case 4:
		block.instructions[4] = new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, null_pointer, structure.fields[0]), one);
		break;
	case 5:
		block.instructions[4] = new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, new SsaNullPointerConstant (span, types.pointer_to (other.semantic_type)), structure.fields[0]), one);
		break;
	case 6:
		block.instructions[4] = new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, new SsaNullPointerConstant (span, new TypedPointerType (structure.semantic_type)), structure.fields[0]), one);
		break;
	case 7:
		block.instructions[4] = new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, new SsaInstructionResult (span, pointer_type, 99), structure.fields[0]), one);
		break;
	case 8:
		block.instructions[2] = new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, address.result, structure.fields[0]), one);
		block.instructions.add (new SsaInitializeInstruction (span, handle, null_pointer));
		break;
	case 9:
		block.instructions[4] = new SsaStoreInstruction (span, indirect, boolean);
		break;
	case 10:
		block.instructions[5] = new SsaInitializeInstruction (span, indirect, one);
		break;
	case 11:
		block.instructions[1] = block.instructions[0];
		break;
	case 12:
		block.instructions.remove_index (2);
		break;
	case 13:
		block.instructions[3] = new SsaAddressOfInstruction (span, types.pointer_to (other.semantic_type), 1, storage);
		break;
	case 14:
		block.instructions[3] = new SsaAddressOfInstruction (span, pointer_type, 1, new SsaAddressableLocal (span, span, "foreign", structure.semantic_type, 0, 0, structure));
		break;
	case 15:
		block.instructions[4] = new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, parameter, new SsaStructField (span, span, "x", structure, types.int_type, 0)), one);
		break;
	case 16:
		block.parameters.add (new SsaBlockParameter.field (span, span, "storage.x", types.int_type, 99, 0, 0));
		break;
	case 18:
		structure.fields[2] = new SsaStructField (span, span, "handle", structure, pointer_type, 2);
		break;
	case 19:
		block.instructions[4] = new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, new SsaNullPointerConstant (span, new SemanticType (TypeKind.RAW_POINTER)), structure.fields[0]), one);
		break;
	case 20:
		block.instructions.add (block.instructions[4]);
		break;
	case 21:
		function.storage[0] = new SsaAddressableLocal (span, span, "other", structure.semantic_type, 0, 0, structure);
		break;
	default:
		break;
	}
	return new SsaProgram (span, functions, null, null, structs);
}

private void memory_model() {
	try {
		SsaProgram? program = memory_program ();
		SsaVerifier.verify (program);
		string dump = SsaDump.format (program);
		foreach (string node in new string[] {"(struct \"Pair\"", "(storage #0", "direct-field", "indirect-field", "address-of", "initialize", "store", "load"}) {
			assert (dump.contains (node));
		}
		var storage_ref = WeakRef (program.functions[0].storage[0]);
		var structure_ref = WeakRef (program.structs[0]);
		var pointer_ref = WeakRef (program.functions[0].parameters[0]);
		var address_ref = WeakRef (program.functions[0].entry.instructions[3]);
		var result_ref = WeakRef (program.functions[0].entry.instructions[3].result);
		var indirect_ref = WeakRef (((SsaStoreInstruction) program.functions[0].entry.instructions[4]).target);
		var direct_ref = WeakRef (((SsaLoadInstruction) program.functions[0].entry.instructions[6]).source);
		program = null;
		assert (storage_ref.get () == null && structure_ref.get () == null && pointer_ref.get () == null);
		assert (address_ref.get () == null && result_ref.get () == null && indirect_ref.get () == null && direct_ref.get () == null);
		program = memory_program ();
		SsaDirectFieldPlace? detached = (SsaDirectFieldPlace) ((SsaLoadInstruction) program.functions[0].entry.instructions[6]).source;
		var detached_storage = WeakRef (detached.storage);
		program = null;
		assert (detached.field.containing_struct == detached.storage.structure);
		detached = null;
		assert (detached_storage.get () == null);
		program = memory_program ();
		SsaMemoryPlace? detached_indirect = ((SsaStoreInstruction) program.functions[0].entry.instructions[4]).target;
		var detached_parameter = WeakRef (((SsaIndirectFieldPlace) detached_indirect).pointer);
		program = null;
		assert (((SsaFieldPlace) detached_indirect).field.containing_struct == null && detached_parameter.get () != null);
		detached_indirect = null;
		assert (detached_parameter.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void memory_invalid() {
	for (int variant = 0; variant < 23; variant++) {
		try {
			SsaVerifier.verify (memory_program (variant));
		} catch (SsaError error) {
			Test.message ("malformed memory %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("invalid standalone memory %d accepted", variant);
	}
}

private void memory_dominance() {
	try {
		var types = new BuiltinTypes ();
		var file = new SourceFile.from_text ("memory-dominance", "P x");
		var span = SourceSpan (file, 0, file.length);
		var structure = new SsaStruct (span, span, "P", new StructType ("P"));
		structure.fields.add (new SsaStructField (span, span, "x", structure, types.int_type, 0));
		var storage = new SsaAddressableLocal (span, span, "s", structure.semantic_type, 0, 0, structure);
		var place = new SsaDirectFieldPlace (span, storage, structure.fields[0]);
		var blocks = new GenericArray<SsaBlock> ();
		for (int i = 0; i < 3; i++) {
			blocks.add (new SsaBlock (span, i, i));
		}
		var functions = new GenericArray<SsaFunction> ();
		var function = new SsaFunction (span, span, "f", types.int_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, blocks[0]);
		function.storage.add (storage);
		functions.add (function);
		blocks[0].complete (new SsaConditionalBranch (span, new SsaBooleanConstant (span, types.bool_type, BooleanLiteral.TRUE), new SsaEdge (blocks[1], new GenericArray<SsaValue> ()), new SsaEdge (blocks[2], new GenericArray<SsaValue> ())));
		blocks[1].instructions.add (new SsaInitializeInstruction (span, place, new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (1))));
		blocks[1].complete (new SsaBranch (span, new SsaEdge (blocks[2], new GenericArray<SsaValue> ())));
		var load = new SsaLoadInstruction (span, place, 0);
		blocks[2].instructions.add (load);
		blocks[2].complete (new SsaReturn (span, load.result));
		var structs = new GenericArray<SsaStruct> ();
		structs.add (structure);
		var program = new SsaProgram (span, functions, null, null, structs);
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			assert (error.message.contains ("initialization must precede and dominate"));
			return;
		}
		assert_not_reached ();
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void register_memory_tests() {
	Test.add_func ("/ssa-standalone/memory/model-lifetime", memory_model);
	Test.add_func ("/ssa-standalone/memory/malformed", memory_invalid);
	Test.add_func ("/ssa-standalone/memory/initialization-dominance", memory_dominance);
}
}
