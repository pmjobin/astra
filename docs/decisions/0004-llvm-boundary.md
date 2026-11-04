# ADR 0004: Narrow LLVM C API backend boundary

Status: accepted in ASTRA-CHARTER-1. The founding LLVM 22 qualification
remains historical; current version selection is superseded by
[ADR 0169](0169-llvm-23-migration.md).

## Decision

Use Astra-owned, minimal, mechanical Vala declarations for the system LLVM C API
under `src/backend/llvm/capi/`. Keep all raw LLVM handles and their operations
below `src/backend/llvm/` (ASTRA-I4). LLVM represents physical machine operations,
not Astra semantic types, ownership, or authoritative storage.

Qualify LLVM major **22** only; the founding host uses **22.1.8**. Query one system
`llvm-config` for its version, C compile flags, and shared Core/Analysis link
flags. Reject other majors and fail configuration if the matching major's C
headers or required symbols cannot be compiled and linked. Qualify additional
majors deliberately after proving this version; do not add speculative adapters.

## Alternatives and rationale

The C++ API and a C++ shim add coupling and toolchain surface not required by
this milestone. A broad foreign Vala binding would expose many concepts with no
current caller. The small C API surface suffices for context/module creation,
function construction, verification, and disposal. A narrow C++ adapter can be
considered later only for a demonstrated capability gap and an explicit ADR.

Meson 1.11.2's built-in LLVM dependency requires a C++ compiler even when linking
the C API. Direct `llvm-config` queries keep Astra's build languages to Vala and
C without hard-coding library directories or adding CMake discovery. Shared
linkage uses the system LLVM library and its own packaged dependencies; no
LLVM source or implementation code is vendored.

## Lifetime and boundary contract

The internal smoke fixture owns a context, module, builder, and LLVM verifier
message. Its single exit path frees the message with `LLVMDisposeMessage`, then
the builder and module, then the context. Function/type/block/value references
borrow storage from that module/context and are not independently destroyed.
The diagnostic is copied before disposal; callers see only a boolean and that
copy. The invalid fixture must return failure with a diagnostic.

These are LLVM fixture lifetimes, not an implementation of Astra ownership or
Core IR. No general backend interface or semantic abstraction is introduced.
