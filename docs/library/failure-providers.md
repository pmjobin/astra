# Explicit failure providers

The shared source declaration is:

```astra
extern(C) void astra_base_fail(int kind, int code);
```

The library contract requires abnormal termination, never returning or unwinding.
Kind 1 means assertion failure; kind 2 means invalid clamp bounds. Default code is
0; `assert_code` forwards the caller's exact int. These protocol numbers are
documented here and written as literals in source; Astra const is not introduced.

`failure.h` uses int32_t and static assertions establishing the qualified C int
boundary. There are no bool, unsigned, string, pointer or callback channels.
Hosted equality adds these exact non-returning C functions:

```c
_Noreturn void astra_base_equal_i32(int32_t code, int32_t actual, int32_t expected);
_Noreturn void astra_base_equal_f32(int32_t code, float actual, float expected);
_Noreturn void astra_base_equal_f64(int32_t code, double actual, double expected);
```

Only C provider implementations receive `_Noreturn`. Astra imports retain their
ordinary conservative effects and have no spelling-based compiler attributes.
Returning, exceptions and longjmp recovery violate this static interface.

## Trap-only

Explicitly link `build/lib/astra/failure-trap.o`. Its implementation uses GCC's
actual trap builtin. GCC documents that its implementation can vary by target
and may call abort, so builtin spelling alone is not qualification.
The measured GCC 16.2.1 x86-64 Linux object emits `ud2`, with no abort fallback,
calls, returns, allocation, formatting or undefined symbols. A linked contract
witness has no CRT/libc, dynamic dependency or undefined runtime symbol, and both
successful and fatal paths execute. This observation does not mandate that every
future compiler emit that opcode. See [GCC's builtin contract](https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html).

Meson builds the supplied providers only with native GCC x86-64 Linux; the C
files also gate their qualified targets. Other compilers/targets require explicit
qualification and are not silently given a libc fallback. `target.txt` records
the build target and C compiler. Do not reuse the object for another target.
A future board can supply this same static interface without language changes.

The ordinary compiler CLI still links through the host driver and CRT. The
qualification's `tests/baselib/fixtures/start.S` is a Linux test entry, not a
new public freestanding CLI option or a library runtime.

## Hosted

Explicitly link `build/lib/astra/failure-hosted.o` instead. It writes the family,
kind and code to stderr and calls abort. Equality reporters additionally print
typed expected/actual evidence. Floating bit inspection uses memcpy; decimal
fields use enough significant digits for each width, but hexadecimal fields are
the authoritative representation evidence. No global locale is changed.

For example, the deliberate mismatch consumer reports:

```text
astra base: equality f64 code=204 expected=1.5 actual=1.25 expected_bits=0x3ff8000000000000 actual_bits=0x3ff4000000000000
```

Writes and flushing are best effort. The `/dev/full` failure witness still
terminates abnormally. No particular signal number is part of the API. No local
owners, fields or buffers are unwound. Hosted libc/stdio internals may allocate;
this component is not advertised as heap-free.

Select exactly one provider. Missing support produces a normal unresolved symbol
error for a live failure call; linking both strong definitions produces a normal
duplicate-symbol error. There is no weak override, registry, callback, dynamic
selection, automatic detection or compiler injection. Header metadata and source
selection do not cause linking.

No source strings, arbitrary messages, formatting language, automatic caller
file/line, expression text or stack traces exist. Adapter source locations are
never presented as the assertion's call site.
