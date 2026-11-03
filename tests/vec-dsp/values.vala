// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.DspValues {
private void exact(AstraIntegerValue actual, IntegerType type, int64 expected) {
	assert (actual.integer_type == type && actual.mathematical_value == expected);
	uint64 bits = (uint64) (expected < 0 ? expected + (int64) type.modulus : expected);
	assert (actual.bits == bits);
}

private void pair(IntegerType type, int64 a, int64 b) {
	assert (type.bit_width <= 32);
	int64 maximum = (int64) type.maximum;
	var left = AstraIntegerValue.from_int64 (type, a);
	var right = AstraIntegerValue.from_int64 (type, b);
	// Independent precondition reference: decide overflow before arithmetic.
	int64 sum = b > 0 && a > maximum - b ? maximum : b < 0 && a < type.minimum - b ? type.minimum : a + b;
	int64 difference = b < 0 && a > maximum + b ? maximum : b > 0 && a < type.minimum + b ? type.minimum : a - b;
	exact (left.saturating_add (right), type, sum);
	exact (left.saturating_sub (right), type, difference);
}

private void exhaustive() {
	var types = new BuiltinTypes ();
	int count = 0;
	foreach (var type in new IntegerType[] {types.i8_type, types.u8_type}) {
		int64 maximum = (int64) type.maximum;
		for (int64 a = type.minimum; a <= maximum; a++) {
			for (int64 b = type.minimum; b <= maximum; b++) {
				pair (type, a, b);
				count += 2;
			}
		}
	}
	assert (count == 262144);
	Test.message ("262144 exhaustive i8/u8 add/sub bit/value checks");
}

private void wider() {
	var types = new BuiltinTypes ();
	int count = 0;
	foreach (var type in integers (types)) {
		if (type.bit_width == 8) {
			continue;
		}
		foreach (int64 a in boundaries (type)) {
			foreach (int64 b in boundaries (type)) {
				pair (type, a, b);
				count += 2;
			}
		}
	}
	Test.message ("%d wider saturation bit/value checks", count);
}

private void conversions() {
	var types = new BuiltinTypes ();
	int pairs = 0;
	int count = 0;
	foreach (var source in integers (types)) {
		foreach (var destination in integers (types)) {
			if (destination.bit_width >= source.bit_width) {
				continue;
			}
			assert (destination.bit_width <= 32);
			int64 maximum = (int64) destination.maximum;
			pairs++;
			foreach (int64 number in boundaries (source)) {
				var value = AstraIntegerValue.from_int64 (source, number);
				int64 expected = number < destination.minimum ? destination.minimum : number > maximum ? maximum : number;
				exact (value.saturating_convert_to (destination), destination, expected);
				count++;
			}
		}
	}
	assert (pairs == 12);
	// Authority is reusable for all widths, including future scalar syntax.
	assert (AstraIntegerValue.from_int64 (types.i8_type, -1).saturating_convert_to (types.u16_type).bits == 0);
	assert (AstraIntegerValue.from_int64 (types.i8_type, -1).convert_to (types.u16_type).bits == 65535);
	Test.message ("%d saturating conversion checks across %d narrower pairs", count, pairs);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dsp/integer-value/exhaustive-i8-u8", exhaustive);
	Test.add_func ("/dsp/integer-value/wider-boundaries", wider);
	Test.add_func ("/dsp/integer-value/saturating-conversion", conversions);
	return Test.run ();
}

}
