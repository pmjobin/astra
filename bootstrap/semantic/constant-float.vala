// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Compiler-only unsigned integer work space. Binary32/64 operations need at
// most 3227 bits here; no source-sized allocation or general bignum API.
private class ConstantMagnitude : Object {
	private uint32[] words;
	internal ConstantMagnitude (uint64 value) {
		words = new uint32[2];
		words[0] = (uint32) (value & 0xffffffffU);
		words[1] = (uint32) (value >> 32);
		trim ();
	}
	private void trim() {
		int n = words.length;
		while (n > 1 && words[n - 1] == 0) {
			n--;
		}
		words.resize (n);
	}
	internal ConstantMagnitude shifted(int bits) {
		assert (bits >= 0 && bits <= 4096);
		var result = new ConstantMagnitude (0);
		result.words = new uint32[words.length + bits / 32 + 1];
		for (int i = 0; i < words.length; i++) {
			uint64 part = (uint64) words[i] << (bits % 32);
			result.words[i + bits / 32] |= (uint32) (part & 0xffffffffU);
			result.words[i + bits / 32 + 1] |= (uint32) (part >> 32);
		}
		result.trim ();
		return result;
	}
	internal int compare(ConstantMagnitude other) {
		if (words.length != other.words.length) {
			return words.length < other.words.length ? -1 : 1;
		}
		for (int i = words.length - 1; i >= 0; i--) {
			if (words[i] != other.words[i]) {
				return words[i] < other.words[i] ? -1 : 1;
			}
		}
		return 0;
	}
	internal ConstantMagnitude add(ConstantMagnitude other) {
		var result = new ConstantMagnitude (0);
		int n = int.max (words.length, other.words.length);
		result.words = new uint32[n + 1];
		uint64 carry = 0;
		for (int i = 0; i < n; i++) {
			uint64 sum = carry + (i < words.length ? (uint64) words[i] : 0) + (i < other.words.length ? (uint64) other.words[i] : 0);
			result.words[i] = (uint32) (sum & 0xffffffffU);
			carry = sum >> 32;
		}
		result.words[n] = (uint32) carry;
		result.trim ();
		return result;
	}
	internal ConstantMagnitude subtract(ConstantMagnitude other) {
		assert (compare (other) >= 0);
		var result = new ConstantMagnitude (0);
		result.words = new uint32[words.length];
		uint64 borrow = 0;
		for (int i = 0; i < words.length; i++) {
			uint64 sub = borrow + (i < other.words.length ? (uint64) other.words[i] : 0);
			uint64 value = (((uint64) 1) << 32) + words[i] - sub;
			result.words[i] = (uint32) (value & 0xffffffffU);
			borrow = value >> 32 == 0 ? 1 : 0;
		}
		assert (borrow == 0);
		result.trim ();
		return result;
	}
	internal ConstantMagnitude multiply(ConstantMagnitude other) {
		var result = new ConstantMagnitude (0);
		result.words = new uint32[words.length + other.words.length];
		for (int i = 0; i < words.length; i++) {
			uint64 carry = 0;
			for (int j = 0; j < other.words.length; j++) {
				uint64 product = (uint64) words[i] * other.words[j] + result.words[i + j] + carry;
				result.words[i + j] = (uint32) (product & 0xffffffffU);
				carry = product >> 32;
			}
			result.words[i + other.words.length] = (uint32) carry;
		}
		result.trim ();
		return result;
	}
}

// Exact rational arithmetic, rounded against adjacent-format midpoints at
// EACH operation. The shared format/value authorities own all IEEE policy.
public class ConstantFloat : Object {
	private static uint64 significand(BinaryFloatValue value) {
		return value.fraction_field | (value.exponent_field == 0 ? 0 : value.format.hidden_bit ());
	}
	private static int unit(BinaryFloatValue value) {
		return value.exponent_field == 0 ? value.format.minimum_unit () : (int) value.exponent_field - value.format.bias () - (int) value.format.fraction_bits ();
	}
	private static BinaryFloatValue special(BinaryFloatFormat format, bool negative, bool infinity) {
		return new BinaryFloatValue.from_bits (format, (negative ? format.sign_mask () : 0) | (infinity ? format.infinity_bits () : 0));
	}
	private static BinaryFloatValue nan(BinaryFloatFormat format) {
		return new BinaryFloatValue.from_bits (format, format.infinity_bits () | (format.hidden_bit () >> 1));
	}

	private static BinaryFloatValue round_rational(BinaryFloatFormat format, bool negative, ConstantMagnitude numerator, ConstantMagnitude denominator, int exponent) {
		uint64 low = 0;
		uint64 high = format.infinity_bits ();
		while (low < high) {
			uint64 middle = low + (high - low) / 2;
			uint64 field = middle >> format.fraction_bits ();
			uint64 sig = (middle & format.fraction_mask ()) | (field == 0 ? 0 : format.hidden_bit ());
			int midpoint_unit = (field == 0 ? format.minimum_unit () : (int) field - format.bias () - (int) format.fraction_bits ()) - 1;
			var midpoint = denominator.multiply (new ConstantMagnitude (2 * sig + 1));
			int common = int.min (exponent, midpoint_unit);
			int comparison = numerator.shifted (exponent - common).compare (midpoint.shifted (midpoint_unit - common));
			if (comparison > 0 || (comparison == 0 && (middle & 1) != 0)) {
				low = middle + 1;
			} else {
				high = middle;
			}
		}
		return new BinaryFloatValue.from_bits (format, low | (negative ? format.sign_mask () : 0));
	}

	public static BinaryFloatValue from_integer(AstraIntegerValue value, BinaryFloatFormat format) {
		return round_rational (format, value.negative, new ConstantMagnitude (value.magnitude), new ConstantMagnitude (1), 0);
	}

	public static AstraIntegerValue? to_integer(BinaryFloatValue value, IntegerType destination) {
		if (value.is_nan || value.is_infinite) {
			return null;
		}
		uint64 magnitude = significand (value);
		int exponent = unit (value);
		if (exponent < 0) {
			magnitude = exponent <= -64 ? 0 : magnitude >> -exponent;
		} else {
			// Check before shifting; even u64.MAX must stay an unsigned
			// magnitude rather than pass through an int64 host conversion.
			if (exponent >= 64 || magnitude > (uint64.MAX >> exponent)) {
				return null;
			}
			magnitude <<= exponent;
		}
		return AstraIntegerValue.from_magnitude (destination, magnitude, value.sign);
	}

	public static bool compare(BinaryOperator operation, BinaryFloatValue a, BinaryFloatValue b) {
		assert (a.format == b.format && (operation.is_relational () || operation.is_equality ()));
		if (a.is_nan || b.is_nan) {
			return operation == BinaryOperator.NOT_EQUAL;
		}
		int order;
		if (a.exact_bits == b.exact_bits || (a.is_zero && b.is_zero)) {
			order = 0;
		} else if (a.sign != b.sign) {
			order = a.sign ? -1 : 1;
		} else {
			order = a.exact_bits < b.exact_bits ? -1 : 1;
			if (a.sign) {
				order = -order;
			}
		}
		return ConstantEvaluator.comparison (operation, order);
	}

	public static BinaryFloatValue arithmetic(BinaryOperator operation, BinaryFloatValue a, BinaryFloatValue second) {
		var b = second;
		assert (a.format == b.format && operation.is_arithmetic () && operation != BinaryOperator.REMAINDER);
		var format = a.format;
		if (a.is_nan || b.is_nan) {
			return nan (format);
		}
		if (operation == BinaryOperator.SUBTRACT) {
			b = b.negated ();
			operation = BinaryOperator.ADD;
		}
		bool negative = a.sign != b.sign;
		if (operation == BinaryOperator.ADD) {
			if (a.is_infinite || b.is_infinite) {
				return a.is_infinite && b.is_infinite && negative ? nan(format) : special (format, a.is_infinite ? a.sign : b.sign, true);
			}
			if (a.is_zero && b.is_zero) {
				return special (format, a.sign && b.sign, false);
			}
			int exponent = int.min (unit (a), unit (b));
			var left = new ConstantMagnitude (significand (a)).shifted (unit (a) - exponent);
			var right = new ConstantMagnitude (significand (b)).shifted (unit (b) - exponent);
			int order = left.compare (right);
			if (negative && order == 0) {
				return special (format, false, false);
			}
			var numerator = !negative ? left.add(right) : order < 0 ? right.subtract (left) : left.subtract (right);
			return round_rational (format, negative && order < 0 ? b.sign : a.sign, numerator, new ConstantMagnitude (1), exponent);
		}
		if (operation == BinaryOperator.MULTIPLY) {
			if ((a.is_infinite && b.is_zero) || (b.is_infinite && a.is_zero)) {
				return nan (format);
			}
			if (a.is_infinite || b.is_infinite || a.is_zero || b.is_zero) {
				return special (format, negative, a.is_infinite || b.is_infinite);
			}
			return round_rational (format, negative, new ConstantMagnitude (significand (a)).multiply (new ConstantMagnitude (significand (b))), new ConstantMagnitude (1), unit (a) + unit (b));
		}
		if ((a.is_zero && b.is_zero) || (a.is_infinite && b.is_infinite)) {
			return nan (format);
		}
		if (a.is_infinite || b.is_zero) {
			return special (format, negative, true);
		}
		if (a.is_zero || b.is_infinite) {
			return special (format, negative, false);
		}
		return round_rational (format, negative, new ConstantMagnitude (significand (a)), new ConstantMagnitude (significand (b)), unit (a) - unit (b));
	}
}
}
