# Arrays, ranges and lazy collections

R-ARRAYS. A fixed local array has a checked element type and compile-time extent.
An owning runtime array has allocation and cleanup responsibility plus a runtime
length. A borrowed array parameter carries a view, not that responsibility.
`len` observes the admitted array/view extent. Indexing checks the mathematical
index before a load/store; invalid dynamic access traps rather than reaching
unbounded memory. Mutable ordinary arrays and readonly borrowed range views are
different access contracts.

R-RANGES. Modern `start..end` excludes the end; `start..=end` includes it. Bounds
have one exact concrete integer type. A range captures its endpoints as values
without allocating. `step_by` requires a positive stride in the checked integer
domain. Iteration must stop safely at integer extrema rather than overflowing
an inclusive last step. Reversed/empty and maximum-end cases have independent
range conformance tests; they are not derived from an assumed C loop.

```astra example=negative-stride
language astra27b;
int main() {
	var sequence = (0..10).step_by(0);
	return 42;
}
```

R-MATERIALIZATION. `collect_array()` explicitly allocates and returns an owning
array. `collect_fixed()` requires a known exact result count and compatible fixed
destination; dynamic or mismatched counts fail. The native fixed program can
link with a Linux syscall entry without libc, an allocator or a dynamic loader.
That bounded result is not a promise that arbitrary collections are freestanding.

R-VIEWS. `values[first..end]` is a half-open borrowed range view. Bounds satisfy
`0 <= first <= end <= len(values)`. The current implementation admits immediate
length/index/borrowing-call consumption, including checked nested views; it
refuses general retained local descriptors. Inclusive slice spelling, writes,
escaping views and owner-copy materialization remain excluded by their tests.

```astra example=negative-view
language astra27b;
int main() {
	var values = (0..3).collect_array();
	var view = values[0..2];
	return len(view);
}
```

R-LAZY. Range/array iteration transformations retain finite checked callable and
capture identity. `map` and `filter` construct lazy plans; their bodies execute
during consumption. Copied scalar captures retain their construction-time value.
`sum` reduces the admitted integer domain; `collect_array` makes allocation
explicit. A comprehension constructs an owning array over its supported bounded
range. It is not a general coroutine, escaping closure or iterable protocol.

The collection regressions observe callback order, deferred visits, capacity
allocation and retirement. The [Guide](../guide/sequences.md) separates a lazy
pipeline, fixed collection, owning collection and immediate view. Current
`foreach` covers admitted integer sequences, not every historical container.
