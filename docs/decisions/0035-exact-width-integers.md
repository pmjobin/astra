# 0035: Exact-width integer semantics and native transport

Status: accepted for ASTRA-INTS-1.

## Context

Astra's existing `int` is exact signed 32-bit. Narrow and unsigned native
arithmetic needs semantic width/sign authority before physical lowering,
without changing ownership, Places, CFG, scalar promotion, or ABI boundaries.

## Decision

Introduce canonical `IntegerType` objects for i8/u8/i16/u16/i32/u32 per
BuiltinTypes universe. Preserve the legacy TypeKind.INT tag for I32 and resolve
both `int` and `i32` to that same object. Debug display remains `int`; no alias
comparison or seventh numeric type exists. New TypeKind tags keep existing
CABI's int-only acceptance closed without editing CABI production sources.
IntegerType derives immutable width, signedness, minimum, maximum, modulus, and
mask from compiler-defined identities. Host and LLVM sizes supply none of them.

Use one immutable `AstraIntegerValue` authority: exact IntegerType plus a uint64
bit pattern bounded by 2^N-1. All arithmetic explicitly computes residues modulo
2^N, with safe wider intermediates. The largest possible product,
(2^32-1)^2, fits uint64 without overflow; signed interpretation and division use
safe int64 magnitudes. Preserve AstraIntValue as an i32-only facade delegating
to this authority. Legacy IR fixture constructors bind that i32 value to their
type universe; new `.typed` constructors carry complete exact values. Verifiers
reject value/type identity disagreement, including equal-width sign mismatch.
No arithmetic implementation is duplicated.

Decimal spelling remains in syntax until the semantic expected integer type is
known. Existing expected-type parameters carry local/assignment/return/argument/
field context into same-type arithmetic. A read-only type probe finds declared
operand types, symmetrically and through nested arithmetic, before the ordinary
left-to-right checker runs. It never evaluates, changes ownership state, emits
diagnostics, crosses comparison result boundaries, or types a call's arguments.
Literal-only trees default to int. No already typed value changes identity.
Direct negative decimal formation admits signed MIN, including parentheses;
unsigned unary minus rejects. No downstream stage reparses source text.

Core, CFG, and SSA retain exact types/values using their existing generic nodes
and storage paths. Scalar promotion and addressable struct lowering require no
width-specific IR architecture. NABI adds I8/U8/I16/U16/U32 and scalar-int-v2;
profile selection is signature-based and preserves old v0/v1 dumps. LLVM uses
exact i8/i16/i32 arithmetic without nsw/nuw, signed/unsigned ordering, and guarded
sdiv/srem or udiv/urem. Signed MIN/-1 uses the existing special path generalized
to N bits. Every split continues to update the existing physical end-block
authority used for phi incoming predecessors.

## Alternatives and consequences

Making int distinct from i32 would violate alias identity and require needless
conversions; changing canonical display would churn established goldens.
Parsing every literal as int first would reject valid contextual u32 maxima and
narrow literal-only expressions. Rechecking operands in a different order would
risk ownership/effect ordering. Widening all operations would erase useful width
semantics. Separate signed/unsigned arithmetic implementations would duplicate
correctness authority. These alternatives are unnecessary with the chosen model.

C exact-width support remains deferred because target extension contracts and C
source mappings require an explicit design. Existing int/i32 C support and
resource ownership contracts remain intact. No production dependency, physical
struct layout guarantee, or new ownership mechanism is added.

Future floating point needs its own semantic value rules. Explicit conversions
must define source/destination identity, representability, and extension or
truncation deliberately; contextual literals do not establish conversion rules.
Bitwise/shift work can reuse exact integer bits but must define counts and signed
behavior. Short vectors can retain these same scalar IntegerTypes as elements.
