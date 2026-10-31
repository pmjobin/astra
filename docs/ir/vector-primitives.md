# Vector primitives through the value pipeline

[VEC-DSP-1](vector-dsp.md) adds a bounded DSP kind and stage-owned value
nodes alongside these lane primitives. Interleave is fixed two-source selection
for all element categories; it does not generalize shuffle syntax. Saturation,
widening and packing use exact scalar integer/conversion authorities. Every DSP
result composes with extract/insert/shuffle/select as one vector value.

Every primitive is explicit in checked semantics, Core, CFG and SSA. Source
semantics are defined in [vector lanes](../language/vector-lanes.md) and
[ADR 0038](../decisions/0038-vector-lane-primitives.md). Existing VectorType,
whole-vector Places, promotion, scalar authorities and NABI are unchanged.

| Operation | Checked | Core | CFG instruction / embedded value | SSA |
| --- | --- | --- | --- | --- |
| Splat | CheckedVectorSplatExpression | CoreVectorSplatValue | CfgVectorSplatInstruction / CfgVectorSplatValue | SsaVectorSplatInstruction |
| Extract | CheckedVectorExtractExpression | CoreVectorExtractValue | CfgVectorExtractInstruction / CfgVectorExtractValue | SsaVectorExtractInstruction |
| Insert | CheckedVectorInsertExpression | CoreVectorInsertValue | CfgVectorInsertInstruction / CfgVectorInsertValue | SsaVectorInsertInstruction |
| Shuffle | CheckedVectorShuffleExpression | CoreVectorShuffleValue | CfgVectorShuffleInstruction / CfgVectorShuffleValue | SsaVectorShuffleInstruction |
| Select | CheckedVectorSelectExpression | CoreVectorSelectValue | CfgVectorSelectInstruction / CfgVectorSelectValue | SsaVectorSelectInstruction |

Each node retains its exact result type and SourceSpan. Splat owns one scalar
operand, lane count and count span. Extract owns one vector operand and exact
VectorLaneIndex. Insert owns vector, index and scalar replacement. Shuffle owns
one vector and ordered VectorLaneSelectors. Select owns mask, true value and
false value in source order. Indices are not CheckedExpressions or IR values.

## Metadata ownership and verification

`VectorLaneIndex` has read-only ordinal/span properties and no storage or runtime
identity. `VectorLaneSelectors` owns a private array with immutable access through
`length` and `at()`. It exposes no mutable array. Constructors copy the index or
selector snapshot at every stage. Source files and types retain their established
immutable ownership. Old semantic/Core/CFG metadata objects can be reclaimed
immediately after lowering; later stages retain complete independent ordinals,
selector order, provenance and operand graphs.

Standalone Core, CFG and SSA verifiers check:

- splat's exact scalar element, supported shape and matching count/result;
- extract's vector source, in-range index and exact scalar element result;
- insert's exact source/result VectorType, replacement type and index range;
- shuffle's exact source/result identity, N selectors and every ordinal in range;
- select's exact equal data/result VectorTypes and bool mask with matching count.

Each operand also passes the stage's normal type/ownership/availability checks.
SSA checks definition ownership and dominance. Forged type identities and invalid
shapes remain rejected by existing independent vector type verification.

## Evaluation and SSA

Core retains the expression tree and operand roles. CFG captures each operand
using the existing ordered-evaluation authority before evaluating the next.
This preserves prior reads, traps and ownership transfers. All five instructions
specialize CfgEvaluateInstruction and produce exactly one CfgEvaluatedValue.
Select has no branch/join lowering and no short-circuit temporary. Ordinary
control flow contained in an operand remains ordinary CFG.

SSA emits one instruction per primitive after operands complete. Extraction
produces a scalar definition; its vector input remains one whole vector.

```text
%0 : i16<4> = vector-splat (lanes 4) (value %x)
%1 : i16 = vector-extract (lane 2) (vector %0)
%2 : i16<4> = vector-insert (lane 1) (vector %0) (value %1)
%3 : i16<4> = vector-shuffle (lanes 3 2 1 0) (vector %2)
%4 : i16<4> = vector-select (mask %m) (true %3) (false %0)
```

No lane Place, lane SSA register bank, source vector memory, new dominance rule,
or new ABI channel is introduced. `v=insert(v,2,x)` is ordinary whole-vector
Place promotion. Results enter branch/loop block arguments as one vector value.
Scalar signatures using these body operations retain their prior NABI profile;
vector boundaries still use vector-v4.

## LLVM realization

Splat inserts its single scalar operand at index zero of a defined zero vector,
then shuffles index zero to every lane, using that seed as both sources. There
are no undefined selected or intermediate lanes. Extraction and insertion use
LLVM extractelement/insertelement with constant i32 indices and exact element
types. Shuffle uses shufflevector with the same vector as both sources and only
valid source ordinals. Select uses vector `select <N x i1>` for numeric and bool
data, including `<N x float>` and `<N x i1>`.

These are physical mechanisms. LLVM constant folding may print exact constants
instead of instructions. No arithmetic or fast-math flags implement selection
or permutation, and no new FMA permission exists. LLVM may ultimately scalarize
execution or spill registers without changing Astra's value semantics. Qualification
remains default x86-64 Linux. See validation.
