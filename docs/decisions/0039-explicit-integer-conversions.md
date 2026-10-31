# 0039: Explicit integer conversions

Status: accepted for ASTRA-ICONV-1, following accepted
[0038](0038-vector-lane-primitives.md) at
`e0a23c9b4f99be579197ce469d224dc6bb33081e`.

## Decision

1. Integer conversions are explicit, using `expression as type-syntax`.
2. No implicit integer widening, narrowing, or signedness conversion is added.
3. `as` converts one already-typed integer value to another canonical IntegerType:
   i8, u8, i16, u16, int/i32, or u32. `int` and `i32` are the same identity.
4. Interpret the source with its exact mathematical integer meaning V. For a
   destination width N, compute the unique residue `V modulo 2^N` in `[0,2^N-1]`.
5. Destination signedness interprets that destination bit pattern. A signed
   destination subtracts `2^N` when the destination high bit is set.
6. Same-width signedness conversion preserves every bit. Same-type conversion,
   including int/i32 aliases, is a permitted semantic identity.
7. Widening a signed source is physically sign extension, including when the
   destination is unsigned: i8(-1) as u16 yields 65535.
8. Widening an unsigned source is physically zero extension, including when the
   destination is signed: u8(255) as i16 yields 255.
9. Narrowing is physically truncation regardless of either signedness:
   i16(-129) as i8 yields 127; u16(65535) as i8 yields -1.
10. These physical rules derive from the single modulo rule; they are not
    independently defined source-language conversion operations.
11. Integer VectorType conversion applies the identical scalar rule lane-wise.
12. Vector conversion preserves lane count, and both shapes must already be
    supported by VEC-1. The 128-bit numeric shape limit does not expand.
13. One conversion remains one semantic operation, one Core value, one CFG
    conversion, one SSA conversion and one exact destination vector SSA value.
    No semantic extract/convert/insert decomposition is introduced.
14. No bool/integer conversion exists. bool<N> masks are not unsigned one-bit integers.
15. No f32/integer conversion exists, for scalars or vectors.
16. No pointer/integer conversion exists. Nominal Resource types and struct
    values also do not participate; a physical PTR representation grants no capability.
17. No C ABI change is required. Exact-width C integer channels remain deferred.
18. No NABI profile or channel change is required; vector-v4 and the four scalar
    profiles remain unchanged. A body-only conversion does not change a signature.
    VAPI and source-extern support are unchanged.
19. LLVM sext/zext/trunc/identity are backend realizations only. Same-width
    signedness needs no bitcast because LLVM integers do not encode signedness.
20. Future saturating conversion must be a distinct semantic operation. Wrapping
    `300 as u8` produces 44, whereas saturation would produce 255.
21. Future split widening of full-width vectors must reuse this scalar conversion
    authority. i8<16> cannot currently widen to i16<16>; later widen_low/widen_high
    or equivalents must select lanes separately from their numerical conversion.
22. Generic code must later treat explicit conversion capability separately from
    ordinary same-type arithmetic. Do not assume arbitrary T supports `as U`.

## Source typing and parsing

`as` is reserved. Conversion is a postfix-like, left-associative operation at
binding power 25: below unary `+ - !` (30), above `* / %` (20), `+ -` (10),
comparisons and logical operations. Thus `-1 as u8` converts int(-1),
`x as i16 + y` means `(x as i16) + y`, `x + y as i16` means `x + (y as i16)`,
and `x as i16 as u32` means `(x as i16) as u32`. Each chain step is retained.
Parentheses and constant lane extraction compose with a conversion naturally.

The operand is checked without destination or surrounding expected-type context.
A context-free integer literal therefore defaults to int. `256 as u8` is int(256)
converted to zero; `u8 x=256` still rejects. `4294967295 as u32` rejects because
its int source cannot form; `u32 x=4294967295; x as int` converts that valid u32.
An already typed result provides ordinary context to subsequent expressions,
such as `(i8_value as i16)+1`, whose `1` is i16. No suffixes, C-style syntax,
function-like casts, or generic syntax are introduced.

Expression-position type parsing uses two-token lookahead: a complete
`<decimal-integer-literal>` is a vector suffix; otherwise `<` is comparison.
After a named type, `*` followed by an expression starter is multiplication;
a terminal `*` is retained as pointer type syntax and rejected semantically.
Whitespace does not change either rule. Complete vector suffixes take priority
in the ambiguous `x as i16 < 4 > y`; use `(x as i16) < 4` when comparing with a
literal before another `>` expression. Declaration type parsing is unchanged.
This limited lookahead avoids treating ordinary `x as i16 * y` as a pointer
conversion and avoids introducing type-name resolution into the parser.

## Representation and evaluation

Dedicated CheckedIntegerConversionExpression, CoreIntegerConversionValue,
CfgIntegerConversionInstruction/Value, and SsaIntegerConversionInstruction retain
one operand, exact source and destination types, and source provenance. The
small IntegerConversion capability authority validates integer scalars or valid
integer vectors with equal lane counts. IR verifiers additionally check that the
declared source type equals the actual operand type and that operands are valid
and available. Immutable type objects and SourceSpan survive stage destruction
without retaining syntax, checked symbols, or upstream IR nodes.

The operand evaluates exactly once at its normal position. Conversion itself is
pure, non-trapping and allocation-free. CFG evaluates it through the existing
value-evaluation instruction authority, before subsequent operands and before an
owned-call transfer commit. Nested operand calls retain their existing effects,
traps, captures and transfer order. Conversion introduces no Place, memory,
addressability or ownership transition; ordinary destination-type locals, block
parameters, struct field stores and native call arguments consume its result.

A dedicated integer node is preferable to a generic numeric-conversion tag here:
float conversion has no defined policies, so a generic node would expose cases
with no authority. Scalar and vector conversions share the node because arity,
evaluation, type retention and the numerical rule are identical. No physical-kind
enum is needed; width and source signedness already determine lowering.

## Oracle, backend derivation and host independence

AstraIntegerValue.convert_to obtains V from its existing exact mathematical_value,
uses int64 remainder with the destination modulus, then adds that modulus to any
negative remainder. All supported values and moduli fit int64. Only the resulting
nonnegative, representable residue is converted to uint64. No host signed
narrowing, overflowing host signed arithmetic, or implementation-defined C sign
conversion determines a language value. Tests independently check low-bit masks,
high-bit extension regions and destination mathematical interpretation.

For narrowing, `2^N` divides the source modulus, so reducing V leaves exactly the
low N source bits. For widening a nonnegative source, its bits already encode V
and high bits are zero. For a negative source of width M, its bits encode `V+2^M`;
the wider residue is `V+2^N`, so filling bits M through N-1 with ones adds precisely
`2^N-2^M`. This proves trunc/zext/sext implement the rule for either destination
signedness. Equal width leaves the residue unchanged. The same proof applies to
each lane of a whole LLVM vector cast. No arithmetic emulation, pointer casts,
float casts, overflow flags or constant folding is required. Register width,
endianness and target instruction selection do not define conversion semantics.

## Deferred capabilities

Float conversions must separately choose integer-to-f32 rounding and f32-to-integer
fractional rounding/truncation, NaN, infinity and out-of-range behavior. LLVM
instructions cannot supply those missing language decisions. Packing must
explicitly distinguish wrapping narrow from saturating narrow. Split widening,
packing/interleave, dot products and MAC must separately define their shape,
selection, multiplication and accumulation policies; this decision supplies only
the per-lane integer conversion rule. No bitwise operations, shifts, saturation,
widening multiply, packing, dot/MAC, ownership redesign or ABI expansion begins here.

See [language rules](../language/integer-conversions.md) and
qualification.
