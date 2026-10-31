# Generic borrowed slice algorithms

`T[]` borrows a collection; a plain `T` parameter or result copies a value.

```astra
T element_at<T>(T[] values, int index) {
	return values[index];
}

void replace<T>(borrowed T[] values, T value) {
	T[] alias = values;
	var index = 0;
	while (index < len(alias)) {
		alias[index] = value;
		index = index + 1;
	}
}
```

Both parameter spellings mean mutable, aliasable, non-owning, bounded
`BORROWED_NOESCAPE`. The parameter binding is immutable. An explicit local view
may be copied and rebound within the existing concrete lifetime rules. Saved
copies retain their own complete pointer/count/origin after another local changes.
There is no owner acquisition, payload copy, refcount, allocation or owner pinning.

A signature occurrence records a mutable storage premise for that exact lexical
T in addition to its plain-copy premise. Definitions are checked before demand.
An unused invalid definition still rejects. A local declaration does not create
a premise, and a favorable specialization cannot make unknown members legal.
`T saved = values[i]` and `T[] alias = values` remain necessary where unresolved
`var` inference is prohibited. `len` returns exact int/i32. Indexing supplies no
Eq, Ordered, Numeric, Bitwise or Shift capability.

| Element candidate | Plain-copy T | Mutable T[] element |
| --- | --- | --- |
| bool, i8/u8, i16/u16, int/i32, u32, f32/f64, void* | Yes | Yes |
| All 24 accepted numeric/mask vectors | Yes | Yes |
| Eligible nonempty ordinary/nested/concrete generic records | Exact field proof | Exact field/storage proof |
| Exact outer plain-copy type parameter | Scoped copy premise | Its signature must supply T[] |
| Known symbolic Box<T> value | Scoped GEN-COPY rule | Constructed symbolic slice form is excluded |
| string, Resource, Class, tracked pointer, array, slice | No | No |

The vector set is i8/u8 lanes 2/4/8/16; i16/u16 lanes 2/4/8;
int/u32/f32 lanes 2/4; bool lanes 2/4/8/16. A void* copies an unmanaged pointer;
it promises nothing about the pointee's lifetime. Concrete record storage reuses
STRUCT-ELEM, including its separate zero and trivial-destruction obligations.
Copying itself grants neither zero nor construction.

Ordinary `string[]` parameters remain valid read-only deep borrows. They cannot
instantiate a mutable T[] helper. `identity(view)` still rejects because it would
copy the entire SliceType as T. `element_at(view, i)` instead infers its exact element.

## Inference and evaluation

For an omitted type list, formal T[] and exact actual SliceType<E> observe T=E.
Named owners may supply the existing temporary borrowed conversion. Fixed arrays
require explicit `slice(array)` or `slice(array, start, count)`; the final argument
is a count, not an endpoint. There is no array decay or arbitrary-view subslicing.
Every observation must agree by canonical identity, including nominal records and
whole generic instances. int/i32 aliases agree. Phantom arguments still need an
explicit type list. Result context and caller metadata supply no observations.

```astra
fill(f64_values, 1.0d);      // two exact f64 observations
fill(f64_values, 1.0f);      // conflict
fill(f64_values, 1.0);       // conflict: standalone literal is f32
fill<f64>(f64_values, 1.0);  // existing explicit contextual-literal rule
```

Arguments evaluate once, left to right. A view is captured at its argument
position and stays borrowed through the invocation. `fill(records, records[0])`
is legal: its record seed is fully copied before the callee starts writing.
A completed `element_at` snapshot can outlive disposal or replacement of its
source, including a later outer argument that explicitly moves that buffer.
Borrowing and transferring the same buffer in one call still rejects. A live
indexed destination remains borrowed through its RHS and final stores. Containing
object/field overlaps retain the existing conservative checks.

Reads guard the complete captured view and index before address arithmetic or
leaf loads. Record reads are independent recursive snapshots at bounded consumers:
locals, arguments, named initializer fields and returns. Writes validate the
destination first, capture the complete source, then store leaves. Self-copy and
aliases are legal; padding has no source copy/equality semantics. Failed source or
bounds checks prevent generated partial writes but do not undo explicit earlier
effects. Empty views are valid; indexing any empty view traps.

Use explicit operator requirements for arithmetic or comparisons, for example
`T fold<T>(T[] values, T seed) where T : Numeric` with `T total = seed`, or an
Eq-constrained search. Copy-only vector/record fill and swap require no operator.

Owned T[] and new T[count] are specified separately in
[generic owned arrays](generic-owned-arrays.md). T[N], T*, T[][], Box<T>[] formals,
borrowed slice results, persistent symbolic fields, generic methods and generic classes
remain excluded. Fully concrete companion
parameters/results, arrays and buffer operations retain their current contracts.
The [library](../library/slice-algorithms.md) is opt-in. Native profile and target
rules are unchanged: the qualified hosted/native target remains x86_64 Linux;
borrow-only internal freestanding qualification adds no public cross-target CLI.
The remaining deferred work is listed in [ADR 0079](../decisions/0079-generic-borrowed-slices.md).
