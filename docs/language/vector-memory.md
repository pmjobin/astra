Surge 11 adds checked vector loads/stores over bounded scalar numeric views,
including runtime-checked alignment and a scalar lowering control. These coexist
with the typed whole-vector pointer places described below. See the
[numerical guide](numerical-policies.md) and
[ADR 0157](../decisions/0157-bounded-vector-memory-and-wide-reductions.md).

# Typed vector pointers and whole-vector memory

[Bounded slices](slices.md) borrow numeric vector arrays explicitly. Whole-vector
loads/stores, strict f32 values and BIT/DSP/dot/mac semantics remain unchanged.
SliceElementPlace adds runtime bounds authority; TypedPointerType and
DereferencePlace retain their existing exact-object contract. Slice and vector
pointer locals coexist, without implicit conversion or pointer extraction.

[Fixed local arrays](arrays.md) now provide independent contiguous backing
storage for numeric vector objects. `T<M>[N]` is ArrayType(VectorType(T,M),N),
with dynamic checked whole-vector element Places and no element address-of.
Vector pointers still require direct-local borrowing; arrays neither decay nor
convert elements into pointers. Array/vector element alignment uses the same
backend target layout policy. Bool-vector arrays and slices remain deferred; numeric slices are supported.

A numeric vector can occupy one addressable object. Its nullable pointer uses
the same `TypedPointerType` and lexical borrow rules as scalar and native struct
pointers. Dereferencing it loads or stores one whole value.

```astra
int main() {
	i16<8> v = {1,2,3,4,5,6,7,8};
	i16<8>* p = &v;
	*p = splat(42,8);
	if (!all(v == splat(42,8))) { return 1; }
	return 0;
}
```

## Types and construction

All currently supported numeric VectorTypes are pointees:

| Element | Lane counts | Pointer spelling examples |
| --- | --- | --- |
| i8, u8 | 2, 4, 8, 16 | `i8<16>*`, `u8<2>*` |
| i16, u16 | 2, 4, 8 | `i16<8>*`, `u16<4>*` |
| int/i32, u32 | 2, 4 | `int<4>*`, `i32<2>*`, `u32<4>*` |
| f32 | 2, 4 | `f32<2>*`, `f32<4>*` |

These are 20 semantic shapes, or 22 spellings counting the int/i32 aliases.
`int<N>*` and `i32<N>*` have identical canonical identity. Signedness, element
identity, and shape otherwise remain exact: `i8<16>*` differs from `u8<16>*`,
`i16<4>*` differs from `i16<8>*`, and `i32<4>*` differs from `f32<4>*`.

`bool<2>*`, `bool<4>*`, `bool<8>*`, and `bool<16>*` reject with
`bool-vector pointers are unsupported; bool memory representation and alignment
are not defined`. Logical masks and LLVM `<N x i1>` by-value transport do not
define bool objects, packed versus byte mask storage, or alignment.

General syntax composes the vector type with `*`; whitespace/comments are
permitted. `f32<4>* p = null` is valid. Exact matching pointer values support
`==` and `!=`, including contextual null in either position. Cross-type equality
and pointer truthiness reject; write `p != null`.

`&v` requires a visible, initialized direct numeric-vector local. Parameters,
fields, `&*p`, `&v[k]`, temporaries, and mask locals cannot be addressed. The
address carries v's lexical region. Stored borrows in the same or a descendant
region work, as do call-bound `mutate(&v)` and native forwarding. An inner
local's pointer cannot be stored in an outer pointer local. Pointer results
remain rejected pending return-lifetime contracts.

## Storage, aliases, and operations

Any checked address-of marks v addressable for its whole relevant lifetime.
Initialization constructs the ordinary vector value and writes that storage
once each time the declaration executes. Every later direct read reloads memory;
every direct assignment stores to it. Such a vector has no promoted SSA copy.
Vectors whose addresses are never taken remain ordinary promotable whole values.

```astra
void mutate(i16<4>* a, i16<4>* b) {
	*a = splat(12,4);
	*b = *b + splat(30,4);
}

int main() {
	i16<4> v = splat(1,4);
	i16<4>* p = &v;
	v = splat(7,4); // *p now observes 7 in every lane.
	*p = splat(9,4); // v now observes 9 in every lane.
	mutate(&v,&v); // Aliasing mutable arguments are allowed.
	if (!all(v == splat(42,4))) { return 1; }
	return 0;
}
```

Borrows govern lifetime, not exclusivity or readonly access. Pointer copies
are ordinary values, without ownership transfers or cleanup responsibility.
Calls, branches, and loops preserve direct/indirect coherence.

`*p` is the ordinary DereferencePlace with exact VectorType. Expression context
loads one vector value; `*p = rhs` stores one whole exact matching vector. An
`i8<8>` value cannot be stored through `i16<8>*` without an explicit valid
`as i16<8>` conversion first. An explicit RHS splat receives the checked left
vector's exact type in binary expressions, including `v == splat(42,8)`.

```astra
i16 lane = (*p)[2]; // One whole-vector load followed by value extraction.
*p = insert(*p,2,42); // Load, produce updated vector, store whole vector.
```

`(*p)[2] = 42` remains invalid. No lane Place or address is exposed. Splat,
shuffle, select, BIT, saturation, widen/pack, interleave, dot and MAC compose
with loaded values without changing their established semantics. For example,
`*out = dot(*a,*b)` combines f32* output and f32<4>* inputs; strict f32 reduction
order and separate rounding points remain unchanged.

## Null, values, alignment, and boundaries

Each dereference traps on null before physical memory access. A store evaluates
its pointer base, then RHS, then performs its guarded store, preserving earlier
RHS effects. `p != null && all(*p == expected)` safely skips the load for null.
No flow-sensitive nonnull type is added; redundant guards may be optimized later.

Integer memory preserves every lane bit and its signed/unsigned interpretation.
F32 memory preserves binary32 values, including signed zero, subnormals,
infinities, and NaN behavior. Plain load/store is not arithmetic and adds no
rounding point, fast math, or observable NaN payload operation.

A non-null typed vector pointer denotes a suitably aligned, live object of its
exact type. Direct local addresses and compatible Astra-native forwarding
guarantee alignment by construction. The target/backend chooses numeric object
alignment; Astra freezes no number, including 16 bytes. Byte order, lane offsets,
packing, and padding are not exposed. Unaligned arbitrary addresses are unsupported.

One whole-vector operation may become one SIMD instruction, narrower accesses,
or scalar machine accesses. Such legalization does not create Astra lane loads
or stores. Ordinary memory is neither volatile nor atomic; no concurrency,
synchronization, visibility, atomicity, or tearing guarantee is introduced.

Native vector pointers transport as existing PTR/LLVM opaque `ptr`. A signature
`void clear(i16<8>* p)` uses the existing pointer-compatible profile. The vector
pointee alone does not select vector-v4. `void store(f32<4>* p,f32<4> value)` does
select vector-v4 because of its actual by-value vector channel. No NABI version
is added. C imports/exports containing vector pointers reject; VAPI gains no
vector-pointer syntax. Default x86-64 Linux remains the qualified target.

Pointer arithmetic/indexing/increments, pointer casts and raw conversions,
pointer-to-pointer, vector-pointer results, Resource*, bool memory, vector struct
fields, lane addresses/assignment, unaligned/explicit-alignment operations,
volatile/atomic memory, pointer-backed slices, gather/scatter, and C vector ABI remain
unsupported. Future extensions must preserve the exact aligned-object invariant.

See [ADR 0044](../decisions/0044-vector-memory.md), [IR](../ir/vector-memory.md),
[typed pointers](typed-data-pointers.md), and qualification.
