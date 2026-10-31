# Opt-in array production

Select both `datadir/astra/base/buffers.astra` and `datadir/astra/base/slices.astra`
from the configured installation. In a checkout their paths begin `lib/astra/base/`.
The dependency is required even by a client using only clone_array: every selected
definition is checked, and filled_array calls the ordinary fill definition.

```astra
owned T[] clone_array<T>(T[] source)
owned T[] filled_array<T>(int count, T value)
```

These are ordinary provisional library names. They are not compiler intrinsics or
reserved identifiers. There is no autoload, autolink, module or namespace machinery;
collisions produce ordinary duplicate-source diagnostics. Meson installs buffers.astra
with the existing base sources using configured datadir, independently of libdir.

clone_array allocates zero-initialized independent storage, then copies elements in
ascending order. The source remains owned by its original owner and usable. Positive
live allocations are distinct; empty descriptors may both be null/zero. Copies follow
the existing exact recursive value rules. Unmanaged void* values copy their addresses,
not their pointees; this is not an object graph clone or padding comparison.

filled_array eagerly copies its value argument before entering the callee, even for
zero or invalid dynamic counts. It zero-initializes storage, calls fill, then transfers
the result. No lazy callback or uninitialized-allocation optimization is promised.
Both helpers use existing language allocation/index traps. They require no ARGS,
output, diagnostic or failure-provider import; allocation uses the existing implicit
qualified concrete allocator realization.

```sh
astrac main.astra "$prefix/$datadir/astra/base/buffers.astra" "$prefix/$datadir/astra/base/slices.astra" -o application
```

Use configured prefix/datadir (or their relocated counterparts), rather than guessing
installation directories. The [four-file client](../../examples/generic-owned-arrays/main.astra)
also selects diagnostics and hosted text and links their exact providers from configured
libdir. Its algorithms execute in Astra. The validation report
records tested argv, relocation, all 24 source orders and a pure client.

This library provides no resize/reserve/append/realloc, container class, allocating
generic class, copy_range/memmove, deep clone, lazy initializer or custom allocator.
See [generic owned arrays](../language/generic-owned-arrays.md) for element and move rules.
