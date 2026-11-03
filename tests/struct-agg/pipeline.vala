// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.StructAgg {
private void lifetime() throws GLib.Error {
	foreach (string name in new string[] {"basic", "pointer", "vector", "f64", "deep", "method", "generic"}) {
		CheckedProgram? checked = check (fixture (name));
		var symbol = WeakRef (checked.structs[0]);
		var field = WeakRef (checked.structs[0].fields[0]);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		checked = null;
		CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (symbol.get () == null && field.get () == null);
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
	var scalar = build (fixture ("scalarize"));
	assert (scalar.structs.length == 0);
	foreach (var function in scalar.functions) {
		assert (function.storage.length == 0);
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				assert (!(parameter.semantic_type is StructType));
			}
		}
	}
	var siblings = build (fixture ("siblings"));
	int nested = 0;
	foreach (var function in siblings.functions) {
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				if (parameter.origin_kind == SsaPromotionOrigin.FIELD && parameter.source_field_path.length == 2) {
					nested++;
				}
			}
		}
	}
	assert (nested >= 4);
	var addressed = build (fixture ("addressed"));
	var f = addressed.functions[1];
	assert (f.name == "pay_for_use" && f.storage.length == 1 && f.storage[0].name == "b");
	var pointer = build (fixture ("pointer"));
	var nabi = NativeAbiBuilder.build (pointer);
	assert (nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1 && nabi.functions[0].signature.physical_parameter_count == 2);
}

private void checked_owner_firewall() throws GLib.Error {
	var checked = check (fixture ("basic"));
	var body = checked.functions[0].body;
	var original = (CheckedStore) body.statements[2];
	var field = (CheckedFieldPlace) original.target;
	body.statements[2] = new CheckedStore (original.span, new CheckedFieldPlace (field.span, field.aggregate, checked.structs[1].fields[1]), original.value);
	bool rejected = false;
	try {
		CoreBuilder.build (checked);
	} catch (CoreError error) {
		rejected = error.message.contains ("exact StructType base");
	}
	assert (rejected);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct-agg/pipeline/all-stage-lifetimes", lifetime);
	add ("/struct-agg/pipeline/promotion-pay-for-use-pointer-abi", promotion);
	add ("/struct-agg/pipeline/checked-owner-firewall", checked_owner_firewall);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
