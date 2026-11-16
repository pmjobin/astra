# Values, decisions and progress

Suppose a reading processor must add a small series while excluding one
calibration sample. We need exact numbers, a condition and a loop that makes
progress. This complete program also demonstrates wrapping at an explicitly
small integer width:

```astra example=values
language astra27b;
int main() {
	u8 wrapped = 255;
	wrapped += 1;
	int total = 0;
	int i = 0;
	while (i < 6) {
		if (i != 2) {
			total += i;
		}
		i += 1;
	}
	bool between = 0 < total && total < 20;
	return between && wrapped == 0 ? total+29 : 1;
}
```

`u8` is an unsigned 8-bit value: incrementing 255 wraps to zero. `int` is a
different exact type. The loop visits zero through five, skips two from its sum,
and finishes with total 13. The final conditional returns 42 only when both
the total's range and the wrapping result agree with the independent expectation.
Any other outcome reaches exit 1.

The `while` condition is tested before each iteration. The update happens after
the branch, so every repeating path advances. Braces around compound assignment
are intentional: the parser's unbraced “simple statement” rule is narrower than
“one line.” See [Control](../reference/control.md).

## Choosing types and expressions

Give externally meaningful values explicit types. Use `var` when the initializer
already makes its checked type and ownership clear. A literal can fit its declared
context; an already typed integer does not silently widen or change signedness.
When you need a supported numeric conversion, write `as` and consider the
destination's range. `bool` conditions are not integers disguised as truth values.

The final `&&` is short-circuiting. Write a safety guard with a logical operator,
not eager bitwise arithmetic. The conditional expression evaluates only its
selected value arm. Parentheses can clarify a calculation, but do not change
the underlying type or ownership contract.

Older manuals describe constants, comparison chains and `for`. The present native
products refuse representative programs using those forms. This chapter uses
typed locals, separate comparisons and `while`; the [Reference](../reference/declarations.md)
retains the actual refusals rather than pretending the parser lacks those syntax
nodes. An out-of-range literal example is in [Lexical structure](../reference/lexical.md).
Use it to recognize the difference between a source error and an environmental
link failure. Numeric values, casts and overflow rules are specified in
[Types](../reference/types.md).

## Observing evaluation order

Named arguments improve readability when several parameters share a type, but
they do not reorder computation to match the declaration. Here the call writes
last, first, middle. The C observer from [Objects](objects.md#independent-lifecycle-observer)
records 312; the callee receives first=1, middle=2, last=3 and returns 123.

```astra example=evaluation-order
language astra27b;
extern(C) int tick(int value);

extern(C) int tick_trace();

int choose(int first, int middle, int last) {
	return first*100 + middle*10 + last;
}

int main() {
	int value = choose(last: tick(3), first: tick(1), middle: tick(2));
	if (value != 123 || tick_trace() != 312) return 1;
	if (false && tick(9) == 9) return 2;
	if (!(true || tick(8) == 8)) return 3;
	int selected = false ? tick(7) : tick(4);
	if (selected != 4 || tick_trace() != 3124) return 4;
	return 42;
}
```

The skipped logical operands leave the trace alone. The conditional evaluates
only tick(4), so the final trace is 3124. If you rewrote this call into positional
form without first capturing values in written order, you could change the
program's effects. See the [Reference](../reference/expressions.md#observing-written-order).

## Checking the numeric contract

Use small concrete checks to learn how an exact numeric domain behaves. These
checks intentionally include the signed minimum and a negative remainder:

```astra example=numeric-contract
language astra27b;
int main() {
	i8 signed_wrap = 127;
	signed_wrap += 1;
	u8 unsigned_wrap = 255;
	unsigned_wrap += 1;
	int minimum = -2147483648;
	if (signed_wrap != -128 || unsigned_wrap != 0) return 1;
	if (minimum / -1 != minimum || minimum % -1 != 0) return 2;
	if (-7 / 3 != -2 || -7 % 3 != -1) return 3;
	i32 signed_bits = -8;
	u32 unsigned_bits = 0x8000_0000;
	if ((signed_bits >> 1) != -4 || (unsigned_bits >> 31) != 1) return 4;
	f64 fraction = 42.75d;
	if ((fraction as int) != 42 || ((-fraction) as int) != -42) return 5;
	return 42;
}
```

The 8-bit additions wrap in their own domains. The signed division special case
returns MIN and zero remainder, while -7 divided by 3 truncates toward zero.
The signed right shift preserves the sign and the unsigned shift inserts zeroes.
Float casts truncate toward zero after checking representability. Division by
zero, an invalid dynamic shift or a nonfinite/out-of-range float cast takes a
fatal path; it is not an ordinary Error you can repair in this program.
The [numeric Reference](../reference/types.md#integer-edge-cases-and-conversion-domains)
separates these cases and links the independent guards.
