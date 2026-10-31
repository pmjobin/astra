# ADR 0063: exact C floating-point boundaries

Status: accepted for ASTRA-CABI-FP-1.

## Context

The accepted STRUCT-ABI baseline `cb3656d12056a6c8bb9702c2c17e6e7c587474f1`
has exact native f32/f64 and native aggregate-v7, but its CABI admits only I32
and PTR. CAD reference `a1fadc5c052e82ae464268787f617252998c24be` adds C double
and process arguments together. These are independent features. Only its
floating-boundary concepts are relevant here.

The initial binary64-only request became ASTRA-CABI-FP-1 by explicit scope
expansion: qualify both C float and C double through the same existing scalar
architecture. CABI v2 is not frozen in the accepted baseline, so its profile is
named `scalar-fp-v2`, replacing the candidate's proposed `scalar-fp64-v2`.
ADR 0063 retains its number; this decision and `c-fp-v2.md` use names matching
both widths instead of the initial binary64-only document names.

## Decision

Astra f32 is one exact binary32 semantic type; Astra f64 is one exact binary64
semantic type. C float and C double are their respective foreign realizations.
CABI has distinct F32 and F64 physical channels, realized as LLVM float and
double with the C calling convention. This is representation transport, with
no numeric conversion, integer carrier, allocation or runtime helper.

VAPI normalizes the exact scalar spellings `float` to `f32` and `double` to
`f64`. Original declaration/type spans retain provenance. The ordinary
CFunctionSymbol carries the semantic type plus ForeignAbi.C; that pair is
sufficient and unambiguous C-float/C-double mapping metadata. No redundant
upstream physical enum, CFloatType, CDoubleType or VAPI-specific IR is needed.
Ordinary Astra source has neither alias. Pointer spellings do not normalize
into new capabilities.

The independent CABI scalar-fp-v2 profile includes I32 and PTR with their
existing pointer/cleanup contracts and adds F32/F64. Any foreign import or
export signature containing either width selects the program profile, including
unused declarations, consistent with the previous pointer-profile policy.
Native or body-local floating values do not select CABI v2. Frozen scalar-v0
and scalar-ptr-v1 still reject either floating channel.

Native f32 remains F32/scalar-fp-v3, native f64 remains F64/fp64-v6, and native
struct value boundaries remain aggregate-v7. CABI planning validates native
export correspondence but does not use NABI profiles to define a C signature.
The existing ccc export wrapper calls its exact native fastcc implementation.
Core/CFG/SSA retain ordinary semantic f32/f64 values and foreign-call identity.
All argument evaluation remains left to right, and foreign calls remain
conservatively effectful.

## Target qualification

Only the default x86-64 Linux C implementation environment is currently
qualified. It must provide IEEE binary32 C float and IEEE binary64 C double,
including signed zeros, subnormals, infinities and the corresponding bit
encodings. A dedicated foreign target gate runs before target configuration,
even for unused foreign floating declarations. Other target triples reject.
LLVM target metadata alone does not establish every C implementation's floating
representation; the explicit target assumption and C companion evidence are
retained until a richer target C-representation descriptor exists.

Host C static assertions check CHAR_BIT, storage sizes, radix, significand
precision, minimum/maximum exponents and subnormal availability. Runtime byte
oracles qualify exact transport in both directions and mixed chained calls.
These are evidence, not Astra semantic authority. Foreign arithmetic is not
promised to preserve NaN payloads. Foreign code must restore the existing
nearest/even, masked-exception, non-FTZ/non-DAZ environment before Astra resumes.
LLVM target lowering controls registers and stack placement; x86 machine
observations do not define the CABI model or future SH-4 lowering.

## Alternatives and consequences

Qualifying f64 alone would leave the same scalar architecture to be revisited
for f32. A generic FP channel would erase width and weaken validation. A new
semantic foreign type would duplicate existing exact types and burden all IR
stages. Reusing native profiles would incorrectly make NABI C-convention
authority. None is necessary with the current direct-channel export model.

The milestone adds no implicit f32/f64 or integer/floating conversions, typed
floating C pointers, C aggregates, varargs, callbacks, long double, float16,
quad precision, libm wrappers, process arguments or entry-signature changes.
Existing explicit f32/f64 casts remain unchanged; integer/floating conversion
and future bindings are separate work. No production dependency is added.

See [C floating profile](../abi/c-fp-v2.md) and
qualification report.
