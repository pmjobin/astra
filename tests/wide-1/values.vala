// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
namespace Astra.Tests.WideValues {
private void boundaries() {
	var t = new BuiltinTypes ();
	var minimum = AstraIntegerValue.from_decimal_magnitude (t.i64_type, "9223372036854775808", true);
	var maximum = AstraIntegerValue.from_decimal_magnitude (t.u64_type, "18446744073709551615");
	assert (minimum != null && minimum.signed_value == int64.MIN && minimum.to_string () == "-9223372036854775808");
	assert (maximum != null && maximum.bits == uint64.MAX && maximum.to_string () == "18446744073709551615");
	assert (AstraIntegerValue.from_decimal_magnitude (t.u64_type, "18446744073709551616") == null);
	assert (AstraIntegerValue.from_decimal_magnitude (t.i64_type, "9223372036854775808") == null);
	assert (AstraIntegerValue.from_decimal_magnitude (t.i64_type, "9223372036854775809", true) == null);
	assert (!maximum.fits_nonnegative (int64.MAX));
	assert (maximum.convert_to (t.i64_type).signed_value == -1);
	assert (AstraIntegerValue.from_int64 (t.i8_type, -1).convert_to (t.u64_type).bits == uint64.MAX);
	assert (minimum.convert_to (t.u8_type).bits == 0);
	assert (t.isize_type != t.i64_type && t.usize_type != t.u64_type && t.isize_type.bit_width == 64 && t.usize_type.bit_width == 64);
}
private void arithmetic() {
	var t = new BuiltinTypes ();
	var maximum = AstraIntegerValue.from_bits (t.u64_type, uint64.MAX);
	var one = AstraIntegerValue.from_int64 (t.u64_type, 1);
	assert (maximum.add_wrap (one).bits == 0);
	assert (one.sub_wrap (maximum).bits == 2);
	assert (maximum.mul_wrap (maximum).bits == 1);
	assert (maximum.saturating_add (one).bits == uint64.MAX);
	assert (one.saturating_sub (maximum).bits == 0);
	var minimum = AstraIntegerValue.from_int64 (t.i64_type, int64.MIN);
	var minus_one = AstraIntegerValue.from_int64 (t.i64_type, -1);
	var signed_maximum = AstraIntegerValue.from_int64 (t.i64_type, int64.MAX);
	assert (minimum.neg_wrap ().bits == minimum.bits);
	assert (minimum.saturating_add (minus_one).bits == minimum.bits);
	assert (signed_maximum.saturating_sub (minus_one).bits == signed_maximum.bits);
	AstraIntegerValue? result;
	assert (minimum.div (minus_one, out result) == IntArithmeticOutcome.VALUE && result.bits == minimum.bits);
	assert (minimum.rem (minus_one, out result) == IntArithmeticOutcome.VALUE && result.bits == 0);
	assert (maximum.div (AstraIntegerValue.from_int64 (t.u64_type, 2), out result) == IntArithmeticOutcome.VALUE && result.bits == 9223372036854775807UL);
	assert (maximum.compare (one) > 0 && minimum.compare (minus_one) < 0);
	assert (minimum.shift_right (AstraIntegerValue.from_int64 (t.i32_type, 63)).bits == uint64.MAX);
	assert (maximum.shift_right (AstraIntegerValue.from_int64 (t.i32_type, 63)).bits == 1);
	assert (maximum.shift_left (AstraIntegerValue.from_int64 (t.i32_type, 64)) == null);
	assert (maximum.shift_left (maximum) == null);
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/wide/value/boundaries", boundaries);
	Test.add_func ("/wide/value/arithmetic", arithmetic);
	return Test.run ();
}
}
