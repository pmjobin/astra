// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenCapCore {
private void specialize() {
	try {
		for (int i = 0; i <= (int) GenericOperationKind.SHIFT_RIGHT; i++) {
			var kind = (GenericOperationKind) i;
			foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "bool", "void*"}) {
				var types = new BuiltinTypes ();
				if (!GenericCapabilityAuthority.satisfies (types.resolve (name), kind.capability ())) {
					continue;
				}
				CoreProgram? original = sample (kind, name);
				var weak_definition = WeakRef (original.generic_functions[0]);
				var weak_type = WeakRef (original.generic_functions[0].type_parameters[0].semantic_type);
				var concrete = CoreGenericMonomorphizer.build (original);
				original = null;
				assert (weak_definition.get () == null && weak_type.get () == null);
				CoreVerifier.verify_concrete (concrete);
				assert (concrete.functions.length == 2);
				var operation = ((CoreReturn) concrete.functions[1].body.statements[0]).value;
				assert (!(operation is CoreGenericCapabilityOperation));
				if (kind == GenericOperationKind.BIT_NOT) {
					assert (operation is CorePrefixValue);
				} else if (kind.is_shift ()) {
					assert (operation is CoreIntegerShiftValue);
				} else {
					assert (operation is CoreBinaryValue && ((CoreBinaryValue) operation).operator_kind == kind.binary_operator ());
				}
				assert (CoreDump.format (concrete) == CoreDump.format (CoreGenericMonomorphizer.build (sample (kind, name))));
			}
		}
		assert (CoreGenericMonomorphizer.build (sample (GenericOperationKind.ADD, "int", true)).functions.length == 1);
		var invalid = sample (GenericOperationKind.ADD, "bool");
		bool rejected = false;
		try {
			CoreGenericMonomorphizer.build (invalid);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected && invalid.functions.length == 1 && ((CoreReturn) invalid.functions[0].body.statements[0]).value is CoreGenericCall);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-cap/monomorphizer/all-operators-all-admitted-scalars-lifetime-determinism-invalid-unused", specialize);
	return Test.run ();
}
}
