// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.DataPointerSsa {
private SsaProgram sample(string name, int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("standalone-dptr", "pointer"), 0, 7);
	var type = t.resolve (name);
	var pointer_type = t.pointer_to (type);
	SemanticType parameter_type = pointer_type;
	switch (variant) {
	case 1:
		parameter_type = new TypedPointerType (t.bool_type);
		break;
	case 2:
		parameter_type = new TypedPointerType (t.vector_of (t.i16_type, 8));
		break;
	case 3:
		parameter_type = new TypedPointerType (new HandleType ("Resource"));
		break;
	case 4:
		parameter_type = new TypedPointerType (pointer_type);
		break;
	case 5:
		parameter_type = new TypedPointerType (t.void_type);
		break;
	case 6:
		parameter_type = t.raw_pointer_type;
		break;
	case 7:
		parameter_type = new RawPointerType (type);
		break;
	case 8:
		parameter_type = new SemanticType (TypeKind.TYPED_POINTER);
		break;
	case 9:
		parameter_type = new TypedPointerType (new BuiltinTypes ().resolve (name));
		break;
	case 10:
		parameter_type = new TypedPointerType (type);
		break;
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var parameter = new SsaFunctionParameter (span, span, "p", parameter_type, 0);
	parameters.add (parameter);
	SemanticType stored_type = variant == 11 ? t.bool_type : type;
	if (variant == 25) {
		stored_type = t.vector_of (t.i16_type, 8);
	}
	var storage = new SsaAddressableLocal (span, span, "x", stored_type, 0, 0);
	var local = new SsaLocalMemoryPlace (span, storage);
	SsaValue one = (type is F32Type) ? (SsaValue) new SsaFloatConstant (span, type, AstraF32Value.from_decimal ("1.25")) : new SsaIntegerConstant.typed (span, type, AstraIntegerValue.from_int64 ((IntegerType) type, 1));
	var boolean = new SsaBooleanConstant (span, t.bool_type, BooleanLiteral.TRUE);
	var origin = new DataPointerProvenance (DataPointerOrigin.LOCAL, 0, 0);
	var foreign_storage = new SsaAddressableLocal (span, span, "foreign", type, 0, 0);
	var address = new SsaAddressOfInstruction (span, variant == 13 ? (SemanticType) t.raw_pointer_type : pointer_type, 1, variant == 14 ? foreign_storage : storage, origin);
	var provenance = new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, variant == 18 ? 1 : 0);
	SsaValue pointer = parameter;
	if (variant == 21) {
		pointer = new SsaInstructionResult (span, pointer_type, 99);
	}
	var dereference = new SsaDereferencePlace (span, pointer, variant == 15 ? t.bool_type : type, provenance);
	var block = new SsaBlock (span, 0, 0);
	if (variant != 12) {
		block.instructions.add (new SsaInitializeInstruction (span, local, one));
	}
	block.instructions.add (address);
	block.instructions.add (variant == 16 ? (SsaInstruction) new SsaInitializeInstruction (span, dereference, one) : new SsaStoreInstruction (span, dereference, variant == 17 ? (SsaValue) boolean : one));
	var load = new SsaLoadInstruction (span, dereference, 2);
	block.instructions.add (load);
	block.instructions.add (new SsaStoreInstruction (span, local, load.result));
	var direct_load = new SsaLoadInstruction (span, local, 3);
	block.instructions.add (direct_load);
	if (variant == 19) {
		block.instructions[0] = new SsaLoadInstruction (span, local, 4);
		block.instructions.add (new SsaInitializeInstruction (span, local, one));
	}
	if (variant == 22) {
		block.instructions.add (new SsaInitializeInstruction (span, local, one));
	}
	if (variant == 24) {
		block.parameters.add (new SsaBlockParameter (span, span, "stale_x", type, 9, 0));
	}
	block.complete (new SsaReturn (span, direct_load.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	var function = new SsaFunction (span, span, "f", variant == 20 ? (SemanticType) pointer_type : type, 0, parameters, blocks, block);
	function.storage.add (storage);
	if (variant == 23) {
		function.storage.add (storage);
	}
	functions.add (function);
	return new SsaProgram (span, functions);
}

private void model() {
	try {
		foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
			SsaProgram? p = sample (name);
			SsaVerifier.verify (p);
			string dump = SsaDump.format (p);
			foreach (string word in new string[] {"address-taken", "address-of", "local-memory", "dereference-place", "null-traps", "load", "store"}) {
				assert (dump.contains (word));
			}
			var storage = WeakRef (p.functions[0].storage[0]);
			var type = WeakRef (p.functions[0].parameters[0].semantic_type);
			SsaDereferencePlace? place = (SsaDereferencePlace) ((SsaLoadInstruction) p.functions[0].entry.instructions[3]).source;
			p = null;
			assert (storage.get () == null && type.get () != null);
			assert (place.provenance.is_valid () && ((TypedPointerType) place.pointer.semantic_type).pointee == place.semantic_type);
			place = null;
			assert (type.get () == null);
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 25; variant++) {
		try {
			SsaVerifier.verify (sample ("i16", variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed SSA data pointer variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dptr/ssa/standalone-memory-and-lifetime", model);
	Test.add_func ("/dptr/ssa/standalone-malformed", malformed);
	return Test.run ();
}
}
