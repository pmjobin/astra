# Floating literal precision

CONST-1 preserves these literal rules in named compile-time values. An inferred
`const` supplies no destination context; an explicit `const f64` supplies ordinary
f64 initializer context. Suffix precision still wins before rounding. A later
reference retains its exact type and bits and cannot be recontextualized. Constant
arithmetic rounds at every operation; see [constants](constants.md).

With [local inference](local-inference.md), `var` supplies no destination
context: `var a = 1.0;` and `var b = 1.0f;` infer f32, while
`var c = 1.0d;` infers f64. `var x = 1.0000000000000002d;` retains exact bits
`0x3ff0000000000001`; the unsuffixed spelling remains f32 `0x3f800000`.

A decimal real spelling may end in `f`/`F` for f32 or `d`/`D` for f64.
Documentation prefers lowercase:

```astra
f32 ratio = 1.25f;
f64 epsilon = 1.0000000000000002d;
f32 small = 1e-10f;
f64 large = 1.0e10d;
```

```ebnf
float-literal = (digits, ".", digits, [exponent] | digits, exponent), [suffix] ;
exponent = ("e" | "E"), ["+" | "-"], digits ;
suffix = "f" | "F" | "d" | "D" ;
```

A suffix fixes the literal's semantic precision **before decimal rounding**.
The compiler's exact, locale-independent decimal machinery rounds once directly
to that format, nearest/ties-even. Host float/double parsing, strtof/strtod and
LLVM text parsing are not semantic authorities.

| Expression | Exact bits |
|---|---|
| `1.0000000000000002d` | f64 `0x3ff0000000000001` |
| `1.0000000000000002f` | f32 `0x3f800000` |
| `1.0000000000000002f as f64` | f64 `0x3ff0000000000000` |

The direct f64 constant differs from the widened f32 value. Widening cannot
recover precision discarded by the first rounding.

Unsuffixed literals retain their existing rule: a floating destination context
selects its precision; otherwise the literal defaults to f32. Thus
`f64 x = 1.0000000000000002;` rounds directly to f64, while
`1.0000000000000002 as f64` first rounds to f32. The destination of `as` does
not supply operand context. NUM-CONV-1 does not retype old source.

A suffix overrides context. `f64 x = 1.0f;` and `f32 x = 1.0d;` reject;
write `1.0f as f64` or `1.0d as f32` for explicit width conversion.
A semantic constant retains only the selected type, exact bits and provenance.
Downstream stages neither inspect suffixes nor reparse decimal source.

Signs remain unary operators. `-1.25f` and `-1.25d` are ordinary negations;
`-0.0f` and `-0.0d` preserve bits `0x80000000` and `0x8000000000000000`.
Existing literal overflow and underflow produce infinity or subnormal/zero.
Integer-looking `1f`/`1d`, `.5`, `1.`, hexadecimal floats, separators, other
suffixes and explicit NaN/infinity tokens remain unsupported. Existing
expressions such as `0.0d / 0.0d` can produce NaN.
