# Explicit scalar numeric conversions

Inside a [constant expression](constants.md), the same accepted conversions run
in the compiler's exact scalar evaluator. An evaluated nonfinite/out-of-range
floating-to-integer conversion diagnoses at the conversion with its constant
context. A validly typed conversion in a skipped boolean operand is not evaluated.
Outside constant contexts the established runtime traps remain unchanged.

[Local inference](local-inference.md) preserves a conversion's exact result:
`var scale = count as f64;` infers f64 and `var pixel = coordinate as int;`
infers canonical int. `var` adds no conversion and never supplies operand or
declaration target context. All rounding, range guards and traps below remain
unchanged.

Use `expression as Type` to convert between an existing concrete integer and
`f32` or `f64`:

```astra
f64 scale = count as f64;
int pixel = transformed_coordinate as int;
```

The integer identities are `i8`, `u8`, `i16`, `u16`, `int`/`i32`, `u32`, `i64`,
`u64`, and the qualified host `isize`/`usize` identities.
`int` and `i32` denote the same signed 32-bit type and dumps use `int`.
Every integer identity converts explicitly to either floating format; either
floating format converts explicitly to every integer identity.

Integer→f32 and integer→f64 round the mathematical integer once directly to
the selected format using nearest/ties-even. For example 16777217 becomes
16777216 in f32, whereas 16777219 becomes 16777220. Binary64 has 53 significant
bits: all original at-most-32-bit integers convert exactly, while wide values
may round. A u64 value of 9223372586610589697 rounds directly to f32
9223373136366403584; conversion through f64 first can produce another result.
The compiler constant evaluator and native conversion both preserve the direct
rounding rule. Neither integer-to-floating conversion traps.

Floating→integer evaluates the existing source value, rejects NaN/infinity,
truncates mathematically toward zero, then checks the integer against the exact
destination range. Failure traps. No clamp or modulo result is produced.

| Source expression | Result |
|---|---|
| `3.9d as int` | 3 |
| `-3.9d as int` | −3 |
| `-0.5d as u32` | 0 |
| `-1.0d as u32` | trap |
| `-128.9d as i8` | −128 |
| `-129.0d as i8` | trap |
| `127.9d as i8` | 127 |
| `128.0d as i8` | trap |
| `255.9d as u8` | 255 |
| `256.0d as u8` | trap |
| `4294967295.9d as u32` | 4294967295 |
| `4294967296.0d as u32` | trap |
| `-9223372036854775808.0d as i64` | -9223372036854775808 |
| `9223372036854775808.0d as i64` | trap |
| `18446744073709549568.0d as u64` | 18446744073709549568 |
| `18446744073709551616.0d as u64` | trap |

Both zeros and all finite subnormals become integer zero. The actual floating
source bits govern the result: `2147483647.0f` has already rounded to 2147483648,
so its conversion to int traps. Decimal text is never reinterpreted at conversion.

The source expression runs once, and conversions preserve left-to-right argument
and expression order. A trapping conversion prevents later arguments/effects and
does not unwind owners. A successful scalar conversion has no ownership effect.

The destination of `as` does not contextualize its operand. Use a
[precision suffix](floating-literals.md) for direct binary64 decimal rounding:
`1.0000000000000002d`, compared with the intentionally rounded-then-widened
`1.0000000000000002f as f64`.

Assignments, calls, returns and operators still require exact types. There are
no implicit integer↔floating or f32↔f64 conversions. Bool, pointers, vectors,
masks, structures and arrays/slices gain no numeric conversion. `T : Numeric`
does not authorize conversion to/from T. C signatures remain exact; supply an
explicitly converted argument for a C float/double parameter.

Existing [integer→integer](integer-conversions.md) modulo behavior and
[f32↔f64](f64.md) widening/narrowing behavior remain separate and unchanged.
The wide and host-size identities preserve these policies. No saturation syntax,
wrapping floating cast, runtime helper, allocation or libm requirement is added. See [ADR 0066](../decisions/0066-explicit-numeric-conversions.md).
