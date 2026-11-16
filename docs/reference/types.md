# Types and numerical values

R-TYPES. Types have exact checked identities. `int` and `i32` name one signed
32-bit semantic type; `bool` is distinct from all integers. Scalar integers
cover signed/unsigned 8, 16, 32 and 64 bits, with separate host-size `isize` and
`usize` identities on the qualified 64-bit host. `f32` and `f64` have separate
floating widths. `void` is a result channel rather than a local value.
`string` is counted borrowed UTF-8, not an arbitrary mutable byte array.

| Family | Width | Identity boundary |
| --- | --- | --- |
| i8 / u8 | 8 | signed and unsigned remain different types |
| i16 / u16 | 16 | no implicit promotion to int |
| int, i32 / u32 | 32 | int and i32 share identity |
| i64 / u64 | 64 | no implicit conversion from int |
| isize / usize | 64 on this host | distinct from i64/u64 |
| f32 / f64 | 32 / 64 | no implicit mixed-width arithmetic |

R-NUMERIC. A literal receives context from a destination or typed operand.
Contextualization does not convert an already typed value. Use explicit `as`
for supported numeric conversions; conditions require scalar bool. Integer
addition, subtraction and multiplication wrap at their exact width. Signed
division truncates toward zero. Division by zero traps. Shift counts must fit
the operand width; signed right shift fills the sign, unsigned right shift
fills zeroes. Invalid dynamic counts must not reach unchecked LLVM operations.

Integer casts preserve destination-width interpretation. Floating-to-integer
conversion checks finite, representable truncated values. Bounds checks use
mathematical indices rather than a narrowing cast. This edition grants no
implicit floating reassociation, fast math or fused-operation promise.

## Structural and nominal types

Records, classes and enums retain declaration identity, not merely spelling or
physical layout. Generic applications retain exact arguments and ownership
channels. Arrays, ranges, shared handles and callable descriptors have
structural forms that require separate native storage admission. Internal
`TypeId` ordinals are meaningful only with their originating table; equal
numbers from separate tables do not establish equivalence.

R-TYPE-BOUNDARY. Existing vector, typed-pointer and callable frontend syntax is
not a blanket native guarantee. [Limits](limits.md) includes actual refusals of
simple vector and typed-pointer programs. Older SIMD and foreign-framework
manuals retain historical scope until exact forms receive current native
qualification. The Guide's working numerical workload uses scalar calculations
and fixed arrays, with expected data checked independently of the compiler.

## Integer edge cases and conversion domains

R-NUMERIC-EDGES. For exact signed width, division of MIN by -1 yields MIN and
its remainder is zero. This wrap case is handled explicitly before any invalid
LLVM division. Other signed division truncates toward zero, with remainder
having the dividend's sign. Integer division by zero is fatal. Dynamic shifts
are guarded before width normalization; the admissible count is from zero
through width minus one. These rules apply to the checked source domain, not
to an unchecked C expression or LLVM poison value.

Floating arithmetic retains scalar width and ordinary IEEE comparisons.
NaN does not compare equal to itself. Negative zero is observable, and this
edition grants no reassociation or fast-math permission. Float-to-integer casts
check the mathematical truncation interval before conversion; nonfinite or
out-of-range values take a fatal path. Integer narrowing and widening follow
the exact destination bit width and signed interpretation. Bounds checks do
not substitute a narrowing conversion for a mathematical range check.

The Guide's [numeric edge program](../guide/values.md#checking-the-numeric-contract)
checks signed/unsigned wrap, MIN division/remainder, signed remainder, both
right-shift forms and positive/negative truncation. The implementations include
[integer guards](../../compiler/backend/llvm/recover-integer-check.astra),
[shift guards](../../compiler/backend/llvm/recover-shift-check.astra) and
[float conversion checks](../../compiler/backend/llvm/recover-float-integer-check.astra).

Exact type identity also applies at a generic result. A completed `u8` value
and an `int` local do not acquire a common promoted type:

```astra example=negative-numeric-mix
language astra27b;
int main() {
	u8 small = 20;
	int wide = 22;
	return small + wide;
}
```

When a literal has insufficient surrounding context, introduce an explicitly
typed expected value. The [generic teaching example](../guide/generics-match.md#constraints-at-concrete-calls)
uses that approach. This makes the required domain visible without adding an
implicit conversion rule.
