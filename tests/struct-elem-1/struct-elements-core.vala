// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.StructElementsCore {
private CoreProgram sample(int variant = 0) {
	var s = SourceSpan (new SourceFile.from_text ("core-record-array", "x"), 0, 1);
	var t = new BuiltinTypes ();
	var record = new CoreStruct (s, s, "S", new StructType ("S"));
	record.fields.add (new CoreStructField (s, s, "x", record, variant == 1 ? (SemanticType) t.string_type : t.int_type, 0));
	record.fields.add (new CoreStructField (s, s, "y", record, t.f64_type, 1));
	var structures = new GenericArray<CoreStruct> ();
	if (variant != 2) {
		structures.add (record);
	}
	var type = t.array_of (record.semantic_type, 2);
	var local = new CoreLocalPlace (s, s, "a", type, 0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (s, s, "x", t.int_type, 0));
	parameters.add (new CoreParameter (s, s, "y", t.f64_type, 1));
	var entries = new GenericArray<CoreArrayRecordEntry> ();
	var places = new GenericArray<CoreFieldPlace> ();
	for (int i = 0; i < (variant == 3 ? 1 : 2); i++) {
		var index = new CoreIntegerValue.typed (s, (IntegerType) t.int_type, AstraIntegerValue.from_int64 ((IntegerType) t.int_type, variant == 4 ? 0 : i));
		var root = new CoreArrayElementPlace (s, local, type, index, new DataPointerProvenance (DataPointerOrigin.LOCAL, variant == 5 ? 3 : 0, 0));
		var initializers = new GenericArray<CoreStatement> ();
		for (int f = 1; f >= 0; f--) {
			var place = new CoreFieldPlace (s, root, record.fields[variant == 6 ? 0 : f]);
			places.add (place);
			initializers.add (new CoreInitialize (s, place, new CoreParameterValue (s, parameters[f])));
		}
		if (variant == 7) {
			initializers.remove_index (1);
		}
		if (variant == 8) {
			initializers.add (initializers[0]);
		}
		entries.add (new CoreArrayRecordEntry (s, root, initializers));
	}
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreArrayInitialize.record_entries (s, local, entries));
	statements.add (new CoreReturn (s, new CoreLoadValue (s, places[1])));
	if (variant == 9) {
		var first = statements[0];
		statements[0] = statements[1];
		statements[1] = first;
	}
	var function = new CoreFunction (s, s, "f", t.int_type, parameters, locals, new CoreBlock (s, statements));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	return new CoreProgram (s, functions, null, null, structures);
}

private void qualify() {
	try {
		CoreProgram? program = sample ();
		CoreVerifier.verify_concrete (program);
		assert (CoreDump.format (program).contains ("record-entry"));
		var root = WeakRef (program.structs[0]);
		program = null;
		assert (root.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant <= 9; variant++) {
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (sample (variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
}

public int run_core(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-elements/core/independent-complete-entry-order-and-malformed-storage", qualify);
	return Test.run ();
}

}
