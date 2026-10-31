// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.F32Values {
private void bits(string spelling, uint32 expected) {
	var value = AstraF32Value.from_decimal (spelling);
	assert (value != null && value.bits == expected);
	assert (value.positive () == value && value.negated ().bits == (expected ^ 0x80000000U));
	assert (value.negated ().negated ().bits == expected);
}

private void known_bits() {
	bits ("0.0", 0x00000000U);
	bits ("1.0", 0x3f800000U);
	bits ("0.5", 0x3f000000U);
	bits ("2.0", 0x40000000U);
	bits ("1.401298464324817e-45", 0x00000001U);
	bits ("1.1754943508222875e-38", 0x00800000U);
	bits ("3.4028234663852886e38", 0x7f7fffffU);
	bits ("1e100", 0x7f800000U);
	bits ("1e-100", 0);
	bits ("1.000000059604644775390625", 0x3f800000U);
	bits ("1.000000178813934326171875", 0x3f800002U);
	bits ("1.000000059604644775390624", 0x3f800000U);
	bits ("1.000000059604644775390626", 0x3f800001U);
	bits ("340282356779733661637539395458142568447.0", 0x7f7fffffU);
	bits ("340282356779733661637539395458142568448.0", 0x7f800000U);
	bits ("340282356779733661637539395458142568449.0", 0x7f800000U);
}

private void classification() {
	uint32[] patterns = {
		0, 0x80000000U, 1, 0x807fffffU, 0x00800000U, 0xbf800000U, 0x7f7fffffU, 0x7f800000U, 0xff800000U, 0x7fc00000U, 0xff800001U
	};
	foreach (uint32 pattern in patterns) {
		var v = new AstraF32Value.from_bits (pattern);
		assert (v.bits == pattern && v.sign == ((pattern >> 31) != 0));
		assert (v.exponent_field == ((pattern >> 23) & 255) && v.fraction_field == (pattern & 0x7fffffU));
		int categories = (v.is_zero ? 1 : 0) + (v.is_subnormal ? 1 : 0) + (v.is_normal ? 1 : 0) + (v.is_infinite ? 1 : 0) + (v.is_nan ? 1 : 0);
		assert (categories == 1);
	}
	assert (new AstraF32Value.from_bits (0x80000000U).is_zero);
	assert (new AstraF32Value.from_bits (1).is_subnormal);
	assert (new AstraF32Value.from_bits (0x00800000U).is_normal);
	assert (new AstraF32Value.from_bits (0xff800000U).is_infinite);
	assert (new AstraF32Value.from_bits (0x7f800001U).is_nan);
}

private void spellings() {
	foreach (string s in new string[] {"1.0", "1.00", "10e-1", "0001.000e+0", "01E0"}) {
		bits (s, 0x3f800000U);
	}
	foreach (string s in new string[] {"", "1", ".5", "1.", "-1.0", "+1.0", "1,5", "1e", "1e+", "1e-", "1.0f", "0x1.0p0", "1_0.0", "NaN", "inf", " 1.0", "1.0 "}) {
		assert (AstraF32Value.from_decimal (s) == null);
	}
	bits ("1e" + string.nfill (10000, '9'), 0x7f800000U);
	bits ("1e-" + string.nfill (10000, '9'), 0);
	bits ("0e" + string.nfill (10000, '9'), 0);
	bits ("1" + string.nfill (10000, '0') + "e-10000", 0x3f800000U);
	bits ("0." + string.nfill (10000, '0') + "1e10001", 0x3f800000U);
	bits ("1.000000059604644775390625" + string.nfill (10000, '0') + "1", 0x3f800001U);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f32/value/known-bits-boundaries-ties", known_bits);
	Test.add_func ("/f32/value/classification", classification);
	Test.add_func ("/f32/value/spellings-bounded-extremes-sticky", spellings);
	return Test.run ();
}
}
