// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
namespace Astra.Tests.GenCapCore {
private void boundary() {
	try {
		var unresolved = sample (GenericOperationKind.EQ);
		var operation = ((CoreReturn) unresolved.generic_functions[0].body.statements[0]).value;
		// A scalar-bool result cannot conceal an unresolved operation in a concrete root.
		unresolved.functions[0].body.statements.remove_index (0);
		unresolved.functions[0].body.statements.add (new CoreReturn (operation.span, operation));
		unresolved.generic_functions.remove_index (0);
		bool rejected = false;
		try {
			CfgBuilder.build (unresolved);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (sample (GenericOperationKind.DIV, "f64"));
		var weak_function = WeakRef (concrete.functions[1]);
		var cfg = CfgBuilder.build (concrete);
		concrete = null;
		assert (weak_function.get () == null);
		CfgVerifier.verify (cfg);
		assert (!CfgDump.format (cfg).contains ("generic-op"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-cap/cfg/forged-unresolved-bool-result-concrete-lifetime", boundary);
	return Test.run ();
}
}
