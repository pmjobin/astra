// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Immutable exact format and bits. Host floats and LLVM are not authorities.
public class BinaryFloatValue : Object {
	public BinaryFloatFormat format { get; private set; }
	public uint64 exact_bits { get; private set; }
	public bool sign { get { return (exact_bits & format.sign_mask ()) != 0; } }
	public uint64 exponent_field { get { return (exact_bits >> format.fraction_bits ()) & format.exponent_mask (); } }
	public uint64 fraction_field { get { return exact_bits & format.fraction_mask (); } }
	public bool is_zero { get { return exponent_field == 0 && fraction_field == 0; } }
	public bool is_subnormal { get { return exponent_field == 0 && fraction_field != 0; } }
	public bool is_normal { get { return exponent_field > 0 && exponent_field < format.exponent_mask (); } }
	public bool is_infinite { get { return exponent_field == format.exponent_mask () && fraction_field == 0; } }
	public bool is_nan { get { return exponent_field == format.exponent_mask () && fraction_field != 0; } }

	public BinaryFloatValue.from_bits (BinaryFloatFormat format, uint64 bits) {
		assert (format == BinaryFloatFormat.BINARY32 || format == BinaryFloatFormat.BINARY64);
		assert (format != BinaryFloatFormat.BINARY32 || bits <= 0xffffffffU);
		this.format = format;
		this.exact_bits = bits;
	}

	public BinaryFloatValue positive() {
		return this;
	}
	public BinaryFloatValue negated() {
		return new BinaryFloatValue.from_bits (format, exact_bits ^ format.sign_mask ());
	}
	public string to_string() {
		return format == BinaryFloatFormat.BINARY32 ? "0x%08x".printf ((uint32) exact_bits) : ("0x%016" + uint64.FORMAT_MODIFIER + "x").printf (exact_bits);
	}

	// Positive grammar only; source '-' is a separate exact sign operation.
	public static BinaryFloatValue? from_decimal(BinaryFloatFormat format, string spelling) {
		var decimal = BinaryFloatDecimal.parse (format, spelling);
		if (decimal == null) {
			return null;
		}
		if (decimal.is_zero || decimal.order < format.minimum_decimal_order ()) {
			return new BinaryFloatValue.from_bits (format, 0);
		}
		if (decimal.order > format.maximum_decimal_order ()) {
			return new BinaryFloatValue.from_bits (format, format.infinity_bits ());
		}
		uint64 low = 0;
		uint64 high = format.infinity_bits ();
		while (low < high) {
			uint64 middle = low + (high - low) / 2;
			int comparison = decimal.compare_midpoint (middle);
			if (comparison > 0 || (comparison == 0 && (middle & 1) != 0)) {
				low = middle + 1;
			} else {
				high = middle;
			}
		}
		return new BinaryFloatValue.from_bits (format, low);
	}

	// Exact dyadic quantization. At most 53 significand bits; no host casts.
	public BinaryFloatValue converted(BinaryFloatFormat destination) {
		assert (destination == BinaryFloatFormat.BINARY32 || destination == BinaryFloatFormat.BINARY64);
		if (destination == format) {
			return this;
		}
		uint64 sign_bits = sign ? destination.sign_mask () : 0;
		if (is_nan) {
			// One internal quiet representative. Payload/sign remain unspecified
			// language data, including conversions (same doctrine as arithmetic).
			return new BinaryFloatValue.from_bits (destination, destination.infinity_bits () | (destination.hidden_bit () >> 1));
		}
		if (is_infinite || is_zero) {
			return new BinaryFloatValue.from_bits (destination, sign_bits | (is_infinite ? destination.infinity_bits () : 0));
		}
		uint64 significand = fraction_field | (exponent_field == 0 ? 0 : format.hidden_bit ());
		int unit = exponent_field == 0 ? format.minimum_unit () : (int) exponent_field - format.bias () - (int) format.fraction_bits ();
		int top = 0;
		for (uint64 remaining = significand; remaining > 1; remaining >>= 1) {
			top++;
		}
		int destination_unit = int.max (unit + top - (int) destination.fraction_bits (), destination.minimum_unit ());
		int shift = destination_unit - unit;
		uint64 rounded;
		if (shift <= 0) {
			rounded = significand << -shift;
		} else if (shift >= 64) {
			rounded = 0;
		} // significand has at most 53 bits
		else {
			rounded = significand >> shift;
			uint64 remainder = significand & ((((uint64) 1) << shift) - 1);
			uint64 half = ((uint64) 1) << (shift - 1);
			if (remainder > half || (remainder == half && (rounded & 1) != 0)) {
				rounded++;
			}
		}
		if (rounded >= destination.hidden_bit () * 2) {
			rounded >>= 1;
			destination_unit++;
		}
		uint64 magnitude;
		if (destination_unit > destination.bias () - (int) destination.fraction_bits ()) {
			magnitude = destination.infinity_bits ();
		} else if (rounded < destination.hidden_bit ()) {
			magnitude = rounded;
		} else {
			magnitude = ((uint64) (destination_unit + destination.bias () + (int) destination.fraction_bits ()) << destination.fraction_bits ()) | (rounded - destination.hidden_bit ());
		}
		return new BinaryFloatValue.from_bits (destination, sign_bits | magnitude);
	}
}

// Every supported midpoint has a terminating decimal coefficient with at
// most 113 (binary32) or 768 (binary64) digits. Keeping that many significant
// source digits plus a sticky tail is exact comparison, never pre-rounding.
private class BinaryFloatDecimal : Object {
	private int digit_limit;
	private BinaryFloatFormat format;
	private StringBuilder digits = new StringBuilder ();
	private bool sticky;
	private int count;
	private int first = -1;
	internal int64 order;
	internal bool is_zero { get { return first < 0; } }

	private static bool digit(char c) {
		return c >= '0' && c <= '9';
	}

	private void append(char c) {
		if (first < 0 && c != '0') {
			first = count;
		}
		count++;
		if (first < 0) {
			return;
		}
		if ((int) digits.len < digit_limit) {
			digits.append_c (c);
		} else if (c != '0') {
			sticky = true;
		}
	}

	internal static BinaryFloatDecimal? parse(BinaryFloatFormat format, string text) {
		int source_length = text.length;
		var result = new BinaryFloatDecimal ();
		result.format = format;
		result.digit_limit = format.decimal_digits ();
		int position = 0;
		while (position < source_length && digit (text[position])) {
			result.append (text[position++]);
		}
		int before = position;
		if (before == 0) {
			return null;
		}
		bool point = position < source_length && text[position] == '.';
		if (point) {
			int start = ++position;
			while (position < source_length && digit (text[position])) {
				result.append (text[position++]);
			}
			if (position == start) {
				return null;
			}
		}
		int64 exponent = 0;
		bool scientific = position < source_length && (text[position] == 'e' || text[position] == 'E');
		if (scientific) {
			position++;
			bool negative = position < source_length && text[position] == '-';
			if (position < source_length && (text[position] == '+' || negative)) {
				position++;
			}
			int start = position;
			// Even an exponent cancelling every source digit remains exact.
			// Beyond this cap the final order is certainly outside both supported formats.
			int64 cap = (int64) source_length + 512;
			while (position < source_length && digit (text[position])) {
				exponent = int64.min (cap, exponent * 10 + text[position++] - '0');
			}
			if (position == start) {
				return null;
			}
			if (negative) {
				exponent = -exponent;
			}
		}
		if (position != source_length || (!point && !scientific)) {
			return null;
		}
		result.order = (int64) before - result.first + exponent;
		return result;
	}

	private int cached_exponent = int.MAX;
	private uint8[] power;
	private int power_length;

	private static int floor_thousand(int value) {
		return value >= 0 ? value / 1000 : -((-value + 999) / 1000);
	}

	internal int compare_midpoint(uint64 lower) {
		assert (lower < format.infinity_bits ());
		uint64 field = lower >> format.fraction_bits ();
		uint64 significand = lower & format.fraction_mask ();
		if (field != 0) {
			significand |= format.hidden_bit ();
		}
		int exponent = (field == 0 ? format.minimum_unit () : (int) field - format.bias () - (int) format.fraction_bits ()) - 1;
		uint64 coefficient = 2 * significand + 1;
		// 10^301 < 2^1000 < 10^302 gives conservative decimal-order
		// bounds using integers alone. Reject distant exponents before
		// constructing their exact terminating decimal coefficients.
		int binary_order = exponent;
		for (uint64 remaining = coefficient; remaining > 1; remaining >>= 1) {
			binary_order++;
		}
		int minimum_order = floor_thousand (binary_order * (binary_order < 0 ? 302 : 301)) + 1;
		int upper = binary_order + 1;
		int maximum_order = floor_thousand (upper * (upper < 0 ? 301 : 302)) + 1;
		if (order < minimum_order) {
			return -1;
		}
		if (order > maximum_order) {
			return 1;
		}

		// Adjacent encodings usually share an exponent. Cache the exact power,
		// then multiply by the <=54-bit coefficient without rebuilding 5^1075.
		if (cached_exponent != exponent) {
			power = new uint8[digit_limit];
			power[0] = 1;
			power_length = 1;
			int steps = exponent < 0 ? -exponent : exponent;
			uint factor = exponent < 0 ? 5 : 2;
			for (int step = 0; step < steps; step++) {
				uint carry = 0;
				for (int i = 0; i < power_length; i++) {
					uint product = power[i] * factor + carry;
					power[i] = (uint8) (product % 10);
					carry = product / 10;
				}
				if (carry != 0) {
					assert (power_length < digit_limit);
					power[power_length++] = (uint8) carry;
				}
			}
			cached_exponent = exponent;
		}
		uint8[] midpoint = new uint8[digit_limit];
		int length = power_length;
		uint64 carry = 0;
		for (int i = 0; i < power_length; i++) {
			uint64 product = power[i] * coefficient + carry;
			midpoint[i] = (uint8) (product % 10);
			carry = product / 10;
		}
		while (carry != 0) {
			assert (length < digit_limit);
			midpoint[length++] = (uint8) (carry % 10);
			carry /= 10;
		}
		int midpoint_order = length + (exponent < 0 ? exponent : 0);
		if (order != midpoint_order) {
			return order < midpoint_order ? -1 : 1;
		}
		for (int i = 0; i < int.max ((int) digits.len, length); i++) {
			int a = i < (int) digits.len ? digits.str[i] - '0' : 0;
			int b = i < length ? midpoint[length - i - 1] : 0;
			if (a != b) {
				return a < b ? -1 : 1;
			}
		}
		return sticky ? 1 : 0;
	}
}
}
