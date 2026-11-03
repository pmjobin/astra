// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.ObjectResult {
private void lifetime() {
	try {
		CheckedProgram? checked = check (read ("method"));
		var symbol = WeakRef (checked.classes[0]);
		var input = WeakRef (checked.classes[0].methods[1].result_storage);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (symbol.get () == null && input.get () == null);
		var core_class = WeakRef (core.classes[0]);
		var core_input = WeakRef (core.classes[0].methods[1].result_storage);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_class.get () == null && core_input.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var cfg_class = WeakRef (cfg.classes[0]);
		var cfg_input = WeakRef (cfg.classes[0].methods[1].result_storage);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_class.get () == null && cfg_input.get () == null);
		SsaVerifier.verify (ssa);
		var ssa_class = WeakRef (ssa.classes[0]);
		var ssa_input = WeakRef (ssa.classes[0].methods[1].result_storage);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		assert (ssa_class.get () == null && ssa_input.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		assert (cabi.cleanups.length == 0);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void companions() {
	try {
		foreach (var name in new string[] { "basic", "null", "param", "forward", "recursive", "life", "method", "vector", "slice", "owned", "empty", "no-deinit", "constructor-owned" }) {
			var ssa = build (read (name));
			var nabi = NativeAbiBuilder.build (ssa);
			var cabi = CAbiBuilder.build (ssa, nabi);
			assert (nabi.abi_version == (name == "slice" ? NativeAbiVersion.SLICE_V5 : name == "vector" ? NativeAbiVersion.VECTOR_V4 : NativeAbiVersion.SCALAR_PTR_V1));
			foreach (var f in ssa.functions) {
				if (f.result_storage != null) {
					var signature = nabi.functions[f.ordinal].signature;
					assert (signature.object_result != null && signature.result.scalar_type == NativeScalarType.PTR);
					assert (f.return_type is ClassType && f.result_contract == ResultOwnershipContract.OWNED_TRANSFER);
				}
			}
			if (name == "owned") {
				assert (cabi.cleanups.length == 1);
			}
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/pipeline/each-upstream-stage-dies-before-next-verification", lifetime);
	Test.add_func ("/obj-ret/pipeline/vector-slice-resource-method-and-profile-stability", companions);
	return Test.run ();
}

}
