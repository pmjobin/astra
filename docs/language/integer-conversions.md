# Explicit integer conversions

[DSP widening and pack_wrap](vector-dsp.md) reuse this exact ICONV authority.
Widen selects low/high ordinal halves before conversion; **source signedness**
controls extension, including signed-to-unsigned widening. Pack-wrap converts
lanes modulo destination width and places the first source before the second.
Pack-sat instead uses `saturating_convert_to`: clamp the source mathematical
value to destination range before encoding. No scalar saturating-cast syntax
is exposed, and `as` remains wrapping. See [conversion families](conversions.md).

`value as Type` converts an already-typed integer value. All pairs among i8, u8,
i16, u16, int/i32, u32, i64, u64 and qualified isize/usize are permitted. A vector
can convert to an integer VectorType with the same lane count when both shapes are already supported.

```astra
i8 negative = -1;
u16 widened = negative as u16; // 65535
u8 byte = 255;
i16 sample = byte as i16;      // 255
u8 wrapped = 256 as u8;        // 0: source is int
u64 high = 18446744073709551615;
i64 signed_bits = high as i64; // -1
usize count = high as usize;   // explicit, distinct host-size identity
u8<8> bytes = splat(255,8);
i16<8> samples = bytes as i16<8>;
i16 lane = (bytes as i16<8>)[3];
```

Interpret the source as its mathematical integer V. Destination bits are the
unique residue `V modulo 2^N` in `[0,2^N-1]`, for destination width N. Interpret
those bits with destination signedness. Conversion is total and never traps;
its operand evaluates exactly once and retains its own effects or traps.

| Source | Destination | Result |
| --- | --- | --- |
| i8(-1) | i16 | -1 |
| i8(-1) | u16 | 65535 |
| u8(255) | i16 | 255 |
| i16(-129) | i8 | 127 |
| u16(65535) | i8 | -1 |
| i16(-1) | u8 | 255 |
| int(-1) | u32 | 4294967295 |
| u32(4294967295) | int | -1 |
| i64(-1) | u64 | 18446744073709551615 |
| u64(18446744073709551615) | i64 | -1 |
| u64(4294967297) | int | 1 |

The parenthesized type/value notation in the table describes values; it is not
function-like cast syntax. Same-width sign changes preserve bits. Same-type and
int/i32 alias conversions are identity. Narrowing wraps, including `300 as u8`
producing 44; it does not saturate.

Conversion binds below unary operators and above multiplication, division,
remainder, addition, subtraction, comparisons, `&&`, and `||`. Chains associate
left to right. `-1 as u8` means `(-1) as u8`; `x+y as i16` means `x+(y as i16)`.
Use `(x+y) as i16` to convert a whole addition. Each source is typed independently
of its destination. Therefore `4294967295 as u32` is an out-of-range default-int
source, while `u32 x=4294967295; int y=x as int;` is valid. An explicit cast is
separate from contextual literal typing; `u8 x=256` still fails range checking.

No implicit conversion is added to assignments, calls, arithmetic, comparisons,
or select. `(i8_value as i16)+1` has i16 operands; `i8_value+i16_value` still
rejects. Conversion results compose with splat, extraction, insertion, shuffle,
select, scalar struct fields, branches, loops and native calls.

`i8<8> as i16<8>` works, but `i8<8> as i16<4>` fails lane-count checking and
`i8<16> as i16<16>` fails the existing shape bound. No lane splitting is implicit.
A vector conversion remains one semantic/SSA value operation. Wide scalar
identities do not add wide vector shapes.

Bool, pointers, Resource handles and structs do not convert to/from integers.
[NUM-CONV-1](numeric-conversions.md) separately defines explicit scalar f32/f64↔integer
conversion; floating→integer traps instead of using ICONV modulo semantics.
Masks are not one-bit integer vectors. Scalar/vector crossing is unsupported.
Diagnostics identify the unsupported source/destination type, shape or lane
mismatch. Existing source-typing errors (such as whole-struct value rejection)
can occur before conversion checking. Casts do not alter a declared foreign
signature; see the qualified wide [integer ABI scope](integers.md).

See [ADR 0039](../decisions/0039-explicit-integer-conversions.md) for the physical
extension/truncation derivation, parser suffix disambiguation and future policies.
