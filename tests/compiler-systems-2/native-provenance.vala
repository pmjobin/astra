// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.NativeProvenance {
// Standalone scalar models also carry immutable generic/private authority.
// Exercise it without adding the upstream builder to these firewall tests.
public void check() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("native-provenance", "x"), 0, 1);
		var origin = new ExactClassDefinitionIdentity ("Bag", "entries", new string[] {"init", "reserve", "append", "count", "capacity"}, new ExactClassOperation[] {ExactClassOperation.INITIALIZE, ExactClassOperation.RESERVE, ExactClassOperation.APPEND, ExactClassOperation.COUNT, ExactClassOperation.CAPACITY});
		assert (origin.valid ());
		var parameter = new NativeParameter (span, span, "value", 0, NativeScalarType.PTR);
		parameter.bind_generic_borrow (0, origin);
		assert (parameter.generic_borrow_origin == origin && parameter.generic_borrow_matches ());
		parameter.generic_borrow_class = 1;
		assert (!parameter.generic_borrow_matches ());
		parameter.generic_borrow_class = 0;
		bool rejected = false;
		try {
			parameter.bind_generic_borrow (1, origin);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		var program = new NativeAbiProgram (span, NativeAbiVersion.SCALAR_V0, new GenericArray<NativeFunction> ());
		var accesses = new GenericArray<NativePrivateFieldAccess> ();
		program.bind_private_accesses (accesses);
		NativeAbiVerifier.verify (program);
		rejected = false;
		try {
			program.bind_private_accesses (accesses);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		accesses.add (new NativePrivateFieldAccess (0, 0, 0));
		rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		accesses.remove_index (0);
		NativeAbiVerifier.verify (program);
		var plan = new NativeClassPlan (span, "Bag<Item>", 0, -1, -1, false, false, new GenericArray<NativeClassField> (), new GenericArray<int> ());
		var instance = new NativeExactClassInstance (origin, 1, new int[] {0, 1, 2, 3, 4});
		plan.bind_generic (instance);
		assert (plan.generic_origin == origin && plan.generic_instance == instance);
		rejected = false;
		try {
			plan.bind_generic (instance);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

}
