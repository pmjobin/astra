# Exact-width native integers

[NUM-CONV-1](numeric-conversions.md) adds explicit integer↔f32/f64 `as`
conversions. IntegerType remains the signedness/range authority. Integer→f32
rounds nearest/ties-even; integer→f64 is exact through the old 32-bit domain
and rounds wider values once nearest/ties-even.
Floating→integer truncates first, then traps unless finite and in range.
These conversions never introduce an implicit type change.

[Fixed local arrays](arrays.md) support every IntegerType as an element and,
independently, every IntegerType as an index. Element literals contextualize to
the exact declared type. Indices use mathematical signed/unsigned values, with
no implicit `as` or matching-to-element conversion. Negative or `>= N` indices
reject statically when directly known, otherwise trap before access/RHS effects.
Valid high-bit unsigned indices preserve their positive ordinal meaning.

DPTR-1 permits [typed data pointers](typed-data-pointers.md) to every integer
type, including i64/u64 and the qualified host-size identities. `int*` and `i32*`
are one exact type; pointers
with differing signedness remain distinct. `&direct_local` makes the local
memory-backed, and `*p` is a Place for exact reads/writes with explicit null
traps and lexical lifetime checks. Direct and pointer accesses remain coherent.
Signedness does not change object width: LLVM uses i8, i16, i32, or i64 loads/stores
without numeric conversions merely for memory access. Pointer arithmetic,
bitwise operations, ordering, indexing, casts, results, and C typed-pointer
boundaries remain unsupported. No layout or numeric alignment query is added.

[BIT-1](bitwise.md) extends the exact W-bit authority with same-type `& | ^ ~`
and `<< >>`. Bitwise results retain width/signedness and reuse symmetric literal
context. Shift counts are separate scalar integer ordinals, valid only in `[0,W)`;
invalid dynamic values trap and direct invalid constants reject. Signed `<<`
wraps the bit pattern; signed `>>` sign-fills (floor division), unsigned `>>`
zero-fills. No host signed-shift behavior or count masking defines Astra results.

[Vector dot/MAC](vector-dot.md) adds `dot_wrap(a,b,D)` and `mac_wrap(c,a,b)`.
Both vectors have the exact same integer S<N>; scalar D is at least as wide
as S and may have different signedness. Exact source mathematical products,
plus C for MAC, are summed then reduced modulo D's width. Source signedness
controls widening; D interprets final bits. Integer reduction grouping and pair
permutation are unobservable within these primitives. Ordinary expression-tree
reassociation rules and saturation remain unchanged.

[VEC-DSP-1](vector-dsp.md) adds explicit `sat_add(a,b)` and `sat_sub(a,b)`
for exact same IntegerType scalars or integer vectors. Their result is the
mathematical sum/difference clamped to the type range, without trapping.
Scalar semantics govern vector lanes, including unsigned subtraction clamping
at zero. Literal context follows ordinary binary arithmetic; `u8 x=sat_add(250,10)`
is 255. Ordinary `+`, `-` and `as` keep wrapping. The internal
`saturating_convert_to` helper clamps before encoding; only `pack_sat` exposes
it in this milestone, with no public scalar saturating cast.

The fixed-width integer family has eight identities. Width and signedness are
language semantics, independent of host C sizes, registers, LLVM types, and C ABI
rules. `isize` and `usize` add two distinct identities in the qualified host scope
described below; they never alias `int`, `i64`, or `u64`.

| Source name | Signed | Bits | Minimum | Maximum |
| --- | --- | --- | --- | --- |
| `i8` | yes | 8 | -128 | 127 |
| `u8` | no | 8 | 0 | 255 |
| `i16` | yes | 16 | -32768 | 32767 |
| `u16` | no | 16 | 0 | 65535 |
| `i32`, `int` | yes | 32 | -2147483648 | 2147483647 |
| `u32` | no | 32 | 0 | 4294967295 |
| `i64` | yes | 64 | -9223372036854775808 | 9223372036854775807 |
| `u64` | no | 64 | 0 | 18446744073709551615 |
| `isize` (qualified host) | yes | 64 | -9223372036854775808 | 9223372036854775807 |
| `usize` (qualified host) | no | 64 | 0 | 18446744073709551615 |

`int` and `i32` are one semantic type. Both resolve to the same `IntegerType`
object in a semantic type universe. Canonical dumps keep the spelling `int`;
syntax dumps preserve an explicitly written `i32`. `bool` is distinct from every
integer, and conditions remain bool-only. There is no `uint` alias.

## Decimal literals and exact types

Unsuffixed decimals retain their spelling in syntax until semantic checking
knows an integer context. A local initializer, assignment RHS, function return,
native call argument, struct field initializer, or field assignment supplies an
expected type. That type propagates through arithmetic and numeric prefix
expressions. Typed operands also supply context symmetrically:

```astra
u8 x = 1 + 2;
u32 checksum = 4000000000;
u16 length = 1000;
bool fits = length < 2000;
x = x + 1;
x = 1 + x;
```

A literal-only expression without stronger context defaults to `int`. Comparison
results are always bool; an enclosing bool context does not become integer
operand context. A type-only traversal reads declared local, parameter, field,
and call-result types, without evaluating calls or changing ownership state.
Normal checking and execution preserve left-to-right order.

Contextual literal typing is not conversion. Every already typed operand keeps
its exact identity. `i8 + i16`, `i8 == u8`, passing `int` to `u32`, and assigning
`u16` to `u8` reject. There is no implicit widening, narrowing, or sign conversion.
[ICONV-1](integer-conversions.md) adds explicit `as` conversion under one
mathematical-value modulo-destination-width rule.

Each literal must fit its contextual range. `u8 x = 256;`, `i8 x = 128;`,
`i16 x = 32768;`, `u16 x = 65536;`, and `u32 x = 4294967296;` diagnose
`integer literal is out of range for 'TYPE'`. Arbitrarily long decimal spelling
may parse and syntax-dump; semantic accumulation checks its bound before every
multiply/add. Leading zeros remain decimal.

Unary minus directly on a decimal literal, including parentheses, may form a
signed minimum: `i8 x = -(128);`, `i16 x = -32768;`,
`int x = -2147483648;`, and `i64 x = -9223372036854775808;`. Positive `+128`
does not fit i8. The exception does not
extend to `-(128 + 0)` in an i8 context: the positive operand literal must fit.
Unsigned unary minus, including `u8 x = -1;` and `u8 x = -0;`, rejects with
`unary '-' is not supported for unsigned integer type 'u8'` (likewise u16/u32/u64/usize).

## Arithmetic and comparisons

`+`, `-`, `*`, `/`, and `%` require exactly the same integer type on both sides
and return that type. Addition, subtraction, and multiplication wrap modulo
2^N. For example, u8 `255 + 1` is 0, i8 `127 + 1` is -128, and u32
`0 - 1` is 4294967295. Overflow does not trap.

Unary plus is identity for every integer. Unary minus is signed-only and wraps,
so `-MIN == MIN` at each signed width.

Signed division truncates toward zero; signed remainder follows the dividend.
For every signed width, `MIN / -1 == MIN` and `MIN % -1 == 0`. Unsigned quotient
and remainder use nonnegative mathematical values. Every division or remainder
by zero explicitly traps without normal return or unwinding cleanup. No
particular host signal is promised.

Equality and ordering require exact same-type operands and return bool.
Signed ordering is mathematical signed ordering; unsigned ordering is
mathematical unsigned ordering. i8 -1 and u8 255 both have bits 0xff, but
`-1 > 1` is false for i8 and `255 > 1` is true for u8. Their quotients by 2 are
0 and 127 respectively. Equal bits do not imply equal typed values.

## Storage, calls, and boundaries

Every integer uses ordinary local/field Places, loads, stores, scalar SSA values,
block parameters, branch merges, and loop carries. Struct fields accept the full
integer family alongside bool and void*. Address-taken native structs use the
existing memory path, with exact-width scalar field loads/stores; no stable
padding, layout, size, alignment, or aggregate ABI is promised.

Native signatures use [scalar-int-v2](../abi/native-integers-v2.md) when they
contain a noncanonical integer identity, including the wide and host-size types. Body-only integer locals do not change the signature
profile. Owned and borrowed Resource contracts coexist with these channels and
retain existing transfer, evaluation, and cleanup rules. Executables still
require canonical `int main()`; `i32 main()` is the same valid signature.

On the qualified GNU/Linux x86-64 LP64 host, C imports, C exports, and normalized
VAPI signatures support `i64`/`u64` as `int64_t`/`uint64_t` channels, `isize` as
`ptrdiff_t`, and `usize` as `size_t`. These are exact declared channels; no C
`long` alias or implicit conversion is introduced. The original i8/u8/i16/u16/u32
C channels still reject with `exact-width C integer channels are not supported
yet`; their C argument-extension contracts remain unqualified.

The wider scalar family preserves every established wrapping, bitwise, shift,
saturation and explicit-conversion rule. Decimal literal context supplies the
wide type; no suffix is required. Unary `&` retains address-of meaning.
[VEC-1 short vectors](vectors.md) remain limited to their existing at-most-32-bit
integer lanes: i64/u64/isize/usize vector forms reject. Vector integer division
and remainder remain deferred.

## Relationship to f32

[F32-1](f32.md) adds a separate binary32 type without changing any integer rule.
`1` remains an integer token even in `f32 x = 1;`, which rejects; `1.0` and `1e0`
are f32 literals. Integer context cannot convert a floating literal. Mixed
integer/float arithmetic, comparison, assignment, call, and return types reject.
Integer zero division still traps; floating zero division has IEEE infinity/NaN
results. NUM-CONV-1 now permits explicit scalar integer/float `as` conversions.

## Explicit generic capabilities

Every scalar integer identity satisfies Eq, Ordered, Numeric, Bitwise and Shift.
Constrained generic specialization reuses ordinary wrapping arithmetic, divide-zero
traps, signed division edges, signed/unsigned comparisons and BIT shift guards.
Capability constraints never add nsw/nuw arithmetic flags. int/i32 still share one
instance identity. See [generic capabilities](generic-capabilities.md).

## Qualified host sizes and diagnostics

Wide native execution is qualified only for GNU/Linux x86-64 with an actual
LLVM target-data pointer size of eight bytes. The target machine checks this
before object emission. Independently compiled C witnesses check
`sizeof(int64_t)`, `sizeof(uint64_t)`, `sizeof(size_t)`, `sizeof(ptrdiff_t)` and
`sizeof(void*)`, and exchange high-bit values through real imported/exported
functions. Source width is therefore a documented host contract checked against
the selected target, not a guess from the compiler process or host `long`.
ILP32 and other target layouts fail closed; portable cross-target size identities
are not established by this implementation.

Array/buffer counts, slice and UTF-8 lengths, and `int main()` retain their I32
contracts. A `usize` count requires an explicit conversion and an application
range check before an I32 API; `as` itself wraps and never supplies that check.
Wide array indices are checked in their mathematical signed/unsigned domain
before memory access, including values above i64.MAX.

`append_i64(builder, value)` and `append_u64(builder, value)` from
`lib/astra/text/scalar-format.astra` append locale-independent decimal ASCII,
including both extreme values. Size identities require an explicit `as i64` or
`as u64` at that formatting boundary.
