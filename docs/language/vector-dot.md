Surge 11 extends `dot`/`mac` to f64<2> with f64 results/accumulators and the same
strict ascending-lane order. Explicit function FP permissions reach each dot/MAC
operation; unannotated code remains separately rounded. See the
[numerical guide](numerical-policies.md) and
[ADR 0157](../decisions/0157-bounded-vector-memory-and-wide-reductions.md).
The earlier milestone profile below retains its historical scope.

# Exact vector dot products

`dot(*a,*b)` and `mac(c,*a,*b)` accept whole vectors loaded from numeric typed
pointers. `*out = dot(*a,*b)` combines scalar f32* output with f32<N>* inputs.
Memory creates no arithmetic rounding point and leaves strict ascending-lane
f32 reduction and unfused multiply/add semantics unchanged. Pointer arguments
use PTR; actual by-value vector arguments/results alone require vector-v4.

[BIT-1](bitwise.md) permits shifted or masked integer vectors as dot_wrap and
mac_wrap inputs. Their existing exact source interpretation, accumulator width,
modular reduction and ordered argument evaluation remain unchanged. A shift
validates its scalar count before dot/MAC receives the vector. F32 bit access,
bitcasts and fixed-point dot interpretations are not introduced.

These four reserved special forms consume two whole vectors of the exact same
supported VectorType and return one scalar. They compose with vector lane/DSP
operations, native calls, branches, loops and owned Resource workloads.

| Form | Vectors | Accumulator/result |
| --- | --- | --- |
| `dot_wrap(a,b,D)` | integer S<N> | explicit scalar IntegerType D |
| `mac_wrap(c,a,b)` | integer S<N> | exact scalar IntegerType of c |
| `dot(a,b)` | f32<N> | scalar f32, starts at +0.0 |
| `mac(c,a,b)` | f32<N> | scalar f32, starts at c |

All runtime operands evaluate once from left to right: a then b for dot; c,
a, then b for MAC. D is type syntax and has no runtime evaluation. Calls,
traps, reads and owned argument transfers inside operands retain this ordering.

## Integer accumulator domain

D is `i8`, `u8`, `i16`, `u16`, `int`/`i32` or `u32`, and its width must be
at least the source element width. Destination signedness may differ from S.

| Source element | Allowed accumulator types |
| --- | --- |
| i8 or u8 | i8, u8, i16, u16, int/i32, u32 |
| i16 or u16 | i16, u16, int/i32, u32 |
| int/i32 or u32 | int/i32, u32 |

For source mathematical values Ai and Bi interpreted according to S, define
`Q = sum(Ai * Bi)`. MAC instead defines `Q = C + sum(Ai * Bi)`, where C is
interpreted according to the scalar accumulator's own type D. Compute the
unique residue `bits = Q mod 2^bit_width(D)` in `[0,2^bit_width(D))`, then
interpret those bits according to D. The operation is total: no overflow trap
and no saturation. There is no observable intermediate source-language product
type, and no source-width multiplication before widening.

```astra
i8<4> s = {-1,-1,-1,-1};
i8<4> one_s = splat(1,4);
u8<4> u = {255,255,255,255};
u8<4> one_u = splat(1,4);
i16 a = dot_wrap(s,one_s,i16); // -4
u16 b = dot_wrap(s,one_s,u16); // 65532
u16 c = dot_wrap(u,one_u,u16); // 1020
u16 d = mac_wrap(2 as u16,s,one_s); // 65534
```

Identical source bits therefore need not contribute identical mathematical
values. Signed `i8(-1)*i8(2)` contributes -2; it does not contribute 254 in a
wider accumulator. Conversely `u8(255)*u8(255)` contributes 65025 before
accumulation. Destination signedness changes interpretation of final bits,
never source extension.

MAC checks its accumulator independently of the surrounding result context.
An ordinary unsuffixed `0` has default int type; use `0 as D` or a typed local
for another domain. `mac_wrap(0_D,a,b)` equals `dot_wrap(a,b,D)` for every valid
operand pair. Repeated MACs obey the same modular recurrence.

Integer contribution grouping is unobservable: sequential reduction, a balanced
tree and exact sum followed by modulo agree. Corresponding pair permutations
also preserve the result. This permission is internal to dot_wrap/mac_wrap;
it does not authorize rewriting arbitrary integer source expression trees.

## Ordered binary32 accumulation

F32 supports both `f32<2>` and `f32<4>`. First compute every `p[i]` using the
exact scalar F32 multiply contract: binary32 nearest/ties-even with one rounding.
Set acc to exact +0.0 for dot, or the supplied scalar f32 for MAC. Then, for
ascending lane ordinal i from 0 through N-1, compute `acc = F32_ADD(acc,p[i])`.
Each addition rounds independently to binary32. Return the final acc.

```astra
f32<4> a = {16777216.0,1.0,-16777216.0,1.0};
f32<4> ones = splat(1.0,4);
f32 ordered = dot(a,ones); // exactly 1.0
f32 reordered = dot(shuffle(a,0,2,1,3),ones); // exactly 2.0
```

Here the first `+1` rounds away at 16777216, the third contribution cancels
the large value, and the final `+1` remains. Pair permutation keeps products
paired but changes contribution order, so F32 results may change. F32 reductions
cannot adopt integer-style reassociation.

MAC is **non-fused**. Each product rounds before its addition, including the
first product added to c. For x=`1.00000011920928955078125`,
y=`0.99999988079071044921875`, c=`-1.0`, the rounded product is 1.0 and the
separate addition yields +0.0; exact fused multiplication/addition would give
`-2^-46`. Embedding x and y in lane 0 with zero products in remaining lanes
must retain the separate-operation result. No FMA, contraction or fast math is
permitted. Future fused operations need distinct explicit syntax and semantics.

NaNs, infinities, signed zero and subnormals follow the existing scalar F32-1
contract. No NaN lane is skipped; zero times infinity produces NaN and opposing
infinities can make the accumulated result NaN. NaN payload/sign/signaling state
remain outside the stable language contract. Arithmetic infinity has no overflow
trap. Qualified targets preserve subnormal products and sums.

Dot's positive-zero start is binding: all-negative-zero products reduce to
positive zero under nearest/ties-even. MAC starting from -0.0 with the same
products retains negative zero. Initializing dot from its first product is
therefore invalid. Zero signs can be observed through `1.0/result`.

## Boundaries

Mixed source widths/signs/shapes, bool vectors and scalar vector operands reject.
Integer `dot`/`mac` and F32 `dot_wrap`/`mac_wrap` reject. Destination vectors,
f32/bool/pointers as integer accumulator types, and narrower accumulators reject.
There is no implicit broadcast or new conversion rule.

Every dot/MAC remains one semantic/SSA operation with one scalar result. Scalar
results use ordinary scalar block parameters and loop-carried locals. Input
vectors remain whole values, including those loaded through ordinary
[typed vector memory](vector-memory.md). There is no LanePlace.
A backend may privately widen `i8<16>` lanes into LLVM `<16 x i32>` without
making Astra `i32<16>` legal. NABI vector-v4 and all scalar profiles are unchanged;
a body-only dot does not change the signature's ABI profile. CABI/VAPI vector
boundaries remain unsupported.

Grouped/partial dot, mixed-source dot, saturating dot/MAC, hsum/horizontal
min/max, widening/high-half multiply syntax, f32 FMA/fused dot, i64/u64,
rotates, per-lane shifts and C vector ABI remain deferred.

See [ADR 0041](../decisions/0041-vector-dot-products.md),
[IR contract](../ir/vector-dot.md), and qualification.
