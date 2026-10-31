# Vector component value operations

[VEC-DSP-1](vector-dsp.md) composes with these value primitives: splat feeds
saturating arithmetic, extraction reads DSP results, insertion updates a whole
result, shuffle permutes widened/packed/interleaved values, and select chooses
packed or saturated vectors. Interleave adds two fixed two-source permutations;
`shuffle` remains one-source, and lanes still have no storage identity.

VEC-LANE-1 adds five explicit operations on existing [short vectors](vectors.md).
A vector remains authoritative as a whole value. Reading a component does not
give that component storage identity or make it addressable.

```astra
i16<4> v = {10, 20, 30, 40};
i16 x = v[2];
v = insert(v, 1, x);
// x is 30; v is {10, 30, 30, 40}.
```

`splat`, `insert`, `shuffle`, and `select` are reserved special forms, not
overloadable user functions. Existing direct-local brace syntax is unchanged.

## Syntax and exact typing

```text
splat-expression   := "splat" "(" expression "," lane-count ")"
extract-expression := expression "[" lane-index "]"  # postfix, highest precedence
insert-expression  := "insert" "(" expression "," lane-index "," expression ")"
shuffle-expression := "shuffle" "(" expression ("," lane-index)* ")"
select-expression  := "select" "(" expression "," expression "," expression ")"
lane-count         := unsuffixed-positive-decimal-integer-literal
lane-index         := unsuffixed-non-negative-decimal-integer-literal
```

Counts and indices are compile-time syntax: no names, negative signs, suffixes,
hexadecimal literals, parenthesized literals, arbitrary constant expressions or
runtime evaluation. Leading zeroes and ordinary inter-token trivia are permitted.
Indices must be less than the source lane count. Huge literals reject without
overflow or constructing a runtime Astra integer.

| Form | Operand/result contract | Runtime evaluation |
| --- | --- | --- |
| `splat(x,N)` | scalar `T` → `T<N>`, supported VEC-1 shape | x exactly once, then broadcast |
| `v[k]` | `T<N>` → exact scalar `T` | v exactly once, then extract |
| `insert(v,k,x)` | `T<N>`, scalar `T` → same exact `T<N>` | v, then x, then new value |
| `shuffle(v,i0,...,iN-1)` | one `T<N>` → same exact `T<N>` | v exactly once, then permutation |
| `select(m,a,b)` | `bool<N>`, `T<N>`, identical `T<N>` → `T<N>` | m, then a, then b, then choice |

These evaluation rules include ordinary traps and effects. If an earlier operand
does not complete, later operands do not execute. Select itself never suppresses
an operand according to mask values; even an all-true mask evaluates the false
vector. The primitive creates no source control flow.

## Splat and literal context

```astra
u8<16> one = splat(1, 16);
f32<4> floats = splat(1.0, 4);
bool<8> yes = splat(true, 8);
```

Expected VectorType supplies its element type as scalar literal context, using
existing exact integer range rules, including through arithmetic with an expected
vector result. An already typed scalar retains its type.
Without stronger vector context `splat(1,4)` defaults to `int<4>`. `splat(1,8)`
therefore exceeds the supported 128-bit numeric payload. `splat(u8_value,16)` is
valid; lane count 3, `splat(int_value,8)` and `splat(f32_value,8)` reject.
`f32<4> v=splat(1,4)` rejects: integer-to-f32 conversion remains unsupported.
Other arithmetic/assignment never broadcasts scalars implicitly.

## Extraction and insertion

The base can be any vector expression, including `make_vector()[2]`, `(a+b)[1]`,
or `shuffle(v,3,2,1,0)[0]`. The result has the exact scalar element type, including
ordinary bool for masks. Integer extraction supplies the same literal context
as an exact scalar local or call in surrounding scalar arithmetic/comparisons.

`insert` returns a new vector with one replacement and all other lanes unchanged.
The source value remains unchanged; only a subsequent whole-vector assignment
updates a local. Its element type contextualizes a replacement literal, so
`insert(bytes,2,255)` works for `u8<4>` and does not add arithmetic/conversion.

`v[i]`, `v[1+1]`, `v[-1]`, and out-of-range literals reject statically.
`v[2]=x` reports **vector lanes are not assignment targets; use insert()**.
`&v[2]` reports that vector lanes have no storage identity. No lane Place exists.

## Shuffle and select

```astra
int<4> reversed = shuffle(v, 3, 2, 1, 0);
int<4> repeated = shuffle(v, 0, 0, 0, 0);
int<4> rotated = shuffle(v, 1, 2, 3, 0);
bool<4> mask = {true, false, true, false};
int<4> chosen = select(mask, a, b);
```

Shuffle requires exactly N in-range selectors. Duplicates and omitted source
lanes are valid; result lane i copies source lane selector[i]. It cannot change
shape or accept two source vectors. Numeric and bool vectors are supported.

Select chooses a[i] where mask[i] is true and b[i] otherwise. Scalar masks,
scalar data, differing element types or shapes reject. Both data vectors must
have identical exact VectorType. Bool data is permitted, including
`all(select(mask,maskA,maskB))` and `any(...)`.

F32 splat/extract/insert/shuffle/select copy exact lane values without arithmetic
or new rounding points. Signed zero, subnormals, infinities and selected NaNs
survive; NaN payload remains non-observable under [F32-1](f32.md).
Surrounding arithmetic retains its rounding points and cannot contract into FMA.

## ABI and future work

[Vector-v4](../abi/native-vectors-v4.md) is unchanged. No CABI or VAPI vector
support is added. Default x86-64 Linux remains the qualified target; LLVM may
legalize operations into SIMD, scalar instructions, moves or spills.

[Vector memory](vector-memory.md) supports numeric vector pointers and addressable
locals through ordinary Places. `(*p)[k]` is a whole-vector load followed by
value extraction, and `*p = insert(*p,k,x)` performs whole-vector read/modify/write.
`(*p)[k] = x` and lane addresses remain invalid. A checked left vector supplies
exact RHS context for explicit splats, including `v == splat(42,8)`.
Vector fields, mask memory, writable swizzles and dynamic indexing require
separate design. [Dot products and MAC](vector-dot.md) consume ordinary values. See [ADR 0038](../decisions/0038-vector-lane-primitives.md).
