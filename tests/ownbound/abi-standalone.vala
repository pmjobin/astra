// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.OwnboundAbi {
private void mapping() {
	try {
		var type = new HandleType ("Resource");
		assert (new BuiltinTypes ().resolve ("Resource") == null);
		foreach (var contract in new PointerParameterContract[] { PointerParameterContract.UNMANAGED, PointerParameterContract.BORROWED_NOESCAPE, PointerParameterContract.OWNED_TRANSFER }) {
			assert (contract.is_valid ());
			assert (NativeTypeMapper.map_scalar (type) == NativeScalarType.PTR);
		}
		assert (ResultOwnershipContract.OWNED_TRANSFER.is_valid ());
		assert (NativeTypeMapper.map_scalar (type) == NativeScalarType.PTR);

	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ownbound/abi/standalone-semantic-to-ptr", mapping);
	return Test.run ();
}

}
