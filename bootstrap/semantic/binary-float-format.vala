// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Closed language capability, not a target-selected or arbitrary IEEE format.
public enum BinaryFloatFormat {
	BINARY32,
	BINARY64;

	public uint bit_width() {
		return this == BINARY32 ? 32 : 64;
	}

	public uint fraction_bits() {
		return this == BINARY32 ? 23 : 52;
	}

	public uint exponent_bits() {
		return this == BINARY32 ? 8 : 11;
	}

	public int bias() {
		return this == BINARY32 ? 127 : 1023;
	}

	public uint64 sign_mask() {
		return ((uint64) 1) << (bit_width () - 1);
	}

	public uint64 hidden_bit() {
		return ((uint64) 1) << fraction_bits ();
	}

	public uint64 fraction_mask() {
		return hidden_bit () - 1;
	}

	public uint64 exponent_mask() {
		return (((uint64) 1) << exponent_bits ()) - 1;
	}

	public uint64 infinity_bits() {
		return exponent_mask () << fraction_bits ();
	}

	public int minimum_unit() {
		return 1 - bias () - (int) fraction_bits ();
	}

	public int decimal_digits() {
		return this == BINARY32 ? 113 : 768;
	}

	public int minimum_decimal_order() {
		return this == BINARY32 ? -45 : -323;
	}

	public int maximum_decimal_order() {
		return this == BINARY32 ? 39 : 309;
	}

	public string spelling() {
		return this == BINARY32 ? "f32" : "f64";
	}

}

}
