# ADR 0124: explicit hosted f32/f64 decimal conversion

Status: implemented and qualified in the bounded Surge 7 U4 scope; campaign integration remains open.

`text/float-format.astra` supplies `format_f32`/`format_f64`, returning an owned
`Utf8Message` through the existing checked error channel, and checked scalar
`parse_f32`/`parse_f64`. Select it explicitly with the existing Error root and
Utf8Message library. Link the optional `float-text-posix.o` provider and `m`.
Unused programs acquire no new linked runtime dependency. The provider is bounded
to GNU x86-64 LP64 Linux with IEEE binary32/binary64.

The selected decimal contract is 9 significant digits for binary32 and 17 for
binary64, using C-locale `%g` formatting. This is a round-trip representation,
not a shortest-string promise. Finite outputs round-trip to identical scalar bits
under round-to-nearest/ties-to-even. Positive zero formats as `0`, negative zero
as `-0`. Infinities format as `inf`/`-inf`; every NaN formats as `nan`, with no
payload or sign preservation guarantee. Exponents use lowercase `e`, a sign and
the hosted libc's decimal exponent digits. No relaxed FP or contraction is added.

Parsing accepts counted ASCII decimal text with optional sign, digits before or
after a decimal point (at least one required), and an optional signed decimal
exponent. Examples include `1`, `.5`, `+5.`, `-0`, and `1.25e-8`. Whole input must
match. Whitespace, comma separators, hex, NaN payloads, trailing bytes, embedded
NUL, and non-ASCII input reject. Explicit special inputs are exactly `nan`, `inf`,
`+inf`, and `-inf`. Binary32 uses direct `strtof_l`, avoiding double rounding.

Representable subnormal results are accepted, including gradual underflow.
A finite decimal that rounds to infinity raises overflow; a nonzero mantissa
that rounds to zero raises underflow. A zero mantissa with an arbitrarily large
exponent remains signed zero. Existing checked ownership cleanup applies to all
error paths. `NumericTextError.reason` identifies invalid input (1), overflow (2),
underflow-to-zero (3), provider scratch/locale allocation failure (4), unsupported
rounding mode (5), or insufficient provider output storage (6). Formatting's
fixed 32-byte stack buffer covers this contract; the returned message owns its
separately validated/copied UTF-8 bytes. Parsing uses explicit provider scratch.

Conversions require the existing default nearest rounding mode. They check and
reject another mode without changing it. Numeric locale isolation uses a private
C locale: formatting temporarily selects it for the calling thread and restores
the previous locale; parsing passes it directly to libc. There is no global
`setlocale` in the provider, cached locale lifetime, locale daemon, or new source
literal parser. Test-only code explicitly changes process locale and rounding to
exercise these boundaries. Standard floating exception flags are not promised
unchanged by conversion.

The public wrappers reuse the qualified counted u8 slice, counted UTF-8, f32/f64
C scalar, and borrowed natural POD pointer transports. No C ABI or ownership
default is revised. Provider code and portable build recipe live in Git; generated
oracles, objects, instrumented LLVM and receipts remain in the external build area.
Qualification compares independent Python decimal strings and exact scalar bits
for 320 selected values of each width, in actual C and French Canadian numeric
locales, then checks midpoint rounding, subnormal/extreme values, errors, signed
zero, native O0/O1/O2, Valgrind, and ASan/UBSan with their explicit coverage limits.

Fresh qualification passed 31 command checks, three public optimized executables,
three clean unsuppressed Valgrind runs, one native LLVM ASan executable, and one
sanitized C provider-guard executable. Three independent native/C/LLVM mutation
and restoration groups passed, including structurally plausible same-sized POD
field substitution. The existing `cabi-fp-native-execution` registration passed.
Formatter qualification also covers the actual library and native witness source.
No allocation-failure injection or other-host libc behavior is inferred.
