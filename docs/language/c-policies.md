# Explicit C function policies

The compiler recognizes selected top-level function `[CImport]` and `[CExport]`
declarations through the canonical declaration registry:

```astra
[CImport(name="abs", header="stdlib.h")]
int magnitude(int value);

[CExport(name="application_magnitude")]
int magnitude_for_c(int value) { return magnitude(value); }
```

`name` is an optional portable C symbol identifier. An import defaults to its
unqualified source name. An export defaults to the same namespace encoding used
by `export(C)`. The source name remains the native name; changing the external
name does not rename source calls. A header is descriptive metadata, not a file
to execute, open or implicitly add to the linker. Build the provider separately
and select its object/library explicitly.

An import is bodyless; an export has a nonthrowing native body. Bare attributes
and empty argument lists use defaults. Both forms reject generic or async
functions, native throws, repeated/conflicting callable attributes, and all
signatures outside the existing finite checked C ABI. No exception can unwind
through the generated C wrapper.

For example, compile an exported library using `astrac -O2 -c boundary.astra
-o boundary.o`, then compile and link a separate C client with `cc client.c
boundary.o -o client`. C scalar signatures currently select `int` (32 bits),
64-bit integer types, `f32`, `f64`, `void*` and `void` in the qualified host
profile. Foreign `bool` requires the separate explicit
[C99 copied-boolean profile](c-booleans.md). An arbitrary borrowed/owned native Class
handle is excluded; use the separate explicit
[opaque Class adapters](c-class-exports.md).

Imports accept the existing finite `text_abi`, `buffer_abi`, `record_abi`,
`callback` and `callback_abi` transport contracts as named string literals,
alongside `name` and `header`. Exports additionally accept
`record_abi="value-lp64"` for the existing qualified numeric POD record profile.
That profile supports at most two parameters and one to three selected numeric
fields, with exact native/C leaf correspondence and target checks. It does not
admit arbitrary C records, unions, variadic functions or retained pointer escape.
The separate [integer union projection profile](c-unions.md) requires its own
frozen active-member/tag representation. The explicit
[header importer](../../tools/headers/README.md) evaluates selected trusted
header constants through an independent C compiler and verified products.
See the existing Surge 5 interop coverage for
the older finite transport profiles and their limitations.

These attributes retain their own source syntax identity. Checked semantics
normalizes them to `CFunctionSymbol`/`CExportSymbol`, both exposing canonical
registry IDs; the existing Core, CFG, SSA, native/C ABI and LLVM verifiers carry
and check their exact signatures, symbols, target and ownership contracts.
`--dump-syntax`, `--policy-registry`, `--tooling-index` and
`--explain-semantics` expose the relevant source or checked identity. There is
no secondary source generator, preprocessor or unchecked attribute-to-text path.
Legacy declarations keep their prior behavior and diagnostics.

`tests/interop-tooling-14/c-policies.py ASTRAC EXTERNAL_OUTPUT` builds an
independent C provider and client with strict C11 flags and layout assertions,
then calls renamed scalar and POD record exports/imports at O0/O1/O2. It also
executes matching legacy declarations, checks formatting and stages, inspects
symbols/dependencies, and restores healthy compilation after refusal controls.
This recipe qualifies this function-policy component; it does not complete the
Surge 14 object/union/out/COM/GObject acceptance gates.

## Borrowed integer out/inout calls

`[CImport(pointer_abi="i32-noescape")]` admits explicit `borrowed int*`
parameters through a finite read/write C `int32_t *` transport. The pointer is
call-scoped, may be null, and must not be retained or used after the foreign
call returns. Initialize local storage before taking its address. The foreign
provider owns its status/out convention; a failure does not invent a successful
value. Copied integer status results preserve negative failures and positive
success codes. This mode excludes other pointer pointees, pointer-like results,
owned results, alternate record/text/buffer transports and callbacks.

The transport is checked in semantics, Core, CFG, SSA and its C ABI sidecar.
The native ABI retains the existing typed pointer and address-place authority;
it does not reinterpret the pointee as a record. The sidecar carries an exact
integer-pointer role in addition to its physical PTR channel. The LLVM verifier
checks the exact argument address. Unsupported target services remain refused,
and no runtime library is added merely by importing an integer-pointer call.

`tests/interop-tooling-14/c-pointers.py` passed 21 independently compiled C
out/inout, failure cleanup, null, positive-status and refusal commands, with
Astra execution at O0/O1/O2 and unsuppressed Valgrind. The separate ABI proof
rejects a lost pointer role and an ordinary-LLVM-valid substituted out address,
then restores and verifies the original program.

## Owned foreign resources and status/out SDKs

Existing VAPI nominal handles can declare a cleanup function, and a typed
`[CImport]` can return an `owned` nullable handle. The result acquires one
foreign resource owner. Explicit `move`, early return, reverse scope cleanup,
owned fields and retained closure retirement use that handle's exact cleanup
authority. A separate duplication call must explicitly acquire another owner;
assignment does not duplicate it. Borrowed and differently named resource
types cannot substitute for owned results or each other.

For a C SDK returning status plus `T **out`, an explicitly compiled C adapter
can normalize this into the existing owned-result channel and a separate
copied status getter. It must retire stray ownership on failure before returning
null. Preserve positive success codes and documented nullable success. The
adapter owns the real `T **` storage; this pattern adds no Astra pointer-to-pointer
storage or automatic HRESULT interpretation. Keep a thread-local status getter
adjacent to its producer call, before another SDK call can replace that status.

`tests/interop-tooling-14/c-owners.py ASTRAC EXTERNAL_OUTPUT` independently
compiles the provider, normalizing SDK and C client with GCC and Clang. Its
O0/O1/O2 executions require seven exact resource destructions, including failed
stray output, explicit duplication/move, early return, reverse destruction and
retained callback cancellation/quiescence. Selected O0/O2 executions use
unsuppressed Valgrind with all leak kinds checked. Stage inspection checks the
cleanup symbol in the checked graphs and C ABI, the backed retained environment
in the native ABI inventory, and real emitted cleanup calls. Copy, borrowed
escape and wrong nominal resource controls must refuse.
