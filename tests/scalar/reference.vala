// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.ScalarReference {
private AstraIntValue value(int64 number) {
	var result = AstraIntValue.from_int64 (number);
	assert (result != null && result.signed_value == number);
	return result;
}

private void construction() {
	assert (AstraIntValue.MIN == -2147483648L && AstraIntValue.MAX == 2147483647L);
	foreach (int64 number in new int64[] {int64.MIN, -2147483649L, 2147483648L, int64.MAX}) {
		assert (AstraIntValue.from_int64 (number) == null);
	}
	foreach (int64 number in new int64[] {AstraIntValue.MIN, -1, 0, 1, AstraIntValue.MAX}) {
		assert (value (number).signed_value == number);
	}
	// No public constructor/setter can inject an unchecked magnitude.
	var object_class = (ObjectClass) typeof (AstraIntValue).class_ref ();
	assert ((object_class.find_property ("signed-value").flags & ParamFlags.WRITABLE) == 0);
}

private void decimal() {
	foreach (string digits in new string[] {"42", "042", "00042"}) {
		assert (AstraIntValue.from_decimal_magnitude (digits).compare (value (42)) == 0);
	}
	assert (AstraIntValue.from_decimal_magnitude ("0000002147483647").signed_value == AstraIntValue.MAX);
	assert (AstraIntValue.from_decimal_magnitude ("2147483648", true).signed_value == AstraIntValue.MIN);
	assert (AstraIntValue.from_decimal_magnitude ("0002147483648", true).to_string () == "-2147483648");
	assert (AstraIntValue.from_decimal_magnitude (string.nfill (1003, '0')).to_string () == "0");
	assert (AstraIntValue.from_decimal_magnitude ("000", true).to_string () == "0");
	assert (AstraIntValue.from_decimal_magnitude ("2147483648") == null);
	assert (AstraIntValue.from_decimal_magnitude ("2147483649", true) == null);
	foreach (string digits in new string[] {"", "-1", "+1", " 1", "1 ", "1_0", "0xff", "1x", "000" + string.nfill (1000, '9')}) {
		assert (AstraIntValue.from_decimal_magnitude (digits) == null);
		assert (AstraIntValue.from_decimal_magnitude (digits, true) == null);
	}
}

private void addition() {
	assert (value (0).add_wrap (value (0)).signed_value == 0);
	assert (value (1).add_wrap (value (2)).signed_value == 3);
	assert (value (AstraIntValue.MAX).add_wrap (value (1)).signed_value == AstraIntValue.MIN);
	assert (value (AstraIntValue.MIN).add_wrap (value (-1)).signed_value == AstraIntValue.MAX);
	assert (value (AstraIntValue.MIN).add_wrap (value (AstraIntValue.MIN)).signed_value == 0);
	assert (value (AstraIntValue.MAX).add_wrap (value (AstraIntValue.MAX)).signed_value == -2);
}

private void subtraction() {
	assert (value (3).sub_wrap (value (2)).signed_value == 1);
	assert (value (AstraIntValue.MIN).sub_wrap (value (1)).signed_value == AstraIntValue.MAX);
	assert (value (AstraIntValue.MAX).sub_wrap (value (-1)).signed_value == AstraIntValue.MIN);
	assert (value (AstraIntValue.MIN).sub_wrap (value (AstraIntValue.MAX)).signed_value == 1);
	assert (value (AstraIntValue.MAX).sub_wrap (value (AstraIntValue.MIN)).signed_value == -1);
}

private void multiplication() {
	assert (value (6).mul_wrap (value (7)).signed_value == 42);
	assert (value (-6).mul_wrap (value (7)).signed_value == -42);
	assert (value (-6).mul_wrap (value (-7)).signed_value == 42);
	assert (value (65536).mul_wrap (value (65536)).signed_value == 0);
	assert (value (1073741824).mul_wrap (value (3)).signed_value == -1073741824);
	assert (value (-1073741824).mul_wrap (value (3)).signed_value == 1073741824);
	assert (value (AstraIntValue.MIN).mul_wrap (value (-1)).signed_value == AstraIntValue.MIN);
	assert (value (AstraIntValue.MIN).mul_wrap (value (AstraIntValue.MIN)).signed_value == 0);
	assert (value (AstraIntValue.MAX).mul_wrap (value (AstraIntValue.MAX)).signed_value == 1);
	assert (value (AstraIntValue.MIN).mul_wrap (value (AstraIntValue.MAX)).signed_value == AstraIntValue.MIN);
}

private void signs() {
	assert (value (0).neg_wrap ().signed_value == 0);
	assert (value (1).neg_wrap ().signed_value == -1);
	assert (value (AstraIntValue.MAX).neg_wrap ().signed_value == -2147483647L);
	assert (value (AstraIntValue.MIN).neg_wrap ().signed_value == AstraIntValue.MIN);
	foreach (int64 number in new int64[] {AstraIntValue.MIN, -1, 0, 1, AstraIntValue.MAX}) {
		var original = value (number);
		assert (original.positive () == original && original.signed_value == number);
	}
}

private void division() {
	int64[] dividends = {
		7, -7, 7, -7, 2, -2, 0, AstraIntValue.MIN, AstraIntValue.MIN, AstraIntValue.MIN, AstraIntValue.MAX
	};
	int64[] divisors = {
		3, 3, -3, -3, 3, 3, -3, -1, 1, AstraIntValue.MIN, AstraIntValue.MIN
	};
	int64[] quotients = {
		2, -2, -2, 2, 0, 0, 0, AstraIntValue.MIN, AstraIntValue.MIN, 1, 0
	};
	int64[] remainders = {
		1, -1, 1, -1, 2, -2, 0, 0, 0, 0, AstraIntValue.MAX
	};
	for (int i = 0; i < dividends.length; i++) {
		AstraIntValue? quotient;
		AstraIntValue? remainder;
		assert (value (dividends[i]).div (value (divisors[i]), out quotient) == IntArithmeticOutcome.VALUE);
		assert (quotient != null && quotient.signed_value == quotients[i]);
		assert (value (dividends[i]).rem (value (divisors[i]), out remainder) == IntArithmeticOutcome.VALUE);
		assert (remainder != null && remainder.signed_value == remainders[i]);
	}
}

private void zero_divisor() {
	foreach (int64 number in new int64[] {AstraIntValue.MIN, -1, 0, 1, AstraIntValue.MAX}) {
		AstraIntValue? result = value (42);
		assert (value (number).div (value (0), out result) == IntArithmeticOutcome.ZERO_DIVISOR_TRAP);
		assert (result == null);
		result = value (42);
		assert (value (number).rem (value (0), out result) == IntArithmeticOutcome.ZERO_DIVISOR_TRAP);
		assert (result == null);
	}
}

private void comparison() {
	int64[] ordered = {
		AstraIntValue.MIN, -1, 0, 1, AstraIntValue.MAX
	};
	for (int i = 0; i < ordered.length; i++) {
		for (int j = 0; j < ordered.length; j++) {
			assert (value (ordered[i]).compare (value (ordered[j])) == (i < j ? -1 : i > j ? 1 : 0));
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/scalar/reference/construction", construction);
	Test.add_func ("/scalar/reference/decimal", decimal);
	Test.add_func ("/scalar/reference/add", addition);
	Test.add_func ("/scalar/reference/sub", subtraction);
	Test.add_func ("/scalar/reference/mul", multiplication);
	Test.add_func ("/scalar/reference/unary-signs", signs);
	Test.add_func ("/scalar/reference/div-rem", division);
	Test.add_func ("/scalar/reference/zero-divisor", zero_divisor);
	Test.add_func ("/scalar/reference/compare", comparison);
	return Test.run ();
}
}
