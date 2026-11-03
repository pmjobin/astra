// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Compatibility adapter for accepted F32 clients; all rules live in the
// shared binary-floating authority. This class adds no rounding algorithm.
public class AstraF32Value : BinaryFloatValue {
	public uint32 bits { get { return (uint32) exact_bits; } }

	public AstraF32Value.from_bits (uint32 bits) {
		base.from_bits (BinaryFloatFormat.BINARY32, bits);
	}
	public new AstraF32Value positive() {
		return this;
	}

	public new AstraF32Value negated() {
		return new AstraF32Value.from_bits ((uint32) base.negated ().exact_bits);
	}

	public new static AstraF32Value? from_decimal(string spelling) {
		var value = BinaryFloatValue.from_decimal (BinaryFloatFormat.BINARY32, spelling);
		return value == null ? null : new AstraF32Value.from_bits ((uint32) value.exact_bits);
	}

}
}
