// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
namespace Astra.Tests.StructAbiSsa {
private SsaProgram sample() throws GLib.Error {
	var s = SourceSpan (new SourceFile.from_text ("ssa-boundary", "x"), 0, 1);
	var t = new BuiltinTypes ();
	var structure = new SsaStruct (s, s, "S", new StructType ("S"));
	var fields = new GenericArray<SemanticType> ();
	fields.add (t.int_type);
	fields.add (t.f64_type);
	fields.add (t.vector_of (t.i16_type, 8));
	for (int i = 0; i < fields.length; i++) {
		structure.fields.add (new SsaStructField (s, s, "f%d".printf (i), structure, fields[i], i));
	}
	CopyabilityFields graph = (type) => type == structure.semantic_type ? fields : null;
	var shape = new StructValueShape ((StructType)structure.semantic_type, StructLeafOrder.enumerate (structure.semantic_type, graph));
	var structures = new GenericArray<SsaStruct> ();
	structures.add (structure);
	var functions = new GenericArray<SsaFunction> ();
	for (int i = 0; i < 2; i++) {
		var parameters = new GenericArray<SsaFunctionParameter> ();
		var leaves = new GenericArray<SsaValue> ();
		foreach (var leaf in shape.leaves) {
			var parameter = new SsaFunctionParameter (s, s, "p%u".printf (parameters.length), leaf.semantic_type, parameters.length);
			parameters.add (parameter);
			leaves.add (parameter);
		}
		var entry = new SsaBlock (s, 0, 0);
		var blocks = new GenericArray<SsaBlock> ();
		blocks.add (entry);
		var f = new SsaFunction (s, s, i == 0 ? "identity" : "forward", structure.semantic_type, i, parameters, blocks, entry);
		f.struct_parameters.add (new StructBoundaryGroup (0, 0, shape));
		f.struct_result = shape;
		if (i == 1) {
			var call = new SsaCallInstruction (s, null, -1, functions[0], leaves);
			call.struct_arguments.add (new StructBoundaryGroup (0, 0, shape));
			var results = new GenericArray<SsaInstructionResult> ();
			foreach (var leaf in shape.leaves) {
				results.add (new SsaInstructionResult (s, leaf.semantic_type, results.length + 3));
			}
			call.struct_result = new SsaStructCallResults (s, shape, results);
			entry.instructions.add (call);
			entry.instructions.add (new SsaStructResultConsume (s, call.struct_result, StructResultUseKind.RETURN));
			leaves = new GenericArray<SsaValue> ();
			foreach (var result in results) {
				leaves.add (result);
			}
		}
		entry.complete (new SsaStructReturn (s, shape, leaves));
		functions.add (f);
	}
	return new SsaProgram (s, functions, null, null, structures);
}
private void positive() {
	try {
		SsaProgram? p = sample ();
		SsaVerifier.verify (p);
		var call = (SsaCallInstruction)p.functions[1].entry.instructions[0];
		assert (call.result == null && call.struct_result.leaves.length == 3 && !(((Object)call.struct_result) is SsaValue));
		foreach (var f in p.functions) {
			assert (f.storage.length == 0);
			foreach (var b in f.blocks) {
				assert (b.parameters.length == 0);
			}
		}
		assert (SsaDump.format (p).contains ("struct-return"));
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
			var call = (SsaCallInstruction)f.entry.instructions[0];
			var results = call.struct_result;
			if (scenario == 0) {
				f.entry.instructions.remove_index (1);
			}
			if (scenario == 1) {
				f.entry.instructions.add (f.entry.instructions[1]);
			}
			if (scenario == 2) {
				results.leaves.remove_index (2);
			}
			if (scenario == 3) {
				results.leaves[0] = new SsaInstructionResult (s, p.structs[0].semantic_type, 3);
			}
			if (scenario == 4) {
				results.leaves[1] = results.leaves[0];
			}
			if (scenario == 5) {
				call.struct_arguments.remove_index (0);
			}
			if (scenario == 6) {
				var leaves = ((SsaStructReturn)f.entry.terminator).leaves;
				var temp = leaves[0];
				leaves[0] = leaves[1];
				leaves[1] = temp;
			}
			if (scenario == 7) {
				f.entry.parameters.add (new SsaBlockParameter (s, s, "aggregate", p.structs[0].semantic_type, 6, 0));
			}
			if (scenario == 8) {
				f.parameters[0] = new SsaFunctionParameter (s, s, "p0", new TypeParameterType ("T"), 0);
			}
			if (scenario == 9) {
				var temp = f.entry.instructions[0];
				f.entry.instructions[0] = f.entry.instructions[1];
				f.entry.instructions[1] = temp;
			}
			if (scenario == 10) {
				f.entry.instructions[1] = new SsaStructResultConsume (s, results, StructResultUseKind.ARGUMENT);
			}
			SsaVerifier.verify (p);
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
	Test.add_func ("/struct-abi/ssa/independent-leaf-definitions-grouped-call-forwarding", positive);
	Test.add_func ("/struct-abi/ssa/aggregate-value-phi-incomplete-order-use-firewalls", invalid);
	return Test.run ();
}
}
