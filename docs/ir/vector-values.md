# Whole-vector values through checked semantics, Core, CFG, and SSA

BIT-1: Vector bitwise and mask operations preserve exact shapes. Integer vector shifts retain one scalar count and one whole vector result; lane semantics reuse the scalar integer authority. No LanePlace, vector storage or semantic count vector is introduced.
See [bitwise/shift IR](bitwise-shifts.md) for verifier, lifetime, evaluation
and backend guard/normalization rules. NABI/CABI/VAPI remain unchanged.

[Dot/MAC](vector-dot.md) consumes two whole vector values and produces one
scalar in one SSA instruction. Integer wrapping modes permit internal modular
reassociation; F32 modes require rounded products and ascending rounded adds.
Backend-private widened vectors, such as LLVM <16 x i32>, never expand source
VectorType legality or introduce lane storage/vector memory.

[DSP operations](vector-dsp.md) preserve this one-vector-value contract:
one saturating, widening, packing or interleave primitive defines one SSA vector
result. Shape changes are explicit and stay within existing VectorType bounds.
Scalar authorities define numerical lanes; backend legalization may split or
scalarize physical operations without changing Astra SSA, ABI or storage rules.

`VectorType` owns the exact immutable scalar element identity and fixed
`lane_count`. `BuiltinTypes.vector_of` canonicalizes their exact pair within
one universe, automatically sharing int/i32 vector identity. Types contain no
syntax, symbols, layouts, ownership contracts, ABI objects, or LLVM backlinks.
Every downstream stage retains the same exact type independently of upstream
lifetime. Signedness survives through SSA and NABI.

VEC-LANE-1 extends this pipeline with [five explicit value primitives](vector-primitives.md).
Constant extraction produces a scalar value, insertion produces a new vector,
and splat/shuffle/select preserve whole-vector authority. Indices and immutable
selector lists are independent compiler-owned metadata, never Places.

## Nodes and ordering

| Stage | Construction | Reduction |
| --- | --- | --- |
| Checked | CheckedVectorConstructExpression | CheckedVectorReductionExpression |
| Core | CoreVectorConstructValue | CoreVectorReductionValue |
| CFG | CfgVectorConstructInstruction / CfgVectorConstructValue | CfgVectorReductionInstruction / CfgVectorReductionValue |
| SSA | SsaVectorConstructInstruction | SsaVectorReductionInstruction |

Construction owns ordered scalar lane operands, the exact vector result type,
and provenance. Reduction owns ALL/ANY, one mask operand, scalar bool result
and provenance. Unary/binary arithmetic and comparisons reuse the existing
operator nodes. No node per vector arithmetic operator is needed.

The checked local is installed in scope only after checking every lane. Core
retains lexical structure and the lane order. CFG captures each lane before
starting the next, preserving earlier traps and reads before later effects.
Its vector instructions specialize `CfgEvaluateInstruction`: one ordered
operation and one `CfgEvaluatedValue`. The embedded construct/reduction value
uses the same verification and availability authority as existing ordered
expression evaluation. Ownership traversals visit the new operands but do not
change the ownership state machine or transfer-commit protocol.

SSA consumes those completed scalar inputs and creates one vector result:

```text
%v : i16<4> = vector-init lane0 lane1 lane2 lane3
%sum : i16<4> = binary + %v %other
%mask : bool<4> = binary < %sum %limit
%condition : bool = vector-all %mask
```

The scalar construction inputs existed before the vector. Neither a vector
addition nor a mask reduction is expanded into per-lane Astra SSA arithmetic.
One vector operation remains one instruction/result. Backend extraction after
SSA does not change this invariant.

## Places, promotion, and block arguments

A vector local has one ordinary `CoreLocalPlace`/`CfgLocalPlace`. Initialization,
load, and store refer to that whole Place. Address taking accepts only existing
native struct locals, and vector fields are rejected. Therefore every source
vector local remains promotable. There is no VectorLanePlace, vector
SsaMemoryPlace, vector GEP, source vector load/store, or layout/alignment contract.

Existing SSA dominance and promotion create one vector block parameter at a
branch join or loop header. Mask block parameters work identically. The existing
edge arguments and physical predecessor handling apply without a vector-specific
CFG or dominance algorithm. One vector block parameter becomes one LLVM vector
phi; backend spills have no bearing on source addressability.

## Verification and lifetime

Independent Core/CFG/SSA verifiers check supported exact element/shape, canonical
pair consistency, lane count/types, operator capability, equal operand types,
comparison `bool<N>` shape, and reduction mask/scalar result identity. Malformed
vector fields and address-taken vector locals reject. Existing SSA definition,
ordinal, availability, and dominance checks apply to every vector operand/result.

Standalone executables compile each model without prior-stage construction code
or LLVM. Weak-reference tests destroy checked/Core/CFG objects in sequence while
retaining exact vector types and scalar F32 constants. NABI survives semantic
and SSA destruction; LLVM survives destruction of every upstream graph/type/source
and still verifies and emits an object. See qualification.
