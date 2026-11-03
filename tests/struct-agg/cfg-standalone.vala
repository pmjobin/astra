// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;
namespace Astra.Tests.StructAggCfg {
private CfgProgram sample(bool addressed = false, bool pointer = false) {
	var s = SourceSpan (new SourceFile.from_text ("standalone", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var inner = new CfgStruct (s, s, "Inner", new StructType ("Inner"));
	var outer = new CfgStruct (s, s, "Outer", new StructType ("Outer"), 1);
	var vector = types.vector_of (types.i16_type, 8);
	inner.fields.add (new CfgStructField (s, s, "x", inner, types.int_type, 0));
	inner.fields.add (new CfgStructField (s, s, "gain", inner, types.f64_type, 1));
	inner.fields.add (new CfgStructField (s, s, "vector", inner, vector, 2));
	outer.fields.add (new CfgStructField (s, s, "inner", outer, inner.semantic_type, 0));
	var structures = new GenericArray<CfgStruct> ();
	structures.add (inner);
	structures.add (outer);
	var parameters = new GenericArray<CfgParameter> ();
	var locals = new GenericArray<CfgLocalPlace> ();
	var projections = new GenericArray<CfgFieldPlace> ();
	CfgPlace root;
	if (pointer) {
		var input = new CfgParameter (s, s, "p", types.pointer_to (outer.semantic_type), 0);
		parameters.add (input);
		root = new CfgDereferencePlace (s, new CfgParameterValue (s, input), outer.semantic_type, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, 0));
	} else {
		var local = new CfgLocalPlace (s, s, "o", outer.semantic_type, 0, addressed);
		locals.add (local);
		root = local;
	}
	var nested = new CfgFieldPlace (s, root, outer.fields[0]);
	var x = new CfgFieldPlace (s, nested, inner.fields[0]);
	var gain = new CfgFieldPlace (s, nested, inner.fields[1]);
	var v = new CfgFieldPlace (s, nested, inner.fields[2]);
	var statements = new GenericArray<CfgInstruction> ();
	if (!pointer) {
		projections.add (nested);
		projections.add (x);
		projections.add (gain);
		projections.add (v);
		foreach (var field in inner.fields) {
			parameters.add (new CfgParameter (s, s, field.name, field.semantic_type, parameters.length));
		}
		statements.add (new CfgInitialize (s, x, new CfgParameterValue (s, parameters[0])));
		statements.add (new CfgInitialize (s, gain, new CfgParameterValue (s, parameters[1])));
		statements.add (new CfgInitialize (s, v, new CfgParameterValue (s, parameters[2])));
	}
	var blocks = new GenericArray<CfgBlock> ();
	var entry = new CfgBlock.reserve (s, 0);
	foreach (var instruction in statements) {
		entry.instructions.add (instruction);
	}
	try {
		entry.complete (s, new CfgReturn (s, new CfgLoadValue (s, x)));
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
	blocks.add (entry);
	var function = new CfgFunction (s, s, "f", types.int_type, 0, parameters, locals, blocks, blocks[0]);
	foreach (var field in projections) {
		function.field_places.add (field);
	}
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	return new CfgProgram (s, functions, null, null, structures);
}

private void positive() {
	try {
		foreach (bool addressed in new bool[] {false, true}) {
			CfgProgram? program = sample (addressed);
			CfgVerifier.verify (program);
			assert (program.functions[0].field_places[1].is_promotable () == !addressed);
			assert (!program.functions[0].field_places[0].is_promotable ());
			assert (CfgDump.format (program).contains ("Inner::x"));
			CfgFieldPlace? detached = program.functions[0].field_places[1];
			var root = WeakRef (detached.root_local ());
			var descriptor = WeakRef (program.structs[0]);
			program = null;
			assert (descriptor.get () == null && root.get () != null);
			detached = null;
			assert (root.get () == null);
		}
		CfgVerifier.verify (sample (false, true));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void invalid() {
	for (int scenario = 0; scenario < 7; scenario++) {
		var program = sample ();
		var f = program.functions[0];
		var s = f.span;
		if (scenario == 0) {
			f.field_places[1] = new CfgFieldPlace (s, f.field_places[0], program.structs[1].fields[0]);
		}
		if (scenario == 1) {
			f.field_places[2] = f.field_places[1];
		}
		if (scenario == 2) {
			program.structs[0].fields[0] = new CfgStructField (s, s, "x", program.structs[0], program.structs[1].semantic_type, 0);
		}
		if (scenario == 3) {
			program.structs[0].fields[0] = new CfgStructField (s, s, "x", program.structs[0], program.structs[0].semantic_type, 0);
		}
		if (scenario == 4) {
			program.structs.remove_index (0);
		}
		if (scenario == 5) {
			f.field_places.remove_index (3);
		}
		if (scenario == 6) {
			f.entry.instructions.remove_index (2);
		}
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			rejected = true;
			if (scenario == 2 || scenario == 3) {
				assert (error.message.contains ("recursive by-value struct layout"));
			}
		}
		assert (rejected);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-agg/cfg/recursive-places-vector-f64-lifetime", positive);
	Test.add_func ("/struct-agg/cfg/owner-canonical-cycle-firewalls", invalid);
	return Test.run ();
}

}
