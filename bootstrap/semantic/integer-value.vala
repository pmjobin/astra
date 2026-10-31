// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Exact W-bit residues. Unsigned host arithmetic is defined modulo 2^64;
// a final mask realizes narrower widths. Signed host overflow is never used.
public class AstraIntegerValue : Object {
	private IntegerType type;
	private uint64 pattern;
	public IntegerType integer_type { get { return type; } }
	public uint64 bits { get { return pattern; } }
	public bool negative { get { return type.is_signed && (pattern & type.sign_bit) != 0; } }
	public uint64 magnitude { get { return negative ? ((~pattern) & type.mask) + 1 : pattern; } }
	// Compatibility for old small-domain oracles. Bounds checks must use
	// fits_nonnegative rather than narrowing a potentially high-bit u64.
	public int64 mathematical_value {
		get {
			assert (negative || pattern <= int64.MAX);
			return negative ? signed_value : (int64) pattern;
		}
	}
	public int64 signed_value {
		get {
			assert (type.is_signed);
			return !negative ? (int64) pattern : magnitude == (((uint64) 1) << 63) ? int64.MIN : -(int64) magnitude;
		}
	}
	public uint64 unsigned_value {
		get {
			assert (!type.is_signed);
			return pattern;
		}
	}
	public bool fits_nonnegative(uint64 maximum) {
		return !negative && pattern <= maximum;
	}

	private AstraIntegerValue (IntegerType type, uint64 bits) {
		assert (bits <= type.mask);
		this.type = type;
		this.pattern = bits;
	}
	public static AstraIntegerValue? from_bits(IntegerType type, uint64 bits) {
		return bits > type.mask ? null : new AstraIntegerValue (type, bits);
	}

	public static AstraIntegerValue? from_magnitude(IntegerType type, uint64 magnitude, bool negative = false) {
		if (negative && magnitude != 0) {
			if (!type.is_signed || magnitude > type.sign_bit) {
				return null;
			}
			return new AstraIntegerValue (type, (0UL - magnitude) & type.mask);
		}
		return magnitude > type.maximum ? null : new AstraIntegerValue (type, magnitude);
	}

	public static AstraIntegerValue? from_int64(IntegerType type, int64 number) {
		uint64 magnitude = number < 0 ? (uint64) (-(number + 1)) + 1 : (uint64) number;
		return from_magnitude (type, magnitude, number < 0);
	}

	// Check before multiply/add, including u64.MAX and the i64.MIN magnitude.
	public static AstraIntegerValue? from_decimal_magnitude(IntegerType type, string digits, bool negative = false) {
		if (digits.length == 0 || (negative && !type.is_signed)) {
			return null;
		}
		uint64 limit = negative ? type.sign_bit : type.maximum;
		uint64 magnitude = 0;
		for (int i = 0; i < digits.length; i++) {
			if (digits[i] < '0' || digits[i] > '9') {
				return null;
			}
			uint64 digit = digits[i] - '0';
			if (magnitude > limit / 10 || (magnitude == limit / 10 && digit > limit % 10)) {
				return null;
			}
			magnitude = magnitude * 10 + digit;
		}
		return from_magnitude (type, magnitude, negative);
	}

	public AstraIntegerValue convert_to(IntegerType destination) {
		uint64 extended = pattern;
		if (negative && destination.bit_width > type.bit_width) {
			extended |= ~type.mask;
		}
		return new AstraIntegerValue (destination, extended & destination.mask);
	}

	public AstraIntegerValue saturating_convert_to(IntegerType destination) {
		if (negative) {
			if (!destination.is_signed) {
				return new AstraIntegerValue (destination, 0);
			}
			return from_magnitude (destination, uint64.min (magnitude, destination.sign_bit), true);
		}
		return new AstraIntegerValue (destination, uint64.min (pattern, destination.maximum));
	}

	public AstraIntegerValue saturating_add(AstraIntegerValue other) {
		assert (type == other.type);
		if (!type.is_signed) {
			return new AstraIntegerValue (type, other.pattern > type.mask - pattern ? type.mask : pattern + other.pattern);
		}
		var result = add_wrap (other);
		return negative == other.negative && result.negative != negative ? new AstraIntegerValue (type, negative ? type.sign_bit : type.maximum) : result;
	}

	public AstraIntegerValue saturating_sub(AstraIntegerValue other) {
		assert (type == other.type);
		if (!type.is_signed) {
			return new AstraIntegerValue (type, pattern < other.pattern ? 0 : pattern - other.pattern);
		}
		var result = sub_wrap (other);
		return negative != other.negative && result.negative != negative ? new AstraIntegerValue (type, negative ? type.sign_bit : type.maximum) : result;
	}

	public string to_string() {
		return negative ? signed_value.to_string () : pattern.to_string ();
	}
	private AstraIntegerValue wrap(uint64 residue) {
		return new AstraIntegerValue (type, residue & type.mask);
	}
	public AstraIntegerValue add_wrap(AstraIntegerValue other) {
		assert (type == other.type);
		return wrap (pattern + other.pattern);
	}
	public AstraIntegerValue sub_wrap(AstraIntegerValue other) {
		assert (type == other.type);
		return wrap (pattern - other.pattern);
	}
	public AstraIntegerValue mul_wrap(AstraIntegerValue other) {
		assert (type == other.type);
		return wrap (pattern * other.pattern);
	}
	public AstraIntegerValue bit_and(AstraIntegerValue other) {
		assert (type == other.type);
		return new AstraIntegerValue (type, pattern & other.pattern);
	}
	public AstraIntegerValue bit_or(AstraIntegerValue other) {
		assert (type == other.type);
		return new AstraIntegerValue (type, pattern | other.pattern);
	}
	public AstraIntegerValue bit_xor(AstraIntegerValue other) {
		assert (type == other.type);
		return new AstraIntegerValue (type, pattern ^ other.pattern);
	}
	public AstraIntegerValue bit_not() {
		return new AstraIntegerValue (type, pattern ^ type.mask);
	}
	public static bool valid_shift_count(IntegerType value_type, AstraIntegerValue count) {
		return count.fits_nonnegative (value_type.bit_width - 1);
	}
	public AstraIntegerValue? shift_left(AstraIntegerValue count) {
		return valid_shift_count (type, count) ? wrap (pattern << (uint) count.pattern) : null;
	}
	public AstraIntegerValue? shift_right(AstraIntegerValue count) {
		if (!valid_shift_count (type, count)) {
			return null;
		}
		uint ordinal = (uint) count.pattern;
		uint64 bits = pattern >> ordinal;
		if (negative) {
			bits |= type.mask ^ (type.mask >> ordinal);
		}
		return new AstraIntegerValue (type, bits);
	}
	public AstraIntegerValue neg_wrap() {
		assert (type.is_signed);
		return wrap (0UL - pattern);
	}
	public AstraIntegerValue positive() {
		return this;
	}

	public IntArithmeticOutcome div(AstraIntegerValue divisor, out AstraIntegerValue? result) {
		assert (type == divisor.type);
		result = null;
		if (divisor.pattern == 0) {
			return IntArithmeticOutcome.ZERO_DIVISOR_TRAP;
		}
		uint64 quotient = magnitude / divisor.magnitude;
		result = wrap (negative != divisor.negative ? 0UL - quotient : quotient);
		return IntArithmeticOutcome.VALUE;
	}
	public IntArithmeticOutcome rem(AstraIntegerValue divisor, out AstraIntegerValue? result) {
		assert (type == divisor.type);
		result = null;
		if (divisor.pattern == 0) {
			return IntArithmeticOutcome.ZERO_DIVISOR_TRAP;
		}
		uint64 remainder = magnitude % divisor.magnitude;
		result = wrap (negative ? 0UL - remainder : remainder);
		return IntArithmeticOutcome.VALUE;
	}
	public int compare(AstraIntegerValue other) {
		assert (type == other.type);
		if (negative != other.negative) {
			return negative ? -1 : 1;
		}
		return pattern < other.pattern ? -1 : pattern > other.pattern ? 1 : 0;
	}
	public bool equal_value(AstraIntegerValue other) {
		return type == other.type && pattern == other.pattern;
	}
}
}
