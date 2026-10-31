# Numerical policies and vector memory

Surge 11 passes its finite N1–N9 contract. See the
current qualification and
working ledger for evidence and scope.

Ordinary f32/f64 operations remain strict at O0/O1/O2. A synchronous native free
function can select independent permissions using existing declaration metadata:

```astra
[FloatingPoint(contract="on", reciprocal="on")]
f64 selected(f64 a, f64 b, f64 c) { return a*b+c/a; }
```

| Key | Permission / checked behavior |
| --- | --- |
| `contract` | Permit contraction of selected arithmetic, including FMA |
| `reassociate` | Permit selected arithmetic to change association |
| `reciprocal` | Permit reciprocal-based division transformations |
| `no_signed_zero` | Permit selected arithmetic to ignore zero signs |
| `no_nan` | Check a conservative finite arithmetic domain, then grant `nnan` |
| `finite` | Check that same domain, then grant `nnan` and `ninf` |
| `strict` | With `"on"`, reject any enabled relaxation on that declaration |

Values are `"on"`/`"off"`. Unknown, duplicate or conflicting options refuse.
Finite/NaN checks require each operand's magnitude to be at most 2^60 for f32 or
2^500 for f64. A divisor must additionally have magnitude at least 2^-60 or
2^-500. Every lane is checked before flagged arithmetic. These bounds deliberately
reject some valid finite computations. They provide proof rather than trusting
a programmer's assertion. Other permissions do not imply these assumptions.

Policies belong to the declared body. A selected caller cannot relax an
unannotated or explicitly strict callee. Methods, foreign declarations, async,
throwing declarations and lexical policy blocks are outside this surface.
Native-unit identities include selected policy bits. Physical call channels are
unchanged. See [ADR 0156](../decisions/0156-checked-floating-point-policies.md).

Permission does not promise a different instruction or a speedup. LLVM may reuse
a strict result for a relaxed calculation. The feature audit uses independent
external inputs to demonstrate actual FMA while checking strict callee results.
The tested environment uses nearest/ties-even rounding, masked SSE exceptions
and gradual subnormals. NaN arithmetic promises classification, not a universal
payload or floating-environment exception-flag contract. Application-specific
relaxed errors require their own measured domains and bounds.

`load_vector(view, offset, lanes, alignment)` and the statement
`store_vector(view, offset, value, alignment)` operate on bounded numeric scalar
views. The complete range and requested alignment are checked before access;
alignment 1 permits unaligned access. The lane count and power-of-two alignment
(1 through 16) are decimal literals. Owning arrays use the ordinary temporary
borrow of the public helpers; a raw primitive does not copy an owner into a view.
Mask/raw-pointer/mismatched-element operations refuse. Overlapping load/store
sequences retain complete value snapshots.

The public `Numerics` helpers provide f32x4, f64x2 and i16x8 memory operations,
scalar reference routes, ordered reductions, selected conversions and NaN-aware
min/max. `dot`/`mac` now support f64<2> with exact f64 accumulators and strict
ascending-lane association by default. See
[ADR 0157](../decisions/0157-bounded-vector-memory-and-wide-reductions.md).

Select source modules explicitly:

| Module under `lib/astra/numerics/` | Contents / dependency choice |
| --- | --- |
| `vectors.astra` | Bounded vector operations and scalar references; no allocator/provider |
| `complex.astra` | Complex64 and Matrix2 values; no allocator/provider |
| `pcm.astra` | Exact scalar/vector PCM saturation; no allocator/provider |
| `filters.astra` | Biquad64 state/reset; no allocator/provider |
| `fir.astra` | Fir64 owns copied coefficients and delay arrays; explicit allocation choice |

The first four modules contain no hosted allocation. Runtime-free qualification
still checks the actual emitted declarations before and after optimization.
`ASTRA_TEST_VECTOR_MEMORY=native|scalar` is the documented test ablation for
vector versus lane memory lowering, with identical checks and semantics. The
receipts record this setting; it is not a CPU-feature or global fast-math switch.

LLVM permissions follow the instruction and rewrite rules in the
[LLVM 22 language reference](https://releases.llvm.org/22.1.0/docs/LangRef.html#fast-math-flags).
The source/IR contracts and finite preconditions above remain Astra authorities.
