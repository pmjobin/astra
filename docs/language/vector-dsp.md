# Vector DSP primitives

[Typed vector memory](vector-memory.md) composes through ordinary values:
`*p = sat_add(*p,amount)`, load/shuffle/store, widen/pack, interleave and integer
bit operations preserve the existing exact types and shape rules. Each memory
read/write is whole-vector; no lane Place, memory arithmetic, or DSP-specific
load/store API is introduced. Bool masks remain values, without bool<N>* storage.

[BIT-1](bitwise.md) composes ordinary exact bit/shift vector values with these
primitives: `sat_add(v << count, bias)`, masking before/after widen or pack, and
shuffle/select of shifted values retain all existing DSP type and saturation
rules. Shift overflow wraps before saturation; an invalid scalar count traps
before the DSP call receives its argument. No fixed-point interpretation is added.

These reserved special forms are exact Astra operations. They compose with
ordinary vector locals, native vector-v4 calls, lane primitives and control flow.
They are not overloadable functions or source aliases for machine instructions.

```text
sat_add(expression, expression)
sat_sub(expression, expression)
widen_low(expression, IntegerType)
widen_high(expression, IntegerType)
pack_wrap(expression, expression, IntegerType)
pack_sat(expression, expression, IntegerType)
interleave_low(expression, expression)
interleave_high(expression, expression)
```

Destination operands are type syntax, never runtime values. Each runtime operand
evaluates exactly once, from left to right; both binary operands always evaluate.
These operations are pure after evaluation and never create lane storage.

## Saturating arithmetic

For exact same scalar IntegerType T operands interpreted as mathematical A and B:
`sat_add` returns `clamp(A+B,T.MIN,T.MAX)`, and `sat_sub` returns
`clamp(A-B,T.MIN,T.MAX)`. Each valid pair has one result and cannot overflow-trap.
Exact same integer VectorType operands apply that scalar rule independently to
each lane and return the same VectorType. Bool, f32, mixed integer types and
scalar/vector mixtures reject.

```astra
u8 x = 250;
u8 a = sat_add(x,10);       // 255
u8 b = sat_add(250,10);     // contextual u8 literals, 255
i8 c = sat_sub(-128,1);     // -128
u8<16> max = splat(255,16);
u8<16> one = splat(1,16);
u8<16> wrapped = max+one;   // all 0
u8<16> clamped = sat_add(max,one); // all 255
```

Literal context follows ordinary integer binary expressions. Without stronger
context `sat_add(1,2)` uses int. Literals must still be in range for their
contextual type. Ordinary `+`, `-` and integer `as` continue to wrap.

## Widening

An integer source `S<N>` must have at least four lanes. Destination D is a scalar
IntegerType with strictly greater bit width, and `D<N/2>` must already be a
supported VectorType. Low selects lanes 0 through N/2-1; high selects N/2 through
N-1. Selected lanes convert using [ICONV](integer-conversions.md).

```astra
i8<16> bytes = splat(-1,16);
i16<8> low = widen_low(bytes,i16);  // all -1
u16<8> high = widen_high(bytes,u16); // all 65535
u8<16> positive = splat(255,16);
i16<8> words = widen_low(positive,i16); // all 255
```

Source signedness controls physical extension, even when destination signedness
differs. `i8<16>` to `i32<8>` rejects because that output shape does not exist.
Same-width sign changes use `as`, not widening. No source lane extraction sequence
is implied by the primitive.

## Packing

Both sources must have the same exact integer `S<N>` type. Destination scalar D
must be strictly narrower, and `D<2N>` must already exist. Output lanes 0 through
N-1 are converted first-source lanes; the remaining lanes are converted
second-source lanes. The ordering is independent of machine byte order.

`pack_wrap` applies ICONV modulo conversion. `pack_sat` clamps the source
mathematical value to `[D.MIN,D.MAX]` before exact destination encoding, using
`AstraIntegerValue.saturating_convert_to`. This authority is separate from
wrapping conversion; there is no public scalar `sat_cast` syntax yet.

| Source value | Destination | pack_wrap lane | pack_sat lane |
| --- | --- | --- | --- |
| i16(-1) | u8 | 255 | 0 |
| i16(300) | u8 | 44 | 255 |
| u16(128) | i8 | -128 | 127 |
| i16(-129) | i8 | 127 | -128 |
| i16(128) | i8 | -128 | 127 |

All signedness combinations and nonadjacent widths are allowed when shapes fit,
including i32<4> pairs to u8<8>. For compatible shapes,
`pack_wrap(widen_low(v,D),widen_high(v,D),S)` equals the original `S<N>` v,
including cross-sign widening destinations.

## Interleave

Both operands have the same exact `T<N>` type; the result has that type.
Every existing integer, bool and f32 vector is supported.

| Variant | Output lane 2k | Output lane 2k+1 | k |
| --- | --- | --- | --- |
| interleave_low(a,b) | a[k] | b[k] | 0 through N/2-1 |
| interleave_high(a,b) | a[N/2+k] | b[N/2+k] | 0 through N/2-1 |

For a={0,1,2,3,4,5,6,7} and b={10,11,12,13,14,15,16,17}, low gives
{0,10,1,11,2,12,3,13} and high gives {4,14,5,15,6,16,7,17}.
F32 lanes are copied without arithmetic, preserving selected signed zero,
subnormal, infinity and NaN values. Bool masks are copied exactly. This adds two
fixed permutations; general two-source `shuffle(a,b,...)` remains unsupported.

Every vector DSP result stays one semantic and SSA vector value. No vector
memory, alignment, C vector ABI or target-specific instruction guarantee follows.
[Whole-vector dot/MAC](vector-dot.md) consumes these ordinary DSP results and
returns a scalar. Integer dot/MAC wraps its accumulator without saturation; f32
dot/MAC freezes separate rounded products and ascending-lane additions. Grouped,
mixed and saturating dot/MAC, widening multiply, horizontal reduction syntax,
FMA, rotates and per-lane shifts remain deferred.
See [the IR contract](../ir/vector-dsp.md) and [ADR 0040](../decisions/0040-vector-dsp-foundations.md).
