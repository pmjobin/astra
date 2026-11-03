// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.ResourceAbi {
private void mapping() {
	try {
		SemanticType a = new HandleType ("ResourceA");
		SemanticType b = new HandleType ("ResourceB");
		var types = new BuiltinTypes ();
		assert (types.resolve ("ResourceA") == null);
		assert (a != b && a != types.raw_pointer_type);
		assert (!BinaryOperator.EQUAL.accepts (a, b, types.bool_type));
		assert (!BinaryOperator.EQUAL.accepts (a, types.raw_pointer_type, types.bool_type));
		assert (NativeTypeMapper.map_scalar (a) == NativeScalarType.PTR && NativeTypeMapper.map_scalar (b) == NativeScalarType.PTR);
		assert (NativeTypeMapper.map_scalar (a) == NativeTypeMapper.map_scalar (types.raw_pointer_type));
		assert (CAbiTypeMapper.map_scalar (a) == CAbiScalarType.PTR && CAbiTypeMapper.map_scalar (b) == CAbiScalarType.PTR);
		assert (CAbiTypeMapper.map_scalar (a) == CAbiTypeMapper.map_scalar (types.raw_pointer_type));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/resource/abi/standalone-semantic-to-ptr", mapping);
	return Test.run ();
}

}
