// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.ObjectOwn {
private void lifetime() {
	try {
		CheckedProgram? checked = check (read ("consume"));
		var type = checked.classes[0].semantic_type;
		var symbol = WeakRef (checked.classes[0]);
		var local = WeakRef (checked.functions[1].locals[0]);
		var storage_symbol = WeakRef (checked.functions[1].locals[0].object_storage);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (symbol.get () == null && local.get () == null && storage_symbol.get () == null);
		CoreVerifier.verify (core);
		assert (core.functions[1].owned_locals[0].object_storage == core.functions[1].object_storage[0]);
		assert (core.functions[1].object_storage[0].transferable && core.cleanups[0].object_class == core.classes[0] && core.cleanups[0].destructor == core.classes[0].destructor);
		var core_class = WeakRef (core.classes[0]);
		var core_storage = WeakRef (core.functions[1].object_storage[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_class.get () == null && core_storage.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		assert (cfg.functions[1].locals[0].object_storage == cfg.functions[1].object_storage[0]);
		assert (cfg.functions[0].locals[0].incoming_parameter == cfg.functions[0].parameters[0] && cfg.functions[0].object_storage.length == 0);
		var cfg_class = WeakRef (cfg.classes[0]);
		var cfg_local = WeakRef (cfg.functions[1].locals[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_class.get () == null && cfg_local.get () == null);
		SsaVerifier.verify (ssa);
		assert (ssa.functions[0].object_storage.length == 0 && ssa.functions[0].storage.length == 0);
		assert (ssa.cleanups[0].object_class == ssa.classes[0] && ssa.cleanups[0].destructor == ssa.classes[0].destructor);
		var ssa_class = WeakRef (ssa.classes[0]);
		var type_witness = WeakRef (type);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		type = null;
		assert (ssa_class.get () == null && type_witness.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		assert (nabi.functions[0].signature.parameters[0].scalar_type == NativeScalarType.PTR && cabi.cleanups.length == 0);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void flow() {
	try {
		string prefix = "class C{int x;void touch(){}}void sink(owned C c){}void inspect(borrowed C c){}";
		foreach (var use in new string[] { "c.x=1;", "int n=c.x;", "c.touch();", "bool b=c==null;", "inspect(c);", "sink(move c);" }) {
			var cfg = CfgBuilder.build (CoreBuilder.build (check (prefix + "void f(owned C c){sink(move c);" + use + "}")));
			assert (CfgFlowChecker.check (cfg).diagnostic.message.contains ("moved owned value 'c'"));
		}
		foreach (var use in new string[] { "c.touch();", "sink(move c);" }) {
			var cfg = CfgBuilder.build (CoreBuilder.build (check (prefix + "void f(owned C c,bool b){if(b){sink(move c);}" + use + "}")));
			var result = OwnershipFlow.analyze (cfg.functions[2]);
			assert (result.dump ().contains ("MAYBE_OWNED") && result.diagnostic.message.contains ("may have been moved"));
		}
		var invalid_loop = CfgBuilder.build (CoreBuilder.build (check (prefix + "void f(owned C c,bool b){while(b){sink(move c);}}")));
		assert (CfgFlowChecker.check (invalid_loop).diagnostic.message.contains ("may have been moved"));
		foreach (var name in new string[] { "forward", "conditional", "loop", "loop-move", "loop-local", "resource", "order", "null" }) {
			var cfg = CfgBuilder.build (CoreBuilder.build (check (read (name))));
			assert (CfgFlowChecker.check (cfg).diagnostic == null);
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void borrowing() {
	try {
		build (read ("borrow-alias"));
		assert (CfgFlowChecker.check (CfgBuilder.build (CoreBuilder.build (check (read ("alias"))))).diagnostic.message.contains ("cannot borrow moved owned value 'c'"));
		build ("class C{int x;}void sink(owned C c){}void g(owned C c){C independent={x=1};sink(move c);independent.x=42;}");
		foreach (var text in new string[] {
				"class C{}void sink(borrowed C view,owned C c){}void g(borrowed C view,owned C c){sink(view,move c);}",
				"class C{int x;}void sink(owned C c){}void g(){owned C c={x=1};sink(move c);c.x=2;}",
				"class C{}void f(owned C a,borrowed C b){}void g(owned C c){f(move c,c);}",
				"class C{}int sink(owned C c){return 1;}void f(borrowed C c,int n){}void g(owned C c){f(c,sink(move c));}",
				"class C{}void sink(owned C c){}void f(borrowed C c,owned C d){}void g(owned C c,owned C d){sink(move c);f(c,move d);}",
				"class C{int x;}int sink(owned C c){return 1;}void g(owned C c){c.x=sink(move c);}",
				"class C{int x;}void sink(owned C c){}void g(borrowed C view,owned C c){sink(move c);view.x=42;}",
				"class C{int x;}void sink(owned C c){}void g(borrowed C view,owned C c){C alias=view;sink(move c);alias.x=42;}"
			}) {
			var cfg = CfgBuilder.build (CoreBuilder.build (check (text)));
			assert (CfgFlowChecker.check (cfg).diagnostic.message.contains ("moved owned value 'c'"));
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void commit() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (check (read ("precall-trap"))));
		var main = cfg.functions[2];
		int capture = -1;
		int arithmetic = -1;
		int commit = -1;
		int invoke = -1;
		for (int i = 0; i < main.entry.instructions.length; i++) {
			var instruction = main.entry.instructions[i];
			if (instruction is CfgOwnedArgumentCapture) {
				capture = i;
			}
			var evaluation = instruction as CfgEvaluateInstruction;
			if (evaluation != null && evaluation.value is CfgBinaryValue) {
				arithmetic = i;
			}
			if (instruction is CfgOwnedCallTransferCommit) {
				commit = i;
			}
			var call = instruction as CfgCallInstruction;
			if (call != null && call.target.name == "consume") {
				invoke = i;
			}
		}
		assert (capture >= 0 && arithmetic > capture && commit > arithmetic && invoke == commit + 1);
		var ssa = SsaBuilder.build (cfg);
		int transfers = 0;
		int disarmed = 0;
		foreach (var block in ssa.functions[2].blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call != null && call.owned_arguments.length > 0) {
					var transfer = call.owned_arguments[0];
					assert (transfer.value.semantic_type is ClassType && transfer.source_after_commit != null && transfer.source_after_commit.semantic_type == transfer.value.semantic_type && transfer.cleanup.is_object);
					transfers++;
				}
				var cleanup = instruction as SsaCleanupInstruction;
				if (cleanup != null && cleanup.value is SsaNullPointerConstant) {
					disarmed++;
				}
			}
		}
		assert (transfers == 1 && disarmed == 1);
		ssa = build (read ("conditional"));
		int phis = 0;
		foreach (var block in ssa.functions[1].blocks) {
			foreach (var parameter in block.parameters) {
				if (parameter.semantic_type is ClassType) {
					phis++;
				}
			}
		}
		assert (phis > 0);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void profiles() {
	try {
		foreach (var name in new string[] { "consume", "multiple", "resource", "slice", "vector", "method", "constructor", "no-deinit", "empty" }) {
			var ssa = build (read (name));
			var nabi = NativeAbiBuilder.build (ssa);
			var cabi = CAbiBuilder.build (ssa, nabi);
			assert (nabi.abi_version == (name == "slice" ? NativeAbiVersion.SLICE_V5 : name == "vector" ? NativeAbiVersion.VECTOR_V4 : NativeAbiVersion.SCALAR_PTR_V1));
			for (int f = 0; f < ssa.functions.length; f++) {
				for (int i = 0; i < ssa.functions[f].parameters.length; i++) {
					if (ssa.functions[f].parameters[i].semantic_type is ClassType) {
						assert (nabi.functions[f].signature.parameters[i].scalar_type == NativeScalarType.PTR);
					}
				}
			}
			assert (cabi.cleanups.length == (name == "resource" ? 1 : 0));
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-own/pipeline/stage-lifetime-exact-storage-and-contract", lifetime);
	Test.add_func ("/obj-own/ownership/owned-moved-joins-loops-and-mixed-domains", flow);
	Test.add_func ("/obj-own/ownership/temporary-same-call-and-nested-borrow-lifetimes", borrowing);
	Test.add_func ("/obj-own/pipeline/capture-trap-commit-null-disarm-and-phi", commit);
	Test.add_func ("/obj-own/nabi/existing-ptr-vector-slice-and-resource-contracts", profiles);
	return Test.run ();
}

}
