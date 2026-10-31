// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.F64Values {
private void literal(string text, uint64 bits) {
	var value = BinaryFloatValue.from_decimal (BinaryFloatFormat.BINARY64, text);
	assert (value != null && value.exact_bits == bits && value.format == BinaryFloatFormat.BINARY64);
	assert (value.negated ().negated ().exact_bits == bits && value.positive () == value);
}

private void boundaries() {
	literal ("9007199254740993.0", 0x4340000000000000UL);
	literal ("1.0000000000000002", 0x3ff0000000000001UL);
	literal ("0.0", 0);
	literal ("4.9406564584124654e-324", 1);
	literal ("2.2250738585072009e-308", 0x000fffffffffffffUL);
	literal ("2.2250738585072014e-308", 0x0010000000000000UL);
	literal ("1.7976931348623157e308", 0x7fefffffffffffffUL);
	literal ("1e309", 0x7ff0000000000000UL);
	literal ("1e-325", 0);
	foreach (string text in new string[] {"", "1", ".5", "1.", "-0.0", "1,5", "1e", "NaN", "inf", "1.0f", "0x1.0p0"}) {
		assert (BinaryFloatValue.from_decimal (BinaryFloatFormat.BINARY64, text) == null);
	}
}

private void formats() {
	foreach (var format in new BinaryFloatFormat[] {BinaryFloatFormat.BINARY32, BinaryFloatFormat.BINARY64}) {
		assert (format.bit_width () == 1 + format.exponent_bits () + format.fraction_bits ());
		foreach (uint64 magnitude in new uint64[] {0, 1, format.hidden_bit () - 1, format.hidden_bit (), format.infinity_bits () - 1, format.infinity_bits (), format.infinity_bits () + 1}) {
			foreach (uint64 sign in new uint64[] {0, format.sign_mask ()}) {
				var v = new BinaryFloatValue.from_bits (format, magnitude | sign);
				assert (v.exact_bits == (magnitude | sign) && v.sign == (sign != 0));
				assert ((v.is_zero ? 1 : 0) + (v.is_subnormal ? 1 : 0) + (v.is_normal ? 1 : 0) + (v.is_infinite ? 1 : 0) + (v.is_nan ? 1 : 0) == 1);
			}
		}
	}
}

private void conversions() {
	var tie = BinaryFloatValue.from_decimal (BinaryFloatFormat.BINARY64, "1.000000059604644775390625");
	assert (tie.converted (BinaryFloatFormat.BINARY32).exact_bits == 0x3f800000U);
	foreach (uint64 bits in new uint64[] {0, 0x80000000U, 1, 0x007fffffU, 0x00800000U, 0x3f800001U, 0x7f7fffffU, 0x7f800000U, 0xff800000U, 0x7f800001U, 0xffc01234U}) {
		var original = new BinaryFloatValue.from_bits (BinaryFloatFormat.BINARY32, bits);
		var wide = original.converted (BinaryFloatFormat.BINARY64);
		var roundtrip = wide.converted (BinaryFloatFormat.BINARY32);
		assert (original.is_nan ? wide.is_nan && roundtrip.is_nan : roundtrip.exact_bits == bits);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f64/values/exact-boundaries", boundaries);
	Test.add_func ("/f64/values/format-special-classes", formats);
	Test.add_func ("/f64/values/conversion-tie-roundtrip", conversions);
	return Test.run ();
}
}
