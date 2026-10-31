# 0036: Compiler-owned binary32 semantics

Status: accepted for ASTRA-F32-1.

## Decision

Introduce one canonical F32Type and immutable AstraF32Value with exact uint32
binary32 bits. Arithmetic rounds to nearest/ties-even after each operation;
signed zero, subnormals, infinity, and NaN are valid. NaN comparisons are explicit
language semantics; payload/sign/signaling construction are not exposed.
There is no arithmetic constant-folding requirement. Existing scalar operators,
Places, field memory, promotion, and SSA carry f32 without parallel machinery.

LLVM float realizes this authority. Constants use LLVMConstInt(i32, bits) followed
by LLVMConstBitCast to float. No host float/double or decimal LLVM parser is used.
Ordinary fadd/fsub/fmul/fdiv/fneg have no fast-math permissions. Comparisons use
oeq/une/olt/ole/ogt/oge, with UNE required for NaN inequality. Floating division
never calls the integer zero-divisor lowering. Native F32 selects scalar-fp-v3;
CABI remains unchanged and C float signatures reject.

## Exact decimal conversion and bound

Decimal-to-double-to-float can round twice. Libc strtof and LLVM decimal parsing
also cannot define frontend semantics. General arbitrary-precision arithmetic
would solve this problem but adds unnecessary infrastructure for one format.
Instead, compare the source decimal with exact binary32 rounding midpoints.

Positive finite binary32 encodings are monotonically ordered. For the value at
encoding b, let m be its integer significand and e its binary exponent. Its next
representable neighbor is one unit of 2^e away, including the exponent transition.
The midpoint is (2m+1)*2^(e-1). For subnormals e=-149; for normal exponent field E,
e=E-150. Thus midpoint coefficient is at most 2^25-1 and exponent lies in
[-150,103]. At max finite the notional upper value is 2^128; its midpoint is
340282356779733661637539395458142568448. At or above that threshold the result
is infinity. Below it the result can still be maximum finite.

Every midpoint has a terminating decimal. For a negative power -k, multiply the
coefficient by 5 exactly k times and give it decimal scale -k. For a positive
power, multiply by 2. A little-endian decimal digit buffer suffices:
(2^25-1)*5^150 < 10^113, so 113 digits cover every midpoint. Individual multiply
and carry operations never exceed 49. No arbitrary-precision division or
unbounded power construction exists in production.

Scan all source characters to validate the grammar and identify the first
nonzero digit. Retain the first 113 significant digits, decimal order, and a
sticky flag recording any nonzero digit beyond the buffer. Comparing decimal
orders and zero-padded coefficients is exact: if all retained digits equal a
midpoint, that midpoint has no remaining nonzero digits, so sticky alone decides
whether the source is larger. This remains correct with arbitrarily long zero
runs and a final nonzero digit. This truncation is not a numerical rounding step.

The exponent scanner saturates at source byte length + 512 in int64. Even a
mantissa cancelling every source digit cannot bring a saturated exponent back
into binary32 range. Decimal order above 39 is certainly infinity; below -45 is
certainly zero. All syntax is validated before early classification, including
zero mantissas. No huge power of ten or host exponent parse is needed.

Binary search over [0,0x7f800000] takes at most 31 midpoint comparisons. At a tie,
the low encoding bit identifies significand parity. Select the even neighbor;
the notional upper neighbor of max finite selects infinity. Source unary minus
then toggles the result sign. Complexity is O(source length) plus bounded
midpoint work; auxiliary storage does not grow with source length.

## Qualification and consequences

Known bits include both tie directions near 1, signed zero, minimum subnormal,
minimum normal, maximum finite, infinity, and underflow. An independent Python
oracle instead quantizes exact rational numerator/denominator using binary
exponents and quotient/remainder rounding. A second, test-only C executable uses
strtof under C locale and FE_TONEAREST with binary32 host-format assertions.
The corpus probes every exponent band and the three sides of midpoint boundaries,
random decimal spellings, long sticky tails, and exponent cancellation. Production
conversion is also executed under installed comma-decimal process locales.

LLVM's [default environment](https://releases.llvm.org/22.1.0/docs/LangRef.html#floating-point-environment)
requires nearest rounding and preserved subnormals with unobservable flags.
Its [default denormal attribute](https://releases.llvm.org/22.1.0/docs/LangRef.html#fnattrs)
is ieee/ieee, so no extra attribute or constrained intrinsic is required.
The [contract permission](https://releases.llvm.org/22.1.0/docs/LangRef.html#fast-math-flags)
is absent. The [constant bitcast C API](https://llvm.org/doxygen/group__LLVMCCoreValueConstantExpressions.html)
is qualified by round-tripping exact bits, including subnormals, signed zeros,
infinities, and NaNs. NaN arithmetic payloads remain outside the source contract.

Only the default x86-64 Linux host emission configuration is qualified for f32 in
this milestone. Other f32 targets reject until they prove the same precision,
subnormal, and non-contraction behavior. Foreign code must restore the required
default environment after changes; dynamic rounding and exception flags are not
Astra state. No production dependency or ownership/CFG/dominance redesign follows.

Future numeric conversions need their own exact rounding/range policy. C float
ABI needs explicit target qualification. Future short vectors must reuse this
scalar lane authority. F64, casts, vectors, FMA, and fast math are not implemented.
