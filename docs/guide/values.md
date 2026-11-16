# Values, decisions and progress

The first program knew all five readings in advance. Now imagine the same
calibration sequence growing longer: readings start at two, increase by two and
stop at ten. A loop can express that pattern once. We will count the readings
as well as add them, so an incorrect loop boundary has two chances to reveal
itself.

Keep the terminal environment from [Getting started](getting-started.md).
The complete program is [pilot-loop.astra](../../tests/books/pilot-loop.astra):

```astra example=pilot-loop
language astra27b;
int main() {
	int total = 0;
	int count = 0;
	int reading = 2;
	while (reading <= 10) {
		total += reading;
		count += 1;
		reading += 2;
	}
	if (count != 5 || total != 30) return 1;
	return 0;
}
```

Build and run it with the same two-step recipe. The message appears only if
compilation, linking and the program all succeed:

```sh tutorial=values
ASTRA_LESSON=pilot-loop
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    "tests/books/$ASTRA_LESSON.astra" &&
cc -no-pie "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
"$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
printf '%s\n' 'Five readings; total 30 (exit 0).'
```

The Astra program itself still prints nothing. It returns 0 after checking
both results. As before, use `-O2` to build the other tested target profile.

## Follow one iteration

`while` tests its condition before entering the body. Initially, `reading` is
2, so `reading <= 10` is true. `total += reading` adds the current reading to
the old total and stores the result. `count += 1` records one accepted reading.
Finally, `reading += 2` prepares the next value.

| Reading used in this iteration | Total after adding it | Count |
| --- | --- | --- |
| 2 | 2 | 1 |
| 4 | 6 | 2 |
| 6 | 12 | 3 |
| 8 | 20 | 4 |
| 10 | 30 | 5 |

After the last row, `reading` becomes 12. The condition is tested again and the
body is skipped. Twelve is not added. Starting above ten would likewise give
zero iterations; a `while` body does not run once unconditionally.

The final `if` uses `||`, meaning “or”: either a wrong count or a wrong total
is enough to fail the check. Conditions have type `bool`. A number such as
`count` is not itself a truth value; compare it with another number to ask a
question about it.

Keep the braces around the loop and the body of an `if` that updates values.
They make the scope and progress visible, and the parser's unbraced statement
forms are narrower than “anything that fits on one line.” This lesson uses the
currently executable `while` form. Historical `for` examples and comparison
chains have different native-admission limits; see [Control](../reference/control.md).

## Decide which readings to keep

Suppose the reading six was a calibration sample and should not contribute to
the report. Before changing the code, predict both new results. Removing six
leaves 2, 4, 8 and 10: four readings totaling twenty-four.

Exercise: add a condition around the two accumulation statements, then update
the final check. Keep the progress step outside that condition. Here is the
[complete tested answer](../../tests/books/pilot-filter.astra):

```astra example=pilot-filter
language astra27b;
int main() {
	int total = 0;
	int count = 0;
	int reading = 2;
	while (reading <= 10) {
		if (reading != 6) {
			total += reading;
			count += 1;
		}
		reading += 2;
	}
	if (count != 4 || total != 24) return 1;
	return 0;
}
```

Why does the position of `reading += 2` matter? If it were inside the `if`,
reaching six would skip the update as well as the addition. The next iteration
would see six again. In the answer, every iteration advances whether the
reading is accepted or rejected.

Run this complete answer:

```sh tutorial=filter-answer
ASTRA_LESSON=pilot-filter
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    "tests/books/$ASTRA_LESSON.astra" &&
cc -no-pie "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
"$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
printf '%s\n' 'Four readings; total 24 (exit 0).'
```

Its expected exit status is 0. You have changed the selection rule while keeping
the traversal rule intact.

## Choose a numeric domain deliberately

`int` is Astra's signed 32-bit integer type, also spelled `i32`. It easily holds
these small totals. There are other widths and unsigned types, but an already
typed value does not silently become a different integer type when used in an
expression. This invalid program makes the distinction visible:

```astra example=negative-numeric-mix
language astra27b;
int main() {
	u8 small = 20;
	int wide = 22;
	return small + wide;
}
```

Compile [the negative example](../../tests/books/negative-numeric-mix.astra) and
check the expected status:

```sh tutorial=mixed-type-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-mix.o" \
    tests/books/negative-numeric-mix.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
```

It must exit 1; the diagnostic includes `operator '+' requires compatible exact operand types`.
The `u8` variable and the `int` variable are different domains even though their
particular values would fit in either.

If this calculation should use `int`, convert the small value explicitly before
adding. The [tested repair](../../tests/books/pilot-conversion.astra) is:

```astra example=pilot-conversion
language astra27b;
int main() {
	u8 small = 20;
	int wide = 22;
	int total = (small as int) + wide;
	if (total != 42) return 1;
	return 0;
}
```

`as int` requests the conversion. Here every possible `u8` value fits in `int`.
That reasoning matters: writing a cast does not establish that an arbitrary
value fits a smaller destination. Run the complete repair:

```sh tutorial=conversion-answer
ASTRA_LESSON=pilot-conversion
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    "tests/books/$ASTRA_LESSON.astra" &&
cc -no-pie "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
"$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
printf '%s\n' 'Converted sum is 42 (exit 0).'
```

It checks the result 42 and returns ordinary success, 0. Forty-two here is data
being checked, not the process's success code.

A literal has a different role from an already typed variable. In `u8 small =
20`, the destination supplies the literal's type. It must fit that type. The
separate [out-of-range example](../../tests/books/negative-literal.astra) uses
`u8 reading = 256` and fails with `integer literal is out of range for 'u8'`.
Changing the destination to hold the value is a design decision; automatic
narrowing is not a repair.

## Checking the numeric contract

For our bounded input, the total fits comfortably in `int`. For a larger data
set, choose input limits and numeric widths before trusting the sum. Integer
addition, subtraction and multiplication wrap at their declared width; they
do not automatically raise a recoverable overflow exception.

The optional [numeric edge experiment](../../tests/books/numeric-contract.astra)
checks signed and unsigned wrapping, division/remainder, shifts and floating
conversion. It deliberately exits 42 when its checks pass. Read it alongside
[Types and numerical values](../reference/types.md), which explains fatal
operations such as division by zero and out-of-range floating-to-integer casts.
The [earlier accumulation experiment](../../tests/books/values.astra) combines
a skipped sample with an 8-bit wrapping check. Both remain complete tested
sources; neither is needed to understand the loop above.

## Observing evaluation order

One further experiment becomes useful when functions have visible effects.
`&&` and `||` short-circuit: the right operand runs only if it is needed.
Likewise, a conditional expression evaluates only its selected value arm.
Named arguments change which parameter receives a value, not the order in
which the argument expressions run.

The [evaluation-order source](../../tests/books/evaluation-order.astra) calls
arguments in the written order last, first, middle. Its independent
[C observer](../../tests/books/lifecycle.c) records 312; the function receives
first=1, middle=2, last=3 and computes 123. Skipped logical operands leave the
trace alone, and the selected conditional operand extends it to 3124. This
optional experiment needs that real provider and deliberately exits 42. The
[observer build recipe](objects.md#independent-lifecycle-observer) shows how to
link it; the [Reference](../reference/expressions.md#observing-written-order)
explains the precise order rules.

For now, the important habit is to predict what changes on each step. You can
trace the five readings, explain why the loop stops, and filter a reading without
losing progress. Next, [Records and small calculations](records.md) gives
related values a name and puts one calculation behind a function.
