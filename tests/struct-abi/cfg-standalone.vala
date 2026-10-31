// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;
namespace Astra.Tests.StructAbiCfg {
private CfgProgram sample() throws GLib.Error {
	var s = SourceSpan (new SourceFile.from_text ("cfg-boundary", "x"), 0, 1);
	var t = new BuiltinTypes ();
	var structure = new CfgStruct (s, s, "S", new StructType ("S"));
	var fields = new GenericArray<SemanticType> ();
	fields.add (t.int_type);
	fields.add (t.f64_type);
	fields.add (t.vector_of (t.i16_type, 8));
	for (int i = 0; i < fields.length; i++) {
		structure.fields.add (new CfgStructField (s, s, "f%d".printf (i), structure, fields[i], i));
	}
	CopyabilityFields graph = (type) => type == structure.semantic_type ? fields : null;
	var shape = new StructValueShape ((StructType)structure.semantic_type, StructLeafOrder.enumerate (structure.semantic_type, graph));
	var structures = new GenericArray<CfgStruct> ();
	structures.add (structure);
	var functions = new GenericArray<CfgFunction> ();
	for (int i = 0; i < 2; i++) {
		var parameters = new GenericArray<CfgParameter> ();
		foreach (var leaf in shape.leaves) {
			parameters.add (new CfgParameter (s, s, "p%u".printf (parameters.length), leaf.semantic_type, parameters.length));
		}
		var entry = new CfgBlock.reserve (s, 0);
		var blocks = new GenericArray<CfgBlock> ();
		blocks.add (entry);
		var local = new CfgLocalPlace (s, s, "value", structure.semantic_type, 0);
		var locals = new GenericArray<CfgLocalPlace> ();
		locals.add (local);
		var f = new CfgFunction (s, s, i == 0 ? "identity" : "forward", structure.semantic_type, i, parameters, locals, blocks, entry);
		var group = new StructBoundaryGroup (0, 0, shape);
		f.struct_parameters.add (group);
		f.struct_result = shape;
		local.struct_parameter = group;
		for (int j = 0; j < 3; j++) {
			var field = new CfgFieldPlace (s, local, structure.fields[j]);
			f.field_places.add (field);
			entry.instructions.add (new CfgInitialize (s, field, new CfgParameterValue (s, parameters[j])));
		}
		var leaves = new GenericArray<CfgValue> ();
		foreach (var field in f.field_places) {
			var result = new CfgEvaluatedValue (s, field.semantic_type);
			entry.instructions.add (new CfgEvaluateInstruction (s, new CfgLoadValue (s, field), result));
			leaves.add (result);
		}
		if (i == 1) {
			var call = new CfgCallInstruction (s, functions[0], leaves, null);
			call.struct_arguments.add (new StructBoundaryGroup (0, 0, shape));
			call.struct_result = new CfgStructCallResults (s, shape);
			entry.instructions.add (call);
			entry.instructions.add (new CfgStructResultConsume (s, call.struct_result, StructResultUseKind.RETURN));
			leaves = new GenericArray<CfgValue> ();
			foreach (var result in call.struct_result.leaves) {
				leaves.add (result);
			}
		}
		entry.complete (s, new CfgStructReturn (s, shape, leaves));
		functions.add (f);
	}
	return new CfgProgram (s, functions, null, null, structures);
}
private void positive() {
	try {
		CfgProgram? p = sample ();
		CfgVerifier.verify (p);
		assert (CfgFlowChecker.check (p).diagnostic == null);
		assert (CfgDump.format (p).contains ("struct-return"));
		var call = (CfgCallInstruction)p.functions[1].entry.instructions[6];
		assert (call.result == null && call.struct_result.leaves.length == 3 && !(((Object)call.struct_result) is CfgValue));
		var owner = WeakRef (p.structs[0]);
		call = null;
		p = null;
		assert (owner.get () == null);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void invalid() {
	for (int scenario = 0; scenario < 11; scenario++) {
		bool rejected = false;
		try {
			var p = sample ();
			var f = p.functions[1];
			var s = f.span;
			var call = (CfgCallInstruction)f.entry.instructions[6];
			if (scenario == 0) {
				f.entry.instructions.remove_index (7);
			}
			if (scenario == 1) {
				f.entry.instructions.add (f.entry.instructions[7]);
			}
			if (scenario == 2) {
				call.struct_result.leaves.remove_index (2);
			}
			if (scenario == 3) {
				call.struct_result.leaves[0] = new CfgCallResultValue (s, p.structs[0].semantic_type);
			}
			if (scenario == 4) {
				f.entry.instructions.remove_index (0);
			}
			if (scenario == 5) {
				f.entry.instructions[1] = new CfgInitialize (s, f.field_places[1], new CfgParameterValue (s, f.parameters[0]));
			}
			if (scenario == 6) {
				f.entry.instructions.add (new CfgStore (s, f.field_places[0], call.struct_result.leaves[0]));
			}
			if (scenario == 7) {
				call.struct_arguments.remove_index (0);
			}
			if (scenario == 8) {
				f.parameters[0] = new CfgParameter (s, s, "p0", new TypeParameterType ("T"), 0);
			}
			if (scenario == 9) {
				var leaves = ((CfgStructReturn)f.entry.terminator).leaves;
				var temp = leaves[0];
				leaves[0] = leaves[1];
				leaves[1] = temp;
			}
			if (scenario == 10) {
				f.entry.instructions[7] = new CfgStructResultConsume (s, call.struct_result, StructResultUseKind.ARGUMENT);
			}
			CfgVerifier.verify (p);
		} catch (GLib.Error e) {
			rejected = true;
		}
		if (!rejected) {
			GLib.error ("accepted forged boundary %d", scenario);
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-abi/cfg/independent-parameters-local-leaves-snapshots-results", positive);
	Test.add_func ("/struct-abi/cfg/unresolved-contract-order-acquisition-mutation-firewalls", invalid);
	return Test.run ();
}
}
