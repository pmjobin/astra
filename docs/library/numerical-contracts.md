# Numerical and assertion contracts

These are ordinary Astra signatures; they require no overloads or extra generic
capabilities:

```astra
T min<T>(T a, T b) where T : Ordered
T max<T>(T a, T b) where T : Ordered
T clamp<T>(T value, T lower, T upper) where T : Ordered
bool is_nan_f32(f32 value)
bool is_nan_f64(f64 value)
bool is_finite_f32(f32 value)
bool is_finite_f64(f64 value)
bool is_infinite_f32(f32 value)
bool is_infinite_f64(f64 value)
void assert(bool condition)
void assert_code(bool condition, int code)
void assert_equal_i32(int actual, int expected, int code)
void assert_equal_f32(f32 actual, f32 expected, int code)
void assert_equal_f64(f64 actual, f64 expected, int code)
```

## Ordered domain and selection

The capability authority admits `i8/u8/i16/u16/int/u32/f32/f64`. `i32` aliases
`int`; there is no i64/u64. Ordered authorizes `< <= > >=`, returning scalar
bool. It does not grant Eq. Eq separately authorizes `== !=` for these scalars,
bool and void*. Vectors, masks, aggregates, typed pointers, slices, classes and
resources do not gain Ordered from being copyable or usable in another context.

Both selection functions first test `!(a <= a)`, then `!(b <= b)`. They return
the first self-unordered operand. Min then selects b only if `b < a`; max selects
b only if `a < b`. Otherwise both select a. No subtraction, arithmetic, numeric
conversion or implicit promotion occurs.

| Inputs | min | max |
| --- | --- | --- |
| NaN, ordered | First operand's NaN | First operand's NaN |
| ordered, NaN | Second operand's NaN | Second operand's NaN |
| NaN A, NaN B | A | A |
| Equal ordered values | First operand | First operand |
| +0, -0 | +0 | +0 |
| -0, +0 | -0 | -0 |
| Integer extrema | Ordinary least value | Ordinary greatest value |

These are not C fmin/fmax aliases. Selected quiet-NaN bits are transported under
the existing qualified Astra policy; no new signaling-NaN exception or payload
guarantee for arithmetic is created.

## Checked clamp

`!(lower <= upper)` fails with hook kind 2, code 0. Reversed bounds and either
NaN bound fail. Ordered infinite bounds and equal bounds are valid. Then a value
below lower selects lower, a value above upper selects upper, and all other
values select the original value. Thus a NaN value with valid bounds propagates;
an in-range signed zero keeps its original sign, even with opposite-sign zero
bounds. There is no saturation cast.

All arguments evaluate once, left-to-right, before validation. A bound check does
not suppress those evaluations. Use `clamp(value, 0.0d, 1.0d)` for f64. Standalone
unsuffixed real arguments are f32; no target-literal inference or promotion makes
conflicting arguments agree. Explicit/inferred requests deduplicate in the same
specialization registry, including accepted exact outer T propagation.

## Classification

`value != value` identifies NaNs. Comparisons against exact positive/negative
maximum finite literals identify finite values; infinity is `!nan && !finite`.
No exceptional arithmetic, source bitcasts or C classification macros occur in
the library.

| Exact input category, either sign | is_nan | is_finite | is_infinite |
| --- | --- | --- | --- |
| Zero | false | true | false |
| Subnormal | false | true | false |
| Normal, including maximum finite | false | true | false |
| Infinity | false | false | true |
| Quiet or signaling NaN | true | false | false |

The source writes exact integer decimal expansions with `.0f`/`.0d` suffixes.
The independent rational oracle derives `(2^24-1)*2^104` and
`(2^53-1)*2^971`, then checks the accepted literal authority and runtime boundary
patterns: f32 `0x7f7fffff`, f64 `0x7fefffffffffffff`. Both adjacent predecessor
patterns and the following infinity patterns are covered. The negative limits
are `0xff7fffff` and `0xffefffffffffffff`. No fast math or floating exception-state
promise is added.

## Assertions

`assert` and `assert_code` are eager functions, active in every build mode. True
returns without a failure call. False calls the hook once with kind 1; `assert`
uses code 0, and `assert_code` forwards the exact signed int, including extrema.
There is no NDEBUG or debug-only removal. Ordinary optimization can remove proven
work while preserving condition and argument side effects.

Assertions do not acquire ownership. Failure terminates without unwinding local
owners, RAII fields or buffers. Successful assertions retain normal later
cleanup. There is no recovery by exception, longjmp or return.

Hosted equality assertions use ordinary numeric equality: +/-0 are equal and
NaNs unequal even to themselves. Mismatch reports width, code, expected/actual
numeric values and floating raw hexadecimal bits. These APIs are neither bit
equality nor approximate equality. Case codes are the caller's diagnostic link;
automatic caller locations and source expression capture remain future work.
