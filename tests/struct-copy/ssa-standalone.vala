// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
namespace Astra.Tests.StructCopySsa {
private SsaProgram sample() throws SsaError {
	var s = SourceSpan (new SourceFile.from_text ("ssa-copy", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var structure = new SsaStruct (s, s, "S", new StructType ("S"));
	structure.fields.add (new SsaStructField (s, s, "x", structure, types.int_type, 0));
	structure.fields.add (new SsaStructField (s, s, "y", structure, types.f64_type, 1));
	structure.fields.add (new SsaStructField (s, s, "v", structure, types.vector_of (types.i16_type, 8), 2));
	var structures = new GenericArray<SsaStruct> ();
	structures.add (structure);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	for (int i = 0; i < 2; i++) {
		parameters.add (new SsaFunctionParameter (s, s, "p%d".printf (i), types.pointer_to (structure.semantic_type), i));
	}
	var destination = new SsaDereferencePlace (s, parameters[0], structure.semantic_type, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, 0));
	var source = new SsaDereferencePlace (s, parameters[1], structure.semantic_type, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 1, 0));
	var entry = new SsaBlock (s, 0, 0);
	entry.instructions.add (new SsaValidatePlaceInstruction (s, destination));
	entry.instructions.add (new SsaValidatePlaceInstruction (s, source));
	var snapshots = new GenericArray<SsaValue> ();
	foreach (var field in structure.fields) {
		var load = new SsaLoadInstruction (s, new SsaFieldPlace.projection (s, source, field), snapshots.length + 2);
		snapshots.add (load.result);
		entry.instructions.add (load);
	}
	for (int i = 0; i < 3; i++) {
		entry.instructions.add (new SsaStoreInstruction (s, new SsaFieldPlace.projection (s, destination, structure.fields[i]), snapshots[i]));
	}
	entry.complete (new SsaReturn (s, null));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (entry);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (s, s, "f", types.void_type, 0, parameters, blocks, entry));
	return new SsaProgram (s, functions, null, null, structures);
}
private void positive() {
	try {
		SsaProgram? p = sample ();
		SsaVerifier.verify (p);
		assert (SsaDump.format (p).contains ("validate-place"));
		foreach (var instruction in p.functions[0].entry.instructions) {
			assert (instruction.result == null || !(instruction.result.semantic_type is StructType));
		}
		assert (((SsaLoadInstruction)p.functions[0].entry.instructions[4]).result.semantic_type is VectorType);
		var owner = WeakRef (p.structs[0]);
		p = null;
		assert (owner.get () == null);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void invalid() {
	for (int scenario = 0; scenario < 3; scenario++) {
		bool rejected = false;
		try {
			var p = sample ();
			var instructions = p.functions[0].entry.instructions;
			if (scenario == 0) {
				var temp = instructions[2];
				instructions[2] = instructions[5];
				instructions[5] = temp;
			}
			if (scenario == 1) {
				var s = p.span;
				var destination = ((SsaValidatePlaceInstruction)instructions[0]).place;
				instructions[2] = new SsaLoadInstruction (s, destination, 2);
			}
			if (scenario == 2) {
				var s = p.span;
				var place = ((SsaValidatePlaceInstruction)instructions[0]).place;
				instructions[0] = new SsaValidatePlaceInstruction (s, new SsaFieldPlace.projection (s, place, new SsaStructField (s, s, "foreign", p.structs[0], p.structs[0].fields[0].semantic_type, 0)));
			}
			SsaVerifier.verify (p);
		} catch (SsaError e) {
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-copy/ssa/ordinary-leaf-values-vector-lifetime", positive);
	Test.add_func ("/struct-copy/ssa/use-before-snapshot-aggregate-value-foreign-place-firewalls", invalid);
	return Test.run ();
}
}
