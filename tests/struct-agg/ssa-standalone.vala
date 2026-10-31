// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
namespace Astra.Tests.StructAggSsa {
private SsaProgram sample(string leaf = "int", bool pointer = false, bool duplicate = false, bool wrong_owner = false) throws SsaError {
	var s = SourceSpan (new SourceFile.from_text ("ssa", "x"), 0, 1);
	var types = new BuiltinTypes ();
	SemanticType type = leaf == "vector" ? (SemanticType) types.vector_of (types.i16_type, 8) : types.resolve (leaf);
	var inner = new SsaStruct (s, s, "Inner", new StructType ("Inner"));
	var outer = new SsaStruct (s, s, "Outer", new StructType ("Outer"), 1);
	inner.fields.add (new SsaStructField (s, s, "value", inner, type, 0));
	outer.fields.add (new SsaStructField (s, s, "a", outer, inner.semantic_type, 0));
	outer.fields.add (new SsaStructField (s, s, "b", outer, inner.semantic_type, 1));
	var structures = new GenericArray<SsaStruct> ();
	structures.add (inner);
	structures.add (outer);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (s, s, "value", type, 0));
	var storage = new SsaAddressableLocal (s, s, "o", outer.semantic_type, 0, 0, outer);
	SsaMemoryPlace root;
	if (pointer) {
		parameters.add (new SsaFunctionParameter (s, s, "p", types.pointer_to (outer.semantic_type), 1));
		root = new SsaDereferencePlace (s, parameters[1], outer.semantic_type, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 1, 0));
	} else {
		root = new SsaLocalMemoryPlace (s, storage);
	}
	var a = new SsaFieldPlace.projection (s, root, outer.fields[0]);
	var b = new SsaFieldPlace.projection (s, root, outer.fields[1]);
	var av = new SsaFieldPlace.projection (s, a, inner.fields[0]);
	var bv = new SsaFieldPlace.projection (s, b, wrong_owner ? outer.fields[0] : inner.fields[0]);
	assert (!SsaMemoryPlace.storage_equal (av, bv));
	var blocks = new GenericArray<SsaBlock> ();
	var block = new SsaBlock (s, 0, 0);
	blocks.add (block);
	if (!pointer) {
		block.instructions.add (new SsaInitializeInstruction (s, av, parameters[0]));
		block.instructions.add (new SsaInitializeInstruction (s, duplicate ? av : bv, parameters[0]));
	}
	block.instructions.add (new SsaStoreInstruction (s, bv, parameters[0]));
	var load = new SsaLoadInstruction (s, av, parameters.length);
	block.instructions.add (load);
	block.complete (new SsaReturn (s, load.result));
	var function = new SsaFunction (s, s, "f", type, 0, parameters, blocks, block);
	if (!pointer) {
		function.storage.add (storage);
	}
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	return new SsaProgram (s, functions, null, null, structures);
}
private void positive() {
	try {
		foreach (string leaf in new string[] {"int", "f64", "vector"}) {
			foreach (bool pointer in new bool[] {false, true}) {
				SsaVerifier.verify (sample (leaf, pointer));
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void invalid() {
	foreach (bool owner in new bool[] {false, true}) {
		bool rejected = false;
		try {
			SsaVerifier.verify (sample ("int", false, !owner, owner));
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
	}
	for (int scenario = 0; scenario < 4; scenario++) {
		bool rejected = false;
		try {
			var program = sample ();
			var inner = program.structs[0];
			var outer = program.structs[1];
			if (scenario < 2) {
				inner.fields[0] = new SsaStructField (inner.span, inner.span, "value", inner, scenario == 0 ? inner.semantic_type : outer.semantic_type, 0);
			}
			if (scenario == 2) {
				program.structs.remove_index (0);
			}
			if (scenario == 3) {
				program.functions[0].entry.instructions.remove_index (1);
			}
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = true;
			if (scenario < 2) {
				assert (error.message.contains ("recursive by-value record storage cycle"));
			}
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-agg/ssa/recursive-addresses-sibling-identity-vector-f64", positive);
	Test.add_func ("/struct-agg/ssa/duplicate-owner-firewalls", invalid);
	return Test.run ();
}
}
