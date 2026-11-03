// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Objects {
private void lifetime() throws GLib.Error {
	foreach (string fixture in new string[] {"basic", "method", "nested-construction", "empty"}) {
		CheckedProgram? checked = check (read (fixture));
		var declaration = WeakRef (checked.classes[0]);
		var region = WeakRef (checked.functions[0].body.region);
		var type = checked.classes[0].semantic_type;
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (declaration.get () == null && region.get () == null);
		CoreVerifier.verify (core);
		assert (core.classes[0].semantic_type == type && CoreDump.format (core).contains ("object-storage"));
		var core_class = WeakRef (core.classes[0]);
		var core_function = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_class.get () == null && core_function.get () == null);
		CfgVerifier.verify (cfg);
		assert (cfg.classes[0].semantic_type == type && CfgDump.format (cfg).contains ("object-ref"));
		var cfg_class = WeakRef (cfg.classes[0]);
		var cfg_function = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_class.get () == null && cfg_function.get () == null);
		SsaVerifier.verify (ssa);
		assert (ssa.classes[0].semantic_type == type && SsaDump.format (ssa).contains ("object-storage"));
		var ssa_class = WeakRef (ssa.classes[0]);
		var ssa_function = WeakRef (ssa.functions[0]);
		var type_witness = WeakRef (type);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		type = null;
		ssa = null;
		assert (ssa_class.get () == null && ssa_function.get () == null && type_witness.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
	}
}

private void storage_and_flow() throws GLib.Error {
	var basic = build (read ("basic"));
	assert (basic.functions[0].object_storage.length == 1 && basic.functions[0].storage.length == 0);
	int references = 0;
	foreach (var instruction in basic.functions[0].entry.instructions) {
		if (instruction is SsaObjectReferenceInstruction) {
			references++;
		}
	}
	assert (references == 1);
	assert (basic.classes[0].methods[0].receiver.contract.instance_type == basic.classes[0].semantic_type);
	foreach (string fixture in new string[] {"branch", "branch-null", "loop"}) {
		var p = build (read (fixture));
		int phis = 0;
		foreach (var function in p.functions) {
			foreach (var storage in function.storage) {
				assert (!(storage.semantic_type is ClassType));
			}
			foreach (var block in function.blocks) {
				foreach (var parameter in block.parameters) {
					if (parameter.semantic_type is ClassType) {
						assert (parameter.origin_kind == SsaPromotionOrigin.SOURCE_LOCAL);
						phis++;
					}
					assert (!(parameter.semantic_type is StructType));
				}
			}
		}
		assert (phis > 0);
	}
	foreach (string fixture in new string[] {"alias", "identity", "null", "lifetime", "empty", "nominal", "construction-order", "nested-construction", "method", "integration", "slice", "owned", "order"}) {
		SsaVerifier.verify (build (read (fixture)));
	}
}

private void receiver_order() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check ("class C{int x;void consume(owned Resource r,int n,borrowed int[] s){this.x=n+s[0];}}int later(){return 2;}void f(owned Resource r){C c=null;int[1] a={1};c.consume(move r,later(),slice(a));}")));
	var events = new StringBuilder ();
	foreach (var instruction in cfg.functions[1].entry.instructions) {
		var evaluation = instruction as CfgEvaluateInstruction;
		if (evaluation != null && evaluation.value is CfgObjectValidateValue) {
			events.append ("validate ");
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
	assert (events.str == "validate capture later slice commit consume ");
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	SsaVerifier.verify (SsaBuilder.build (cfg));
	cfg = CfgBuilder.build (CoreBuilder.build (check ("class C{int x;}int effect(){return 42;}int main(){C c=null;c.x=effect();return 0;}")));
	events.truncate (0);
	foreach (var instruction in cfg.functions[1].entry.instructions) {
		var evaluation = instruction as CfgEvaluateInstruction;
		if (evaluation != null && evaluation.value is CfgObjectValidateValue) {
			events.append ("validate ");
		}
		if (instruction is CfgCallInstruction) {
			events.append ("effect ");
		}
		if (instruction is CfgStore) {
			events.append ("store ");
		}
	}
	assert (events.str == "validate effect store ");
}

private void profiles() throws GLib.Error {
	foreach (string type in new string[] {"int", "u8", "f32", "i16<8>"}) {
		var p = build ("class C{int x;%s f(%s n){return n;}}".printf (type, type));
		var nabi = NativeAbiBuilder.build (p);
		var expected = type == "int" ? NativeAbiVersion.SCALAR_PTR_V1 : type == "u8" ? NativeAbiVersion.SCALAR_INT_V2 : type == "f32" ? NativeAbiVersion.SCALAR_FP_V3 : NativeAbiVersion.VECTOR_V4;
		assert (nabi.abi_version == expected && nabi.functions[0].signature.physical_parameter_count == 2 && nabi.functions[0].declaring_type_is_class);
		try {
			NativeTypeMapper.map_type (p.classes[0].semantic_type);
		} catch (NativeAbiError error) {
			continue;
		}
		GLib.error ("ClassType acquired an explicit NABI channel");
	}
	var body_only = NativeAbiBuilder.build (build ("class C{}int main(){C c={};return 42;}"));
	assert (body_only.abi_version == NativeAbiVersion.SCALAR_V0);
	var slice = NativeAbiBuilder.build (build (read ("slice")));
	assert (slice.abi_version == NativeAbiVersion.SLICE_V5 && slice.functions[1].signature.receiver.scalar_type == NativeScalarType.PTR && slice.functions[1].signature.physical_parameter_count == 3);
	var nominal = NativeAbiBuilder.build (build (read ("nominal")));
	assert (!nominal.functions[1].declaring_type_is_class && nominal.functions[2].declaring_type_is_class && nominal.functions[3].declaring_type_is_class);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/object/pipeline/stage-lifetime-self-construction-and-exact-identities", lifetime);
	add ("/object/pipeline/reference-promotion-memory-and-branch-loop-phis", storage_and_flow);
	add ("/object/pipeline/receiver-before-arguments-owned-commit-and-field-rhs", receiver_order);
	add ("/object/pipeline/existing-native-profiles-and-no-object-channel", profiles);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
