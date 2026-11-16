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
