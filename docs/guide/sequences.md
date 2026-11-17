# Sequences without hidden costs

Generating one reading per loop was enough to compute a sum. A file reader will
instead obtain a group of values that other functions need to inspect. Before
choosing a container, ask two questions: do we need storage at all, and who will
own it? A range describes values; an array stores them; a borrowed slice gives
access to part of existing storage.

This chapter expresses the familiar five readings in each form. Then we will
change the stride and predict exactly which values remain. No new I/O machinery
is needed; keep the terminal environment from the preceding chapters.

## Store readings and borrow a window

The [complete program](../../tests/books/guide-sequences.astra) has one ordinary
summing function and several ways to supply or calculate data:

```astra example=guide-sequences
language astra27b;
int sum(borrowed int[] values) {
	int total = 0;
	int at = 0;
	while (at < len(values)) {
		total += values[at];
		at += 1;
	}
	return total;
}

int main() {
	int[5] fixed = (2..=10).step_by(2).collect_fixed();
	var readings = (2..=10).step_by(2).collect_array();
	if (sum(fixed[0..5]) != 30 || sum(readings) != 30) return 1;
	if (sum(readings[1..4]) != 18) return 2;
	var selected = (2..=10).step_by(2).filter(value => value != 6);
	if (selected.sum() != 24) return 3;
	return 0;
}
```

Start with the two materializations. `2..=10` includes both endpoints;
`.step_by(2)` yields 2, 4, 6, 8, 10. `collect_fixed()` fills an explicitly typed
`int[5]` destination. Its element count must be provable from literal bounds
and stride. `collect_array()` creates owning storage whose length is carried
at runtime. Both contain the same values, but they have different storage
contracts.

`sum` takes `borrowed int[]`: it reads an array view during the call and does not
acquire the storage. `len(values)` gives the view's length. A runtime owning
array can supply this parameter directly. A fixed array does not silently become
that parameter type; `fixed[0..5]` explicitly supplies an immediate view of all
five elements.

The middle slice, `readings[1..4]`, starts at index one and stops before index
four. It contains 4, 6, 8, so its sum is eighteen. Slice bounds are half-open even
though the earlier generation range was inclusive. Index zero is the first
element; the last valid index is one less than the length.

```sh tutorial=sequences
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/sequences.o" tests/books/guide-sequences.astra
cc -no-pie "$ASTRA_BOOK_BUILD/sequences.o" -o "$ASTRA_BOOK_BUILD/sequences"
"$ASTRA_BOOK_BUILD/sequences"
printf '%s\n' 'Stored total 30; middle 18; filtered total 24 (exit 0).'
```

The shell prints that summary after the silent Astra checks return 0. The array
owner remains in `main` throughout each borrowing call and is cleaned up when
its scope ends. A returned integer has no borrowing relationship to that array.

## A view is not an independently stored owner

It is tempting to write a local variable for every intermediate value. The
current view domain is narrower: consume a range view immediately in an admitted
length, index or borrowing call. The complete
[retained-view mistake](../../tests/books/negative-view.astra) tries to store
`values[0..2]` in a local before asking for its length:

```sh tutorial=view-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-view.o" \
    tests/books/negative-view.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/rejected-view.o"
```

The diagnostic includes `consumed immediately`. The working repair is the
immediate `sum(readings[1..4])` call above. Do not describe the rejected local
as an owning copy: no materialization was requested. The supported slice is
readonly and must remain rooted in actual live backing. Dynamic bounds are
checked; an invalid access traps rather than becoming a recoverable `Error`.

## Delay a calculation until it is consumed

The last part of our program needs only a filtered total. It builds a lazy plan
with `filter(value => value != 6)`, then consumes that plan with `sum()`. The
lambda takes one value and returns a Boolean decision. The five generated
values become four accepted values, totaling twenty-four, just as in the
[early filtering exercise](values.md#decide-which-readings-to-keep).

Constructing the plan checks its body and retains the required receiver and
captures; it does not yet run the body for every element. Consumption performs
the work. Adding `.collect_array()` would explicitly materialize owning storage
instead of merely reducing to a scalar.

The [lazy capture experiment](../../tests/books/lazy.astra) makes another useful
prediction possible. It captures `bias = 1` while constructing a map, changes
the local to 100, then consumes the plan. Its copied scalar capture remains one:
values one through six are filtered to four, five and six, total fifteen.
Its comprehension separately materializes three squares. The whole experiment
returns the intentional sentinel 42.

A borrowed array receiver retains its named backing, not a new independent array.
The [floating reduction experiment](../../tests/books/numeric-pipeline.astra)
uses that relationship to map 20, 40, 24 to 10, 20, 12 and check 42. These values
are exactly representable; arbitrary decimal arithmetic still involves rounding.
Current chains and captures have finite checked limits, including eight stages;
these examples do not introduce general escaping closures or an iterator protocol
for every container. See [Collections](../reference/collections.md).

## Change the stride, then check the edges

Exercise: sample every fourth value starting at two, through an inclusive bound
of ten. How many values are there, and what should the fixed destination's size
be? Also check what happens for the empty half-open range `3..3` and the reversed
range `5..2`.

The [complete answer](../../tests/books/guide-stride.astra) checks the actual
elements as well as their sum:

```astra example=guide-stride
language astra27b;
int main() {
	int[3] readings = (2..=10).step_by(4).collect_fixed();
	if (readings[0] != 2 || readings[1] != 6 || readings[2] != 10) return 1;
	int total = 0;
	foreach (var value in (2..=10).step_by(4)) {
		total += value;
	}
	var empty = (3..3).collect_array();
	var reversed = (5..2).collect_array();
	if (total != 18 || len(empty) != 0 || len(reversed) != 0) return 2;
	return 0;
}
```

The values are 2, 6, 10: count three, total eighteen. `foreach` consumes this
admitted integer sequence; it does not mean every array supports that syntax.
The empty and reversed ranges both produce zero-length owning arrays. There is
no first element to read from either.

```sh tutorial=stride-answer
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/stride.o" tests/books/guide-stride.astra
cc -no-pie "$ASTRA_BOOK_BUILD/stride.o" -o "$ASTRA_BOOK_BUILD/stride"
"$ASTRA_BOOK_BUILD/stride"
printf '%s\n' 'Stride four: 2, 6, 10; total 18; empty bounds checked (exit 0).'
```

A stride must be positive. The [zero-stride mistake](../../tests/books/negative-stride.astra)
is a compilation refusal, not a request for an endless sequence. A fixed count
must also agree: the [wrong-size destination](../../tests/books/negative-fixed-count.astra)
requests four slots for three values and is refused with `exact destination count`.
Use the answer's `int[3]` for its three generated values. A named variable whose
initializer happens to be a literal does not supply every static proof;
the [dynamic comprehension control](../../tests/books/negative-dynamic-comprehension.astra)
shows that boundary.

| Need | Choice | Responsibility |
| --- | --- | --- |
| Generate bounded values | Range | Captured endpoints, no element storage |
| Store a statically exact count | Fixed array | Fixed local storage |
| Keep a runtime collection | Owning array | Allocation and cleanup |
| Inspect part of existing storage | Immediate slice | Borrow backing that remains alive |
| Transform or select before reducing | Lazy plan | Retain admitted receiver/captures until consumption |

The [original collections program](../../tests/books/collections.astra) and
[endpoint experiment](../../tests/books/range-edges.astra) remain further tested
readings, including the maximum `u8` endpoint and an inclusive bound a stride
does not land on. Their exit-42 checks are separate from our new exit-0 lessons.
Next, [Generics and matching](generics-match.md) asks how much of a calculation
can be shared between types, and how to represent more than one kind of result.
