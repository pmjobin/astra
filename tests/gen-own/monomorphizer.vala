// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenOwnCore {
private void specialize() {
	try {
		foreach (bool resource in new bool[] {false, true}) {
			foreach (bool drop in new bool[] {false, true}) {
				CoreProgram? p = sample (resource, drop);
				var weak_definition = WeakRef (p.generic_functions[1]);
				var weak_type = WeakRef (p.generic_functions[1].return_type);
				var result = CoreGenericMonomorphizer.build (p);
				p = null;
				assert (weak_definition.get () == null && weak_type.get () == null);
				CoreVerifier.verify_concrete (result);
				assert (result.generic_functions.length == 0 && result.functions.length == (drop ? 2 : 3));
				foreach (var cleanup in result.cleanups) {
					assert (cleanup.type_parameter == null && cleanup.is_object != resource);
				}
				foreach (var f in result.functions) {
					foreach (var owner in f.owned_locals) {
						assert (!(owner.place.semantic_type is TypeParameterType) && owner.cleanup == result.cleanups[0]);
					}
					if (!drop) {
						assert ((f.result_storage != null) != resource && f.owned_cleanup == result.cleanups[0]);
					}
				}
				assert (CoreDump.format (result) == CoreDump.format (CoreGenericMonomorphizer.build (sample (resource, drop))));
			}
		}
		var interleaved = sample ();
		var first = interleaved.cleanups[0];
		var last = interleaved.cleanups[interleaved.cleanups.length - 1];
		interleaved.cleanups[0] = last;
		last.ordinal = 0;
		interleaved.cleanups[interleaved.cleanups.length - 1] = first;
		first.ordinal = (int) interleaved.cleanups.length - 1;
		CoreVerifier.verify (interleaved);
		var normalized = CoreGenericMonomorphizer.build (interleaved);
		CoreVerifier.verify_concrete (normalized);
		assert (normalized.cleanups.length == 1 && normalized.cleanups[0] == first && first.ordinal == 0);
		assert (CoreGenericMonomorphizer.build (sample (false, false, true)).functions.length == 0);
		var invalid = sample ();
		var call = ((CoreOwnershipReturn) invalid.functions[0].body.statements[1]).producer as CoreGenericCall;
		call.type_arguments[0] = new BuiltinTypes ().int_type;
		bool rejected = false;
		try {
			CoreGenericMonomorphizer.build (invalid);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected && invalid.functions.length == 1 && call.target is CoreGenericFunction);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/monomorphizer/resource-class-nodeinit-forward-lifetime-invalid-unused", specialize);
	return Test.run ();
}

}
