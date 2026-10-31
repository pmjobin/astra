# Optional hosted math

Select `lib/astra/hosted/math.vapi` and explicitly pass `--link-library m`.
VAPI uses existing float/double grammar and CCode cname/cheader_filename metadata;
the header name describes the declaration and performs no parsing or autolinking.

| Astra public signature | C symbol/signature |
| --- | --- |
| `f32 sqrt_f32(f32 value)` | `float sqrtf(float)` |
| `f64 sqrt_f64(f64 value)` | `double sqrt(double)` |
| `f32 floor_f32(f32 value)` | `float floorf(float)` |
| `f64 floor_f64(f64 value)` | `double floor(double)` |
| `f32 ceil_f32(f32 value)` | `float ceilf(float)` |
| `f64 ceil_f64(f64 value)` | `double ceil(double)` |
| `f32 trunc_f32(f32 value)` | `float truncf(float)` |
| `f64 trunc_f64(f64 value)` | `double trunc(double)` |
| `f32 abs_f32(f32 value)` | `float fabsf(float)` |
| `f64 abs_f64(f64 value)` | `double fabs(double)` |

These are thin declarations, not wrappers, intrinsics or new arithmetic operators.
No integer abs is included: INT_MIN policy is undesigned. No trigonometry,
exp/log/pow, FMA, varargs, pointers, long double or new ABI profile is introduced.

## Three separate contracts

1. Astra primitive arithmetic, literals and explicit conversions are unchanged.
2. Astra-to-C transport retains CABI-FP-1's exact binary32/float and
   binary64/double channels, qualified only on x86-64 Linux. Foreign declarations
   retain their conservative effects and the existing target gate, including
   unused declarations. No readnone/readonly/noexcept/noreturn attribute or
   name-based intrinsic rewrite is added.
3. Results and domain behavior come from the selected C library. This campaign
   qualifies Fedora x86-64 Linux, GCC 16.2.1, LLVM 22.1.8 and glibc/libm 2.43.
   It does not implement a universally bit-identical Astra math library.

Execution uses round-to-nearest, ties-to-even, masked floating exceptions and
preserved subnormals (FTZ/DAZ off). The test inspects fegetround/MXCSR without
changing them. The library does not change rounding mode, errno, floating
exception flags/masks, FTZ/DAZ or global locale. C library calls may have their
usual errno/exception effects; no Astra trap or exception is synthesized from them.

## Qualified numerical behavior

Floor/ceil round to the lower/upper integral floating value; trunc rounds toward
zero. Their zero results retain the applicable sign. Abs clears a finite or
infinite value's sign, including turning -0 into +0. Sqrt preserves signed zero,
returns +infinity for +infinity, and returns a domain NaN for negative nonzero
inputs. Classification/assertions can handle that NaN. NaN results are tested by
classification; no unspecified payload identity is promised.

The independent oracle in `tests/baselib/oracle.py` decodes bits to Python exact
integers/rationals. It computes floor/ceil/trunc without any out-of-range C cast.
For sqrt it brackets the exact result between adjacent representable values and
compares the input against the exact square of their midpoint, resolving ties
to even. It tests exact squares, nonsquares, fractions of both signs, signed
zeros, subnormals, finite extrema and nonfinites. This is separate from a C
companion invoking the same libm provider as binding/transport evidence. Every
Astra input arrives at runtime across an opaque C call; optimization cannot turn
the boundary test into a constant-only calculation.

Glibc's accuracy policy singles out sqrt's IEEE operation while declining general
correct rounding for all math functions. This qualification requires exact bits
for the specified finite cases, not exhaustive proof for every input, target or
libc release. See the primary [accuracy policy](https://sourceware.org/glibc/manual/latest/html_node/Errors-in-Math-Functions.html),
[rounding functions](https://sourceware.org/glibc/manual/latest/html_node/Rounding-Functions.html),
[absolute value](https://sourceware.org/glibc/manual/latest/html_node/Absolute-Value.html)
and [domain/error behavior](https://sourceware.org/glibc/manual/latest/html_node/Math-Error-Reporting.html).

Fixed-source compilation is deterministic for the qualified toolchain. Different
libc versions or targets need not produce identical bytes. Preserved-call tests
and optimizer-freedom O0/O2/+FMA tests are distinct; no fast math or contraction
policy is changed and no particular math machine instruction is mandated.

## Named library CLI

`--link-library NAME` and `--link-library=NAME` are repeatable. Names match
`[A-Za-z0-9][A-Za-z0-9_.-]*`: empty names, leading option markers, paths, spaces,
control characters, shell syntax and raw linker flags reject. The narrow grammar
deliberately excludes names such as `stdc++`; this is not a universal linker
escape hatch. No `-L`, rpath, environment mutation or search policy is added.

Object/library occurrences retain user order and repetitions, whether before or
after source arguments. The generated Astra object comes first, then that stream,
then the existing mandatory `-o OUTPUT` pair. The process uses argv directly.
Check/dump modes reject executable-only link inputs and never invoke a linker.
Failed links preserve an existing output and remove the temporary sibling
directory. There is no automatic -lm or transitive library discovery.
