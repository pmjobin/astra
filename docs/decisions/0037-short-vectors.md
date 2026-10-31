# ADR 0037: first-class fixed-lane short vectors and masks

Status: accepted for ASTRA-VEC-1, following accepted ASTRA-F32-1 at
`b2a3a58bbe1a0d5e2f2e880ee2860748bc6f01bf`.

## Decision

1. A short vector is a first-class Astra semantic value type.
2. Its lane semantics come from the existing exact scalar element type.
3. Exact element identity and fixed lane count together determine type identity.
4. Vectors are not arrays, slices, addressable sequences, or array aliases.
5. LLVM vector types do not define Astra vector semantics.
6. A vector remains one value through Astra SSA.
7. The compiler does not split a vector into independent semantic lanes to implement it.
8. Backend and target legalization may physically split or scalarize that value.
9. Numeric vector comparisons produce `bool<N>` masks.
10. `bool<N>` is distinct from scalar `bool` and contains one semantic bool per lane.
11. A mask cannot directly control `if`, `while`, `&&`, or `||`.
12. `all()` and `any()` explicitly reduce masks to scalar bool.
13. No implicit scalar broadcast or splat exists.
14. No implicit element conversion exists.
15. VEC-1 has no indexing, extraction, insertion, or lane Place.
16. A whole-vector local Place is promotable as one value.
17. Vector locals cannot currently become addressable.
18. Vector fields are deferred; this milestone establishes no vector memory layout.
19. Native ABI may carry one direct vector channel per parameter or result.
20. C ABI vectors, including VAPI signatures, remain unsupported.
21. Every f32 lane inherits the complete exact F32-1 contract.
22. Every integer lane inherits INTS-1 wrapping and signedness semantics.
23. Vector f32 operations grant no fast-math permission.
24. Vector multiply followed by add cannot be implicitly contracted; both rounding points remain observable.
25. A concrete VectorType must be usable as an ordinary exact future generic type argument; its semantics do not depend on general const generics.

## Bounded syntax and identity

`vector-element "<" decimal-lane-count ">"` is a dedicated type constructor.
Elements are i8/u8/i16/u16/i32/int/u32/f32/bool. Counts are decimal literals,
not expressions, named constants, or const parameters. VEC-1 supports counts
2, 4, 8, and 16, with numeric payload at most 128 bits. Bool supports all four
counts without a packed storage-width definition. These are qualification bounds,
not permanent language maxima or promises about physical register widths.

`BuiltinTypes.vector_of` interns the exact `(element object, lane count)` pair.
There are only 24 supported shapes, so a bounded identity list is sufficient;
no speculative generic instantiation or type-substitution architecture is needed.
The already canonical int/i32 scalar identity makes `int<4>` and `i32<4>` the
same VectorType. Display is `int<4>`; syntax preserves `i32<004>` when written.
Future `Box<f32<4>>` can contain the same concrete VectorType as a type argument.

## Construction and lowering choices

A direct local brace initializer supplies exactly N expressions, checked against
the exact scalar element type. Evaluation is lane 0 through lane N-1, and the
new local enters scope only afterward. Named braces remain struct initializers.
One-token lookahead distinguishes `identifier =` from a positional expression;
comparison parsing and address-of/short-circuit tokenization retain their roles.

Checked/Core construction owns an ordered list of scalar inputs and one vector
result type. CFG vector construction and reduction specialize its existing
ordered evaluation instruction. This retains the existing definition, availability,
trap-order, and ownership authorities instead of introducing another result graph.
SSA construction consumes N scalar inputs and defines one vector. Arithmetic,
comparison, assignment promotion, branch joins, and loop carries keep that value
whole. Input evaluation is not scalarization of an already constructed vector.

NABI generalizes channels to NativeAbiType, with separate NativeScalarAbiType
and NativeVectorType forms. Its established program-wide profile selection
adds vector-v4 above v0/v1/v2/v3. No-vector signatures retain previous selection
and dump bytes; body-only vectors do not require v4. Signedness remains in both
semantic and ABI types until LLVM selects physical types and predicates.

LLVM construction uses exact constant vectors, or insertion into a fully defined
zero vector. Reductions use backend extraction and scalar AND/OR; these operations
exist only after the SSA/LLVM boundary. Sharing scalar arithmetic dispatch keeps
signed predicates and F32 ordered/unordered predicates authoritative in one place.
No integer overflow flags, vector memory architecture, support library, or runtime
is necessary. Ordinary LLVM f32 operations preserve separate rounding points.

## Qualification and deferred work

Native vector emission is qualified on default x86-64 Linux with the existing
empty CPU/features, PIC/default code model, and no Astra optimization pipeline.
Other native vector targets reject pending explicit qualification. An FMA-enabled
LLVM instruction-selection audit additionally checks and executes the two-rounding
witness. Actual SIMD instruction selection is evidence about this target, not a
language requirement; semantically correct scalarized lowering remains valid.

Lane access, splat/shuffle/select, wider shapes, vector memory and C ABI require
separate designs. A future writable lane may be a whole-vector load/insert/store
operation; a lane is not automatically an authoritative Place. Vector memory
would need an explicit layout/alignment and addressability contract. Integer
vector division/remainder, saturation, widening/narrowing, dot products, MAC/FMA,
and other DSP operations need their own edge-case and rounding semantics.

See [language vectors](../language/vectors.md), [vector IR](../ir/vector-values.md),
[native vectors v4](../abi/native-vectors-v4.md), and
qualification.
