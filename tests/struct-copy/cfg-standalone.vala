// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;
namespace Astra.Tests.StructCopyCfg {
private CfgProgram sample() throws CfgError {
	var s = SourceSpan (new SourceFile.from_text ("cfg-copy", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var structure = new CfgStruct (s, s, "S", new StructType ("S"));
	structure.fields.add (new CfgStructField (s, s, "x", structure, types.int_type, 0));
	structure.fields.add (new CfgStructField (s, s, "y", structure, types.f64_type, 1));
	structure.fields.add (new CfgStructField (s, s, "v", structure, types.vector_of (types.i16_type, 8), 2));
	var structures = new GenericArray<CfgStruct> ();
	structures.add (structure);
	var parameters = new GenericArray<CfgParameter> ();
	for (int i = 0; i < 2; i++) {
		parameters.add (new CfgParameter (s, s, "p%d".printf (i), types.pointer_to (structure.semantic_type), i));
	}
	var destination = new CfgDereferencePlace (s, new CfgParameterValue (s, parameters[0]), structure.semantic_type, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, 0));
	var source = new CfgDereferencePlace (s, new CfgParameterValue (s, parameters[1]), structure.semantic_type, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 1, 0));
	var entry = new CfgBlock.reserve (s, 0);
	entry.instructions.add (new CfgValidatePlace (s, destination));
	entry.instructions.add (new CfgValidatePlace (s, source));
	var snapshots = new GenericArray<CfgEvaluatedValue> ();
	foreach (var field in structure.fields) {
		var snapshot = new CfgEvaluatedValue (s, field.semantic_type);
		snapshots.add (snapshot);
		entry.instructions.add (new CfgEvaluateInstruction (s, new CfgLoadValue (s, new CfgFieldPlace (s, source, field)), snapshot));
	}
	for (int i = 0; i < 3; i++) {
		entry.instructions.add (new CfgStore (s, new CfgFieldPlace (s, destination, structure.fields[i]), snapshots[i]));
	}
	entry.complete (s, new CfgReturn (s, null));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (entry);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (s, s, "f", types.void_type, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, entry));
	return new CfgProgram (s, functions, null, null, structures);
}

private void positive() {
	try {
		var p = sample ();
		CfgVerifier.verify (p);
		assert (CfgDump.format (p).contains ("validate-place"));
		for (int i = 2; i < 5; i++) {
			assert (p.functions[0].entry.instructions[i] is CfgEvaluateInstruction);
		}
		for (int i = 5; i < 8; i++) {
			assert (p.functions[0].entry.instructions[i] is CfgStore);
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void invalid() {
	for (int scenario = 0; scenario < 4; scenario++) {
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
				instructions.remove_index (4);
			}
			if (scenario == 2) {
				var v = (CfgValidatePlace)instructions[0];
				instructions[0] = new CfgValidatePlace (v.span, new CfgFieldPlace (v.span, v.place, new CfgStructField (v.span, v.span, "foreign", p.structs[0], p.structs[0].fields[0].semantic_type, 0)));
			}
			if (scenario == 3) {
				var f = p.functions[0];
				var s = f.span;
				var local = new CfgLocalPlace (s, s, "local", f.parameters[0].semantic_type, 0);
				f.locals.add (local);
				instructions.insert (0, new CfgInitialize (s, local, new CfgParameterValue (s, f.parameters[0])));
				instructions[1] = new CfgValidatePlace (s, local);
			}
			CfgVerifier.verify (p);
		} catch (CfgError e) {
			rejected = true;
			if (scenario == 3) {
				assert (e.message.contains ("Place validation requires memory-backed storage"));
			}
		}
		assert (rejected);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-copy/cfg/independent-leaf-snapshots-and-validation", positive);
	Test.add_func ("/struct-copy/cfg/undefined-snapshot-and-foreign-place-firewalls", invalid);
	return Test.run ();
}

}
