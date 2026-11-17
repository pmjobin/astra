# Native ABI and runtime profiles

R-ABI. Native code generation is qualified here for GNU/Linux x86-64 using exact
LLVM 23.1.4. Source types, ownership channels and effect signatures are checked
independently of physical LLVM layout. LLVM accepting a module is necessary but
does not prove its correspondence to Astra source. The compiler retains separate
Flow, Core, CFG, SSA and physical/native consumers. Layout caches remain owned
by their LLVM module; the books introduce no new cache or verifier shortcut.

`extern(C)` declares an explicit foreign implementation. The declaration must
use an admitted C signature and matching real provider. Calling-convention
metadata cannot prove that a foreign body obeys its lifetime or buffer promises.
An externally supplied address cannot become an owner merely because its
physical type is pointer-shaped. Public ABI approval remains E25-A-v1 with its
exact pinned proposal; no book example revises that approval.

R-COUNTED-C. Selected counted text imports use `[CCode(text_abi = "utf8-i32")]`
with a borrowed string channel. The physical call supplies UTF-8 bytes and an
i32 count in the defined channel order. The C observer in the [application](../guide/application.md)
checks the count and bytes independently. The analogous selected byte-buffer
contract uses `buffer_abi = "u8-i32"`. Neither supplies a retained foreign view,
automatic NUL termination, alias attributes or an arbitrary C aggregate ABI.

Opaque nonowning `void*` channels have bounded admission. General typed-pointer,
function-pointer, varargs, aggregate, foreign-object-policy and framework
bindings must not be inferred from scalar C calls. GObject/COM and other older
interop contracts retain their historical scope; current native safety requires
the exact admitted declaration and provider, with separate tests.

## Hosted and freestanding programs

R-PROFILES. Selected hosted libraries require their authenticated C providers.
Including all historical libraries by default is not part of this driver.
The minimal scalar/fixed-array profile can avoid runtime allocation; the fixed
fixture is linked to a Linux x86-64 syscall entry with no libc, allocator,
dynamic interpreter or undefined symbols. This is a bounded executable profile,
not a portable operating-system ABI or firmware qualification.

Owning arrays need their allocation/free dependencies. Formatting and errors
need their actual selected runtime. No-heap claims identify the final object's
imports and real link/execution evidence; source absence of `new` alone is
insufficient. No WebAssembly, Windows, macOS, embedded interrupt, MMIO, DMA or
device-memory acceptance is granted by the native host tests. Native structure
layout is not a stable public serialized schema, and source debug metadata is
not a release ABI commitment.

## Counted import shape and independent obligations

R-COUNTED-SIGNATURE. The admitted counted import is a top-level `extern(C)`
function with no Astra body, export, async marker, generic/foreign policy or
throwing channel. Exactly one CCode entry selects `text_abi = "utf8-i32"` or
`buffer_abi = "u8-i32"`. At least one argument must use the corresponding borrowed
counted type; a counted result is excluded. Other channels must meet the admitted
scalar signature. Text bytes and byte-buffer bytes are paired with i32 counts,
in declared channel order. The borrowed lifetime promise neither supplies LLVM
alias attributes nor proves a foreign body's implementation.

The [source signature consumer](../../compiler/semantic/foreign-text.astra) and
[physical external-call consumer](../../compiler/backend/llvm/recover-foreign-check.astra)
check different facts. The actual C client/provider tests must still observe
argument/result order and exact bytes. Native private record, enum, Error and
owner-slot layouts are not arbitrary C aggregate contracts; public E25-A-v1
approval is preserved unchanged.

`--check` still performs the retained Flow/Core/CFG/SSA admission before returning.
`--dump-syntax` stops after parsing. `astrac doc` uses the separate semantic-only
path with no LLVM backend calls. These commands therefore have different proof
boundaries. Neither checking nor API extraction establishes an ELF link or a
freestanding runtime profile. Select explicit sources/providers and verify the
final imports and actual target execution when claiming no runtime dependencies.
