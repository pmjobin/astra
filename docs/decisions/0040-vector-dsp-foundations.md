# ADR 0040: Vector DSP foundations

Status: accepted for ASTRA-VEC-DSP-1. Builds on accepted exact integers,
binary32, VEC-1, VEC-LANE-1 and ICONV-1 without changing their contracts.

## Decision

1. DSP primitives are exact Astra semantic operations. SSE/AVX, NEON, SH-4
   instructions and LLVM intrinsics do not define them.
2. Existing scalar IntegerType semantics remain the numerical authority.
3. ICONV-1 remains the authority for wrapping integer conversion.
4. Saturating conversion explicitly clamps the source mathematical value to
   the destination representable interval, then encodes that integer exactly.
5. Saturating arithmetic is distinct from wrapping arithmetic and never traps.
6. Existing `+`, `-` and `as` semantics are unchanged.
7. `sat_add` and `sat_sub` are explicit, reserved special forms. Operands and
   result have the exact same integer scalar or integer VectorType. Literal
   context follows ordinary integer binary operations; no implicit broadcast.
8. Widening selects one half of an integer vector and converts selected lanes.
9. `widen_low` selects ordinal lanes `0 .. N/2-1`.
10. `widen_high` selects ordinal lanes `N/2 .. N-1`.
11. Both use ICONV-1 conversion lane-wise. Source mathematical interpretation
    controls extension, including signed source to unsigned destination.
12. Packing consumes two vectors of the exact same integer type `S<N>` and
    produces `D<2N>`; D is strictly narrower, with any signedness combination.
13. `pack_wrap` uses ICONV-1 wrapping conversion on each lane.
14. `pack_sat` uses the reusable saturating-conversion authority on each lane.
15. Pack output is the first source followed by the second. These are lane
    ordinals, independent of byte order, memory layout or register presentation.
16. Interleave is a bounded two-source permutation of equal, even-sized vectors.
17. It does not introduce general two-source shuffle syntax.
18. Every current vector element category is permitted: integer, bool and f32.
    Interleave performs no arithmetic or rounding; it copies selected lanes.
19. Every vector DSP primitive remains one Astra semantic operation and one
    SSA vector operation/result, even when its physical realization expands.
20. No primitive creates lane storage identity or a LanePlace.
21. No primitive requires source vector memory, addressability or alignment.
22. NABI vector-v4 already transports every involved vector type; body-only
    vector operations do not upgrade an otherwise scalar signature profile.
23. C ABI vectors and VAPI vectors remain unsupported; their models do not change.
24. LLVM saturating intrinsics, compare/select clamps, extension, truncation and
    shuffles are backend realizations only. Exact expansions are permitted.
25. Machine instruction matching is optimization/qualification evidence, never
    semantic authority or a condition for source legality. Default x86-64 Linux
    remains the qualified vector execution configuration.
26. Future dot/MAC must explicitly define product and accumulator widths,
    signedness, overflow and reduction/rounding order; these are not inferred
    from widening, packing or target instructions.

## Representation and alternatives

A bounded `DspPrimitiveKind` represents precisely eight identities. Checked,
Core, CFG and SSA each own their nodes, operands, exact types and provenance.
The shared type validator verifies arity, categories, identity, destination
element and shape constraints; unknown enum values reject.

Separate classes per operation would encode some arity distinctions in class
structure but repeat the same operand/type transport across four stages. The
bounded node keeps that transport uniform while making every distinction
verifier-visible. It is not an opaque call or an extensible overload framework.
A temporary generic builtin architecture would solve a larger, unneeded problem.

`AstraIntegerValue.saturating_add`, `.saturating_sub` and
`.saturating_convert_to` share one clamp-before-encoding rule. For the current
at-most-32-bit family, mathematical values, sums and differences fit int64.
No host signed overflow, signed narrowing or target behavior determines results.
The vector oracle delegates numerical work to these helpers and `.convert_to`.

LLVM saturation uses source-signedness-specific saturating intrinsics. Widening
shuffles the selected half then uses source-signedness `sext` or `zext`. Wrapping
pack truncates both sources and concatenates. Saturating pack compares source
values to representable destination bounds, selects clamps, then truncates and
concatenates. Bounds are derived from IntegerType, with no destination-specific
opcode semantics. Interleave is a pure two-source shuffle with every lane defined.

All runtime operands evaluate once, left to right, before the pure primitive.
CFG captures values before subsequent calls or ownership transfers; no saturation
branches enter Astra CFG. Whole-vector locals promote and cross branches/loops
through ordinary vector block arguments. Stage destruction leaves successors
complete and every stage before the backend remains LLVM-free.

## Shape and scope boundaries

Widen requires N >= 4 and a strictly wider destination scalar IntegerType;
`D<N/2>` must already exist in VEC-1. Pack requires a strictly narrower scalar
IntegerType and a supported `D<2N>`. Nonadjacent widths and cross-sign conversion
are legal when shapes exist. Neither operation enlarges the VectorType family.

The widening/pack-wrap roundtrip recovers original bits for every compatible
shape, including a signed source widened into an unsigned destination. In that
cross-sign case the intermediate mathematical value can differ; ICONV's modular
embedding and subsequent truncation still restore the original value exactly.

No public scalar saturating cast is added. F32/bool saturation, dot, MAC, FMA,
horizontal sum, widening/high-half multiply, bitwise operators, shifts, rotates,
dynamic indexing, writable lanes, general two-source shuffle, vector memory,
vector fields, pointers, gather/scatter, C vector ABI and general const generics
remain outside this milestone.
