// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.StructAggCore {
private CoreProgram sample(bool addressed = false, bool pointer = false) {
	var s = SourceSpan (new SourceFile.from_text ("standalone", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var inner = new CoreStruct (s, s, "Inner", new StructType ("Inner"));
	var outer = new CoreStruct (s, s, "Outer", new StructType ("Outer"), 1);
	var vector = types.vector_of (types.i16_type, 8);
	inner.fields.add (new CoreStructField (s, s, "x", inner, types.int_type, 0));
	inner.fields.add (new CoreStructField (s, s, "gain", inner, types.f64_type, 1));
	inner.fields.add (new CoreStructField (s, s, "vector", inner, vector, 2));
	outer.fields.add (new CoreStructField (s, s, "inner", outer, inner.semantic_type, 0));
	var structures = new GenericArray<CoreStruct> ();
	structures.add (inner);
	structures.add (outer);
	var parameters = new GenericArray<CoreParameter> ();
	var locals = new GenericArray<CoreLocalPlace> ();
	var projections = new GenericArray<CoreFieldPlace> ();
	CorePlace root;
	if (pointer) {
		var input = new CoreParameter (s, s, "p", types.pointer_to (outer.semantic_type), 0);
		parameters.add (input);
		root = new CoreDereferencePlace (s, new CoreParameterValue (s, input), outer.semantic_type, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, 0));
	} else {
		var local = new CoreLocalPlace (s, s, "o", outer.semantic_type, 0, addressed);
		locals.add (local);
		root = local;
	}
	var nested = new CoreFieldPlace (s, root, outer.fields[0]);
	var x = new CoreFieldPlace (s, nested, inner.fields[0]);
	var gain = new CoreFieldPlace (s, nested, inner.fields[1]);
	var v = new CoreFieldPlace (s, nested, inner.fields[2]);
	var statements = new GenericArray<CoreStatement> ();
	if (!pointer) {
		projections.add (nested);
		projections.add (x);
		projections.add (gain);
		projections.add (v);
		foreach (var field in inner.fields) {
			parameters.add (new CoreParameter (s, s, field.name, field.semantic_type, parameters.length));
		}
		var children = new GenericArray<CoreStatement> ();
		children.add (new CoreInitialize (s, x, new CoreParameterValue (s, parameters[0])));
		children.add (new CoreInitialize (s, gain, new CoreParameterValue (s, parameters[1])));
		children.add (new CoreInitialize (s, v, new CoreParameterValue (s, parameters[2])));
		statements.add (new CoreStructInitialize (s, nested, children));
	}
	statements.add (new CoreReturn (s, new CoreLoadValue (s, x)));
	var function = new CoreFunction (s, s, "f", types.int_type, parameters, locals, new CoreBlock (s, statements));
	foreach (var field in projections) {
		function.field_places.add (field);
	}
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	return new CoreProgram (s, functions, null, null, structures);
}
private void positive() {
	try {
		foreach (bool addressed in new bool[] {false, true}) {
			CoreProgram? program = sample (addressed);
			CoreVerifier.verify (program);
			assert (program.functions[0].field_places[1].is_promotable () == !addressed);
			assert (!program.functions[0].field_places[0].is_promotable ());
			assert (CoreDump.format (program).contains ("Inner::x"));
			CoreFieldPlace? detached = program.functions[0].field_places[1];
			var root = WeakRef (detached.root_local ());
			var descriptor = WeakRef (program.structs[0]);
			program = null;
			assert (descriptor.get () == null && root.get () != null);
			detached = null;
			assert (root.get () == null);
		}
		CoreVerifier.verify (sample (false, true));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void invalid() {
	for (int scenario = 0; scenario < 6; scenario++) {
		var program = sample ();
		var f = program.functions[0];
		var s = f.span;
		if (scenario == 0) {
			f.field_places[1] = new CoreFieldPlace (s, f.field_places[0], program.structs[1].fields[0]);
		}
		if (scenario == 1) {
			f.field_places[2] = f.field_places[1];
		}
		if (scenario == 2) {
			program.structs[0].fields[0] = new CoreStructField (s, s, "x", program.structs[0], program.structs[1].semantic_type, 0);
		}
		if (scenario == 3) {
			program.structs[0].fields[0] = new CoreStructField (s, s, "x", program.structs[0], program.structs[0].semantic_type, 0);
		}
		if (scenario == 4) {
			program.structs.remove_index (0);
		}
		if (scenario == 5) {
			f.field_places.remove_index (3);
		}
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
			if (scenario == 2 || scenario == 3) {
				assert (error.message.contains ("recursive by-value struct layout"));
			}
		}
		assert (rejected);
	}
}
private void initializer_firewalls() {
	for (int scenario = 0; scenario < 5; scenario++) {
		var program = sample ();
		var f = program.functions[0];
		var initializer = (CoreStructInitialize) f.body.statements[0];
		var children = initializer.initializers;
		if (scenario == 0) {
			children.remove_index (2);
		}
		if (scenario == 1) {
			children[1] = children[0];
		}
		if (scenario == 2) {
			children[0] = new CoreInitialize (f.span, initializer.target, new CoreParameterValue (f.span, f.parameters[0]));
		}
		if (scenario == 3) {
			children[0] = new CoreInitialize (f.span, f.field_places[1], new CoreLoadValue (f.span, f.field_places[1]));
		}
		if (scenario == 4) {
			f.body.statements[0] = new CoreInitialize (f.span, initializer.target, new CoreLoadValue (f.span, initializer.target));
		}
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-agg/core/recursive-places-vector-f64-lifetime", positive);
	Test.add_func ("/struct-agg/core/owner-canonical-cycle-firewalls", invalid);
	Test.add_func ("/struct-agg/core/recursive-initializer-firewalls", initializer_firewalls);
	return Test.run ();
}
}
