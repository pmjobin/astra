// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenOwnCore {
private void concrete() {
	try {
		foreach (bool resource in new bool[] {false, true}) {
			var p = CoreGenericMonomorphizer.build (sample (resource));
			CoreVerifier.verify_concrete (p);
			assert (p.generic_functions.length == 0);
			foreach (var f in p.functions) {
				assert (!(f.return_type is TypeParameterType));
				foreach (var owner in f.owned_locals) {
					assert (owner.cleanup.type_parameter == null && owner.object_storage == null);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/concrete-core/exact-resource-class-contracts", concrete);
	return Test.run ();
}

}
