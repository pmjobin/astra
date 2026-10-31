// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.DspValues {
internal IntegerType[] integers(BuiltinTypes types) {
	return new IntegerType[] {
			   types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type
	};
}

internal int64[] boundaries(IntegerType source) {
	int64[] result = {
		source.minimum
	};
	assert (source.bit_width <= 32);
	int64 maximum = (int64) source.maximum;
	int64[] candidates = {
		source.minimum, source.minimum + 1, maximum - 1, maximum, -2147483648, -2147483647, -65537, -65536, -32769, -32768, -32767, -257, -256, -255, -129, -128, -127, -2, -1, 0, 1, 2, 126, 127, 128, 129, 254, 255, 256, 257, 32766, 32767, 32768, 32769, 65534, 65535, 65536, 65537, 2147483646, 2147483647, 2147483648, 2147483649, 4294967294, 4294967295
	};
	foreach (int64 candidate in candidates) {
		if (candidate < source.minimum || candidate > maximum) {
			continue;
		}
		bool seen = false;
		foreach (int64 old in result) {
			if (old == candidate) {
				seen = true;
			}
		}
		if (!seen) {
			result += candidate;
		}
	}
	return result;
}

}
