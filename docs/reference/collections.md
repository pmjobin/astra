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

## Exact materialization and finite callable bounds

R-COLLECTION-COUNTS. A forward half-open range is empty when start is at least
end; an inclusive range is empty when start exceeds end. For a positive stride,
the nonempty count is the ceiling of distance divided by stride for half-open
ranges, or the floor of distance divided by stride plus one for inclusive
ranges. Count arithmetic must handle signed endpoints and integer extrema
without wrapping the traversal into another iteration. The native fill loop
advances only if another element exists.

`collect_fixed()` requires an explicit fixed integer array destination. Only
pure literal bounds/stride, including supported parenthesis/sign/conversion
forms, establish its static cardinality. Inspecting a named variable's initializer
does not make it a constant. A count mismatch is refused:

```astra example=negative-fixed-count
language astra27b;
int main() {
	int[4] values = (0..3).collect_fixed();
	return 42;
}
```

The [cardinality consumer](../../compiler/semantic/range-materialization.astra)
and [independent LLVM materialization check](../../compiler/backend/llvm/recover-range-materialize-check.astra)
keep count validation, allocation and fill separate. Runtime collection uses
owning storage; failure of its checked count or allocation is fatal, with no
recoverable Error or unwind promise.

R-FINITE-LAZY. Inline scalar lambdas admit at most eight scalar or rooted
numeric-view captures, with bounded body traversal. A lazy chain admits at
most eight stages. Bodies are checked at construction but execute only when
reached during consumption. Copied scalar captures snapshot their values;
numeric-view captures retain their actual named backing and borrowing contract.
Owner captures and arbitrary escaping runtime closures are outside this domain.
`filter` requires bool; `sum` accepts the admitted numeric element type,
including scalar floating reductions. No reduction reassociation is implied.

A comprehension materializes immediately. Its source must have pure literal
integer bounds/positive stride proving at most 1,048,576 elements, and its element
must fit the finite scalar callable domain. This dynamic count is refused even
though its initializer happens to be a small literal:

```astra example=negative-dynamic-comprehension
language astra27b;
int main() {
	int count = 3;
	var values = [for (var i in 0..count) => i*i];
	return 42;
}
```

R-VIEW-ROOTS. An immediate range view requires direct half-open int bounds and
an actual named numeric/bool fixed-array or buffer root. Its constant bounds
must be valid; dynamic bounds are guarded. Parentheses and supported nested
views preserve that root. A temporary array, arbitrary field/pointer, inclusive
slice, stored descriptor or escaping loan does not acquire authority from a
matching counted representation. See the existing retained-view negative and
the [root verifier](../../compiler/semantic/range-slicing.astra).
