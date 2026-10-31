// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Lifecycle {
private void stages() {
	try {
		CheckedProgram? checked = check (read ("alias"));
		var ctor_symbol = WeakRef (checked.classes[0].constructor);
		var dtor_symbol = WeakRef (checked.classes[0].destructor);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (ctor_symbol.get () == null && dtor_symbol.get () == null);
		CoreVerifier.verify (core);
		var ctor_core = WeakRef (core.classes[0].constructor);
		var storage_core = WeakRef (core.functions[0].object_storage[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (ctor_core.get () == null && storage_core.get () == null);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var ctor_cfg = WeakRef (cfg.classes[0].constructor);
		var storage_cfg = WeakRef (cfg.functions[0].object_storage[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (ctor_cfg.get () == null && storage_cfg.get () == null);
		SsaVerifier.verify (ssa);
		assert (ssa.classes[0].constructor.receiver.contract.mode == ReceiverMode.INITIALIZING);
		assert (ssa.classes[0].destructor.receiver.contract.mode == ReceiverMode.LIVE);
		var ctor_ssa = WeakRef (ssa.classes[0].constructor);
		var storage_ssa = WeakRef (ssa.functions[0].object_storage[0]);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		assert (ctor_ssa.get () == null && storage_ssa.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		assert (NativeAbiDump.format (nabi).contains ("constructor initializing"));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void cleanups() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (check (read ("order"))));
		CfgVerifier.verify (cfg);
		var function = cfg.functions[0];
		var order = new StringBuilder ();
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var object = instruction as CfgLifecycleCallInstruction;
				if (object != null && !object.constructs) {
					order.append_printf ("O%d ", object.storage.cleanup_rank);
				}
				var resource = instruction as CfgCleanupInstruction;
				if (resource != null) {
					order.append_printf ("R%d ", ((CfgLocalPlace) ((CfgLoadValue) resource.value).source).ordinal);
				}
			}
		}
		assert (order.str == "O5 O4 O3 R2 O1 R0 ");
		var ssa = SsaBuilder.build (cfg);
		assert (SsaDump.format (ssa).contains ("object-deinit"));
		foreach (var name in new string[] { "return", "loop", "return-loop", "brace", "empty", "deinit", "constructor-trap", "argument-trap", "destructor-trap", "constructor-local", "init-unreachable" }) {
			SsaVerifier.verify (build (read (name)));
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void argument_commit() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (check ("class C{int x;init(owned Resource r,int n,borrowed int[] s){this.x=n+s[0];}}int later(){return 2;}void f(owned Resource r){int[1] a={1};C c=C.init(move r,later(),slice(a));}")));
		var events = new StringBuilder ();
		foreach (var instruction in cfg.functions[1].entry.instructions) {
			var evaluation = instruction as CfgEvaluateInstruction;
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
			if (evaluation != null && evaluation.value is CfgObjectReferenceValue) {
				events.append ("publish ");
			}
		}
		assert (events.str == "capture later slice commit init publish ");
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		SsaVerifier.verify (SsaBuilder.build (cfg));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void channels() {
	try {
		foreach (var name in new string[] { "init", "init-branch", "vector", "slice", "owned", "owned-argument-trap" }) {
			var ssa = build (read (name));
			var nabi = NativeAbiBuilder.build (ssa);
			if (name == "vector") {
				assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4);
			}
			if (name == "slice" || name == "owned") {
				assert (nabi.abi_version == NativeAbiVersion.SLICE_V5);
			}
			foreach (var function in nabi.functions) {
				if (function.kind == NativeCallableKind.CONSTRUCTOR || function.kind == NativeCallableKind.DESTRUCTOR) {
					assert (function.signature.result == null && function.signature.receiver.scalar_type == NativeScalarType.PTR);
				}
			}
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/pipeline/lifecycle-identities-survive-upstream-release", stages);
	Test.add_func ("/obj-life/pipeline/unified-cleanup-order-and-exits", cleanups);
	Test.add_func ("/obj-life/pipeline/native-contract-and-profile-integration", channels);
	Test.add_func ("/obj-life/pipeline/argument-capture-commit-before-construction-publication", argument_commit);
	return Test.run ();
}
}
