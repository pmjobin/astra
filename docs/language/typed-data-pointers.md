# Typed data pointers

F64-1 admits `f64*` as TypedPointerType(f64) through this same Place and borrow
architecture. `&local`, aliasing, direct/dereferenced reads and writes, native
borrowing and null traps use exact double alloca/load/store without arithmetic
rounding. An f64 pointee still maps to PTR and does not select fp64-v6; a separate
by-value f64 parameter/result does. Floating C boundaries remain deferred.

OBJ-1's [ClassType](objects.md) is a nominal reference type, architecturally
separate from TypedPointerType. `C` already denotes a nullable object reference;
`C*`, `&reference`, object/raw-pointer conversions and object/typed-pointer
conversions are unsupported. Class references use the same lexical borrow-region
rule but do not become data pointers. Their backend opaque `ptr` representation
and the existing PTR method-receiver channel introduce no source conversion or
pointer-to-reference storage. Existing `Struct*`, scalar/vector T* and null-field
semantics are unchanged.

[Struct methods](methods.md) share authoritative storage with existing Struct*
aliases. `c.add(2)` implicitly makes only c address-taken, so direct `c.value`
and `p->value` for `p = &c` observe the same mutation. The specialized `this`
receiver is exact, mutable, non-owning and nonnull, not an ordinary `Struct*`
local. It adds no general nonnull pointer type, exclusivity or noalias promise.
`this.field` needs no null guard; ordinary `p->field` still traps on null.
Neither `p.method()` nor `p->method()` is supported in METHOD-1. Explicit method
T* parameters retain all ordinary native pointer and lifetime rules.

[Slices](slices.md) use `T[]` for borrowed bounded views, separately from `T*`.
Typed pointers retain one-object semantics, no extent, and no indexing/arithmetic.
`len` accepts arrays/slices, never pointers. Slices and scalar/vector pointers
coexist without implicit conversions, `.data`, `&s[i]`, or pointer-backed slice
construction. A slice is non-nullable even when its empty physical base is null.

`T*` is a nullable, non-owning pointer to an exact live `T` object. DPTR-1
supports `i8*`, `u8*`, `i16*`, `u16*`, `int*`/`i32*`, `u32*`, `f32*`, `f64*`, and existing
[native struct pointers](typed-struct-pointers.md). VEC-MEM-1 also admits every
supported [numeric vector pointee](vector-memory.md). They use one typed-pointer
model. `void*` remains a separate [opaque raw pointer](raw-pointers.md).

```astra
void increment(int* p) {
	*p = *p + 1;
}

int main() {
	int x = 1;
	int* p = &x;
	*p = 40;
	x = x + 1;
	increment(p);
	return x;
}
```

This returns 42. Direct `x` reads and writes and indirect `*p` accesses use the
same authoritative storage. There is no cached scalar copy of an address-taken
local. A local whose address is never taken retains ordinary scalar promotion.

## Types and syntax

```text
pointer-type := pointee-type "*"
address-expression := "&" identifier
dereference-expression := "*" unary-expression
dereference-assignment := dereference-expression "=" expression ";"
```

Whitespace/comments may surround the type star. Prefix `*p`, type `int*`, and
infix multiplication `a * b` have distinct parser contexts. Prefix dereference
binds more tightly than multiplication; parentheses can delimit its base:
`*(p)` and `*(&x)` work. Address-of itself accepts only a direct local identifier:
`&(x)` is outside the narrow address syntax, while `(&x)` is a parenthesized
address expression.

Pointer types are canonicalized by exact pointee identity. `int*` and `i32*`
are identical. `i8*`/`u8*`, `i16*`/`u16*`, `int*`/`u32*`, `f32*`/`int*`, and
`Pair*`/`int*` are distinct even when physical storage widths match.

`bool*` is deferred because B1 transport defines no bool memory layout.
`Resource*` would point at an ownership-bearing resource slot, a separate
semantic problem. Numeric vector pointers use the same constructor; bool-vector
pointers remain deferred because their memory representation is undefined. Pointer-to-pointer, including `void**`, remains unsupported.

## Nullable values and comparisons

```astra
int* p = null;
int* q = p;
if (p == null || q != p) {
	// Ordinary bool condition and short circuit.
}
```

Literal null adopts the expected pointer type for initialization, assignment,
arguments, and equality. `p == null` and `null != p` work. With no more specific
context, null still defaults to `void*`. `==` and `!=` require exactly matching
types after contextualization; an ordinary void* variable, even holding null,
does not convert to T*.

Conditions require bool: `if (p)` rejects; use `p != null`. Pointers have no
ordering, arithmetic, bitwise operations, shifts, subtraction distance,
indexing, or increment/decrement. `p[0]` rejects. `as` remains an integer
conversion: pointer/integer, cross-pointee, and typed/void conversions reject.

## Direct local addresses and lexical borrows

`&x` requires a visible, fully initialized direct local of a supported integer,
f32, f64, numeric vector, or native struct type. It produces exact `T*` and marks `x` address-taken
throughout its relevant lifetime. Initial declaration evaluates and initializes
that actual storage once per execution of the declaration. A loop-local
declaration initializes its storage each iteration.

Parameters, fields, dereferences, vector lanes, temporaries, and bool, resource,
mask-vector, or pointer locals cannot newly be addressed. Copy a supported parameter
to a local before taking an address. `&*p`, `&pair.x`, and `&v[2]` are unsupported.

The existing [lexical borrow rule](borrows.md) applies: a stored pointer's
source region must equal or enclose its destination region. Native pointer
parameters guarantee the invocation region; null needs no pointee lifetime;
reading a pointer local guarantees that pointer local's region. These are
lifetime proofs, not alias restrictions.

```astra
int x = 1;
int* p = &x;
int* q = p;
if (x > 0) {
	int* inner = &x; // Enclosing storage outlives the nested pointer.
	*inner = 42;
}
```

An inner local cannot escape into an enclosing pointer:

```astra
int* p = null;
if (true) {
	int inner = 1;
	p = &inner;
}
```

This reports `borrow from 'inner' cannot be stored in pointer 'p' because 'inner'
has a shorter lexical lifetime`. An outward copy of an inner pointer also
rejects conservatively even if its original pointee was an enclosing local.

`consume(&x)` creates the same addressable storage and lifetime proof as storing
`&x`. Multiple mutable aliases are valid: `modify(&x, &x)` passes the same
storage to both parameters. Copying a typed pointer neither moves ownership
nor acquires cleanup. `owned`, `release`, and `rearm` do not apply to T*.

## Dereference is a storage Place

For an integer, f32, f64, or numeric vector pointer, `*p` denotes `Place<T>`. Value context explicitly
loads it; assignment explicitly stores through it. The base is evaluated once.
For `*pointer_expression = rhs`, evaluation is base, RHS, then guarded store.
A null store therefore preserves earlier RHS effects before trapping.

This differs intentionally from [vector lane extraction](vector-lanes.md):
`v[2]` produces a value, so `v[2] = x` remains invalid. `(*p)[2]` loads a whole
vector then extracts a value; `*p = insert(*p,2,x)` stores a whole-vector update.
Struct pointers retain `p->field`; whole
struct `*p` cannot load a struct value.

Every dereference read or write checks null before the physical access. Null
reaches the existing non-returning, non-unwinding trap; it is not undefined
behavior. No particular host signal is source semantics. Normal short circuit
can skip the dereference:

```astra
if (p != null && *p > 0) {
	*p = *p + 1;
}
```

No flow-sensitive nonnull type is introduced. An explicit source check need not
remove the dereference's runtime guard. Eager bool `&` still evaluates both
operands and cannot substitute for `&&`.

## Exact memory and native calls

| Pointee | LLVM storage and load/store type |
| --- | --- |
| i8, u8 | i8 |
| i16, u16 | i16 |
| int, i32, u32 | i32 |
| f32 | float |
| f64 | double |
| numeric T<N> | exact fixed vector `<N x T>`; see [vector memory](vector-memory.md) |

Signedness does not change object width. A load preserves the scalar's exact
semantic interpretation; memory itself performs no numeric extension or
truncation. f32 memory preserves binary32 values, including signed zero,
subnormals, infinity, and NaN behavior, without an arithmetic rounding point.

A non-null T* denotes suitably aligned live storage of exact T. Local address
construction and compatible native forwarding guarantee this invariant. The
backend selects natural alignment; no numeric alignment, stable object layout,
pointer width, endianness, `sizeof`, or `alignof` is exposed. There is no byte
reinterpretation, volatile/atomic memory, or unaligned primitive.

Native parameters physically use existing PTR and LLVM opaque `ptr`. `void
f(i8*)` can use scalar-ptr-v1; `i8 f(i8*)` selects scalar-int-v2 because its
result needs I8. An f32 result needs scalar-fp-v3; vector arguments use vector-v4
with the same PTR parameter. Pointee identity is checked before ABI erasure.

Typed-pointer results reject pending return-lifetime contracts. C imports,
exports, and VAPI typed pointers remain unsupported. No C scalar/layout promise
is inferred from the LLVM widths above.

Vector computation can write a scalar result through a scalar pointer:

```astra
void dot_to(f32* out, f32<4> a, f32<4> b) {
	*out = dot(a, b);
}
```

Vector memory extends this same pointer and DereferencePlace architecture.
A vector pointee uses PTR and does not itself select vector-v4. Only actual
by-value vector channels do so. Alignment is target/backend authority; ordinary
whole-vector load/store makes no atomicity or concurrency promise. Foreign and
unaligned vector memory remain deferred. See [ADR 0043](../decisions/0043-typed-data-pointers.md),
[dereference Places](../ir/dereference-places.md), and
qualification.

## Recursive struct fields

Existing concrete Struct* storage composes with recursive fields:
`p->inner.x` projects nested storage without loading an intermediate struct.
Aliases remain coherent and null trapping is unchanged. There is no new pointer
category or ABI profile; struct pointers still pass PTR. Typed pointer fields
remain rejected and subobject address-of remains deferred. See [nested fields](nested-struct-fields.md).

## Generic native structs

GEN-STRUCT-1 supports fully concrete generic Struct* such as Pair<int,f64>* and Box<i16<8>>*. int/i32 applications share exact pointee and pointer identity; signed/unsigned applications remain distinct. Address-of, arrow access, nested projections, alias coherence, null traps and lexical lifetime rules are unchanged. Pair<T,U>* remains deferred. Every accepted concrete generic Struct* parameter is one PTR channel; aggregate fields create no additional ABI channels. See [generic structs](generic-structs.md).

## Concrete struct copy Places

[Whole copy](struct-copy.md) permits `S b = *p;`, `*p = source;` and `*p = *q;`
for exact same-type native struct storage. Destination capture/null validation
precedes source capture/null validation, then all source leaf loads precede all
destination stores. Same-storage aliases and self-copy are valid. Null source
traps cause no partial destination update. Copy introduces no pointer conversion,
noalias assumption, field pointer eligibility, escaping pointer result contract
or general aggregate Value. Struct* still maps to existing PTR.
