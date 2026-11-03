// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.BitInteger {
private uint64 reference(uint64 a, uint64 b, int op) {
	uint64 result = 0;
	uint64 place = 1;
	for (int i = 0; i < 32; i++) {
		bool x = a % 2 == 1;
		bool y = b % 2 == 1;
		if (op == 0 ? x && y : op == 1 ? x || y : x != y) {
			result += place;
		}
		a /= 2;
		b /= 2;
		place *= 2;
	}
	return result;
}

private void pair(IntegerType type, uint64 a, uint64 b) {
	var x = AstraIntegerValue.from_bits (type, a);
	var y = AstraIntegerValue.from_bits (type, b);
	assert (x.bit_and (y).bits == reference (a, b, 0));
	assert (x.bit_or (y).bits == reference (a, b, 1));
	assert (x.bit_xor (y).bits == reference (a, b, 2));
	assert (x.bit_and (y).integer_type == type && x.bit_or (y).integer_type == type && x.bit_xor (y).integer_type == type);
}

private void unary(IntegerType type, uint64 bits, IntegerType count_type) {
	var x = AstraIntegerValue.from_bits (type, bits);
	assert (x.bit_not ().bits == type.mask - bits && x.bit_not ().integer_type == type);
	int64 scale = 1;
	for (int c = 0; c < type.bit_width; c++) {
		var count = AstraIntegerValue.from_int64 (count_type, c);
		var left = x.shift_left (count);
		var right = x.shift_right (count);
		assert (left != null && right != null && left.integer_type == type && right.integer_type == type);
		assert (left.bits == bits * (uint64) scale % type.modulus);
		int64 v = x.mathematical_value;
		int64 floor = v < 0 ? -((-v + scale - 1) / scale) : v / scale;
		assert (right.mathematical_value == floor);
		scale *= 2;
	}
	assert (count_type.bit_width <= 32);
	foreach (int64 c in new int64[] {-1, type.bit_width, (int64) count_type.maximum}) {
		var count = AstraIntegerValue.from_int64 (count_type, c);
		if (count == null) {
			continue;
		}
		assert (x.shift_left (count) == null && x.shift_right (count) == null);
	}
}

private void exhaustive() {
	var types = new BuiltinTypes ();
	foreach (var type in new IntegerType[] {types.i8_type, types.u8_type}) {
		for (uint64 a = 0; a < 256; a++) {
			for (uint64 b = 0; b < 256; b++) {
				pair (type, a, b);
			}
			unary (type, a, types.i32_type);
		}
	}
	Test.message ("393216 binary bit results, 512 complements, 8192 exact 8-bit shift results; independent division/modulo bit oracle");
}

private void wider() {
	var t = new BuiltinTypes ();
	foreach (var type in new IntegerType[] {t.i16_type, t.u16_type, t.i32_type, t.u32_type}) {
		uint64[] patterns = {
			0, 1, type.mask, type.modulus / 2, type.modulus / 2 - 1, type.mask / 3, type.mask / 3 * 2, type.mask - 1
		};
		foreach (uint64 a in patterns) {
			foreach (uint64 b in patterns) {
				pair (type, a, b);
			}
			foreach (var count in new IntegerType[] {t.i8_type, t.u8_type, t.i16_type, t.u16_type, t.i32_type, t.u32_type}) {
				unary (type, a, count);
			}
		}
	}
	Test.message ("768 wider binary results, all valid wider counts across all six count types, negative/width/maximum invalid counts");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/bit/integer/exhaustive-i8-u8", exhaustive);
	Test.add_func ("/bit/integer/wider-and-count-domain", wider);
	return Test.run ();
}

}
