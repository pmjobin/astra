// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Methods {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check (read ("recursive"));
	var symbol = WeakRef (checked.structs[0].methods[0]);
	var receiver = WeakRef (checked.structs[0].methods[0].receiver);
	var region = WeakRef (checked.functions[1].body.region);
	var contract = checked.structs[0].methods[0].receiver.semantic_type;
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (symbol.get () == null && receiver.get () == null && region.get () == null);
	CoreVerifier.verify (core);
	assert (core.structs[0].methods[0] == core.functions[1] && core.structs[0].methods[0].receiver.contract == contract);
	var core_method = WeakRef (core.functions[1]);
	var core_receiver = WeakRef (core.structs[0].methods[0].receiver);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_method.get () == null && core_receiver.get () == null);
	CfgVerifier.verify (cfg);
	assert (cfg.structs[0].methods[0] == cfg.functions[1] && cfg.structs[0].methods[0].receiver.contract == contract);
	var cfg_method = WeakRef (cfg.functions[1]);
	var cfg_receiver = WeakRef (cfg.structs[0].methods[0].receiver);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_method.get () == null && cfg_receiver.get () == null);
	SsaVerifier.verify (ssa);
	assert (ssa.structs[0].methods[0] == ssa.functions[1] && ssa.structs[0].methods[0].receiver.contract == contract);
	var ssa_method = WeakRef (ssa.functions[1]);
	var ssa_receiver = WeakRef (ssa.structs[0].methods[0].receiver);
	var contract_witness = WeakRef (contract);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	contract = null;
	ssa = null;
	assert (ssa_method.get () == null && ssa_receiver.get () == null && contract_witness.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	assert (nabi.functions[1].signature.receiver.scalar_type == NativeScalarType.PTR);
}

private void storage() throws GLib.Error {
	var p = build (read ("mutate"));
	assert (p.functions[0].storage.length == 1 && p.functions[0].storage[0].name == "c" && p.functions[0].storage[0].source_local_ordinal == 1);
	assert (p.structs[0].methods[0].storage.length == 0);
	int loads = 0;
	foreach (var block in p.structs[0].methods[0].blocks) {
		foreach (var instruction in block.instructions) {
			var load = instruction as SsaLoadInstruction;
			if (load == null) {
				continue;
			}
			assert (((SsaIndirectFieldPlace) load.source).pointer == p.structs[0].methods[0].receiver);
			loads++;
		}
	}
	assert (loads == 1);
	p = build ("struct Unused{int x;} struct S{int x;void f(){this.x=1;}} int main(){S a={x=40};a.x=a.x+2;return a.x;}");
	assert (p.functions[0].storage.length == 0 && p.functions[1].storage.length == 0);
	foreach (string name in new string[] {"basic", "alias", "call", "recursive", "vector", "slice", "owned", "order"}) {
		SsaVerifier.verify (build (read (name)));
	}
}

private void profiles() throws GLib.Error {
	foreach (string type in new string[] {"int", "u8", "f32", "i16<8>"}) {
		var p = build ("struct S{int x;%s f(%s n){return n;}}".printf (type, type));
		var nabi = NativeAbiBuilder.build (p);
		var expected = type == "int" ? NativeAbiVersion.SCALAR_PTR_V1 : type == "u8" ? NativeAbiVersion.SCALAR_INT_V2 : type == "f32" ? NativeAbiVersion.SCALAR_FP_V3 : NativeAbiVersion.VECTOR_V4;
		assert (nabi.abi_version == expected && nabi.functions[0].signature.physical_parameter_count == 2 && nabi.functions[0].signature.parameters.length == 1);
	}
	var ssa = build (read ("slice"));
	var abi = NativeAbiBuilder.build (ssa);
	assert (abi.abi_version == NativeAbiVersion.SLICE_V5 && abi.functions[1].signature.parameters[0].abi_type is NativeSliceType && abi.functions[1].signature.physical_parameter_count == 3);
	ssa = build (read ("owned"));
	abi = NativeAbiBuilder.build (ssa);
	foreach (var method in ssa.structs[0].methods) {
		assert (method.parameters.length == (method.name == "consume" ? 3 : 2));
		assert (abi.functions[method.ordinal].signature.receiver.scalar_type == NativeScalarType.PTR);
		if (method.name != "consume") {
			assert (method.owned_cleanup != null && abi.functions[method.ordinal].signature.result.scalar_type == NativeScalarType.PTR);
		}
	}
}

private void order() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check ("struct S{int x;void consume(owned Resource r,int n,borrowed int[] s){this.x=n+s[0];}} int later(){return 2;} void f(owned Resource r){S object={x=0};int[1] a={1};object.consume(move r,later(),slice(a));}")));
	var events = new StringBuilder ();
	foreach (var instruction in cfg.functions[1].entry.instructions) {
		var evaluation = instruction as CfgEvaluateInstruction;
		if (evaluation != null && evaluation.value.semantic_type is ReceiverType) {
			events.append ("receiver ");
		}
		if (instruction is CfgOwnedArgumentCapture) {
			events.append ("capture ");
		}
		if (evaluation != null && evaluation.value is CfgSliceFromArrayValue) {
			events.append ("slice ");
		}
		if (instruction is CfgOwnedCallTransferCommit) {
			events.append ("commit ");
		}
		var call = instruction as CfgCallInstruction;
		if (call != null) {
			events.append (call.target.name + " ");
		}
	}
	assert (events.str == "receiver capture later slice commit consume ");
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	SsaVerifier.verify (SsaBuilder.build (cfg));
	cfg = CfgBuilder.build (CoreBuilder.build (check ("struct S{int x;void f(owned Resource r,int n){}} int inspect(borrowed Resource r){return 1;} void bad(owned Resource r){S s={x=0};s.f(move r,inspect(r));}")));
	assert (CfgFlowChecker.check (cfg).diagnostic.message.contains ("moved owned value 'r'"));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/method/pipeline/stage-lifetimes-exact-recursive-identities", lifetime);
	add ("/method/pipeline/selective-storage-and-integration", storage);
	add ("/method/pipeline/existing-native-profiles", profiles);
	add ("/method/pipeline/receiver-before-arguments-and-owned-commit", order);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
