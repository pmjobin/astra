# ADR 0066 — Explicit scalar numeric conversions and precise floating literals

Status: accepted for ASTRA-NUM-CONV-1.

Baseline: ASTRA-BUFFER-1, `04530f13800bdbba792b4214f182d276557fb4d8`.

Integer metadata and floating geometry need ordinary explicit expressions.
Decimal constants must also let the author select precision before rounding.

## Decision

```astra
f64 scale = count as f64;
int index = coordinate as int;
f64 epsilon = 1.0000000000000002d;
```

The existing `expression as Type` syntax admits all pairs between the six
concrete integer identities (`i8`, `u8`, `i16`, `u16`, `int`/`i32`, `u32`) and
`f32`/`f64`. Signedness belongs to semantics. No implicit promotion, bool,
pointer, aggregate, mask, generic parameter or floating vector conversion is
added. Existing integer modulo conversions and f32↔f64 conversions are unchanged.

Integer→floating rounds once to the destination format, nearest with ties to
even, without trapping. Every current integer is exact in binary64: its magnitude
is below 2^32, within binary64's 53-bit significand. Binary32 has 24-bit precision;
conversion does not pass through a semantic f64 intermediate.

Floating→integer rejects NaN/infinity, mathematically truncates toward zero,
and traps if that integer falls outside the exact destination interval. It
neither saturates nor wraps. In particular, `-0.5d as u32`, `-128.9d as i8` and
`255.9d as u8` produce 0, −128 and 255. Traps do not unwind or run later effects.
Each operand is evaluated once in the existing left-to-right order.

`f`/`F` selects binary32 and `d`/`D` selects binary64 on existing decimal real
spellings, including exponents. Lowercase is canonical style. The semantic
constructor consumes the suffix before invoking the unchanged exact decimal
authority. A suffix fixes the semantic type despite destination context.
Unsuffixed contextual typing and the uncontextualized f32 default stay unchanged.
No suffix metadata survives in numeric IR. Provenance may still quote the source.

## Representation and safety

Checked and Core gain exact scalar numeric conversion nodes with source type,
destination type, one of eight signed/unsigned format-specific kinds, policy and
source span. The shared LLVM-free policy authority reuses IntegerType and
FloatingType. Independent verifiers reject malformed type, kind or policy.

CFG emits an ordered numeric guard for floating→integer, then an explicit
conversion consuming that guard's ordinary floating result. SSA preserves those
two instructions. The result producer certifies the exact destination interval;
the verifier independently checks the producer and normal definition dominance.
A missing guard, another range, reordered guard or one-sided branch proof rejects.
There is no runtime type tag, proof object, boxed number or new ABI channel.

LLVM widens f32 exactly to f64 **only for comparisons**. With current integer
widths both `MIN−1` and `MAX+1` are exactly representable in f64. Ordered
`x > MIN−1 && x < MAX+1` implements truncation-first validity, rejecting all
nonfinite values. A select substitutes zero for an invalid conversion operand;
the original invalid value still branches to `llvm.trap`. Physical fptosi/fptoui
is emitted in the successful continuation. O2 qualification checks that this
control dependence remains and executes adversarial exact-bit inputs.

The backend uses ordinary sitofp/uitofp for integer sources under the existing
nearest/ties-even floating environment. Foreign code must continue to restore
that environment; dynamic rounding modes are not Astra state. No environment
mutation, fast math, contraction, libm, allocator or mandatory helper is added.
Machine instructions realize this contract; they do not define it. See the
[LLVM 22 instruction and floating-environment contracts](https://releases.llvm.org/22.1.0/docs/LangRef.html#floating-point-environment).

## Alternatives and boundaries

Checking `[MIN, MAX]` before truncation would incorrectly reject valid fractional
edges. Comparing all bounds in f32 would round 32-bit boundary constants and
misclassify values. Exact f64 comparisons avoid both problems for this bounded
integer inventory. A helper library or new constant evaluator is unnecessary.
Separate guards fit the existing ordered bounds-check model and permit independent
proof verification; keeping the guard implicit until LLVM would weaken that check.

Future i64/u64 need a fresh boundary design: the current MIN−1/MAX+1 exactness
argument must not be extended to them. Numeric generic capability, vector casts,
var/const inference, literal defaults, compile-time conversion evaluation and a
math library require separate decisions. No review trigger or ABI redesign was
needed. See [language](../language/numeric-conversions.md),
[literals](../language/floating-literals.md), [IR](../ir/numeric-conversions.md)
and qualification.
