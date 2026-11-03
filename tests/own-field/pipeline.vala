// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.OwnedFieldPipeline {
private void lifetime() {
	try {
		foreach (var name in new string[] { "basic", "multi", "borrow", "replace", "null", "result", "generic", "alias", "deinit-replace", "branch", "reentrant" }) {
			SsaProgram? ssa = build (name);
			var ssa_class = WeakRef (ssa.classes[0]);
			var ssa_field = WeakRef (ssa.classes[0].fields[0]);
			var nabi = NativeAbiBuilder.build (ssa);
			var cabi = CAbiBuilder.build (ssa, nabi);
			ssa = null;
			assert (ssa_class.get () == null && ssa_field.get () == null);
			NativeAbiVerifier.verify (nabi);
			CAbiVerifier.verify (cabi);
			assert (nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/own-field/pipeline/destroy-each-upstream-stage-before-next-verification", lifetime);
	return Test.run ();
}

}
