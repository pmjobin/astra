# Dot/MAC value operations

`CheckedVectorDotExpression`, `CoreVectorDotValue`,
`CfgVectorDotValue`/`CfgVectorDotInstruction` and `SsaVectorDotInstruction`
retain `VectorDotKind`, exact source/result type, optional scalar accumulator,
two whole vector operands and source provenance. Each stage owns its nodes and
retains the shared LLVM-free authority after its predecessor is destroyed.

| Mode | Accumulator | Result | Reduction contract |
| --- | --- | --- | --- |
| INTEGER_WRAP_DOT | absent | explicit IntegerType D | exact source product sum modulo D |
| INTEGER_WRAP_MAC | scalar D | same D | accumulator plus exact product sum modulo D |
| F32_DOT | absent, exact +0 implicit | scalar f32 | rounded products, ascending rounded additions |
| F32_MAC | scalar f32 | scalar f32 | supplied start, same strict non-fused sequence |

Mode fixes ordering and fusion semantics. There is no independently mutable
order/fast-math field that could contradict a mode. Unknown modes reject.
Semantic, Core, CFG and SSA dumps expose mode, source, accumulator type and
`order modular` or `order ascending-lane`. MAC additionally carries c:

```text
(dot-wrap (source i8<16>) (accumulator int) (order modular) a b)
(mac-wrap (source i8<16>) (accumulator u16) (order modular) (acc c) a b)
(dot-f32 (source f32<4>) (accumulator f32) (order ascending-lane) a b)
(mac-f32 (source f32<4>) (accumulator f32) (order ascending-lane) (acc c) a b)
```

## Verification and ordering

`VectorDotKind.type_error` is the shared stage-independent type verifier. It
requires a supported source VectorType and both operands with exactly that
identity. Integer modes require IntegerType elements and a scalar IntegerType
result at least as wide as the source. F32 modes require f32 elements and the
exact same scalar f32 result identity. MAC requires an accumulator of the exact
result type; dot requires its absence. Stage verifiers also check provenance,
operand definitions/availability, scalar result and normal graph invariants.
Synthetic standalone tests reject invalid modes, unsupported shapes, mixed
operand types, wrong source metadata, narrow/vector/non-domain results, wrong
accumulator type/arity and missing definitions.

CFG captures c first when present, then a, then b, before the single pure
`CfgVectorDotInstruction`. Each capture precedes evaluation of the next operand,
including reads, traps and nested owned transfers. OWNBOUND pending-transfer
checks recognize dot expressions; ownership flow visits all operands in source
order. Captures of incoming parameters promote away, leaving exactly one
`SsaVectorDotInstruction` and one scalar result. No reduction loop, lane
extraction, lane Place or vector memory is introduced upstream.

Scalar result merges and loop-carried accumulators use existing block parameters
and dominance/promotion. NABI vector-v4 handles vector parameters with ordinary
integer/F32 scalar results. Body-only vectors leave scalar signature profiles
unchanged; CABI/VAPI and all ownership/cleanup contracts remain unchanged.

## Backend realization

Let D have W bits. Convert source lanes to W-bit LLVM integer lanes: sext for
signed source elements, zext for unsigned, no conversion at equal widths.
Destination signedness does not select extension. Multiply at W bits, extract
contributions and add modulo W, starting at zero or the supplied scalar
accumulator. Ordinary mul/add carry neither nsw nor nuw. This is equivalent to
exact mathematical product/sum followed by final modulo; even products larger
than any source-language type are well-defined. Integer tree reassociation and
exact target selection are permitted within this operation. Hidden intermediate
saturation must never change the result.

The LLVM type is constructed directly from its scalar element and source lane
count. `<16 x i32>` may be used for `i8<16>` to i32; no `types.vector_of(i32,16)`
or illegal Astra VectorType is created. Backend-private widths and physical
scalarization are legalization choices without upstream semantic consequences.

F32 uses one ordinary vector fmul, followed by lane 0 extract/fadd, lane 1
extract/fadd, and so on. Dot starts at LLVM float +0.0; MAC starts at the supplied
scalar. Each product and addition has its own binary32 rounding point. No
floating reduction intrinsic is emitted. No reassoc, nnan, ninf, nsz, arcp,
contract, afn or fast flag, llvm.fma, llvm.fmuladd or target FMA is allowed to
change this strict sequence. FMA-capable and optimized qualification checks
results and machine instructions. DPPS-like hardware selection is not an
acceptance requirement; scalar/legalized code is valid when exact.

See [language](../language/vector-dot.md),
[ADR 0041](../decisions/0041-vector-dot-products.md), and
qualification.
