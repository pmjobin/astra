// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public enum IntArithmeticOutcome {
	VALUE,
	ZERO_DIVISOR_TRAP
}

// Compatibility facade for the established i32-only semantic oracle API.
// All parsing and arithmetic delegate to the one generalized authority.
public class AstraIntValue : Object {
	public const int64 MIN = -2147483648L;
	public const int64 MAX = 2147483647L;
	private static IntegerType? i32;
	private static Mutex type_mutex;
	private AstraIntegerValue value;
	public int64 signed_value { get { return value.signed_value; } }

	private AstraIntValue (AstraIntegerValue value) {
		this.value = value;
	}

	private static IntegerType legacy_type() {
		type_mutex.lock ();
		if (i32 == null) {
			i32 = new IntegerType (TypeKind.INT);
		}
		var result = i32;
		type_mutex.unlock ();
		return result;
	}

	public static AstraIntValue? from_int64(int64 number) {
		var value = AstraIntegerValue.from_int64 (legacy_type (), number);
		return value == null ? null : new AstraIntValue (value);
	}

	public static AstraIntValue? from_decimal_magnitude(string digits, bool negative = false) {
		var value = AstraIntegerValue.from_decimal_magnitude (legacy_type (), digits, negative);
		return value == null ? null : new AstraIntValue (value);
	}

	// Bind a legacy i32 fixture to its own type universe, never convert a
	// width/sign. Null preserves malformed legacy IR for verifier tests.
	public AstraIntegerValue in_type(IntegerType? type) {
		if (type == null) {
			return value;
		}
		assert (type.kind == TypeKind.INT);
		return AstraIntegerValue.from_bits (type, value.bits);
	}

	public string to_string() {
		return value.to_string ();
	}

	public AstraIntValue add_wrap(AstraIntValue other) {
		return new AstraIntValue (value.add_wrap (other.value));
	}

	public AstraIntValue sub_wrap(AstraIntValue other) {
		return new AstraIntValue (value.sub_wrap (other.value));
	}

	public AstraIntValue mul_wrap(AstraIntValue other) {
		return new AstraIntValue (value.mul_wrap (other.value));
	}

	public AstraIntValue neg_wrap() {
		return new AstraIntValue (value.neg_wrap ());
	}

	public AstraIntValue positive() {
		return this;
	}

	public IntArithmeticOutcome div(AstraIntValue divisor, out AstraIntValue? result) {
		AstraIntegerValue? computed;
		var outcome = value.div (divisor.value, out computed);
		result = computed == null ? null : new AstraIntValue (computed);
		return outcome;
	}

	public IntArithmeticOutcome rem(AstraIntValue divisor, out AstraIntValue? result) {
		AstraIntegerValue? computed;
		var outcome = value.rem (divisor.value, out computed);
		result = computed == null ? null : new AstraIntValue (computed);
		return outcome;
	}

	public int compare(AstraIntValue other) {
		return value.compare (other.value);
	}
}
}
