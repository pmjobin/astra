# Generic functions and matching

Our summing function uses `int`, which comfortably holds the bounded readings.
Suppose a small sensor also needs to add two `u8` values without changing their
numeric domain. We could write two additions with different signatures. A generic
can express the shared operation while keeping the two concrete types distinct.

Later in this chapter, we will represent a reading that may be present, missing
or invalid. Generics answer a type-reuse question; an enum and a match answer an
alternatives question. Neither removes the ownership or exact-type rules we
have already learned.

## Constraints at concrete calls

Begin with the operation: add two values of the same numeric type and return
that type. `T` names the type parameter; `where T: Numeric` states the capability
needed by `+`. This [complete program](../../tests/books/guide-generics.astra)
uses the same declaration with both `int` and `u8`:

```astra example=guide-generics
language astra27b;
T add<T>(T first, T last) where T: Numeric {
	return first + last;
}

int main() {
	int total = 0;
	int reading = 2;
	while (reading <= 10) {
		total = add<int>(total, reading);
		reading += 2;
	}
	u8 left = 2;
	u8 right = 4;
	u8 expected = 6;
	if (add<u8>(last: right, first: left) != expected || total != 30) return 1;
	return 0;
}
```

`add<int>` selects a concrete integer instance for the accumulating loop.
`add<u8>` selects a different instance for the sensor values two and four.
The `expected` local is explicitly `u8` too, so the comparison stays in that
domain. A generic does not silently widen a small integer or make arithmetic
overflow recoverable.

Named arguments select declared parameter labels. In the `u8` call, `last:`
and `first:` identify destinations despite their reversed written order.
Argument expressions still evaluate in written order; labels do not rearrange
side effects. Here the expressions are just locals, so there is no observable
effect to reorder.

```sh tutorial=generics
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/generics.o" tests/books/guide-generics.astra
cc -no-pie "$ASTRA_BOOK_BUILD/generics.o" -o "$ASTRA_BOOK_BUILD/generics"
"$ASTRA_BOOK_BUILD/generics"
printf '%s\n' 'int readings total 30; u8 pair totals 6 (exit 0).'
```

The program is silent and exits 0 after both checks. The older
[generic-contract experiment](../../tests/books/generic-contract.astra) uses
20 and 22 and keeps its exit-42 convention.

## A constraint can say no

Does `add<bool>(true, false)` make sense under this contract? The complete
[incompatible call](../../tests/books/negative-generic-capability.astra) is
intentionally invalid:

```sh tutorial=generic-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-generic.o" \
    tests/books/negative-generic-capability.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/rejected-generic.o"
```

Its diagnostic identifies a constraint failure. Boolean is not a numeric
substitution here. Choose a Boolean operation for Boolean data, or supply actual
numeric inputs as in the working example; removing the constraint would not
establish a supported addition for every type.

The current capability set is finite. `Numeric` is not user-defined operator
reflection, and a parsed generic body is not proof that every substitution emits
native code. Every actual instance still goes through type and lifetime checks.
A plain `T` cannot copy an owner merely because this example copies integers.
There is also a ceiling of 256 instances. [Generics](../reference/generics.md)
describes these boundaries without requiring them as steps in this small program.

## Give absence a name

Using zero for a missing measurement is tempting, but zero might itself be a
valid reading. An enum preserves the distinction until a calculation deliberately
chooses what each alternative contributes. This
[complete example](../../tests/books/guide-matching.astra) uses nested alternatives:

```astra example=guide-matching
language astra27b;
enum Problem {
	Missing,
	Invalid(int code)
}

enum Reading {
	Value(int value),
	Failure(Problem problem)
}

int contribution(Reading reading) => match (reading) {
	case Reading.Value(value) => value;
	case Reading.Failure(Problem.Missing()) => 0;
	case Reading.Failure(Problem.Invalid(code)) => 0;
};

int main() {
	int total = 0;
	int value = 2;
	while (value <= 10) {
		total += contribution(Reading.Value(value));
		value += 2;
	}
	if (total != 30) return 1;
	if (contribution(Reading.Failure(Problem.Missing())) != 0) return 2;
	if (contribution(Reading.Failure(Problem.Invalid(64))) != 0) return 3;
	return 0;
}
```

`Reading.Value` carries an integer. `Reading.Failure` carries a `Problem`, whose
alternatives are `Missing` and `Invalid(code)`. The expression-bodied function
returns the selected match arm's value. Each arm ends in a semicolon; even a
zero-payload pattern uses parentheses, as in `Problem.Missing()`.

For this first policy, present values contribute their value and either problem
contributes zero. Five present readings still total thirty. The two separate
checks exercise both problem alternatives; they do not rely on only the branch
that happens to appear in the loop.

```sh tutorial=matching
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/matching.o" tests/books/guide-matching.astra
cc -no-pie "$ASTRA_BOOK_BUILD/matching.o" -o "$ASTRA_BOOK_BUILD/matching"
"$ASTRA_BOOK_BUILD/matching"
printf '%s\n' 'Five present readings total 30; both problem alternatives checked (exit 0).'
```

This enum policy differs from the [throwing validator](text-errors.md). A match
handles an ordinary returned alternative as data; a `catch` handles the declared
error channel of a throwing computation. Choose where the caller should make
the decision rather than disguising one mechanism as the other.

## Exhaustiveness is part of the calculation

The [missing-case mistake](../../tests/books/negative-match.astra) defines a
simpler `Reading` with `Value` and `Missing`, but matches only `Value`. Even
though its particular call constructs a value, the match has not covered its
input type:

```sh tutorial=match-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-match.o" \
    tests/books/negative-match.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/rejected-match.o"
```

The compiler refuses the nonexhaustive match. Repair the calculation by deciding
what the missing alternative means, as the complete three-arm function above
does for its larger type. The [original nested match](../../tests/books/matching.astra)
instead returns an invalid code, and keeps its intentional exit 42.

Our payloads are copied integers and enums made from them. An owning payload
requires a separate choice between inspecting and consuming. A match does not
make a borrowed payload escape safely or allow a second move of one owner.

## Exercise: preserve the accepted count

Returning zero from `contribution` loses information needed for a count: a
valid zero and a missing reading both return zero. Exercise: return a small
record containing the numeric contribution and either one accepted reading or
zero. Keep total 30 and count 5, and explicitly check that a valid zero is counted.

The [full answer](../../tests/books/guide-match-answer.astra) defines
`Contribution { value, accepted }`. Each `Value` arm returns its value with
`accepted = 1`; both problem arms return zero with `accepted = 0`. The loop
accumulates both fields, while separate missing, invalid and valid-zero checks
make the distinction observable:

```astra example=guide-match-answer
language astra27b;
enum Problem {
	Missing,
	Invalid(int code)
}

enum Reading {
	Value(int value),
	Failure(Problem problem)
}

struct Contribution {
	int value;
	int accepted;
}

Contribution contribution(Reading reading) => match (reading) {
	case Reading.Value(value) => Contribution {value, accepted = 1};
	case Reading.Failure(Problem.Missing()) => Contribution {value = 0, accepted = 0};
	case Reading.Failure(Problem.Invalid(code)) => Contribution {value = 0, accepted = 0};
};

int main() {
	int count = 0;
	int total = 0;
	int value = 2;
	while (value <= 10) {
		var item = contribution(Reading.Value(value));
		count += item.accepted;
		total += item.value;
		value += 2;
	}
	var missing = contribution(Reading.Failure(Problem.Missing()));
	var invalid = contribution(Reading.Failure(Problem.Invalid(64)));
	var zero = contribution(Reading.Value(0));
	if (count != 5 || total != 30) return 1;
	if (missing.accepted != 0 || invalid.accepted != 0) return 2;
	if (zero.accepted != 1 || zero.value != 0) return 3;
	return 0;
}
```

```sh tutorial=match-answer
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/match-answer.o" tests/books/guide-match-answer.astra
cc -no-pie "$ASTRA_BOOK_BUILD/match-answer.o" -o "$ASTRA_BOOK_BUILD/match-answer"
"$ASTRA_BOOK_BUILD/match-answer"
printf '%s\n' 'Count 5, total 30; valid zero remains a reading (exit 0).'
```

That record reconnects alternatives with the count-and-total model from the
opening lessons. We now have enough language to organize the calculation.
Next, [Calling native C code](ffi.md) supplies the actual external boundary for
reporting and, eventually, loading the readings from a file.
