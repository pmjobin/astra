# C scalar floating-point profile v2

`CAbiProfile.SCALAR_FP_V2`, printed `scalar-fp-v2`, subsumes scalar-v0 and
scalar-ptr-v1 and adds two exact direct channels. Older profiles are frozen.

| Astra semantic type | C physical channel | Foreign realization | LLVM |
| --- | --- | --- | --- |
| int | CAbiScalarType.I32 | qualified signed int32_t | i32 |
| void* / accepted Resource contract | CAbiScalarType.PTR | void* | ptr |
| f32 | CAbiScalarType.F32 | IEEE binary32 C float | float |
| f64 | CAbiScalarType.F64 | IEEE binary64 C double | double |
| void result | absent | void | void |

Each parameter has one channel. A result has one channel or is absent. Multiple
floats and mixed I32/F32/F64/PTR signatures follow the same physical planning,
validation and C-convention lowering. LLVM's target lowering chooses machine
registers or stack slots. No extension/truncation, integer bitcast transport,
helper, allocation, fast math or FMA is introduced by these boundaries.

Example source:

```astra
extern(C) f32 echo_float(f32 value);
extern(C) f64 echo_double(f64 value);
extern(C) int mixed(int tag, f32 small, f64 precise, void* token);
export(C) f64 astra_echo(f64 value) { return echo_double(value); }
```

Pure foreign IR uses `declare float @echo_float(float)` and
`declare double @echo_double(double)` with corresponding ordinary C calls.
An export has a C-visible float/double signature and uses the established
wrapper to call its separate internal native implementation.

CABI dumps explicitly identify the mapping, for example
`(parameter #0 F64 (semantic f64) (c-type double))`. Completed plans contain
physical enums, copied metadata and provenance, without semantic type objects,
VAPI objects, SSA or NABI backlinks. An export retains a native ordinal only.

Any declared C floating parameter/result selects scalar-fp-v2, including unused
imports and exports. Pointer cleanups and borrowed/owned import contracts keep
their previous meaning under the superset profile. Native floating signatures,
body locals and struct fields alone do not upgrade CABI. Exact semantic width
checking precedes physical mapping and is independently checked at each stage.
C float requires f32; C double requires f64. No implicit conversion is permitted.

| Boundary authority | Type | Minimum profile |
| --- | --- | --- |
| NABI | f32 → native F32 | scalar-fp-v3 |
| NABI | f64 → native F64 | fp64-v6 |
| NABI | concrete struct with floating leaves | aggregate-v7 |
| CABI | f32 → C F32 / float | scalar-fp-v2 |
| CABI | f64 → C F64 / double | scalar-fp-v2 |

The same native aggregate function can call both foreign widths. Neither ABI's
profile is the other's semantic or calling-convention authority.

The currently qualified C environment is default x86-64 Linux with 8-bit bytes,
4-byte binary32 float (radix 2, precision 24, FLT_MIN_EXP -125, FLT_MAX_EXP 128)
and 8-byte binary64 double (precision 53, DBL_MIN_EXP -1021, DBL_MAX_EXP 1024),
including IEEE subnormals and encodings. A separate C floating target gate
rejects unqualified triples before object production, even for declaration-only
use. This is an explicit platform qualification, not a general inference from
LLVM float/double metadata. Future platforms, including SH-4, must qualify their
C ABI representations before extending the gate.

Bit transport without arithmetic preserves ±0, subnormals, normals, infinities
and quiet NaN payloads. C companions use memcpy for standards-safe bit inspection;
C arithmetic and changes to the floating environment are outside that payload
transport guarantee. The existing Astra floating environment obligation holds.

No float*/double*, C structs/aggregate ABI, slices over C floating memory,
varargs, function pointers/callbacks, long double, float16/quad, numeric
conversion campaign, libm layer, process arguments or new main signature is
provided. See [ADR 0063](../decisions/0063-c-floating-point.md).
