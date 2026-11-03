// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.StructAbiCore {
private CoreProgram sample() {
	var s = SourceSpan (new SourceFile.from_text ("core-boundary", "x"), 0, 1);
	var t = new BuiltinTypes ();
	var structure = new CoreStruct (s, s, "S", new StructType ("S"));
	structure.fields.add (new CoreStructField (s, s, "x", structure, t.int_type, 0));
	structure.fields.add (new CoreStructField (s, s, "y", structure, t.f64_type, 1));
	structure.fields.add (new CoreStructField (s, s, "v", structure, t.vector_of (t.i16_type, 8), 2));
	var structures = new GenericArray<CoreStruct> ();
	structures.add (structure);
	var functions = new GenericArray<CoreFunction> ();
	for (int i = 0; i < 2; i++) {
		var parameters = new GenericArray<CoreParameter> ();
		parameters.add (new CoreParameter (s, s, "value", structure.semantic_type, 0));
		var local = new CoreLocalPlace (s, s, "value", structure.semantic_type, 0, false, parameters[0]);
		var locals = new GenericArray<CoreLocalPlace> ();
		locals.add (local);
		var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
		var f = new CoreFunction (s, s, i == 0 ? "identity" : "forward", structure.semantic_type, parameters, locals, body);
		foreach (var field in structure.fields) {
			f.field_places.add (new CoreFieldPlace (s, local, field));
		}
		body.statements.add (new CoreAcquireStructParameter (s, local, parameters[0]));
		CoreStructProducer producer = new CoreStructSnapshot (s, local);
		if (i == 1) {
			var args = new GenericArray<CoreValue> ();
			args.add (new CoreStructArgument (s, functions[0].parameters[0], producer));
			producer = new CoreStructCallResult (s, structure.semantic_type, functions[0], args);
		}
		body.statements.add (new CoreStructReturn (s, producer));
		functions.add (f);
	}
	return new CoreProgram (s, functions, null, null, structures);
}

private void positive() {
	try {
		CoreProgram? p = sample ();
		CoreVerifier.verify_concrete (p);
		assert (p.functions[0].parameters[0].struct_value_contract.mode == StructValueMode.COPY_VALUE);
		assert (CoreDump.format (p).contains ("struct-return"));
		assert (!(((Object)((CoreStructReturn)p.functions[1].body.statements[1]).producer) is CoreValue));
		var owner = WeakRef (p.structs[0]);
		p = null;
		assert (owner.get () == null);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void invalid() {
	for (int scenario = 0; scenario < 10; scenario++) {
		var p = sample ();
		var f = p.functions[0];
		var s = f.span;
		if (scenario == 0) {
			f.parameters[0].struct_value_contract = null;
		}
		if (scenario == 1) {
			f.struct_result_contract = null;
		}
		if (scenario == 2) {
			f.body.statements.remove_index (0);
		}
		if (scenario == 3) {
			f.body.statements.insert (1, new CoreStore (s, f.field_places[0], new CoreLoadValue (s, f.field_places[0])));
		}
		if (scenario == 4) {
			f.body.statements[1] = new CoreReturn (s, new CoreLoadValue (s, f.locals[0]));
		}
		if (scenario == 5) {
			f.body.statements[1] = new CoreStructReturn (s, new CoreStructSnapshot (s, f.field_places[0]));
		}
		if (scenario == 6) {
			f.body.statements.insert (1, f.body.statements[0]);
		}
		if (scenario == 7) {
			p.structs[0].fields[0] = new CoreStructField (s, s, "x", p.structs[0], new ClassType ("Resource"), 0);
		}
		if (scenario == 8) {
			f.return_type = new TypeParameterType ("T");
			f.struct_result_contract = null;
		}
		if (scenario == 9) {
			var call = (CoreStructCallResult)((CoreStructReturn)p.functions[1].body.statements[1]).producer;
			p.functions[1].body.statements[1] = new CoreCallStatement (s, call.target, call.arguments);
		}
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (p);
		} catch (CoreError e) {
			rejected = true;
		}
		if (!rejected) {
			GLib.error ("accepted forged boundary %d", scenario);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-abi/core/independent-copy-contracts-forwarding-lifetime", positive);
	Test.add_func ("/struct-abi/core/contract-nominality-acquisition-mutation-value-firewalls", invalid);
	return Test.run ();
}

}
