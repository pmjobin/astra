// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.Generics {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check (read ("property"));
	var symbol = WeakRef (checked.generic_functions[0].definition);
	var capability = WeakRef (checked.generic_functions[0].capability_requirements[0].capability);
	var requirement = WeakRef (checked.generic_functions[0].capability_requirements[0]);
	CoreProgram? parameterized = CoreBuilder.build (checked);
	checked = null;
	assert (symbol.get () == null && capability.get () == null && requirement.get () == null);
	CoreVerifier.verify (parameterized);
	var generic = parameterized.generic_functions[1];
	var property = parameterized.classes[0].properties[0];
	var method = parameterized.classes[0].methods[0];
	var field = parameterized.classes[0].fields[0];
	var weak_generic = WeakRef (generic);
	var weak_parameter = WeakRef (generic.type_parameters[0]);
	generic = null;
	CoreProgram? concrete = CoreGenericMonomorphizer.build (parameterized);
	parameterized = null;
	assert (weak_generic.get () == null && weak_parameter.get () == null);
	int observed = 0;
	foreach (var f in concrete.functions) {
		if (f.generic_instance == null || f.generic_instance.origin.name != "observe") {
			continue;
		}
		observed++;
		assert (((CoreCallValue) ((CoreInitialize) f.body.statements[0]).value).target == property.getter);
		assert (((CoreCallValue) ((CoreInitialize) f.body.statements[1]).value).target == method);
		assert (((CoreIndirectFieldPlace) ((CoreLoadValue) ((CoreInitialize) f.body.statements[2]).value).source).field == field);
	}
	assert (observed == 2);
	property = null;
	method = null;
	field = null;
	var weak_function = WeakRef (concrete.functions[concrete.functions.length - 1]);
	CfgProgram? cfg = CfgBuilder.build (concrete);
	concrete = null;
	assert (weak_function.get () == null);
	CfgVerifier.verify (cfg);
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

private void integrations() throws GLib.Error {
	foreach (string name in new string[] {"eq", "ordered", "numeric", "bitwise", "shift", "multi", "forward", "recursive", "property", "owned", "object-owned"}) {
		SsaVerifier.verify (build (read (name)));
	}
	var unused = core ("T f<T>(T a,T b) where T : Numeric {return a+b;}");
	assert (unused.functions.length == 0);
	var parameterized = CoreBuilder.build (check (read ("forward")));
	var concrete = CoreGenericMonomorphizer.build (parameterized);
	int outer = 0;
	int phantom = 0;
	int bytes = 0;
	foreach (var f in concrete.functions) {
		if (f.generic_instance == null) {
			continue;
		}
		var instance = f.generic_instance;
		assert (instance.origin.name != "unused");
		if (instance.origin.name == "outer") {
			outer++;
			assert (instance.requests == 2);
		}
		if (instance.origin.name == "tag") {
			phantom++;
		}
		if (instance.origin.name == "inner" && instance.type_arguments[0] is IntegerType && ((IntegerType) instance.type_arguments[0]).bit_width == 8) {
			bytes++;
		}
	}
	assert (outer == 1 && phantom == 2 && bytes == 2);
}

private void profiles() throws GLib.Error {
	foreach (string type in new string[] {"int", "i8", "u32", "f32", "f64", "void*", "bool"}) {
		var ssa = build ("bool same<T>(T a,T b) where T : Eq {return a==b;}bool root(" + type + " a," + type + " b){return same<" + type + ">(a,b);}");
		var nabi = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (nabi);
		assert (nabi.functions.length == 2);
		var signature = nabi.functions[1].signature;
		assert (signature.parameters.length == 2 && signature.physical_parameter_count == 2);
		if (type == "f64") {
			assert (nabi.abi_version == NativeAbiVersion.FP64_V6);
		}
		if (type == "void*") {
			assert (nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
		}
		if (type == "int" || type == "bool") {
			assert (nabi.abi_version == NativeAbiVersion.SCALAR_V0);
		}
		assert (!NativeAbiDump.format (nabi).contains ("capability"));
	}
	bool rejected = false;
	try {
		SsaVerifier.verify (unresolved_ssa ());
	} catch (SsaError error) {
		rejected = true;
	}
	assert (rejected);
	rejected = false;
	try {
		NativeAbiBuilder.build (unresolved_ssa ());
	} catch (NativeAbiError error) {
		rejected = true;
	}
	assert (rejected);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-cap/pipeline/stage-lifetime-exact-members", lifetime);
	add ("/gen-cap/pipeline/forward-recursion-property-ownership-dedup", integrations);
	add ("/gen-cap/pipeline/nabi-concrete-profiles-firewalls", profiles);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
