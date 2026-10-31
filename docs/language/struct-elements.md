# Struct elements

Fixed local arrays, owned runtime arrays and bounded native slices can contain
eligible concrete structs. Records occupy contiguous ordinary record storage.
Elements are copied by value; moving an owned array transfers its one allocation.

```astra
struct Kernel { int left; int right; f64 weight; }
int main() {
	var kernels = new Kernel[4];
	kernels[0].left = 1;
	kernels[0].right = 3;
	kernels[0].weight = 0.5d;
	var saved = kernels[0];
	kernels[1] = saved;
	kernels[0].weight = 1.0d;
	assert_that(saved.weight == 0.5d);
	assert_that(kernels[1].weight == 0.5d);
	return 0;
}
```

This example is retained in `tests/struct-elem-1/fixtures/kernel.astra` and requires
explicit selection of `base/diagnostics.astra` and one diagnostics provider, such
as `diagnostics-hosted.o`. Assertions are ordinary library functions.

## Eligibility and identity

An element must have a nonempty, complete acyclic field graph, ordinary copyability,
trivial destruction and a defined structural zero. Supported leaves are bool,
i8/u8/i16/u16/int/i32/u32, f32/f64, unmanaged `void*`, and the 24 supported numeric
and mask vectors. Nested eligible records recurse. `Box<f64>` and `Box<i16<8>>`
can qualify from their actual concrete fields. `Box<int>` and `Box<i32>` are the
same canonical application; different definitions, signedness or phantom arguments
remain nominally distinct even if their layouts match.

Resource, Class, string, slices, fixed arrays, tracked typed pointers and unresolved
type parameters do not qualify. Field-admissibility restrictions remain in force.
Copyability and zero-initializability are separate predicates. `void*` copies and
zeroes as an unmanaged scalar; it carries no checked pointee lifetime.

## Fixed arrays and slices

```astra
struct Pair { int x; f64 y; }
Pair make() { Pair value = {x=7,y=0.5d}; return value; }
void update(Pair[] view) { view[0].x = 9; }
void example() {
	Pair first = {x=1,y=2.0d};
	Pair[3] values = {first, {y=3.0d,x=2}, make()};
	update(slice(values, 1, 2));
}
```

Array extents use CONST-1 expressions and remain in 1..1024. Exactly N entries
are required. Named entries use the existing `field=initializer` grammar and
require every field exactly once. These braces initialize storage in a declaration;
they are not general struct expressions. Entries execute in written order, and
named fields execute in written order. Each expression/producer executes once.
A producer's complete leaf snapshot precedes its entry stores. The next entry
does not begin until the preceding entry finishes.

`slice(array)` covers the array; `slice(array,start,count)` uses start and count,
not an end index. Borrowed views may alias and mutate their records. Existing
lexical lifetime and reborrow rules apply. There is no implicit array decay,
arbitrary-view subslicing, fixed-array copying, array parameter/result or embedded
array field.

## Runtime storage and ownership

`new S[count]` takes exact int/i32. Zero count produces canonical null/zero without
allocation or free. Positive count creates one contiguous allocation. Before an
owner is published, every semantic leaf is structurally zero: false bool/masks,
zero integers, positive floating zero, null `void*`, recursively through records.
No ordinary method, initializer-like method or property setter runs. Structural
zero promises no application-specific invariant.

Negative count, size/address overflow and unannotated nonzero OOM trap without
publishing an owner. An optional [allocation-failure action](allocation-failure.md)
runs only for allocator null and traps if it returns. Replacement completes
incoming production before releasing the previous allocation; OOM leaves the
previous owner live at action entry and adds no caller unwinding.
Locals, consuming parameters, results and owned class fields retain BUFFER's
capture/disarm/rearm and cleanup rules. Cleanup frees one allocation without
element callbacks. A class owning `S[]` does not gain permission for an embedded S
field. User deinit may inspect and replace its array under the existing live
receiver rules; reverse automatic cleanup releases the final owner.

## Access and value composition

`records[i].field`, nested field chains and `this.records[i].field` are addressable
projections. Collection/receiver and index are evaluated once, then bounds are
checked before any element load/store. `len` counts records. Indexed methods and
existing scalar/vector properties act on that element. Source `&records[i]` and
`&records[i].field` remain excluded. Vector fields are whole leaves; use existing
extraction/insertion operations for lanes.

An element can initialize a typed or inferred local, be assigned to an exact
element or subobject, passed to an ordinary exact struct parameter, or returned
from an exact struct-result function. These are complete snapshots. Later mutation,
replacement or disposal of the array cannot change a copied record. Struct value
parameters remain recursively read-only; an independent mutable local copy is
required for mutation or a mutating receiver.

Assignment captures and validates the destination first, then evaluates and
completes the source snapshot, then writes every destination leaf. Self-copy and
overlapping borrowed views are legal. A destination bounds failure precedes RHS
effects. Source failure causes no copy-generated partial destination update;
unrelated explicit RHS effects are not rolled back. Padding is not a source value.

A completed COPY_VALUE argument can precede `move records` in a later argument.
A live slice borrow, destination or indexed method receiver cannot overlap an
operation that consumes/replaces its backing owner, including through a containing
object alias. No persistent owned-buffer alias or runtime owner pin is introduced.

Generic-function transport and capability rules are unchanged. Concrete generic
record storage does not make `identity(record)` or `identity(records)` legal.
Arbitrary `make_record().field`, C record/slice exports, text-bearing elements and
ownership-bearing records remain outside this feature.

Initial target coverage is x86-64 Linux with 64-bit addresses, with hosted GNU
LP64 allocation where needed. Record alignment, padding and stride follow ordinary
target storage, not flattened native argument channels. All-zero allocation is
qualified for this target and leaf domain; it is not a universal null/zero proof.
