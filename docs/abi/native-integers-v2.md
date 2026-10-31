# Native integer ABI v2

[GEN-1](../ir/generics.md) uses these channels only after concrete substitution.
A generic definition has no native ABI. int/i32 aliases request one semantic
instance; i8/u8, i16/u16 and int/u32 request distinct instances even when LLVM
integer widths match. Each concrete signature contributes its ordinary profile
requirements to the accepted program-wide effective profile; GEN-1 adds none.

`NativeAbiVersion.SCALAR_INT_V2`, dumped as `scalar-int-v2`, subsumes the
[scalar-v0](native-scalar-v0.md) and [scalar-ptr-v1](native-pointer-v1.md)
capabilities. It is an internal native transport contract, with no stable
external, separate-compilation, register-placement, or C ABI promise.

| Semantic type | Native channel | LLVM realization |
| --- | --- | --- |
| i8 | I8 | i8 |
| u8 | U8 | i8 |
| i16 | I16 | i16 |
| u16 | U16 | i16 |
| int / i32 | I32 | i32 |
| u32 | U32 | i32 |
| i64 | I64 | i64 |
| u64 | U64 | i64 |
| isize (qualified host) | I64 | i64 |
| usize (qualified host) | U64 | i64 |
| bool | B1 | i1 |
| void*, native Struct*, nominal Resource | PTR | ptr |
| void result | no result | void |

I8/U8, I16/U16, I32/U32, and I64/U64 are distinct physical channel identities.
Host-size identities remain distinct in semantics and checked IR, then use the
qualified corresponding wide physical channel. LLVM's
shared integer width does not erase NABI signedness. Semantic checking and SSA
retain exact semantic identity before this mapping; NABI inserts no conversions.
Owned/borrowed parameter and result contracts remain upstream authority, while
native functions and calls use the existing internal/fastcc realization.

Profile selection inspects native signatures across the complete program:

- Any noncanonical integer parameter or result, including wide and host-size
  identities, selects scalar-int-v2, with or without PTR.
- Otherwise any PTR parameter or result selects scalar-ptr-v1.
- Otherwise the profile remains scalar-v0, including explicitly spelled i32.

Body-only locals, fields, constants, and arithmetic do not select a profile.
All signatures in a sidecar share its profile. v0 rejects PTR and the new integer
channels; v1 rejects the noncanonical integer channels; v2 permits all ten physical
channel identities.
Old source retains its previous native dumps byte-for-byte.

For `u8 narrow(u16 x, i8 y)`, the signature has U16 and I8 parameters and a U8
result, under scalar-int-v2. No width/sign information is reconstructed from
source spelling. Completed NativeAbiProgram, NativeSignature, verifier, and dump
remain independent of semantic types, SSA, and LLVM; semantic types may die.

The backend realizes constants from `AstraIntegerValue.bits`, preserves native
width in arithmetic/phis/storage, and chooses signed or unsigned operations from
semantic integer authority. See [integer semantics](../language/integers.md)
and [LLVM lowering](../backend/llvm-scalar-v0.md#exact-width-integers).

The wider C ABI separately qualifies int64_t/uint64_t and host-size C channels
on GNU/Linux x86-64 LP64, using actual target-data pointer width plus independent
C witnesses. This does not extend the narrow C ABI: LLVM i8 alone makes no
portable C int8_t/uint8_t argument-extension promise. See
[qualified host integers](../language/integers.md#qualified-host-sizes-and-diagnostics).
No C long alias or portable cross-target size contract is inferred.

## Floating profile precedence

F32-1 preserves v0/v1/v2 behavior for signatures without f32. If any native
parameter/result is f32, [scalar-fp-v3](native-f32-v3.md) takes precedence and
also supports every v2 channel. Body-only f32 values do not select v3. Integer
channel identities and narrow C integer deferral are unchanged.
