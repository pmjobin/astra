// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.GenStruct {
private void lifetime() throws GLib.Error {
	foreach (string name in new string[] {"basic", "nested", "generic-fn", "cap", "pointer", "f64", "vector", "box-matrix", "members"}) {
		CheckedProgram? checked = check (fixture (name));
		var symbol = WeakRef (checked.generic_structs[0].definition);
		var field = WeakRef (checked.generic_structs[0].fields[0]);
		var function = WeakRef (checked.generic_functions.length == 0 ? null : checked.generic_functions[0]);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		checked = null;
		assert (symbol.get () == null && field.get () == null && function.get () == null);
		CoreVerifier.verify (parameterized);
		var core_definition = WeakRef (parameterized.generic_structs[0]);
		var generic_function = WeakRef (parameterized.generic_functions.length == 0 ? null : parameterized.generic_functions[0]);
		CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (core_definition.get () == null && generic_function.get () == null);
		CoreVerifier.verify_concrete (core);
		var core_field = WeakRef (core.structs[0].fields[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_field.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_field = WeakRef (cfg.structs[0].fields[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_field.get () == null);
		SsaVerifier.verify (ssa);
		var ssa_ref = WeakRef (ssa);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		assert (ssa_ref.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
	}
}

private void promotion() throws GLib.Error {
	foreach (string name in new string[] {"basic", "nested", "generic-fn", "cap", "multi", "phantom", "dedup"}) {
		var ssa = build (fixture (name));
		assert (ssa.structs.length == 0);
		foreach (var function in ssa.functions) {
			assert (function.storage.length == 0);
		}
	}
	var pointer = build (fixture ("pointer"));
	assert (pointer.functions[2].name == "pay_for_use" && pointer.functions[2].storage.length == 1 && pointer.functions[2].storage[0].name == "b");
	var nabi = NativeAbiBuilder.build (pointer);
	assert (nabi.functions[0].signature.physical_parameter_count == 2 && nabi.functions[1].signature.physical_parameter_count == 1);
	var vector = build (fixture ("vector"));
	assert (vector.functions[0].name == "scalarized" && vector.functions[0].return_type is VectorType && vector.functions[0].storage.length == 0);
	var f64 = build (fixture ("f64"));
	assert (f64.functions[0].return_type is F64Type && f64.functions[0].storage.length == 0);
}

private void matrix() throws GLib.Error {
	var parameterized = CoreBuilder.build (check (fixture ("box-matrix")));
	var concrete = CoreGenericMonomorphizer.build (parameterized);
	assert (concrete.structs.length == 34 && concrete.functions.length == 69);
	int vectors = 0;
	foreach (var structure in concrete.structs) {
		assert (structure.fields.length == 1 && structure.fields[0].semantic_type == structure.generic_instance.type_arguments[0]);
		if (structure.fields[0].semantic_type is VectorType) {
			vectors++;
		}
	}
	assert (vectors == 24);
}

private void members() throws GLib.Error {
	var parameterized = CoreBuilder.build (check (fixture ("members")));
	var meter = parameterized.structs[0];
	var method = meter.methods[0];
	var property = meter.properties[0];
	var counter_property = parameterized.classes[0].properties[0];
	var before = (CoreCallValue) ((CoreInitialize) parameterized.generic_functions[0].body.statements[1]).value;
	assert (before.target == counter_property.getter);
	var concrete = CoreGenericMonomorphizer.build (parameterized);
	assert (concrete.structs[0] == meter && meter.methods[0] == method && meter.properties[0] == property && concrete.classes[0].properties[0] == counter_property);
	bool found = false;
	foreach (var function in concrete.functions) {
		if (function.generic_instance == null || function.generic_instance.origin.name != "observe") {
			continue;
		}
		var after = (CoreCallValue) ((CoreInitialize) function.body.statements[1]).value;
		assert (after.target == before.target && after.target == counter_property.getter && after.semantic_type == before.semantic_type);
		found = true;
	}
	assert (found);
	CoreVerifier.verify_concrete (concrete);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-struct/pipeline/checked-core-generic-cfg-ssa-nabi-lifetimes", lifetime);
	add ("/gen-struct/pipeline/promotion-selective-addressability-ptr-abi", promotion);
	add ("/gen-struct/pipeline/all-34-exact-concrete-fields", matrix);
	add ("/gen-struct/pipeline/exact-method-property-accessor-targets", members);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
