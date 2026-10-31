// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.Exec {
private void matrix() throws GLib.Error {
	// SCALAR-1's numeric authority is the oracle. Parameterized functions
	// keep all tested operations in machine code without constant operands.
	var source = new StringBuilder ("""
int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
int mul(int a, int b) { return a * b; }
int neg(int a) { return -a; }
int div(int a, int b) { return a / b; }
int rem(int a, int b) { return a % b; }
bool lt(int a, int b) { return a < b; }
bool le(int a, int b) { return a <= b; }
bool gt(int a, int b) { return a > b; }
bool ge(int a, int b) { return a >= b; }
bool eq(int a, int b) { return a == b; }
bool ne(int a, int b) { return a != b; }
int main() {
""");
	int64[] left = {
		0, 1, -1, 7, -7, 7, -7, AstraIntValue.MIN, AstraIntValue.MAX, AstraIntValue.MIN, 65536, 1073741824, AstraIntValue.MAX, AstraIntValue.MIN
	};
	int64[] right = {
		0, -1, 1, 3, 3, -3, -3, -1, 1, AstraIntValue.MIN, 65536, 3, AstraIntValue.MAX, AstraIntValue.MAX
	};
	int checks = 0;
	for (int i = 0; i < left.length; i++) {
		var a = AstraIntValue.from_int64 (left[i]);
		var b = AstraIntValue.from_int64 (right[i]);
		string arguments = a.to_string () + ", " + b.to_string ();
		string[] operations = {
			"add", "sub", "mul", "neg"
		};
		AstraIntValue[] expected = {
			a.add_wrap (b), a.sub_wrap (b), a.mul_wrap (b), a.neg_wrap ()
		};
		for (int j = 0; j < operations.length; j++) {
			source.append_printf ("\tif (%s(%s) != %s) { return %d; }\n", operations[j], j == 3 ? a.to_string () : arguments, expected[j].to_string (), ++checks);
		}
		string[] comparisons = {
			"lt", "le", "gt", "ge", "eq", "ne"
		};
		int relation = a.compare (b);
		bool[] truths = {
			relation < 0, relation <= 0, relation > 0, relation >= 0, relation == 0, relation != 0
		};
		for (int j = 0; j < comparisons.length; j++) {
			source.append_printf ("\tif (%s(%s) != %s) { return %d; }\n", comparisons[j], arguments, truths[j] ? "true" : "false", ++checks);
		}
		AstraIntValue? quotient;
		AstraIntValue? remainder;
		var div_outcome = a.div (b, out quotient);
		var rem_outcome = a.rem (b, out remainder);
		assert (div_outcome == rem_outcome);
		if (div_outcome == IntArithmeticOutcome.VALUE) {
			source.append_printf ("\tif (div(%s) != %s) { return %d; }\n", arguments, quotient.to_string (), ++checks);
			source.append_printf ("\tif (rem(%s) != %s) { return %d; }\n", arguments, remainder.to_string (), ++checks);
		} else {
			assert (quotient == null && remainder == null);
		}
	}
	source.append ("\treturn 0;\n}\n");
	assert (checks == 166 && checks < 256);
	Test.message ("14 operand pairs, 166 machine checks against AstraIntValue, one compile/link/run");
	execute (source.str);
}

private void register_matrix() {
	add ("/exec/scalar-reference-matrix", matrix);
}
}
