// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.StructCopy {
private void lifetime() throws GLib.Error {
	foreach (string name in new string[] {"basic", "assign", "nested", "deep", "vector", "f64", "pointer", "alias", "generic", "scalarize", "mixed", "method", "null-source", "null-destination"}) {
		CheckedProgram? checked = check (fixture (name));
		var body = WeakRef (checked.functions[0].body);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		checked = null;
		assert (body.get () == null);
		CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		CoreVerifier.verify_concrete (core);
		var core_ref = WeakRef (core);
		var field = WeakRef (core.structs[0].fields[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_ref.get () == null && field.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_ref = WeakRef (cfg);
		field = WeakRef (cfg.structs[0].fields[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_ref.get () == null && field.get () == null);
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
private void snapshots() throws GLib.Error {
	var checked = check (fixture ("pointer"));
	var core = CoreGenericMonomorphizer.build (CoreBuilder.build (checked));
	var cfg = CfgBuilder.build (core);
	var copy = cfg.functions[0];
	var instructions = copy.entry.instructions;
	assert (instructions[0] is CfgEvaluateInstruction && instructions[1] is CfgValidatePlace && instructions[2] is CfgEvaluateInstruction && instructions[3] is CfgValidatePlace);
	string[] names = {
		"x", "y", "v", "x", "y", "v"
	};
	for (int i = 0; i < 6; i++) {
		var read = (CfgEvaluateInstruction)instructions[4 + i];
		var leaf = (CfgFieldPlace)((CfgLoadValue)read.value).source;
		assert (leaf.field.name == names[i]);
		assert (leaf.aggregate is CfgFieldPlace);
		var write = (CfgStore)instructions[10 + i];
		assert (write.value == read.result && write.target.semantic_type == read.result.semantic_type);
	}
	var ssa = SsaBuilder.build (cfg);
	var si = ssa.functions[0].entry.instructions;
	assert (si.length == 14 && si[0] is SsaValidatePlaceInstruction && si[1] is SsaValidatePlaceInstruction);
	for (int i = 0; i < 6; i++) {
		var load = (SsaLoadInstruction)si[2 + i];
		var store = (SsaStoreInstruction)si[8 + i];
		assert (store.value == load.result);
	}
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.functions[0].signature.physical_parameter_count == 2 && nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
}
private void promotion() throws GLib.Error {
	foreach (string name in new string[] {"basic", "assign", "nested", "deep", "scalarize"}) {
		var ssa = build (fixture (name));
		assert (ssa.structs.length == 0);
		foreach (var f in ssa.functions) {
			assert (f.storage.length == 0);
			foreach (var b in f.blocks) {
				foreach (var parameter in b.parameters) {
					assert (!(parameter.semantic_type is StructType));
				}
				foreach (var instruction in b.instructions) {
					assert (instruction.result == null || !(instruction.result.semantic_type is StructType));
				}
			}
		}
	}
	var mixed = build (fixture ("mixed"));
	assert (mixed.functions[0].storage.length == 1 && mixed.functions[0].storage[0].name == "c");
	var generic = build (fixture ("generic"));
	foreach (var f in generic.functions) {
		foreach (var local in f.storage) {
			assert (local.name == "b");
		}
	}
}
private void checked_firewall() throws GLib.Error {
	for (int scenario = 0; scenario < 3; scenario++) {
		var checked = check (fixture ("basic"));
		var body = checked.functions[0].body;
		var original = (CheckedStructCopy)body.statements[1];
		body.statements[1] = new CheckedStructCopy (original.span, original.destination, scenario == 0 ? original.destination : original.source, scenario == 1 ? checked.types.int_type : original.semantic_type, scenario == 2 ? Copyability.NOT_COPYABLE : Copyability.COPYABLE, true);
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct-copy/pipeline/all-stage-lifetimes", lifetime);
	add ("/struct-copy/pipeline/destination-source-snapshots-delayed-writes", snapshots);
	add ("/struct-copy/pipeline/scalarization-mixed-storage-generics", promotion);
	add ("/struct-copy/pipeline/checked-model-firewalls", checked_firewall);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
