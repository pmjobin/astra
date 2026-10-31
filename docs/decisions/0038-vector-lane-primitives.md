# 0038: Vector lane value primitives

Status: accepted for ASTRA-VEC-LANE-1, following accepted
[0037](0037-short-vectors.md) at `865f526b58277a0efd85403f06ddd8076d14a295`.

## Decision

1. Lane extraction observes a vector value and produces its exact scalar element
   value. It is never a load from projected lane storage.
2. Lane insertion transforms a vector value into a new vector value, preserving
   every untouched lane exactly. Assignment of the result is a separate operation.
3. No `VectorLanePlace` exists in VEC-LANE-1. Whole-vector locals remain promotable.
4. Constant indices are compiler-owned compile-time syntactic ordinals with source
   provenance, not runtime integers, constant expressions, or generic arguments.
5. Dynamic indexing is unsupported. Indices must be direct unsuffixed non-negative
   decimal integer literals, including optional leading zeroes, in range `[0,N)`.
6. `v[index]` can read any VectorType expression but cannot be an assignment
   target or address operand. Writable indexing reports guidance to use `insert()`.
7. `insert(v,index,x)` returns the same exact VectorType as `v`; `x` must have the
   exact element type. Evaluate `v`, then `x`, then construct the result.
8. `splat(value,N)` explicitly broadcasts one scalar value, evaluated exactly
   once. N is one unsuffixed positive decimal literal and must form a VEC-1 shape.
9. No scalar broadcast or element conversion is implicit. Expected VectorType
   supplies scalar element context to splat's integer literals. Without stronger
   context, `splat(1,4)` is `int<4>`. F32 splats require f32 syntax/values.
10. `shuffle` is an explicit one-source vector permutation, evaluating its source
    once and performing no arithmetic, memory operation, or control flow itself.
11. Shuffle preserves the source's exact type and lane count. It requires N selectors.
12. Selectors can duplicate lanes and omit source lanes.
13. Every shuffle selector is a compile-time decimal lane index in `[0,N)`.
    No output lane has undefined or poison semantics.
14. `select(mask,a,b)` chooses `a[i]` when `mask[i]` is true and `b[i]` otherwise.
    The mask is `bool<N>`, data operands have identical exact `T<N>`, and the
    result has that same exact type. Scalar select and scalar masks are unsupported.
15. Select is one vector value primitive, not control flow. It introduces no Astra
    CFG branch or join; an operand may contain ordinary source control flow.
16. Select evaluates all operands in order: mask, true vector, false vector,
    then selection. It is eager, including with all-true and all-false masks.
17. F32 selection copies the selected binary32 value without arithmetic or an
    additional rounding point; signed zero and subnormals survive exactly.
    A selected NaN remains NaN; its payload remains non-observable under F32-1.
18. Mask data vectors are permitted: `select(bool<N>,bool<N>,bool<N>)` yields
    `bool<N>` and composes with `all()`/`any()`.
19. None of these body primitives changes vector physical ABI or source memory.
20. NABI vector-v4 remains sufficient. Scalar signatures with lane operations
    retain their prior program profile when no vector boundary exists. CABI and
    VAPI vector support remain unchanged and unsupported.
21. LLVM `extractelement`, `insertelement`, `shufflevector`, and vector `select`
    are backend realizations of these semantics, not their definitions. Splat
    seeds a defined zero vector then shuffles lane zero to every destination.
22. Target legalization may still scalarize every operation, use moves or spills,
    or use SIMD. Astra keeps one whole vector per semantic/SSA value. Default
    x86-64 Linux remains the only qualified native vector configuration.
23. Future writable indexing should initially be expressible as whole-vector
    load/insert/store. Writable syntax must not retroactively make these values Places.
24. Future vector memory/addressability must explicitly decide whether true lane
    storage projection is necessary. Read-only swizzles could become shuffle sugar;
    writable swizzles need separate simultaneous-assignment and duplicate-lane rules.

## Implementation choice

Five distinct checked, Core, CFG and SSA forms keep operand roles and types
directly verifier-visible. A compact tagged primitive could represent the same
contract, but would require kind/arity dispatch and irrelevant optional fields.
The existing small construct/reduction classes already establish the distinct-node
pattern. No common Place, scalarization pass, runtime dependency, or ABI extension
is needed. CFG uses the existing capture authority to complete each runtime operand
before beginning the next, including traps, reads, calls, and ownership transfers.

`VectorLaneIndex` is immutable exact ordinal/provenance metadata.
`VectorLaneSelectors` owns a private immutable ordered snapshot. Every node
constructor copies index/list metadata; scalar/vector types and source files
retain their existing immutable ownership. No stage retains an upstream node.
Independent verifiers validate source/result types, shapes, counts, range,
replacement type, select masks, operand availability and SSA dominance.

## Boundaries

No fast-math, FMA contraction, integer division/remainder, bitwise operations or
shifts are added. Dynamic/writable indexing, LanePlace, swizzles, two-source or
shape-changing permutations, vector memory/pointers/fields, widening/narrowing,
saturation, packing/interleave, dot products, MAC/FMA, C vector ABI, VAPI vectors,
and general const generics remain future work. No architectural review trigger
requires a redesign of accepted VEC-1 authorities.

See the [language rules](../language/vector-lanes.md),
[IR contract](../ir/vector-primitives.md), and
qualification.
