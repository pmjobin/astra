# Opt-in slice algorithms

Explicitly select `lib/astra/base/slices.astra`, or the installed
`datadir/astra/base/slices.astra`. It exports two ordinary source functions:

```astra
void fill<T>(T[] values, T value)
void swap_elements<T>(T[] values, int first, int second)
```

`fill` stores the already-captured value in ascending index order. Empty fill
performs no element access; its value argument has still evaluated. A record seed
is an independent value snapshot. `swap_elements` snapshots both selected values
before its first generated write. Matching indices still undergo both checked
reads, and either invalid index traps before a swap-generated write.

Both algorithms borrow the collection and copy its eligible scalar/vector/mask or
record values. They allow aliases and overlapping legitimate views. They are eager
operations without atomicity or synchronization. There is no prelude, automatic
lookup, autolink, intrinsic recognition or reserved name. Conflicting selected
functions receive ordinary global duplicate diagnostics. Bounds failures use
language traps and require no BASELIB failure provider or caller metadata.

Meson installs this file with the other base sources using the configured datadir.
The four-file [example](../../examples/generic-slices/main.astra) additionally
selects diagnostics and hosted text and explicitly links their exact providers
and ARGS. Those dependencies belong to that client, not to slices.astra. The
validation report records actual commands from
outside the compiler source tree, all 24 application orders, staged relocation,
configured directory discovery and a provider-free pure consumer.

This API adds no copying ranges, memmove contract, sorting, allocating clones,
callbacks, iterators, collection class, resizing, slice-return provenance or
arbitrary-view subranges. See the [language rules](../language/generic-slices.md)
for element premises, literal inference and lifetime restrictions.

The separate [array-production library](array-production.md) adds ordinary clone_array and filled_array owners and explicitly depends on this source. It is installed through the same configured datadir convention.
