# Hosted arguments v0

The private x86-64 Linux LP64 bridge uses:

```c
struct AstraArgsTextV0 {
	const unsigned char *data;
	int32_t byte_length;
};
int32_t astra_host_args_prepare_v0(int32_t argc, char *const *argv, const struct AstraArgsTextV0 **out_items);
void astra_host_args_dispose_v0(const struct AstraArgsTextV0 *items);
```

These are compiler-owned physical startup details, not a newly admitted Astra
source C struct, raw pointer or incoming-text ABI. The source entry is an ordinary
internal native function. ProgramEntry selects its exact identity; the independent
NativeProgramEntryPlan records that symbol's ordinal/provenance, entry kind,
descriptor contract and ordered protocol. Before lowering, the entry builder
checks correspondence against both the selected SSA function and verified NABI.
Debug names cannot reconstruct missing plans. Generic LLVM calls to a function
named main remain ordinary native calls.

The wrapper has one pointer-sized output slot and three bounded blocks. It
initializes null, calls prepare, returns a nonzero status directly, and only on
zero loads/publishes the table and invokes native main with the complete table/
count group. After normal native lexical cleanup it captures the I32 result,
disposes once, and returns the result. Plan verification rejects missing success
guards and disposal before invocation. The provider symbols cannot collide with
source boundaries. No ownership flags, runtime registry or atexit root exists.

The host supplies argc readable NUL-terminated strings and a readable vector with
a null element at argv[argc], stable during capture. Negative counts, null entries,
missing vectors, invalid terminal shape and unrepresentable sizes return 2.
For count zero, argv is not dereferenced and no allocation occurs. Ordinary C
cannot validate arbitrary unreadable pointers or racing hostile mutation.
These framing conventions are described by the [GNU argument contract](https://sourceware.org/glibc/manual/latest/html_node/Program-Arguments.html)
and [Linux execve](https://man7.org/linux/man-pages/man2/execve.2.html).

For positive count, checked multiplication and addition plan one allocation:
natural-aligned descriptor table at the base, followed by copied payload bytes.
All sizes and offsets fit PTRDIFF_MAX; each text length fits signed I32. Copying
checks the actual bytes against remaining planned capacity and length bounds.
Empty entries become null/zero and terminators are not copied. The copied bytes
are then validated using the [RFC 3629 scalar and shortest-form contract](https://www.rfc-editor.org/rfc/rfc3629.html#section-3).
Every failure frees incomplete storage and leaves the output null. Allocation
failure returns 3. Publication occurs only after every descriptor is valid.
The implementation has no diagnostic output, stdio or text-output dependency.

The provider asserts CHAR_BIT=8, host int/I32 agreement, LP64 pointer widths and
alignment, signed-I32 layout, descriptor offsets/stride/alignment and allocator
alignment. The compiler independently checks its LLVM target-layout witness.
Natural layout, not register transport, establishes table stride.

Install/build artifacts follow existing Meson conventions:
`lib/astra/platform/args-posix.[ch]`, `build/lib/astra/args-posix.o`, installed
`${datadir}/astra/platform/args-posix.[ch]` and
`${libdir}/astra/x86_64-linux/args-posix.o` beside `target.txt`.
Meson's existing Linux/x86-64/GCC support-object gate is retained; GCC and Clang
provider/harness objects are qualified separately. Derive installation directories
from configured prefix/datadir/libdir; never assume lib64 or reuse another target's
object. Select this object explicitly with `--link-object`; there is no autolink.

After publication, changes to original argv strings/table do not affect native
views. This is snapshot stability, not protection against arbitrary foreign memory
corruption. Positive normal return frees one allocation; zero disposal is a no-op
without an allocator call. View copies, helpers and output add no owners. Handled
output failure still cleans native owners before snapshot disposal. Fatal traps,
signals, foreign exit/longjmp or other nonreturn do not unwind. Runtime validation
failure is a normal cleaned error path, not a fatal-memory exception.

The [POSIX.1-2024 exec reference](https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html)
is the specified platform reference (the documentation fetch returned HTTP 403
during qualification). Strict UTF-8 acceptance, copying, statuses and ownership
sequencing above are Astra policy decisions, not claims imposed by POSIX.
