# ADR 0013: Concrete scalar semantics and integer constant authority

Status: accepted for ASTRA-SCALAR-1.

## Decision

1. Astra `int` is signed, with exactly 32 bits of value representation on every
   target: **-2147483648 through 2147483647**, inclusive. It is never target-sized.
2. Ordinary `+`, `-`, `*`, and unary `-` reduce their mathematical result modulo
   2^32 and interpret it as signed two's complement. Overflow wraps, with no
   undefined behavior, implicit overflow trap, or debug/release difference.
3. Unary `+` returns the same int value.
4. Signed division truncates toward zero.
5. For a nonzero divisor, remainder is `a - q*b`, where `q` is the mathematical
   quotient truncated toward zero. A nonzero remainder has the dividend's sign.
6. Integer division and remainder by zero are deterministic runtime trap
   conditions with no numeric result. Literal operands do not introduce a
   compile-time constant-expression diagnostic.
7. `INT_MIN / -1` wraps to `INT_MIN` (-2147483648).
8. `INT_MIN % -1` is zero. Neither exceptional edge inherits instruction traps,
   C undefined behavior, or LLVM poison/undefined behavior.
9. Integer relational comparisons use signed ordering; equality compares exact
   int values.
10. Astra defines these semantics. Vala, C, host architecture, and LLVM provide
    implementation mechanisms, never language authority.
11. `bool` has exactly `false` and `true`, carried symbolically by
    `BooleanLiteral.FALSE/TRUE`. It is distinct from int: no integer truthiness,
    subtype relationship, or implicit conversion in either direction.
12. SourceFile/SourceSpan owns source spelling and provenance. Immutable
    `AstraIntValue` owns the numeric meaning of checked integer constants.
13. Semantic analysis checks literal representability before constructing a
    checked integer node or Core. Core, CFG, and SSA retain the semantic value
    and provenance; they never parse source text to recover numeric meaning.
14. Future checked, saturating, and possibly overflow-reporting operations are
    explicit language extensions. They are not implemented in SCALAR-1.
15. Semantic width does not specify physical layout, parameter/return registers,
    calling convention, linkage, symbol names, bool memory/ABI width, or LLVM
    types. These remain downstream physical-lowering and ABI decisions.

## Why wrapping is the baseline

Astra is intended to be deterministic, systems-capable, embedded-friendly, and
DSP-friendly. Modulo arithmetic provides a usable baseline across x86-64,
AArch64, SH-4/Dreamcast, embedded systems, and future targets without C's signed
overflow UB or build-mode-dependent behavior. Checked arithmetic would impose
implicit traps on ordinary operators; saturation would impose a different
numeric model. Those facilities remain valuable explicit extensions. One
ordinary operator has one meaning across builds and targets.

## Literal formation

Decimal syntax remains `[0-9]+`; leading zeroes are decimal. There are no radix
prefixes, separators, suffixes, or explicit-width forms. Positive literals must
fit 0 through INT_MAX. Direct unary `+` or `-` applied to an integer-literal
syntax form, through any parentheses, forms one signed constant. Negative
formation admits magnitude 2147483648 without ever creating a positive int
constant with that value.

Thus `-2147483648`, `-(2147483648)`, and `-((2147483648))` all form INT_MIN.
`2147483648`, `+2147483648`, and `-2147483649` fail with
`integer literal is out of range for 'int'`. The negative diagnostic/constant
span includes its sign and intervening parentheses/comments. Unsigned literals
retain their exact literal span. Syntax is unchanged and retains every token.

This normalization is literal formation, not an expression evaluator. The
outer operator in `-(-2147483648)` remains an operation. So do `1 + 2`, `4 * 5`,
`!false`, and division/remainder by literal zero. A sign surrounding an
arithmetic expression does not rescue an out-of-range literal within it.

## Executable reference authority

`src/semantic/int-value.vala` contains the immutable `AstraIntValue` and
`IntArithmeticOutcome`. The value's constructor and int64 field are private;
its public numeric property is read-only. `from_int64` rejects values outside
the Astra range; it is an implementation factory, not a source conversion.
Every normal IR constant constructor requires an existing valid value. No
unchecked constructor is exposed for malformed-IR tests.

Decimal formation accumulates a nonnegative magnitude against either INT_MAX
or 2147483648. Before appending digit `d`, it checks
`magnitude <= (limit - d) / 10`. It never calls a host textual integer parser,
and even arbitrarily many leading zeroes remain decimal and safe.

Arithmetic uses exact int64 intermediates. Every 32-bit operand product fits
within magnitude 2^62; sums, differences, negation, and the exceptional division
quotient also fit. Wrapping explicitly reduces modulo 4294967296, adjusts a
negative residue into 0 through 2^32-1, and subtracts 2^32 above INT_MAX. No
operation depends on overflowing signed host arithmetic or narrowing casts.
Division uses nonnegative magnitudes and explicitly applies the quotient's
sign. Remainder uses the unwrapped mathematical quotient, including INT_MIN/-1.

`div` and `rem` return `VALUE` with a non-null AstraIntValue, or
`ZERO_DIVISOR_TRAP` with null. The zero check precedes host division; no host
exception, runtime exception object, panic string, or LLVM trap call exists.
These operations define a reference oracle for later folding and backend
differential tests. The compiler pipeline only uses the literal factory.

## Ordering defect exposed by traps

CALL-1 sequences calls in CFG while retaining arithmetic trees until use.
With newly observable zero-divisor traps, `a / b + effect()` incorrectly reached
SSA as call, division, addition. Likewise `pair(a % b, effect())` placed the
later argument's call before the earlier argument's potential trap.

SCALAR-1 fixes that concrete defect with `CfgEvaluateInstruction` and its
independent `CfgEvaluatedValue`. Before lowering a binary right operand
containing calls, CFG materializes a potentially trapping left tree. Earlier
call arguments are similarly materialized when a later argument contains a
call. A tree may trap if it contains division/remainder; no divisor is evaluated
or proven nonzero. Loads are unchanged because current calls cannot alias
caller scalar Places.

The verifier requires one defining evaluation, matching non-void value/result
types, and definition before use in the same block. Results have no owning
backlink. SSA lowers the evaluation at its instruction position and maps uses
to the existing SSA value, introducing no new SSA operation or Place.

Eagerly making all arithmetic CFG instructions would alter unaffected shapes.
The chosen narrow materialization preserves existing trees and call identities
while retaining the already accepted left-to-right language semantics. Calls,
block arguments, dominance, reachability, and Place promotion are unchanged.

## Regression transition and validation

The historical 1,003-digit literal (`000` and 1,000 nines), and SEM-1's 60-digit
fixture, remain syntax successes with exact spelling. Every checked/downstream
CLI mode now rejects them semantically with empty stdout. Their obsolete
success goldens become diagnostic goldens; historical source and syntax
regressions remain. Leading-zero constants dump canonically downstream.
Lifetime tests use valid INT_MAX with 1,003 decimal digits (leading zeroes),
retaining numeric meaning, semantic type, and exact source provenance after
upstream destruction.

Reference tests cover construction, decimal boundaries, wrapping arithmetic,
all quotient/remainder signs, zero-divisor outcomes, INT_MIN/-1, and signed
ordering. The same tests run optimized with strict host overflow assumptions
and trapping undefined-behavior instrumentation where supported, without a
sanitizer runtime dependency. Pipeline tests cover signed formation, source
provenance independent of meaning, calls/locals, explicit operations, and trap
ordering. Existing standalone and LLVM firewalls remain mandatory.

See [scalar language semantics](../language/scalars.md) for the complete user
contract. No native/C ABI, LLVM lowering, optimizer, new scalar type, external
dependency, or copied Vala/LLVM-v2 implementation is introduced.

## SCALAR-1 qualification

Validated on 2026-09-06 from the clean accepted CALL-1 baseline
`409c45e9caf267089dce7f0ed0b422017d774ec6`, on branch `astra-scalar-1`:

```sh
CCACHE_DISABLE=1 meson setup build-scalar-1-final -Dwerror=true
CCACHE_DISABLE=1 meson compile -C build-scalar-1-final
CCACHE_DISABLE=1 meson test -C build-scalar-1-final --print-errorlogs
```

The fresh build passed **648 Meson entries and 631 GLib/TAP subtests**, with no
warnings or failures. All **287 C compile commands** retain `VALA_STRICT_C` and
`-Werror`. The reference suite passes 9 cases in both ordinary and optimized
UB-trapping builds; scalar pipeline tests pass 8 cases. Existing call tests
pass 13, including forward/self/mutual identity and reclamation. Standalone
Core/CFG/SSA suites pass 5/9/40 cases; all previous 44 malformed call cases
remain. The extra CFG cases cover ordered evaluations and their malformed
constructible states.

All **15 protected executables**, including the CLI harness and new scalar
suites, pass actual link-command, `ldd`, `readelf`, and `nm` audits. The LLVM
smoke executable fails the firewall as the required negative control. Standalone
compile-input audits exclude upstream models/builders and backend sources.
Syntax/source infrastructure and the CHARTER backend remain unchanged.

**27 representative Valgrind runs** report zero errors and zero definitely,
indirectly, or possibly lost bytes, without added suppressions. These include
scalar reference/pipeline tests, full SSA/call and standalone suites, focused
Core/CFG lifetime tests, every boundary dump stage, huge syntax/rejection paths,
positive/negative overflow, wrapping/division/trap-order fixtures, and self/mutual
recursion. Two additional full Core/CFG suite runs each report one 16,384-byte
allocation originating in GLib process initialization. Freshly built tests from
an archive of the exact accepted baseline reproduce the same allocation/stack
and one error context in each suite. This is a pre-existing host-library
finding, not a SCALAR-1 regression; no source changes or suppressions hide it.

Existing source and syntax goldens are unchanged. Ninety-five downstream goldens
were independently checked to differ only by canonical integer formatting; the
remaining operator golden additionally normalizes direct `-0007` to -7 while
preserving outer unary plus. Historical huge success goldens intentionally
become semantic diagnostic expectations. A new call-overflow diagnostic golden
initially pointed at the call parenthesis; source inspection established the
literal's correct column 18, and all five affected mode checks now pass.

No production/test dependency, broad warning suppression, optimizer, new scalar
type, native/C ABI, or LLVM lowering was added. The only architectural extension
is the documented evaluation instruction required by newly observable traps.
ASTRA-NABI-1 must preserve the scalar contract, trap order, and exceptional
signed-division results while making its separate ABI decisions.
