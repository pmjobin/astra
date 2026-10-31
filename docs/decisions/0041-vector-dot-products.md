# 0041: Exact whole-vector dot products and multiply-accumulate

Status: accepted for ASTRA-VEC-DOT-1. Builds on accepted INTS-1, ICONV-1,
F32-1, VEC-1, VEC-LANE-1 and VEC-DSP-1.

## Decision

1. Dot products are explicit semantic primitives, with reserved special-form
   syntax. They are never represented as generic function calls.
2. Integer `dot_wrap(a,b,D)` selects an explicit wrapping accumulator domain D.
3. Integer `mac_wrap(c,a,b)` uses the same modular domain, selected by c's type.
4. Each integer contribution is the product of the source mathematical integer
   values. Source signedness determines those values independently of D.
5. The exact mathematical sum is reduced modulo `2^bit_width(D)`. D must be a
   scalar IntegerType at least as wide as the source element.
6. Destination signedness interprets the final result bits; cross-signed
   accumulators are valid. MAC also interprets its input c according to D.
7. Integer contribution grouping and pair permutation are unobservable because
   modular addition is associative and commutative. This grants no permission
   to reassociate arbitrary source integer expression trees.
8. F32 dot reduction grouping is observable and binding.
9. F32 dot/MAC accumulate lanes in ascending ordinal order, 0 through N-1.
10. Every product rounds independently to binary32 nearest/ties-even, using
    the existing F32 multiplication contract before accumulation.
11. Every accumulator addition rounds independently under that same F32-1
    contract. No hidden extended-precision accumulator exists.
12. F32 `dot(a,b)` starts from exact positive zero, bits `0x00000000`.
13. F32 `mac(c,a,b)` starts from the supplied scalar f32 accumulator.
14. F32 MAC is non-fused multiply-accumulate; the name does not imply FMA.
15. F32 dot/MAC cannot reassociate or reorder contributions if results can differ.
16. Products and additions cannot contract into FMA; no fast-math flags apply.
17. Integer dot/MAC may physically reassociate products/additions provided their
    exact modulo result is preserved. Hidden intermediate saturation is invalid.
18. Dot/MAC consume whole Astra vector semantic values and return one scalar.
19. Each source dot/MAC remains one Astra SSA instruction and one scalar result.
20. Backend expansion may extract and scalarize lanes physically. Core, CFG and
    SSA do not decompose the reduction or synthesize a reduction loop.
21. Backend-private vector widths may exceed source VectorType shape limits.
22. Such widened backend vectors do not create new Astra semantic vector types.
    In particular `i8<16>` to i32 may lower via LLVM `<16 x i32>`, while
    Astra `i32<16>` remains illegal.
23. No LanePlace exists; lane values do not acquire storage identity.
24. No vector memory, addressability, load/store or alignment model is added.
25. NABI vector-v4 and its existing scalar channels remain sufficient. Profile
    selection depends on signatures, never dot/MAC inside a function body.
26. C vector ABI remains unsupported; CABI and VAPI do not change.
27. Any future explicit fused F32 operation requires distinct syntax and
    semantics, such as an independently specified `fma` primitive.
28. Future saturating dot/MAC must be distinct from integer wrapping forms;
    product, per-step and final-sum saturation are different possible contracts.

Runtime operands evaluate exactly once, left to right: a then b for dot; c,
a, then b for MAC. The dot_wrap destination is type syntax with no runtime
evaluation. Both vectors must have the exact same supported VectorType.
Integer forms reject bool/f32 vectors; F32 forms reject integers/bool and
require scalar f32 results/accumulators. Scalar operands and mixed source
widths/signs/shapes reject.

## Representation and alternatives

A dedicated `VectorDotKind` has four modes: INTEGER_WRAP_DOT,
INTEGER_WRAP_MAC, F32_DOT and F32_MAC. Each stage has a dedicated node with
source/result type, optional accumulator, a, b and provenance. Mode fixes the
accumulator arity and reduction contract; an independently mutable order flag
would allow contradictory states and is unnecessary. Shared LLVM-free type
validation checks every mode and rejects malformed combinations.

The generic backend converts integer source lanes to D width, preserving
source signedness, then multiplies and adds modulo D without nsw/nuw. Physical
scalar extraction/add is a conservative initial realization; a modular tree,
vector integer reduction or exact target intrinsic remains permitted.

F32 lowering uses ordinary vector fmul followed by explicit lane extraction
and scalar fadd in ascending order. This makes each rounding point and the
initial accumulator directly reviewable. An unordered reduction, a tempting
hardware dot instruction or a contracted multiply-add cannot replace that
sequence merely because it has a similar name. Backend optimization and
FMA-capable targets must preserve the same results.

No accepted numeric, ownership, ABI or VectorType architecture changes.
Grouped/partial dot, mixed-sign or mixed-width dot, dot_sat/mac_sat, hsum and
horizontal min/max, widening/high-half multiply syntax, FMA/fused dot, i64/u64,
bitwise/shifts, vector memory and C vector ABI remain outside this milestone.

See [language](../language/vector-dot.md), [IR](../ir/vector-dot.md), and
qualification.
