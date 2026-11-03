// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Semantic;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Sources {
private void lifetime() {
	try {
		foreach (string name in fixtures ()) {
			GenericArray<Witness> sources;
			CheckedProgram? checked = fixture (name, out sources);
			CoreProgram? core = CoreBuilder.build (checked);
			checked = null;
			core = CoreGenericMonomorphizer.build (core);
			CfgProgram? cfg = CfgBuilder.build (core);
			core = null;
			SsaProgram? ssa = SsaBuilder.build (cfg);
			cfg = null;
			var function = WeakRef (ssa.functions[0]);
			NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
			CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
			var artifact = LlvmLowering.lower (ssa, nabi, cabi);
			ssa = null;
			nabi = null;
			cabi = null;
			assert (function.get () == null);
			foreach (var source in sources) {
				assert (source.get () == null);
			}
			artifact.verify ();
			assert (!artifact.dump ().contains (".astra"));
			assert (artifact.requires_hosted_buffers == (name == "ownership" || name == "cad" || name == "partition"));
			assert (artifact.requires_c_floating == (name == "foreign"));
			if (artifact.requires_hosted_buffers) {
				bool rejected = false;
				try {
					LlvmBufferAllocation.qualify ("x86_64-unknown-none");
				} catch (LlvmError error) {
					rejected = error.message.contains ("owned runtime-array allocator is not qualified");
				}
				assert (rejected);
			}
			var target = new LlvmTargetMachineArtifact ();
			target.configure (artifact);
			artifact.verify ();
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/llvm/one-module-source-destruction-target-aggregation", lifetime);
	return Test.run ();
}

}
