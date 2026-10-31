// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.GenOwn {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check (read ("recursive"));
	var weak_checked = WeakRef (checked.generic_functions[0].definition);
	var weak_owner = WeakRef (checked.generic_functions[0].locals[0]);
	var weak_capability = WeakRef (checked.generic_functions[0].capability_requirements[0].capability);
	CoreProgram? parameterized = CoreBuilder.build (checked);
	checked = null;
	assert (weak_checked.get () == null && weak_owner.get () == null && weak_capability.get () == null);
	CoreVerifier.verify (parameterized);
	var weak_generic = WeakRef (parameterized.generic_functions[0]);
	var weak_parameter = WeakRef (parameterized.generic_functions[0].type_parameters[0].semantic_type);
	foreach (var f in parameterized.generic_functions) {
		if (f.return_type is TypeParameterType) {
			assert (f.result_storage == null && f.owned_cleanup.type_parameter == f.return_type);
		}
	}
	CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
	parameterized = null;
	assert (weak_generic.get () == null && weak_parameter.get () == null);
	CoreVerifier.verify_concrete (core);
	var weak_core = WeakRef (core.functions[core.functions.length - 1]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (weak_core.get () == null);
	CfgVerifier.verify (cfg);
	foreach (var f in cfg.functions) {
		assert (OwnershipFlow.analyze (f).diagnostic == null);
	}
	var weak_cfg = WeakRef (cfg.functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (weak_cfg.get () == null);
	SsaVerifier.verify (ssa);
	var weak_ssa = WeakRef (ssa.functions[0]);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (weak_ssa.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
}
private void abi() throws GLib.Error {
	var core = concrete (read ("relay"));
	var ssa = SsaBuilder.build (CfgBuilder.build (core));
	var nabi = NativeAbiBuilder.build (ssa);
	int relays = 0;
	for (int i = 0; i < core.functions.length; i++) {
		var f = core.functions[i];
		if (f.generic_instance == null || f.generic_instance.origin.name != "relay") {
			continue;
		}
		relays++;
		var signature = nabi.functions[i].signature;
		bool object_result = f.return_type is ClassType;
		assert (signature.parameters.length == 1 && signature.physical_parameter_count == (object_result ? 2 : 1));
		assert ((signature.object_result != null) == object_result && (f.result_storage != null) == object_result);
		var returned = f.body.statements[1] as CoreOwnershipReturn;
		assert (returned.source == f.owned_locals[0] && returned.source.place.incoming_parameter == f.parameters[0] && returned.source.object_storage == null);
		assert (f.owned_cleanup.type_parameter == null && f.owned_cleanup.is_object == object_result);
	}
	assert (relays == 2 && nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
}
private void integrations() throws GLib.Error {
	foreach (string name in new string[] {"drop-resource", "drop-object", "conditional", "null", "class-nodeinit", "multi", "property", "struct", "loop", "order", "left-to-right", "short-circuit", "trap"}) {
		SsaVerifier.verify (build (read (name)));
	}
	var unused = concrete ("void dispose<T>(owned T v) where T : Ownable {}");
	assert (unused.functions.length == 0 && unused.generic_functions.length == 0);
	var dedup = concrete (read ("drop-object"));
	int count = 0;
	foreach (var f in dedup.functions) {
		if (f.generic_instance != null) {
			count++;
			assert (f.generic_instance.requests == 2 && f.generic_instance.origin.name == "dispose");
		}
	}
	assert (count == 1);
	CoreProgram? parameterized = CoreBuilder.build (check (read ("property")));
	var property = parameterized.classes[1].properties[0];
	var method = parameterized.classes[1].methods[0];
	var getter = property.getter;
	var materialized = CoreGenericMonomorphizer.build (parameterized);
	parameterized = null;
	int observed = 0;
	foreach (var f in materialized.functions) {
		if (f.generic_instance == null || f.generic_instance.origin.name != "observe") {
			continue;
		}
		observed++;
		assert (((CoreCallValue) ((CoreInitialize) f.body.statements[1]).value).target == getter);
		assert (((CoreCallValue) ((CoreInitialize) f.body.statements[2]).value).target == method);
	}
	assert (observed == 1);
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-own/pipeline/complete-stage-lifetime", lifetime);
	add ("/gen-own/pipeline/abi-differential-provenance", abi);
	add ("/gen-own/pipeline/integrations-dedup-unused-exact-members", integrations);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
