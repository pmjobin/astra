# Sequences without hidden costs

A range is a useful recipe for readings; an array is storage for them. Keep
those ideas separate so that allocation and borrowing remain visible:

```astra example=collections
language astra27b;
int first(borrowed int[] values) {
	return values[0];
}

int main() {
	var samples = (2..=10).step_by(2).collect_array();
	int total = 0;
	int at = 0;
	while (at < len(samples)) {
		total += samples[at];
		at += 1;
	}
	int traversed = 0;
	foreach (var sample in 0..3) {
		traversed += sample;
	}
	int[3] calibration = (2..=6).step_by(2).collect_fixed();
	if (len(samples[1..4]) != 3 || first(samples[1..4]) != 4 || calibration[2] != 6 || traversed != 3) return 1;
	return total+12;
}
```

The inclusive range produces 2, 4, 6, 8 and 10. `collect_array()` allocates their
owning storage. Indexed `while` sums it to 30. The separate `foreach` consumes
an admitted range, whose element binding is immutable. This avoids assuming
that every array supports the historical iterator protocol.

`collect_fixed()` materializes exactly three values into a known destination.
It is different from an owning runtime collection. `samples[1..4]` is a
half-open readonly borrowed view containing 4, 6 and 8. The program consumes it
immediately in `len` and the borrowing helper. General retained view locals
currently fail; the [Reference](../reference/collections.md) includes that negative.

## Delay work deliberately

When a sequence will be filtered or reduced, constructing intermediate owning
arrays can be unnecessary. A lazy pipeline records its receiver and admitted
captures, then performs mapping/filtering during consumption:

```astra example=lazy
language astra27b;
int main() {
	int bias = 1;
	var pipeline = (0..6).map(i => i+bias).filter(value => value>3);
	bias = 100;
	int total = pipeline.sum();
	var squares = [for (var i in 0..3) => i*i];
	if (total != 15 || len(squares) != 3 || squares[2] != 4) return 1;
	return total+27;
}
```

The copied capture is `bias = 1` when the pipeline is constructed. Assigning
100 later does not change that capture. Consumption maps zero through five to
one through six, filters out values below four and sums to 15. The independent
check also verifies a three-element comprehension's length and last value.
The expected exit is 42; no stdout is expected.

Lazy construction does not mean every later consumer is allocation-free.
`sum` reduces values; `collect_array` creates owning storage. A comprehension
also creates owning storage in this supported bounded domain. The regression
suite separately observes callback order, deferred execution and allocation
counts. No escaping closure, coroutine, arbitrary owned capture or generalized
iterator protocol is promised by this example.

Choose a range when you need bounds, a lazy plan when you need deferred work,
fixed materialization when the count is statically exact, and owning collection
when runtime storage is required. Positive stride, bounds and lifetime checks
are part of those choices, not optional debugging features.
