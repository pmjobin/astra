# 0054: Exact binary64 scalar semantics

Status: accepted for ASTRA-F64-1, based on accepted OBJ-RET-1
`3cf216df0588e62c83da0ff5f1111fad68456387`.

This deliberately precedes PROP-1. PROP-1's previously proposed 0054 is superseded;
its next ADR is 0055. No property work is included here.

## Language decisions

1. `f64` means exactly IEEE-754 binary64: 64 bits, one sign, 11 exponent bits,
   52 stored fraction bits, 53-bit precision and exponent bias 1023.
2. Format and width are target-independent language authority. Neither C double,
   host double, target preference nor LLVM chooses the language type.
3. Decimal conversion is compiler-owned, locale-independent and correctly rounded
   to nearest, ties to even. The F32 decimal token grammar is unchanged.
4. Expected FloatingType selects the format before parsing the value. A contextual
   f64 literal never passes through f32. Without a stronger expectation a decimal
   literal remains f32, including the operand of `literal as f64`.
5. Host strtod/strtof/scanf/atof, host casts/evaluation and LLVM's textual decimal
   parser are not semantic authorities. Later stages never reparse source text.
6. Every ordinary add, subtract, multiply and divide rounds independently to its
   operand/result format under nearest/ties-even. Grouping is significant.
7. Ordinary arithmetic never contracts into FMA or reassociates when results
   differ. No fast-math assumptions, excess precision, reciprocal rewrite, NaN,
   infinity or signed-zero elimination permission is granted.
8. Unary minus toggles the floating sign, including either zero. Unary plus is
   identity. Loads/stores create no arithmetic rounding point.
9. Signed zero is meaningful wherever IEEE operations distinguish it. The zeros
   compare equal but their reciprocals have opposite infinity signs.
10. Subnormals are supported as inputs and results. FTZ/DAZ is not language behavior.
11. Division by zero follows IEEE behavior without an Astra trap. Overflow creates
    signed infinity; underflow rounds to subnormal or signed zero. Finite decimal
    literal overflow to infinity remains the accepted F32 policy.
12. NaN equality and ordered comparisons are false; inequality is true, including
    NaN against itself. There is no totalOrder.
13. F32's NaN policy is explicit and unchanged: payload, sign and signaling/quiet
    construction are not stable language-visible data. Arithmetic and conversions
    may select a quiet NaN. The exact upstream conversion helper chooses an internal
    canonical quiet representative; this is not a new source payload guarantee.
14. f32 and f64 are distinct nominal scalar types. Assignment, calls, returns and
    binary operations require exact type equality; no implicit promotion exists.
15. `f32 as f64` explicitly widens every finite mathematical value exactly,
    preserving signed zero and signed infinity.
16. `f64 as f32` explicitly rounds nearest/ties-even. Finite overflow yields signed
    infinity; tiny finite values produce normal/subnormal/signed-zero results as
    appropriate. Zero/infinity signs are preserved; NaNs follow decision 13.
17. Integer modulo conversion (ICONV), FLOAT_WIDEN and FLOAT_NARROW remain distinct
    verifier-visible operations. Integer/float conversion is unsupported because
    range, fraction, NaN, infinity and overflow rules need their own design.
18. Scalar f64 uses ordinary checked values, Places, Core, CFG and scalar SSA.
    Struct/class fields, typed pointers, arrays and slices gain existing f32 parity.
19. F64 does not imply VectorType<f64>, splat, mask vectors, lanes, vector memory,
    DSP or dot/MAC. Existing F32 vector shape/operation contracts are unchanged.
20. Native by-value f64 uses F64 in a new monotonic `fp64-v6` profile; v0–v5 stay
    frozen. Pointee/element f64 in PTR or SLICE(PTR,I32) is not an F64 channel.
21. This does not expand CABI or VAPI floating interoperability. Source C imports,
    exports and normalized foreign signatures deterministically reject f64.
22. Only the established default x86-64 Linux execution configuration is qualified.
    F64 language semantics impose no SH-4 hardware/software/helper-call decision.
23. Shared binary-floating authority must preserve every accepted F32 behavior;
    no unrelated F64 parser or oracle rule engine is introduced.
24. Generalization is bounded to BINARY32 and BINARY64, with immutable format/bits.
    No arbitrary IEEE formats, new production dependency or parallel memory/SSA
    architecture is needed.
25. FMA, transcendental functions, integer/float conversions, floating C ABI, f64
    vectors and future target qualification require separately bounded campaigns.

## Implementation choice and proof

[F32's exact midpoint algorithm](0036-binary32-semantics.md) already solves the
required decimal comparison problem without arbitrary-precision dependencies.
An independent F64 clone would duplicate policy; using host double would replace
semantic authority. We therefore retain one `BinaryFloatValue` implementation
parameterized by the closed `BinaryFloatFormat` enum. `AstraF32Value` remains a
thin compatibility adapter with its accepted uint32 API and no rounding rules.
`F32Type` and `F64Type` inherit `FloatingType`, retaining distinct exact identities.
Generic floating literal nodes retain their format, immutable bits and provenance;
F32 text dumps retain their original spelling and hexadecimal width.

For a positive finite encoding with significand m and unit exponent e, the upper
rounding midpoint is `(2m+1)*2^(e-1)`. Binary64 midpoint coefficient is at most
`2^54-1`, and its exponent is in `[-1075,970]`. For a negative exponent -k,
multiply by `5^k` and assign decimal scale -k; for a nonnegative exponent,
multiply by `2^k`. The bounds are:

```text
binary32: (2^25-1) * 5^150  < 10^113
binary64: (2^54-1) * 5^1075 < 10^768
```

The source scanner retains exactly that many significant digits, decimal order
and a sticky nonzero tail. This is exact comparison, not preliminary rounding:
a midpoint has no further nonzero digits, so sticky decides an otherwise equal
comparison. Every character is validated, even after overflow/underflow becomes
certain. Exponents saturate at source length + 512; even complete mantissa
cancellation then leaves decimal order outside both formats' finite rounding
intervals. Orders below -323 or above 309 are certainly zero/infinity for f64.

Positive encodings are ordered, so binary search over `[0,infinity_bits]` takes
at most 63 comparisons for f64 (31 for f32). At a tie, encoding parity gives
significand parity. The notional successor of max finite is 2^1024; the midpoint
rounds upward to infinity. Temporary storage is bounded independently of source
length. The exact integer inequalities `10^301 < 2^1000 < 10^302` provide conservative
decimal-order bounds to skip distant midpoints before digit construction.
The cached exact power of 2/5 is reused for nearby midpoints. Decimal
power multiplication is at most 49 per digit; coefficient multiplication stays
below 2^58. This optimization is shared with F32 and changes no result.

Cross-format conversion decodes the finite exact integer significand and binary
unit exponent, then quantizes once at the destination unit. Right-shift remainder
and halfway parity implement nearest/even; left shifts are exact. The closed
formats require at most 53 significant bits and never a host cast. The independent
test reference uses Python integer/rational quotient/remainder quantization for
both formats and the same IEEE special-case rules for arithmetic/comparison.

## Backend realization and execution contract

F64 constants use LLVMConstInt(i64, exact_bits) then LLVMConstBitCast to double;
this backend-only integer carrier does not introduce an Astra i64 or I64 NABI
channel. F32 retains i32-bitcast-to-float. Ordinary floating arithmetic and
comparisons share the existing lowering; FLOAT_WIDEN becomes fpext and
FLOAT_NARROW becomes fptrunc. The per-operation source policy is already fixed.

LLVM 22's [default floating environment and semantics](https://releases.llvm.org/22.1.0/docs/LangRef.html#floating-point-environment)
match the existing Astra execution contract: nearest rounding, preserved
subnormals and unobservable exception flags. Its default denormal mode is IEEE;
ordinary operations without fast-math permissions preserve required rounding
points. The [constant bitcast API](https://llvm.org/doxygen/group__LLVMCCoreValueConstantExpressions.html)
materializes already-chosen representations. Backend tests roundtrip exact bits.

Astra exposes no dynamic rounding environment. As in F32-1, foreign code must
restore nearest/ties-even, masked exceptions and preserved subnormals before
returning to Astra. Changing process rounding, exception masks, FTZ or DAZ does
not redefine Astra semantics; failure to restore the environment violates the
accepted foreign execution contract. Qualification checks actual host controls,
subnormal/special results and non-contraction with FMA-capable x86-64 features.
The compiler's production CPU/features remain empty and optimization level NONE.
O2 and FMA-enabled pipelines are audits, not expanded production target profiles.

## ABI and scope consequences

The repository names v3 documentation `native-f32-v3.md`; it is updated in place
instead of adding a duplicate `native-scalar-fp-v3.md`. The new documentation is
[native-fp64-v6.md](../abi/native-fp64-v6.md). Existing program-wide maximum
capability selection is retained, so all signatures in a program share its
selected profile. A by-value f64 anywhere selects v6; body-only f64 does not.
Ordinary pointer/slice storage and object receiver/result-storage channels remain
PTR and SLICE(PTR,I32), with ownership contracts upstream. V6 supports their
coexistence with F64 and all existing vector channels; F64 vector channels reject.

See qualification for exact matrices, lifetime checks,
golden stability, native execution, machine evidence and Valgrind results.
