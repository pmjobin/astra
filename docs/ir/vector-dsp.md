# DSP value operations

[Dot/MAC](vector-dot.md) composes with saturation, widening, packing and
interleave through their ordinary whole-vector results. Its dedicated
`VectorDotKind` and stage nodes distinguish modular integer reduction from
strict ordered non-fused F32 accumulation. Dot/MAC returns one scalar and does
not add source widening-multiply or horizontal-reduction syntax.

`CheckedDspExpression`, `CoreDspValue`, `CfgDspValue`/`CfgDspInstruction` and
`SsaDspInstruction` retain a bounded `DspPrimitiveKind`, exact source/result
types, optional destination IntegerType, first and optional second operand, and
source provenance. Each stage owns its representation without an upstream node
backlink. Kinds are SAT_ADD, SAT_SUB, WIDEN_LOW, WIDEN_HIGH, PACK_WRAP, PACK_SAT,
INTERLEAVE_LOW and INTERLEAVE_HIGH; unknown kinds reject.

```text
(%1 : u16<8> = vector-widen-low (from i8<16>) (to u16<8>) %0 : i8<16>)
(%2 : i16<8> = sat-add (from i16<8>) (to i16<8>) %0 : i16<8> %1 : i16<8>)
(%2 : u8<16> = vector-pack-sat (from i16<8>) (to u8<16>) %0 : i16<8> %1 : i16<8>)
```

These examples each define one result with one DSP instruction. Vector lanes
are never exploded into separate Astra SSA values. They remain ordinary
promotable whole-value locals and vector block arguments through branches/loops.
Extraction, insertion, shuffle and select compose around DSP results unchanged.

`DspPrimitiveKind.type_error` is shared by checking and Core/CFG/SSA verification.
It verifies exact operand identity and arity; integer scalar/vector saturation
and identical result type; supported integer widening from N>=4 lanes to N/2
lanes with strictly wider destination element; supported integer packing from
two equal S<N> inputs to D<2N> with strictly narrower element; and equal even
VectorTypes for interleave. Each verifier also verifies operand availability and
that the declared source type equals the first operand type. Destination element
metadata must equal the result's element identity. Saturation/interleave cannot
carry conversion metadata. Stage verifiers retain their ordinary provenance,
use/definition, ownership and result checks.

CFG materializes operands left to right before its pure `CfgDspInstruction`,
which uses the existing CfgEvaluateInstruction mechanism and one evaluated
result. Operand captures may precede it; captures of incoming parameters do not
become extra SSA computations. Traps, reads and nested owned argument transfers
stay before later effects. Saturation itself introduces no Astra CFG branch.
No primitive adds Place subclasses, lane identity, vector loads/stores,
addressability, runtime descriptors or ABI channels.

Scalar `AstraIntegerValue` is the numerical authority. Saturating add/sub and
conversion clamp mathematical integers before encoding; ICONV's `convert_to`
defines wrapping widening and packing. Vector oracle methods apply these scalar
helpers lane-wise. F32 interleave preserves existing value objects; it does no
floating arithmetic. No host overflow or narrowing defines source results.

The backend realizes scalar/vector saturation with `llvm.[su]{add,sub}.sat`.
Widen shuffles a half-vector then extends according to **source signedness**.
Pack-wrap truncates each input and concatenates; pack-sat compares/selects
IntegerType-derived bounds in the source width, truncates, then concatenates.
Interleave uses exact masks `(start+k, N+start+k)` for each pair, with start 0 or
N/2. All output selectors refer to defined input lanes; no undef/poison shortcut,
overflow flag or fast-math flag is introduced. Backend expansion/legalization
may use one or several instructions or scalar code without changing Astra SSA.

NABI vector-v4 and existing scalar profiles remain sufficient. CABI and VAPI
remain unchanged. Standalone and lifetime tests enforce the LLVM firewall and
destroy each upstream stage before verifying its successor, including SSA
destruction before LLVM verification/object emission. See
[ADR 0040](../decisions/0040-vector-dsp-foundations.md) and the
qualification report.
