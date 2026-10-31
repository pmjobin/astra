// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.GenInfer {
private void lifetimes() {
	try {
		foreach (string name in fixtures ()) {
			CheckedProgram? checked = fixture (name);
			var checked_function = WeakRef (checked.functions[0]);
			var checked_argument = WeakRef (checked.functions[0].body);
			var parameter_symbol = WeakRef (checked.generic_functions[0].definition.type_parameters[0]);
			var source = WeakRef (checked.generic_functions[0].symbol.span.file);
			CoreProgram? core = CoreBuilder.build (checked);
			checked = null;
			assert (checked_function.get () == null && checked_argument.get () == null && parameter_symbol.get () == null);
			CoreVerifier.verify (core);
			CoreProgram? explicit_core = CoreBuilder.build (fixture (name, false));
			assert (CoreDump.format (core) == CoreDump.format (explicit_core));
			explicit_core = null;
			core = CoreGenericMonomorphizer.build (core);
			var core_function = WeakRef (core.functions[0]);
			CfgProgram? cfg = CfgBuilder.build (core);
			core = null;
			assert (core_function.get () == null);
			CfgVerifier.verify (cfg);
			assert (CfgFlowChecker.check (cfg).diagnostic == null);
			var cfg_function = WeakRef (cfg.functions[0]);
			SsaProgram? ssa = SsaBuilder.build (cfg);
			cfg = null;
			assert (cfg_function.get () == null);
			SsaVerifier.verify (ssa);
			var ssa_function = WeakRef (ssa.functions[0]);
			NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
			CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
			ssa = null;
			assert (ssa_function.get () == null);
			NativeAbiVerifier.verify (nabi);
			CAbiVerifier.verify (cabi);
			nabi = null;
			cabi = null;
			assert (source.get () == null);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void dedup() {
	try {
		var checked = check ("T identity<T>(T x){return x;}T outer<T>(T x){T a=identity(x);return identity<T>(a);}int main(){return outer(42);}");
		var core = CoreGenericMonomorphizer.build (CoreBuilder.build (checked));
		int count = 0;
		foreach (var function in core.functions) {
			var instance = function.generic_instance;
			if (instance != null && instance.origin.name == "identity") {
				count++;
				assert (instance.requests == 2 && instance.type_arguments[0] == checked.types.int_type);
			}
		}
		assert (count == 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-infer/pipeline/explicit-equivalence-destroy-predecessors", lifetimes);
	Test.add_func ("/gen-infer/pipeline/parameterized-request-global-dedup", dedup);
	return Test.run ();
}
}
