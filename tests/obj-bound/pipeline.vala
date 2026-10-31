// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.ObjectBound {
private void lifetime() {
	try {
		CheckedProgram? checked = check ("class C{int x;}void f(borrowed C c){C local=c;local.x=42;helper(local);}void helper(borrowed C c){}");
		var type = checked.classes[0].semantic_type;
		var parameter = WeakRef (checked.functions[0].symbol.parameters[0]);
		var region = WeakRef (checked.functions[0].body.region);
		var declaration = WeakRef (checked.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (parameter.get () == null && region.get () == null && declaration.get () == null);
		CoreVerifier.verify (core);
		assert (core.functions[0].parameters.length == 1 && core.functions[0].parameters[0].semantic_type == type && core.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && core.functions[0].object_storage.length == 0);
		var core_parameter = WeakRef (core.functions[0].parameters[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_parameter.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		assert (cfg.functions[0].parameters.length == 1 && cfg.functions[0].parameters[0].semantic_type == type && cfg.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && cfg.functions[0].object_storage.length == 0);
		var cfg_parameter = WeakRef (cfg.functions[0].parameters[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_parameter.get () == null);
		SsaVerifier.verify (ssa);
		assert (ssa.functions[0].parameters.length == 1 && ssa.functions[0].parameters[0].semantic_type == type && ssa.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
		assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].object_storage.length == 0);
		var ssa_parameter = WeakRef (ssa.functions[0].parameters[0]);
		var type_witness = WeakRef (type);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		type = null;
		assert (ssa_parameter.get () == null && type_witness.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		assert (nabi.functions[0].signature.parameters.length == 1 && nabi.functions[0].signature.physical_parameter_count == 1 && nabi.functions[0].signature.parameters[0].scalar_type == NativeScalarType.PTR);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void values() {
	try {
		foreach (var name in new string[] { "basic", "mutate", "null", "alias", "identity", "copy", "forward", "recurse", "method", "struct-method", "constructor", "life", "slice", "vector", "owned", "empty", "null-field", "null-write", "null-method" }) {
			var ssa = build (read (name));
			SsaVerifier.verify (ssa);
			foreach (var function in ssa.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaCallInstruction;
						if (call == null) {
							continue;
						}
						assert (call.arguments.length == call.target.parameters.length);
						for (int i = 0; i < call.arguments.length; i++) {
							if (!(call.target.parameters[i].semantic_type is ClassType)) {
								continue;
							}
							assert (call.arguments[i].semantic_type == call.target.parameters[i].semantic_type && call.target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
						}
					}
				}
			}
		}
		var copy = build (read ("copy"));
		int phis = 0;
		foreach (var block in copy.functions[0].blocks) {
			foreach (var p in block.parameters) {
				if (p.semantic_type is ClassType) {
					phis++;
				}
			}
		}
		assert (phis >= 2);
		var forward = build (read ("forward"));
		foreach (var block in forward.functions[1].blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call != null) {
					assert (call.arguments[0] == forward.functions[1].parameters[0] && call.arguments[1] == call.arguments[0]);
				}
			}
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void profiles() {
	try {
		foreach (var name in new string[] { "basic", "alias", "method", "constructor", "vector", "slice", "owned" }) {
			var ssa = build (read (name));
			var abi = NativeAbiBuilder.build (ssa);
			assert (abi.abi_version == (name == "vector" ? NativeAbiVersion.VECTOR_V4 : name == "slice" ? NativeAbiVersion.SLICE_V5 : NativeAbiVersion.SCALAR_PTR_V1));
			for (int f = 0; f < ssa.functions.length; f++) {
				for (int i = 0; i < ssa.functions[f].parameters.length; i++) {
					if (ssa.functions[f].parameters[i].semantic_type is ClassType) {
						assert (abi.functions[f].signature.parameters[i].scalar_type == NativeScalarType.PTR);
					}
				}
			}
		}
		assert (NativeAbiBuilder.build (build ("class C{}void f(){C c={};}")).abi_version == NativeAbiVersion.SCALAR_V0);
		assert (NativeAbiBuilder.build (build ("class C{}void f(borrowed C c,i16 n){}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
		assert (NativeAbiBuilder.build (build ("class C{}void f(f32 n,borrowed C c){}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
		assert (NativeAbiBuilder.build (build ("class C{}void f(borrowed C c,i16<8> v,borrowed int[] s,owned Resource r){}")).abi_version == NativeAbiVersion.SLICE_V5);
		var source = new StringBuilder ("class C{}void f(");
		for (int i = 0; i < 20; i++) {
			source.append_printf ("%sborrowed C p%d", i == 0 ? "" : ",", i);
		}
		source.append ("){}");
		assert (NativeAbiBuilder.build (build (source.str)).functions[0].signature.physical_parameter_count == 20);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void ordering() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (check ("class C{}int effect(){return 1;}void consume(borrowed C c,owned Resource r,int n){}void f(borrowed C c,owned Resource r){consume(c,move r,effect());}")));
		var events = new StringBuilder ();
		CfgEvaluateInstruction? object = null;
		CfgCallInstruction? consume = null;
		foreach (var instruction in cfg.functions[2].entry.instructions) {
			var evaluation = instruction as CfgEvaluateInstruction;
			if (evaluation != null && evaluation.value is CfgParameterValue && evaluation.value.semantic_type is ClassType) {
				events.append ("object ");
				object = evaluation;
			}
			if (instruction is CfgOwnedArgumentCapture) {
				events.append ("capture ");
			}
			if (instruction is CfgOwnedCallTransferCommit) {
				events.append ("commit ");
			}
			var call = instruction as CfgCallInstruction;
			if (call != null) {
				events.append (call.target.name + " ");
				if (call.target.name == "consume") {
					consume = call;
				}
			}
		}
		assert (events.str == "object capture effect commit consume " && consume.arguments[0] == object.result);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		SsaVerifier.verify (SsaBuilder.build (cfg));
		cfg = CfgBuilder.build (CoreBuilder.build (check ("class C{}int effect(borrowed Resource r){return 1;}void consume(borrowed C c,owned Resource r,int n){}void f(borrowed C c,owned Resource r){consume(c,move r,effect(r));}")));
		assert (CfgFlowChecker.check (cfg).diagnostic.message.contains ("moved owned value 'r'"));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void malformed_nabi() {
	try {
		var ssa = build ("class A{}class B{}void f(borrowed A a){}void g(borrowed B b){}");
		var abi = NativeAbiBuilder.build (ssa);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		for (int i = 0; i < ssa.functions.length; i++) {
			map.insert (ssa.functions[i], abi.functions[i]);
		}
		assert (abi.functions[0].signature.parameters[0].abi_type.same_type (abi.functions[1].signature.parameters[0].abi_type));
		var arguments = new GenericArray<SsaValue> ();
		arguments.add (ssa.functions[1].parameters[0]);
		var call = new SsaCallInstruction (ssa.span, null, -1, ssa.functions[0], arguments);
		bool rejected = false;
		try {
			NativeAbiValidator.validate_call (call, abi, map, "mismatch");
		} catch (NativeAbiError e) {
			rejected = e.message.contains ("exact semantic ClassType");
		}
		assert (rejected);
		foreach (var bad in new NativeAbiType[] { new NativeScalarAbiType (NativeScalarType.I32), new NativeSliceType (), new NativeVectorType (NativeScalarType.I16, 8) }) {
			abi.functions[0].signature.parameters[0] = new NativeParameter.typed (ssa.span, ssa.span, "a", 0, bad);
			rejected = false;
			try {
				NativeAbiValidator.validate_ssa_calls (ssa, abi, map);
			} catch (NativeAbiError e) {
				rejected = e.message.contains ("parameter channel type");
			}
			assert (rejected);
		}
		foreach (var contract in new PointerParameterContract[] { PointerParameterContract.UNMANAGED }) {
			rejected = false;
			try {
				NativeTypeMapper.map_parameter (ssa.classes[0].semantic_type, contract);
			} catch (NativeAbiError e) {
				rejected = e.message.contains ("borrowed-noescape");
			}
			assert (rejected);
		}
		assert (((NativeScalarAbiType) NativeTypeMapper.map_parameter (ssa.classes[0].semantic_type, PointerParameterContract.OWNED_TRANSFER)).scalar_type == NativeScalarType.PTR);
		rejected = false;
		try {
			NativeTypeMapper.map_result (ssa.classes[0].semantic_type);
		} catch (NativeAbiError e) {
			rejected = true;
		}
		assert (rejected);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/pipeline/one-exact-value-contract-and-stage-lifetimes", lifetime);
	Test.add_func ("/obj-bound/pipeline/fields-methods-copies-phis-forwarding-and-call-binding", values);
	Test.add_func ("/obj-bound/pipeline/existing-profiles-and-mixed-contracts", profiles);
	Test.add_func ("/obj-bound/pipeline/object-evaluation-and-delayed-owned-commit", ordering);
	Test.add_func ("/obj-bound/pipeline/reject-semantic-and-physical-nabi-mismatches", malformed_nabi);
	return Test.run ();
}
}
