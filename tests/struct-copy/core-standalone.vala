// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.StructCopyCore {
private CoreStruct? leaf_owner;
private CoreStruct? resolve_leaf(SemanticType type) {
	return leaf_owner.semantic_type == type ? leaf_owner : null;
}
private CoreProgram sample() {
	var s = SourceSpan (new SourceFile.from_text ("core-copy", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var inner = new CoreStruct (s, s, "I", new StructType ("I"));
	var outer = new CoreStruct (s, s, "O", new StructType ("O"), 1);
	inner.fields.add (new CoreStructField (s, s, "x", inner, types.int_type, 0));
	inner.fields.add (new CoreStructField (s, s, "y", inner, types.f64_type, 1));
	inner.fields.add (new CoreStructField (s, s, "v", inner, types.vector_of (types.i16_type, 8), 2));
	outer.fields.add (new CoreStructField (s, s, "inner", outer, inner.semantic_type, 0));
	outer.fields.add (new CoreStructField (s, s, "tail", outer, types.int_type, 1));
	var structures = new GenericArray<CoreStruct> ();
	structures.add (inner);
	structures.add (outer);
	var parameters = new GenericArray<CoreParameter> ();
	foreach (var field in inner.fields) {
		parameters.add (new CoreParameter (s, s, field.name, field.semantic_type, parameters.length));
	}
	var locals = new GenericArray<CoreLocalPlace> ();
	var projections = new GenericArray<CoreFieldPlace> ();
	foreach (string name in new string[] {"a", "b"}) {
		var local = new CoreLocalPlace (s, s, name, outer.semantic_type, locals.length);
		locals.add (local);
		var nested = new CoreFieldPlace (s, local, outer.fields[0]);
		projections.add (nested);
		foreach (var field in inner.fields) {
			projections.add (new CoreFieldPlace (s, nested, field));
		}
		projections.add (new CoreFieldPlace (s, local, outer.fields[1]));
	}
	var children = new GenericArray<CoreStatement> ();
	for (int i = 0; i < 3; i++) {
		children.add (new CoreInitialize (s, projections[i + 1], new CoreParameterValue (s, parameters[i])));
	}
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreStructInitialize (s, projections[0], children));
	statements.add (new CoreInitialize (s, projections[4], new CoreParameterValue (s, parameters[0])));
	statements.add (new CoreStructCopy (s, locals[1], locals[0], outer.semantic_type, true));
	statements.add (new CoreStructCopy (s, locals[0], locals[1], outer.semantic_type));
	statements.add (new CoreReturn (s, new CoreLoadValue (s, projections[6])));
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
		CoreProgram? program = sample ();
		CoreVerifier.verify_concrete (program);
		leaf_owner = program.structs[0];
		var leaves = CoreStructLeaves.enumerate (program.structs[1], resolve_leaf);
		leaf_owner = null;
		assert (leaves.length == 4 && leaves[0].fields.length == 2 && leaves[2].semantic_type is VectorType && leaves[3].fields.length == 1);
		for (int i = 0; i < 3; i++) {
			assert (leaves[i].fields[1] == program.structs[0].fields[i]);
		}
		assert (CoreDump.format (program).contains ("struct-copy"));
		CoreStructCopy? copy = (CoreStructCopy)program.functions[0].body.statements[2];
		var root = WeakRef (copy.source);
		var owner = WeakRef (program.structs[0]);
		leaves = null;
		program = null;
		assert (owner.get () == null && root.get () != null);
		copy = null;
		assert (root.get () == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void invalid() {
	for (int scenario = 0; scenario < 9; scenario++) {
		var p = sample ();
		var f = p.functions[0];
		var s = f.span;
		var a = f.locals[0];
		var b = f.locals[1];
		if (scenario == 0) {
			f.body.statements[2] = new CoreStructCopy (s, b, b, b.semantic_type, true);
		}
		if (scenario == 1) {
			f.body.statements[2] = new CoreStructCopy (s, a, a, a.semantic_type, true);
		}
		if (scenario == 2) {
			f.body.statements[2] = new CoreStructCopy (s, b, a, b.semantic_type);
		}
		if (scenario == 3) {
			f.body.statements[2] = new CoreStructCopy (s, b, a, p.structs[0].semantic_type, true);
		}
		if (scenario == 4) {
			f.body.statements[2] = new CoreStructCopy (s, f.field_places[5], f.field_places[0], p.structs[0].semantic_type, true);
		}
		if (scenario == 5) {
			f.body.statements[2] = new CoreStructCopy (s, b, new CoreLocalPlace (s, s, "foreign", a.semantic_type, 0), b.semantic_type, true);
		}
		if (scenario == 6) {
			p.structs[0].fields[0] = new CoreStructField (s, s, "x", p.structs[0], new HandleType ("Resource"), 0);
		}
		if (scenario == 7) {
			f.body.statements[2] = new CoreInitialize (s, b, new CoreLoadValue (s, a));
		}
		if (scenario == 8) {
			f.body.statements[2] = new CoreStructCopy (s, b, f.field_places[0], b.semantic_type, true);
		}
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (p);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-copy/core/exact-copy-recursive-leaves-independent-lifetime", positive);
	Test.add_func ("/struct-copy/core/nominality-initialization-foreign-lifecycle-value-firewalls", invalid);
	return Test.run ();
}
}
