# Exact bitwise, boolean and shift operations

The scalar integer family supports `& | ^ ~ << >>` for every exact integer
identity, including i64/u64 and qualified isize/usize. Supported integer vectors
retain their existing at-most-32-bit element scope. `int` and `i32` remain one type. Integer representation is
exactly W bits; signedness interprets those bits and never changes their width.

## Bitwise integer rules

| Form | Exact W-bit result |
| --- | --- |
| `a & b` | A bit is set exactly when both input bits are set |
| `a \| b` | A bit is set when either input bit is set |
| `a ^ b` | A bit is set exactly when the input bits differ |
| `~a` | `a_bits XOR (2^W - 1)` |

Binary operands must have the exact same IntegerType or exact same integer
VectorType. The result retains that type. There are no promotions, broadcasts,
width changes or implicit signedness conversions. `i8 & u8`, `i8 & i16`,
`int | u32` and `u16 ^ i16` reject. Use [explicit `as`](integer-conversions.md)
first when desired. Every vector lane reuses the scalar bit rule.

For example, i8(-1) AND i8(1) operates on `ff & 01` and produces i8(1).
Complementing u8(0), u8(255), i8(0), i8(-1) yields 255, 0, -1, 0 respectively.
Those hexadecimal descriptions are explanatory bit patterns; source literals
remain decimal.

The existing literal contextualization works symmetrically: if `value` is u8,
both `value & 15` and `15 & value` type the literal as u8. `1 | 2` defaults to int
without stronger context; `u8 x = 1 | 2;` types both literals as u8. Unrepresentable
literals reject. Context affects literal construction, never a typed operand.

## Eager bool and masks

Scalar `bool & bool`, `bool | bool`, and `bool ^ bool` produce bool. Same-shape
bool<N> forms produce bool<N> lane-wise. Both producers evaluate once, left then
right, before the operation. They are boolean operations, without integerizing
bool. XOR is false/true/true/false for FF/FT/TF/TT.

`false & record_true()` evaluates the right call; `true | record_false()` does
too. The existing `false && record_true()` and `true || record_false()` suppress
those right calls. `&&`/`||` remain scalar short-circuit control flow and reject
masks. Eager bool creates no conditional branch solely to evaluate its operands.

Use `!` for bool/mask complement. `~bool` and `~mask` reject. f32 and f32 vectors,
void*/Struct* and Resource values reject all integer bit/shift operators. Physical
IEEE or pointer bits do not grant source-level integer access.

```astra
bool<8> in_range = (x >= low) & (x <= high);
i16<8> result = select(in_range, a, b);
```

## Shift value and count domains

`value << count` and `value >> count` accept an integer scalar or integer vector
value and any scalar IntegerType count. The count need not match the value's
width or signedness. Result type is exactly the value type. For example, a u8
value with an int count is valid without an implicit numeric conversion.

Interpret the count as its exact mathematical integer. For element width W,
valid counts are `0 <= count < W`. Zero is identity; W-1 is valid. Negative
signed counts, W and larger counts, including u32(4294967295), are invalid.
Counts are never masked to a machine instruction's count domain.

An immediate checked integer constant outside that range rejects statically,
including `x << 8` for u8, `x >> 9`, and `x << -1`. Parentheses and the existing
unary-literal handling preserve obvious constant knowledge. BIT-1 adds no general
constant-expression evaluator. Other counts require runtime validation unless
later exact constant knowledge proves them valid.

Evaluate the value expression, then the count expression, then validate, then
shift. An invalid dynamic count explicitly traps without returning or unwinding.
Both expressions' prior effects occur; no shift result is produced and cleanup
unwinding is not invented. No particular host signal is required.

## Exact shift results

Left shift is `(source_bits * 2^count) modulo 2^W`, interpreted as the same type.
Signed left shift is defined, including negative sources and sign-bit overflow:
i8(-1)<<1 and i8(127)<<1 both produce -2; u8(255)<<1 produces 254. These do not
trap for overflow and have no C-like UB.

Unsigned `>>` zero-fills: u8(255)>>1 is 127. Signed `>>` sign-fills and equals
`floor(value / 2^count)`: -1>>1 is -1, -2>>1 is -1, -3>>1 is -2, and i8(-128)>>7
is -1. Division still truncates toward zero, so i8(-3)/2 is -1 while i8(-3)>>1
is -2. The same `ff` bits as i8 and u8 shift right to -1 and 127 respectively.
For a logical-right interpretation of signed bits, convert explicitly:

```astra
i8 signed_value = -1;
u8 logical = (signed_value as u8) >> 1; // 127
```

A vector shift applies one scalar count to every lane using the exact scalar
rule. Validate against element width, not total vector width: u8<16> allows
0..7, i16<8> 0..15, u32<4> 0..31. Validate once, before producing any result.
A vector count rejects. Vector results remain ordinary whole values usable by
shuffle, select, saturation, widen/pack, dot/MAC, loops and native vector calls.

## Precedence

Strongest to weakest; binary levels associate left. Primary/postfix forms retain
their existing placement above unary. Existing `as` precedence is unchanged.

| Level | Operators |
| --- | --- |
| Unary | `+` `-` `!` `~` address-of `&` |
| Integer conversion | `as` |
| Multiplicative | `*` `/` `%` |
| Additive | `+` `-` |
| Shift | `<<` `>>` |
| Relational | `<` `<=` `>` `>=` |
| Equality | `==` `!=` |
| Bitwise/eager AND | `&` |
| Bitwise/eager XOR | `^` |
| Bitwise/eager OR | `\|` |
| Short-circuit AND | `&&` |
| Short-circuit OR | `\|\|` |

Thus `a > b & c > d` parses as `(a > b) & (c > d)`. Prefix address-of remains
the restricted existing Place form; binary `&` is unambiguous. Maximal munch
preserves `&&`/`||` and recognizes `<<`/`>>`. Future nested type closers need
contextual splitting of `>>`; token spans permit this without a lexer replacement.
Generics and splitting are not implemented now.

## Backend and exclusions

LLVM and/or/xor realize exact bit operations. Guarded shl/ashr/lshr realize exact
shifts, with no nsw/nuw/exact flags. No invalid count reaches a shift instruction.
After validation, physical count normalization/splat is backend-private and adds
no source conversion or vector count type. Target legalization may split or
scalarize vectors, including byte shifts; specific SIMD instructions are not
language guarantees. See [IR rules](../ir/bitwise-shifts.md).

No rotates, `>>>`, masked/wrapping count primitive, per-lane counts, compound
assignments, bool/integer conversions, bitcasts, hexadecimal literal expansion,
fixed point, vector memory or C exact-width/vector ABI is added. NABI's existing
five profiles and CABI/VAPI retain their contracts.
