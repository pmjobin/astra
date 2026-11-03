// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenStructCore {
private void combined() {
	try {
		CoreProgram? source = sample ();
		var struct_witness = WeakRef (source.generic_structs[0]);
		var function_witness = WeakRef (source.generic_functions[0]);
		var concrete = CoreGenericMonomorphizer.build (source);
		source = null;
		assert (struct_witness.get () == null && function_witness.get () == null);
		assert (concrete.generic_structs.length == 0 && concrete.generic_functions.length == 0 && concrete.structs.length == 12 && concrete.functions.length == 7);
		assert (concrete.functions[1].generic_instance.requests == 2);
		foreach (var function in concrete.functions) {
			foreach (var local in function.locals) {
				assert (local.semantic_type.kind != TypeKind.GENERIC_STRUCT_APPLICATION && !(local.semantic_type is TypeParameterType));
			}
		}
		var shared = concrete.structs[0];
		assert (shared.generic_instance.display_name () == "Pair<f64,f64>" && shared.generic_instance.requesters.length == 3);
		assert (concrete.functions[1].field_places.length == 6 && concrete.functions[1].field_places[1].field.generic_origin == concrete.functions[2].field_places[1].field.generic_origin);
		assert (concrete.functions[1].field_places[1].field != concrete.functions[2].field_places[1].field);
		assert (concrete.functions[1].field_places[1].field == concrete.functions[1].field_places[4].field);
		CoreVerifier.verify_concrete (concrete);
		assert (!CoreDump.format (concrete).contains ("generic-field-place"));
		var empty = CoreGenericMonomorphizer.build (sample (false, true));
		assert (empty.structs.length == 0 && empty.functions.length == 1);
		assert (CoreDump.format (CoreGenericMonomorphizer.build (sample ())) == CoreDump.format (CoreGenericMonomorphizer.build (sample ())));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void keys() {
	try {
		var types = new BuiltinTypes ();
		var roots = new GenericArray<CoreFunction> ();
		roots.add (root (types));
		var program = new CoreProgram (span (), roots);
		var box = definition ("Box", 1, 0);
		field (box, "value", box.type_parameters[0].semantic_type);
		var tagged = definition ("Tagged", 1, 1);
		field (tagged, "value", types.int_type);
		var other = definition ("Other", 1, 2);
		field (other, "value", other.type_parameters[0].semantic_type);
		program.generic_structs.add (box);
		program.generic_structs.add (tagged);
		program.generic_structs.add (other);
		var pass = new CoreGenericMonomorphizer (program);
		var a = pass.request_struct (box.application (arguments (types.int_type)), roots[0]);
		var alias = pass.request_struct (box.application (arguments (types.i32_type)), roots[0]);
		var signed = pass.request_struct (box.application (arguments (types.i8_type)), roots[0]);
		var unsigned = pass.request_struct (box.application (arguments (types.u8_type)), roots[0]);
		var p = pass.request_struct (tagged.application (arguments (types.i8_type)), roots[0]);
		var q = pass.request_struct (tagged.application (arguments (types.u8_type)), roots[0]);
		var b = pass.request_struct (other.application (arguments (types.int_type)), roots[0]);
		assert (a == alias && a.generic_instance.requests == 2 && a.fields[0] == alias.fields[0]);
		assert (signed.semantic_type != unsigned.semantic_type && signed.fields[0] != unsigned.fields[0] && signed.fields[0].generic_origin == unsigned.fields[0].generic_origin);
		assert (p.semantic_type != q.semantic_type && p.fields[0].semantic_type == q.fields[0].semantic_type && a.semantic_type != b.semantic_type);
		assert (pass.struct_instances.length == 6 && a.generic_instance.field_for (box.fields[0]) == a.fields[0]);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cycles() {
	for (int scenario = 0; scenario < 4; scenario++) {
		var types = new BuiltinTypes ();
		var roots = new GenericArray<CoreFunction> ();
		roots.add (root (types));
		var program = new CoreProgram (span (), roots);
		var a = definition (scenario == 2 ? "Flip" : scenario == 3 ? "Freeze" : "A", scenario == 2 ? 2 : 1, 0);
		program.generic_structs.add (a);
		var t = a.type_parameters[0].semantic_type;
		if (scenario == 0) {
			field (a, "next", a.application (arguments (t)));
		}
		if (scenario == 1) {
			var b = definition ("B", 1, 1);
			program.generic_structs.add (b);
			field (a, "next", b.application (arguments (t)));
			field (b, "next", a.application (arguments (b.type_parameters[0].semantic_type)));
		}
		if (scenario == 2) {
			field (a, "next", a.application (arguments (a.type_parameters[1].semantic_type, t)));
		}
		if (scenario == 3) {
			field (a, "next", a.application (arguments (types.int_type)));
		}
		var pass = new CoreGenericMonomorphizer (program);
		bool rejected = false;
		try {
			pass.request_struct (a.application (scenario == 2 ? arguments (types.int_type, types.f64_type) : arguments (types.f64_type)), roots[0]);
		} catch (CoreError error) {
			rejected = error.message.contains ("recursive generic struct layout:");
			if (scenario == 2) {
				assert (error.message.contains ("Flip<int,f64> → Flip<f64,int> → Flip<int,f64>"));
			}
			if (scenario == 3) {
				assert (error.message.contains ("Freeze<f64> → Freeze<int> → Freeze<int>"));
			}
		}
		assert (rejected && pass.struct_instances.length == (scenario == 0 ? 1 : 2));
		foreach (var instance in pass.struct_instances) {
			assert (instance.generic_instance.state != GenericStructInstanceState.COMPLETE);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-struct/materializer/combined-functions-structs-lifetimes-fixed-point", combined);
	Test.add_func ("/gen-struct/materializer/exact-key-alias-sign-phantom-definition", keys);
	Test.add_func ("/gen-struct/materializer/direct-mutual-permuted-collapse-cycle-states", cycles);
	return Test.run ();
}

}
