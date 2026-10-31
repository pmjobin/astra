// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.IntegersReference {
private int64 interpret(uint64 bits, uint width, bool signed) {
	int64 modulus = ((int64) 1) << width;
	return signed && bits >= (uint64) (modulus / 2) ? (int64) bits - modulus : (int64) bits;
}

private uint64 residue(int64 number, int64 modulus) {
	int64 remainder = number % modulus;
	return (uint64) (remainder < 0 ? remainder + modulus : remainder);
}

private void pair(IntegerType type, uint64 a, uint64 b) {
	var left = AstraIntegerValue.from_bits (type, a);
	var right = AstraIntegerValue.from_bits (type, b);
	uint64 modulus = ((uint64) 1) << type.bit_width;
	int64 x = interpret (a, type.bit_width, type.is_signed);
	int64 y = interpret (b, type.bit_width, type.is_signed);
	assert (left.mathematical_value == x && right.mathematical_value == y);
	assert (left.add_wrap (right).bits == (a + b) % modulus);
	assert (left.sub_wrap (right).bits == residue (x - y, (int64) modulus));
	assert (left.mul_wrap (right).bits == (a * b) % modulus);
	assert (left.compare (right) == (x < y ? -1 : x > y ? 1 : 0));
	assert (left.equal_value (right) == (a == b));
	AstraIntegerValue? quotient;
	AstraIntegerValue? remainder;
	if (b == 0) {
		assert (left.div (right, out quotient) == IntArithmeticOutcome.ZERO_DIVISOR_TRAP && quotient == null);
		assert (left.rem (right, out remainder) == IntArithmeticOutcome.ZERO_DIVISOR_TRAP && remainder == null);
	} else {
		// Every signed operand is at most 32 bits; int64 division cannot
		// overflow, including i32 MIN/-1. Unsigned u32 also fits int64.
		int64 q = x / y;
		assert (left.div (right, out quotient) == IntArithmeticOutcome.VALUE);
		assert (left.rem (right, out remainder) == IntArithmeticOutcome.VALUE);
		assert (quotient.integer_type == type && remainder.integer_type == type);
		assert (quotient.bits == residue (q, (int64) modulus));
		assert (remainder.mathematical_value == x - q * y);
	}
	assert (left.positive () == left);
	if (type.is_signed) {
		assert (left.neg_wrap ().bits == residue (-x, (int64) modulus));
	}
}

private void identities() {
	var types = new BuiltinTypes ();
	assert (types.resolve ("int") == types.resolve ("i32") && types.int_type == types.i32_type);
	IntegerType[] family = {
		types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type
	};
	string[] names = {
		"i8", "u8", "i16", "u16", "int", "u32"
	};
	int64[] minima = {
		-128, 0, -32768, 0, -2147483648L, 0
	};
	int64[] maxima = {
		127, 255, 32767, 65535, 2147483647L, 4294967295L
	};
	for (int i = 0; i < family.length; i++) {
		var type = family[i];
		assert (type == types.resolve (names[i]) && type.display_name () == names[i]);
		assert (type.is_signed == (i % 2 == 0) && type.bit_width == (8U << (i / 2)));
		assert (type.minimum == minima[i] && type.maximum == maxima[i]);
		assert (type != types.bool_type);
		for (int j = 0; j < family.length; j++) {
			assert ((type == family[j]) == (i == j));
		}
	}
	assert (types.resolve ("uint") == null);
	assert (types.resolve ("i64") == types.i64_type && types.i64_type.bit_width == 64 && types.i64_type.is_signed);
	assert (types.resolve ("u64") == types.u64_type && types.u64_type.bit_width == 64 && !types.u64_type.is_signed);
	var signed = AstraIntegerValue.from_bits (types.i8_type, 255);
	var unsigned = AstraIntegerValue.from_bits (types.u8_type, 255);
	assert (signed.bits == unsigned.bits && !signed.equal_value (unsigned));
	assert (signed.signed_value == -1 && unsigned.unsigned_value == 255);
	var another = new BuiltinTypes ();
	assert (types.i32_type != another.i32_type && types.u8_type != another.u8_type);
	foreach (var name in new string[] {"integer-type", "bits", "mathematical-value", "signed-value", "unsigned-value"}) {
		var property = ((ObjectClass) typeof (AstraIntegerValue).class_ref ()).find_property (name);
		assert (property != null && (property.flags & ParamFlags.WRITABLE) == 0);
	}
	foreach (var name in new string[] {"bit-width", "is-signed", "minimum", "maximum", "mask", "modulus"}) {
		var property = ((ObjectClass) typeof (IntegerType).class_ref ()).find_property (name);
		assert (property != null && (property.flags & ParamFlags.WRITABLE) == 0);
	}
}

private void literals() {
	var types = new BuiltinTypes ();
	foreach (var type in new IntegerType[] {types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
		assert (AstraIntegerValue.from_int64 (type, type.minimum - 1) == null);
		// This legacy oracle intentionally covers only the <=32-bit family.
		assert (type.maximum < int64.MAX);
		assert (AstraIntegerValue.from_int64 (type, (int64) (type.maximum + 1)) == null);
		assert (AstraIntegerValue.from_bits (type, type.mask + 1) == null);
		var max = AstraIntegerValue.from_decimal_magnitude (type, "000" + type.maximum.to_string ());
		assert (max.mathematical_value == type.maximum);
		assert (AstraIntegerValue.from_decimal_magnitude (type, (type.maximum + 1).to_string ()) == null);
		assert (AstraIntegerValue.from_decimal_magnitude (type, string.nfill (4000, '0')).bits == 0);
		assert (AstraIntegerValue.from_decimal_magnitude (type, string.nfill (4000, '9')) == null);
		foreach (string bad in new string[] {"", "-1", "+1", "1u8", " 1", "1.0", "a", "1a"}) {
			assert (AstraIntegerValue.from_decimal_magnitude (type, bad) == null);
		}
		if (type.is_signed) {
			assert (AstraIntegerValue.from_decimal_magnitude (type, (-type.minimum).to_string (), true).signed_value == type.minimum);
			assert (AstraIntegerValue.from_decimal_magnitude (type, (-type.minimum + 1).to_string (), true) == null);
		} else {
			assert (AstraIntegerValue.from_decimal_magnitude (type, "1", true) == null);
			assert (AstraIntegerValue.from_decimal_magnitude (type, "0", true) == null);
		}
	}
}

private void exhaustive() {
	var types = new BuiltinTypes ();
	foreach (var type in new IntegerType[] {types.i8_type, types.u8_type}) {
		for (uint64 a = 0; a < 256; a++) {
			for (uint64 b = 0; b < 256; b++) {
				pair (type, a, b);
			}
		}
	}
	Test.message ("131072 i8/u8 pairs: add/sub/mul, all order/equality outcomes, division/remainder, zero traps and negation");
}

private void wider() {
	var types = new BuiltinTypes ();
	foreach (var type in new IntegerType[] {types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
		uint64 half = type.modulus / 2;
		uint64[] values = {
			0, 1, 2, 3, 7, half - 2, half - 1, half, half + 1, type.mask - 1, type.mask
		};
		foreach (uint64 a in values) {
			foreach (uint64 b in values) {
				pair (type, a, b);
			}
		}
		uint64 state = 0x61427;
		for (int i = 0; i < 4096; i++) {
			state = (state * 1664525 + 1013904223) % 4294967296UL;
			uint64 a = state & type.mask;
			state = (state * 1664525 + 1013904223) % 4294967296UL;
			pair (type, a, state & type.mask);
		}
	}
	Test.message ("16868 wider pairs: 11x11 boundary matrix and 4096 deterministic pairs per type");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ints/reference/identities-ranges-immutable", identities);
	Test.add_func ("/ints/reference/literals", literals);
	Test.add_func ("/ints/reference/exhaustive-eight-bit", exhaustive);
	Test.add_func ("/ints/reference/wider-matrices", wider);
	return Test.run ();
}
}
