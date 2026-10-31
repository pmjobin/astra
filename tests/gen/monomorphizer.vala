// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenCore {
private void dedup() {
	try {
		CoreProgram? source = sample ();
		var definition = WeakRef (source.generic_functions[0]);
		var type = WeakRef (source.generic_functions[0].return_type);
		var generic_parameter = WeakRef (source.generic_functions[0].parameters[0]);
		var generic_local = WeakRef (source.generic_functions[0].locals[0]);
		var concrete = CoreGenericMonomorphizer.build (source);
		source = null;
		assert (definition.get () == null && type.get () == null && generic_parameter.get () == null && generic_local.get () == null);
		CoreVerifier.verify_concrete (concrete);
		assert (concrete.functions.length == 14 && concrete.generic_functions.length == 0);
		assert (concrete.functions[1].generic_instance.requests == 2);
		for (int i = 1; i < concrete.functions.length; i++) {
			var f = concrete.functions[i];
			assert (f.generic_instance.state == GenericInstanceState.COMPLETE && !(f.return_type is TypeParameterType));
			assert (f.generic_instance.ordinal == i - 1 && f.generic_instance.origin.ordinal == 0);
			for (int j = 1; j < i; j++) {
				assert (f.parameters[0] != concrete.functions[j].parameters[0] && f.locals[0] != concrete.functions[j].locals[0]);
			}
		}
		assert (concrete.functions[2].return_type.kind == TypeKind.I8 && concrete.functions[3].return_type.kind == TypeKind.U8);
		assert (CoreDump.format (concrete) == CoreDump.format (CoreGenericMonomorphizer.build (sample ())));
		assert (CoreGenericMonomorphizer.build (sample (0, true)).functions.length == 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void recursion() {
	try {
		for (int mode = 1; mode <= 2; mode++) {
			var concrete = CoreGenericMonomorphizer.build (sample (mode));
			assert (concrete.functions.length == 1 + mode * 13);
			for (int i = 1; i < concrete.functions.length; i++) {
				var f = concrete.functions[i];
				var callee = ((CoreCallValue) ((CoreReturn) f.body.statements[1]).value).target;
				assert (callee != null && callee.return_type == f.return_type);
				if (mode == 1) {
					assert (callee == f);
				} else {
					assert (((CoreCallValue) ((CoreReturn) callee.body.statements[1]).value).target == f);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen/monomorphizer/canonical-dedup-fresh-identities-lifetime-determinism-unused", dedup);
	Test.add_func ("/gen/monomorphizer/registered-placeholder-direct-mutual", recursion);
	return Test.run ();
}
}
