# ADR 0103: Counted application text and synchronous hosted files

Status: implemented under `ASTRA-APPLICATION-RUNTIME-SURGE-1`'s delegated,
compatible library authority. Qualification is in
application-runtime-1-validation.md.

Use existing Astra source, Q19A immutable `Utf8Message`, Q19B
`Utf8ByteBuilder`, unique arrays, checked `Error` and exact-Class `Bag<T>`.
No syntax, allocator, text representation, exception ABI or generic ownership
contract changes. `scalar-format.astra` supplies native decimal I32/U32 and
boolean appends. Unsigned magnitude arithmetic handles I32_MIN without signed
negation overflow. Floating formatting is not delivered.

Strings currently expose counts and equality, but no source byte indexing.
An explicit hosted `text-ops-posix.c` observer borrows the existing authentic
`utf8-i32` descriptor for one bounded byte read. Search, scalar-boundary checks,
copying, splitting, decimal parsing and composition remain Astra algorithms.
All offsets are bytes. Extraction allocates and validates an independent owner;
it never creates a return loan. There is no normalization or grapheme promise.

`text_split` appends independent fields to a caller-owned Bag. Its finite
nonthrowing borrowed Bag boundary is preserved: it catches local checked errors
and returns false, retaining any fields already committed. Empty delimiter
returns false before mutation. Caller code can translate false into its checked
domain. No generic Bag result/throwing-helper extension is introduced. Explicit
bounded reserve precedes append; Bag itself retains its full-capacity trap.

The current foreign ABI has no safe native byte-slice channel. The opt-in
`files-posix` adapter therefore exposes counted-path open and scalar byte
read/write, fsync and close. Astra owns all byte arrays, growth, traversal,
application algorithms and checked failures. This costs O(n) syscalls for n
bytes. A separately verified bulk-byte ABI is a future performance improvement,
not an implicit pointer cast or a C-side full-file implementation.

`FileHandle` starts closed, acquires through checked open and disarms before
checked close. Reopening a live handle rejects. Destructor close cannot throw;
successful public whole-file operations explicitly flush/close and report
failures. Linux close is never retried after EINTR. Other operations retry
EINTR; one-byte transfers make successful short positive I/O impossible; zero
write becomes EIO. No shared/global descriptors or retained source pointers.
Raw externs are the existing explicit trusted foreign boundary, not safe fd
ownership constructors.

Payloads are arbitrary counted octets, including NUL and invalid UTF-8. Decode
is explicit through unchanged Q19A. Paths are source UTF-8, copied and terminated
only at POSIX open; embedded NUL rejects. Counts are bounded I32, checked before
growth/allocation. Hosted OOM stays fatal, with no unwind guarantee. Writes
truncate immediately and may leave partial output on error; fsync is not an
atomic rename or directory-durability policy. Error operation and negative
Linux errno are copied observations; source-path context stays with the caller
so a borrowed argument is never retained in an exception.

Integration exposed a preexisting LLVM layout-discovery omission: slots-only
field uses were absent from the layout demand scan. Scan `SsaSlotsEffect` and
`SsaSlotsValueInstruction` through the same exact field-owner walk used by
ordinary loads. This fixes borrowed-only Bag helpers without weakening semantic,
Core, CFG, SSA, native or actual LLVM field authority. A regression has no user
Bag allocation, verifies all stages, corrupts an actual field index, rejects it,
restores it and verifies again; corrupted IR is never executed.

The target is GNU Linux x86-64 LP64. Providers are explicit source/object inputs;
integer/bool formatting adds no hosted provider dependency. No packages, global
locale mutation, GLib/GObject runtime or liburing dependency is added. Existing
unique-owner runtime allocator assumptions remain. Self-hosting, public optimizer,
bulk/async I/O, modules, full Bible and other targets remain outside this delivery.
