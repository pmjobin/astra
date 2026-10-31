# Exact floating scalar values and conversions

`FloatingType` carries the closed BinaryFloatFormat identity. Canonical F32Type
and F64Type remain distinct immutable semantic types; Core/CFG/SSA may retain
these type authorities without retaining checked symbols or declarations.
BinaryFloatValue owns format and exact uint64 bits (upper bits zero for binary32).
The legacy AstraF32Value adapter exposes uint32 bits for existing compiler clients;
all decimal/conversion/classification rules reside in the shared foundation.

Literal nodes are CheckedFloatExpression, CoreFloatValue, CfgFloatValue and
SsaFloatConstant. Each owns exact value/type/provenance. Source text is not
reparsed, and checked destruction cannot invalidate literal or conversion meaning.
F32 dumps preserve `(f32 0x80000000 : f32)`; f64 uses 16 hexadecimal digits,
for example `(f64 0x8000000000000000 : f64)`.

Ordinary prefix/binary scalar nodes carry exact operand/result types. Verifiers
reject cross-format operations and incorrect literal formats. Comparisons retain
exact source types and bool results. Arithmetic is per-format nearest/ties-even
with a separate rounding point per operation; unary minus flips sign. NaN
payload/sign are unspecified source data, while IEEE comparison results are fixed.

`ConversionExpressionSyntax` is the shared `expr as type` syntax. Integer nodes
remain ICONV's modulo conversion. Floating conversions have dedicated checked,
Core, CFG and SSA nodes with source type, destination type, operand, provenance
and FloatConversionKind:

```text
(float-convert (from f32) (to f64) (mode widen-exact) ...)
(float-convert (from f64) (to f32) (mode nearest-ties-even) ...)
```

FLOAT_WIDEN accepts only F32Type -> F64Type; FLOAT_NARROW only the reverse.
Malformed direction, integer/vector/identity conversions and incorrect literal
formats reject. CFG records one explicit evaluation; operand traversal, owned
argument capture and transfer ordering use existing scalar scheduling. SSA has
one scalar conversion instruction, one operand and one scalar result. F64 branch
joins and loop carries use ordinary block parameters/phis.

F64 pointers, fields, arrays and slices reuse existing Places and lifetime
contracts. Plain load/store has no extra arithmetic rounding. Native by-value
F64 selects fp64-v6, while f64 pointers/slices remain PTR/SLICE(PTR,I32).
Completed native physical models own no semantic types. LLVM lowering uses exact
integer-bitcast constants, double, flag-free arithmetic, ordered predicates/UNE,
fpext and fptrunc, requiring no semantic re-resolution after NABI planning.

There is no floating arithmetic constant evaluator upstream today. Any future
one must obey the shared exact authority rather than evaluate host float/double.
The independent test reference uses rational arithmetic for both formats and
compares exact non-NaN bits or NaN class, without tolerances.
