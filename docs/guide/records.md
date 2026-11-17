# Records and small calculations

So far, a reading has been one integer. Suppose a reading now contributes a
chosen number of times to the total. We need its value and its weight to travel
together. Two unrelated local variables can hold them, but a named record makes
the relationship part of the program.

A `Sample` will contain two `int` fields: `value` and `weight`. A function will
multiply them. With weight one for every reading, the total must stay thirty;
we can change the representation without changing that result.

The [complete program](../../tests/books/pilot-records.astra) includes the loop
you already know and two small checks we will examine below:

```astra example=pilot-records
language astra27b;
struct Sample {
	int value;
	int weight;
}

int weighted(Sample sample) {
	return sample.value*sample.weight;
}

int main() {
	int total = 0;
	int reading = 2;
	while (reading <= 10) {
		int weight = 1;
		var sample = Sample {value = reading, weight};
		total += weighted(sample);
		reading += 2;
	}
	var original = Sample {value = 6, weight = 1};
	Sample copy = original;
	copy.weight = 2;
	if (weighted(sample: original) != 6 || weighted(copy) != 12) return 1;
	if (total != 30) return 2;
	return 0;
}
```

Run it in the terminal prepared in [Getting started](getting-started.md):

```sh tutorial=records
ASTRA_LESSON=pilot-records
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    "tests/books/$ASTRA_LESSON.astra" &&
cc -no-pie "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
"$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
printf '%s\n' 'Weighted total and independent copy checks passed (exit 0).'
```

There is no Astra stdout in this example. Exit 1 would mean the independent-copy
check failed; exit 2 would mean the total check failed. Ordinary success is 0.
The same complete source is tested with `-O2` as well.

## Describe a value, then construct one

`struct Sample` declares a nominal record type. “Nominal” means that the
particular declaration identifies the type. Another record with two identical
integer fields would still be a different type; equal-looking layouts do not
make the records interchangeable.

The declaration says what a sample contains. The expression
`Sample {value = reading, weight}` creates a particular sample. The explicit
field initializer takes its value from `reading`. The shorthand `weight` means
“initialize the weight field from the same-named local variable.” It does not
make the field an alias of that local.

`var` asks Astra to infer the local's type from its initializer. Here that type
is visibly `Sample`. Inference saves repeating the name; it does not remove
field or type checking. Each required field must be supplied exactly once with
a compatible value. Field construction uses `=`, whereas a named function
argument uses `:`. These are two distinct syntactic roles.

## Give a calculation a name

`weighted` takes a `Sample` and returns an `int`. Inside the function,
`sample.value` and `sample.weight` select fields from its parameter. The call
`weighted(sample)` supplies the record created in the current iteration. The
returned integer contributes to `total`.

This function gives the multiplication a useful name and a small responsibility.
The loop decides which readings exist; the function decides how one sample
contributes. Weight one leaves each reading unchanged, so the familiar sum
2 + 4 + 6 + 8 + 10 is still thirty.

The function receives this scalar record by value. It is appropriate to reason
about copied integers here. Do not generalize that reasoning to class objects,
owners or arbitrary records containing ownership-bearing fields; those have
separate rules. The next chapter introduces object identity and responsibility
for a lifetime.

## Predict what a copy changes

After the loop, the program creates a sample with value six and weight one.
`Sample copy = original` initializes another record value. Changing
`copy.weight` to two changes only that copy:

| Value after the assignment | value | weight | weighted result |
| --- | --- | --- | --- |
| `original` | 6 | 1 | 6 |
| `copy` | 6 | 2 | 12 |

The two calls in the first check observe both results. If assignment merely
created another name for the same mutable record, the original's weighted
result would also change. It does not. Notice that these samples are created
after the loop: changing the copy does not go back and alter the total already
computed from earlier samples.

The [earlier record experiment](../../tests/books/records.astra) checks the same
idea by changing a copied field and computing from the original. It remains
available as a complete tested source, with its documented exit-42 convention.
The [record Reference](../reference/values.md) gives the construction and copying
rules beyond this two-integer example.

## Call a parameter by name

The copy check spells one call `weighted(sample: original)`. The function's
parameter is named `sample`; the caller's local value is named `original`.
The colon associates that argument with the declared parameter. The other
call, `weighted(copy)`, supplies its argument by position. Both calls use the
same concrete function.

Keep the two forms of naming separate: `Sample {value = 6, weight = 1}` names
record fields with `=`, while `weighted(sample: original)` names a function
parameter with `:`. Neither form creates an alias just because it names
something.

A parameter label must come from the function declaration. This separate,
intentionally invalid program makes a common mistake:

```astra example=negative-label
language astra27b;
int identity(int value) {
	return value;
}
int main() {
	return identity(other: 42);
}
```

Compile [the negative source](../../tests/books/negative-label.astra) and check
the expected refusal status, 1:

```sh tutorial=label-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-label.o" \
    tests/books/negative-label.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
```

Its diagnostic includes
`named arguments require unique declared parameter labels and every required argument`.
There is no parameter named `other`. For this function, the valid named call
would use `value:`; a positional call can also supply the parameter. Notice
that `sample:` belongs to `weighted`, while `value:` belongs to `identity`.
The label is a property of the called function, not of all functions.

Concrete functions are enough for the measuring project. Finish the weight
exercise first; an optional generic extension follows it.

## Try a different weight

Exercise: in the loop, give only the reading ten a weight of two. Predict the
new total before compiling. Does the independent-copy check need to change?

The [complete tested answer](../../tests/books/pilot-weight.astra) starts each
iteration with weight one, changes it to two when `reading == 10`, and then
constructs the sample. Its total is 2 + 4 + 6 + 8 + 20 = 40. The separate samples
created after the loop have not changed, so their check stays exactly the same.
Build the complete answer and observe its ordinary success status:

```sh tutorial=weight-answer
ASTRA_LESSON=pilot-weight
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    "tests/books/$ASTRA_LESSON.astra" &&
cc -no-pie "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
    -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
"$ASTRA_BOOK_BUILD/$ASTRA_LESSON" &&
printf '%s\n' 'Weighted total 40; copy checks passed (exit 0).'
```

## An optional first generic

The [earlier record experiment](../../tests/books/records.astra) adds one small
extension: `T identity<T>(T value)` returns its argument unchanged. The type
parameter `T` stands for the concrete type selected at a call. Its
`identity<int>(value: weighted(sample))` call selects `int`, passes the weighted
result through, and returns 42 from `main`. Run that complete source separately:

```sh tutorial=generic-preview
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/generic-preview.o" \
    tests/books/records.astra &&
cc -no-pie "$ASTRA_BOOK_BUILD/generic-preview.o" \
    -o "$ASTRA_BOOK_BUILD/generic-preview" &&
{
    ASTRA_STATUS=0
    "$ASTRA_BOOK_BUILD/generic-preview" || ASTRA_STATUS=$?
    printf 'generic preview exit: %s\n' "$ASTRA_STATUS"
    test "$ASTRA_STATUS" -eq 42
}
```

This older experiment uses the explicit exit-42 convention introduced at the
end of Getting started. It produces no Astra text output. The identity helper
is unnecessary for a single integer calculation; it lets us examine one
substitution without another algorithm. It does not show that every type can
be copied: a plain `T` gives no permission to duplicate an owner. Keep that
limit in mind when [Generics and matching](generics-match.md) motivates
operations used with more than one concrete type.

We now have a calculation whose data and responsibilities are visible: a loop
produces readings, a record keeps related values together, and a function
computes each contribution. Before adding heap storage, continue to
[Objects, owners and observers](objects.md). That chapter asks a new question:
when two parts of a program refer to one object, who is responsible for keeping
it alive and eventually retiring it?
