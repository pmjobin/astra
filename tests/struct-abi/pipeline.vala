// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.StructAbi {
private void validate_plan(SsaProgram ssa, NativeAbiProgram nabi) throws NativeAbiError {
	var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	for (int i = 0; i < ssa.functions.length; i++) {
		map.insert (ssa.functions[i], nabi.functions[i]);
	}
	NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
}
private void lifetime() throws GLib.Error {
	foreach (string name in new string[] {"basic", "identity", "result", "order", "nested", "vector", "f32", "f64", "branch", "forward", "generic", "single", "cad", "method", "mixed", "pointer", "deep", "many"}) {
		CheckedProgram? checked = check (fixture (name));
		var body = WeakRef (checked.functions[0].body);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		checked = null;
		assert (body.get () == null);
		CoreVerifier.verify (parameterized);
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
		var semantic_type = WeakRef (ssa.structs[0].semantic_type);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		assert (ssa_ref.get () == null && semantic_type.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		assert (nabi.abi_version == NativeAbiVersion.AGGREGATE_V7);
	}
}
private void snapshots() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (fixture ("order")))));
	var f = cfg.functions[4];
	assert (f.name == "main");
	var body = f.entry.instructions;
	int first = -1;
	int last = -1;
	int mutate = -1;
	int call_index = -1;
	for (int i = 0; i < body.length; i++) {
		var snapshot = body[i] as CfgEvaluateInstruction;
		var load = snapshot == null ? null : snapshot.value as CfgLoadValue;
		if (load != null && load.source is CfgFieldPlace && ((CfgFieldPlace)load.source).root_local () != null && mutate == -1) {
			if (first == -1) {
				first = i;
			}
			last = i;
		}
		var call = body[i] as CfgCallInstruction;
		if (call != null && call.target.name == "mutate") {
			mutate = i;
		}
		if (call != null && call.target.name == "observe") {
			call_index = i;
			assert (call.struct_arguments.length == 2 && call.arguments.length == 6);
			assert (call.arguments[0] == ((CfgEvaluateInstruction)body[first]).result && call.arguments[1] == ((CfgEvaluateInstruction)body[last]).result);
		}
	}
	assert (first >= 0 && last == first + 1 && mutate > last && call_index > mutate);
	var ssa = SsaBuilder.build (cfg);
	foreach (var function in ssa.functions) {
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				assert (!(parameter.semantic_type is StructType));
			}
			foreach (var instruction in block.instructions) {
				assert (instruction.result == null || !(instruction.result.semantic_type is StructType));
			}
		}
	}
}
private void shapes() throws GLib.Error {
	var ssa = build (fixture ("nested"));
	var f = ssa.functions[0];
	assert (f.storage.length == 0 && f.parameters.length == 3 && f.struct_parameters.length == 1);
	var shape = f.struct_result;
	assert (shape.leaves.length == 3 && shape.leaves[0].spelling () == "0.0" && shape.leaves[1].spelling () == "0.1" && shape.leaves[2].spelling () == "1" && shape.leaves[2].semantic_type is VectorType);
	var nabi = NativeAbiBuilder.build (ssa);
	var plan = nabi.functions[0].signature.struct_result;
	assert (plan.leaves[0].abi_type.spelling () == "I32" && plan.leaves[1].abi_type.spelling () == "F64" && plan.leaves[2].abi_type is NativeVectorType);
	validate_plan (ssa, nabi);
	var single = NativeAbiBuilder.build (build (fixture ("single")));
	assert (single.functions[0].signature.struct_result.result_carrier == NativeStructResultCarrier.SINGLE_LEAF);
	var pointer = NativeAbiBuilder.build (build ("struct S{int x;}int f(S* p){return p->x;}"));
	assert (pointer.abi_version == NativeAbiVersion.SCALAR_PTR_V1 && pointer.struct_values.length == 0);
	var local = NativeAbiBuilder.build (build ("struct S{f64 x;}int f(){S a={x=3.5};S b=a;return 0;}"));
	assert (local.abi_version == NativeAbiVersion.SCALAR_V0 && local.struct_values.length == 0);
	var branch = build (fixture ("branch"));
	bool merged = false;
	foreach (var block in branch.functions[1].blocks) {
		if (block.parameters.length == 2) {
			merged = true;
			assert (block.parameters[0].semantic_type.kind != TypeKind.STRUCT && block.parameters[1].semantic_type.kind != TypeKind.STRUCT);
		}
	}
	assert (merged);
}
private void checked_firewall() throws GLib.Error {
	for (int scenario = 0; scenario < 3; scenario++) {
		var checked = check (fixture ("identity"));
		var f = checked.functions[0];
		var original = ((CheckedStructReturn)f.body.statements[0]).producer as CheckedStructSnapshot;
		if (scenario == 0) {
			f.symbol.struct_result_contract = null;
		}
		if (scenario == 1) {
			f.symbol.parameters[0].struct_value_contract = null;
		}
		if (scenario == 2) {
			f.body.statements[0] = new CheckedStructReturn (original.span, new CheckedStructSnapshot (original.span, original.source, Copyability.NOT_COPYABLE));
		}
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError e) {
			rejected = true;
		}
		assert (rejected);
	}
}
private void nominal_firewall() throws GLib.Error {
	var ssa = build ("struct A{int x;}struct B{int x;}A fa(A a){return a;}B fb(B b){return b;}");
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.struct_values.length == 2 && nabi.struct_values[0] != nabi.struct_values[1]);
	var original = nabi.functions[0];
	var signature = original.signature;
	var result = signature.struct_result;
	var parameter = signature.struct_parameters[0];
	signature.struct_result = nabi.struct_values[1];
	signature.struct_parameters[0] = new NativeStructParameterPlan (0, 0, nabi.struct_values[1]);
	bool rejected = false;
	try {
		NativeAbiVerifier.verify (nabi);
	} catch (NativeAbiError error) {
		rejected = error.message.contains ("original copy/move signature declaration");
	}
	assert (rejected);
	signature.struct_result = result;
	signature.struct_parameters[0] = parameter;
	NativeAbiVerifier.verify (nabi);
	validate_plan (ssa, nabi);
	// Build a self-consistent independent physical declaration for B. Its
	// identical fields still cannot substitute for the SSA declaration of A.
	var other = new NativeSignature (signature.abi_version, signature.parameters, signature.result);
	other.struct_result = nabi.struct_values[1];
	other.struct_parameters.add (new NativeStructParameterPlan (0, 0, nabi.struct_values[1]));
	other.bind_struct_transport (other.struct_parameters.length, other.struct_result);
	var functions = new GenericArray<NativeFunction> ();
	foreach (var native in nabi.functions) {
		var replacement = new NativeFunction (native.span, native.name_span, native.name, native.ordinal, native == original ? other : native.signature, native.linkage);
		replacement.bind_effects (native.effect_facts);
		replacement.bind_runtime_lifetimes (native.runtime_lifetimes);
		replacement.bind_scoped_readonly (native.scoped_readonly, native.readonly_inputs, native.callback_inputs, native.callback_input_count, native.callback_contract_supported);
		functions.add (replacement);
	}
	var physical = new NativeAbiProgram (nabi.span, nabi.abi_version, functions);
	foreach (var plan in nabi.struct_values) {
		physical.struct_values.add (plan);
	}
	NativeAbiVerifier.verify (physical);
	rejected = false;
	try {
		validate_plan (ssa, physical);
	} catch (NativeAbiError error) {
		rejected = error.message.contains ("exact source StructType declaration");
	}
	assert (rejected);
	NativeAbiVerifier.verify (nabi);
	validate_plan (ssa, nabi);
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct-abi/pipeline/all-stage-lifetimes", lifetime);
	add ("/struct-abi/pipeline/left-to-right-complete-argument-snapshot", snapshots);
	add ("/struct-abi/pipeline/shared-leaf-order-v7-scalarization-leaf-merges", shapes);
	add ("/struct-abi/pipeline/checked-contract-copyability-firewalls", checked_firewall);
	add ("/struct-abi/pipeline/same-layout-physical-plan-exact-nominal-firewall", nominal_firewall);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
