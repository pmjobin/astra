# Explicit hosted text output

The [argument echo example](../../examples/args/echo.astra) selects both `args-posix.o` and `text-posix.o`: the first validates/copies process arguments, the second provides output. Text-slice helpers and argument-only programs do not require the output provider. Installed consumers use `${libdir}/astra/x86_64-linux/args-posix.o` and the separately selected output object. See [the argument protocol](../backend/hosted-arguments-v0.md).

Select `lib/astra/hosted/text.astra` and one qualified `text-posix.o` object:

```sh
build/astrac examples/text-output/hello.astra lib/astra/hosted/text.astra --link-object build/lib/astra/text-posix.o -o build/text-io-1/hello
build/text-io-1/hello
```

The complete example handles failure:

```astra
int main() {
	if (!println("Hello from Astra.")) {
		return 1;
	}
	return 0;
}
```

| Native function | Destination | Requested bytes |
| --- | --- | --- |
| `bool print(string text)` | stdout | text |
| `bool println(string text)` | stdout | text then one LF |
| `bool print_stderr(string text)` | stderr | text |
| `bool println_stderr(string text)` | stderr | text then one LF |

These are ordinary functions, with ordinary native parameter borrowing. They
are neither keywords nor a prelude. Unrelated functions with these names work
normally; selecting conflicting definitions produces SOURCES diagnostics.
There are no overloads, implicit library lookup, formatting, interpolation or
numeric-to-text conversion. `%s%n` is data. Unicode bytes, embedded zeros and
bytes after NUL pass unchanged. There is no trimming, normalization, locale or
terminal conversion, stdio formatting or platform newline rewriting.

True means the provider completed all requested writes. False reports an
ordinary returned failure, potentially after a prefix was emitted. A failed
LF still returns false after the payload. Callers can return normally and get
normal RAII cleanup; no assertion, abort, exception or must-use-result feature
is introduced. A host signal may terminate the process before control returns,
so false and cleanup are not guaranteed for abnormal termination.

The library selects one annotated import, physically:

```c
int32_t astra_host_text_write(int32_t stream, const unsigned char *data, int32_t byte_length, int32_t newline);
```

Stream 1 selects descriptor 1 and stream 2 descriptor 2. Newline is 0 or 1.
The provider returns 0 for complete success and 1 for failure; native wrappers
use ordinary equality to produce bool. It checks selectors, nonnegative counts
and nonempty/null consistency before I/O. This validates shape, not arbitrary
pointer readability. It honors the complete [trusted borrow contract](../abi/c-text-views.md).

The provider advances only by positive write progress and retries EINTR at the
unconsumed suffix. Zero progress on nonempty data, EAGAIN/EWOULDBLOCK and other
returned errors fail. Empty print succeeds without a syscall or null-pointer
arithmetic; empty println writes only LF. LF follows successful payload
completion. No pointer is retained and no application buffer is allocated.

Production code never changes SIGPIPE disposition, signal masks, descriptor
flags or locale. Tests separately observe default signal termination and a
child harness that explicitly ignores SIGPIPE to inspect the returned error.
The provider does not promise atomic lines, concurrent ordering, synchronization
with foreign buffered stdio, resumability, errno exposure, rendering success or
disk durability. It neither flushes unrelated FILE streams nor calls fsync.
The implementation follows the primary [Linux write(2) documentation](https://man7.org/linux/man-pages/man2/write.2.html)
and [POSIX write specification](https://pubs.opengroup.org/onlinepubs/9799919799/functions/write.html).
The Linux manual was consulted during implementation; the POSIX web endpoint
returned HTTP 403 in the qualification environment.

The qualified platform is x86-64 Linux with the repository's GCC-built support
objects, separately checked with Clang. Wider size_t/ssize_t counts are local C
implementation details. `target.txt` records the actual build target and C
compiler. Build guards and C static assertions fail on unqualified shapes;
the compiler has its own independent C text compatibility gate.

The configured installation here uses prefix `/usr/local`, datadir `share`,
libdir `lib64`, and bindir `bin`. Meson options are authoritative; do not assume
lib64 on another configuration. The installation contains:

- `bin/astrac`
- `share/astra/hosted/text.astra`
- `share/astra/platform/text-posix.h` and `text-posix.c`
- `lib64/astra/x86_64-linux/text-posix.o` and `target.txt`

Reproduce installation and relocation, retaining the exact paths and commands:

```sh
python3 -B tests/text-io/install.py build build/text-io-1/installation
```

Each run stages `meson install --no-rebuild`, copies the prefix and consumer
sources into a new directory beneath that campaign path, and invokes the
relocated compiler from the consumer directory. `installation.json` records
configured directories, actual artifacts, commands, hashes and canonical-stage
comparisons. The multi-source [client](../../examples/text-output/main.astra)
uses static labels, ordinary borrowed helpers, generic concrete text use,
existing numeric assertions and a class owning a buffer. Both success and a
handled false return execute its destructor and field cleanup.

| Consumer | Explicit inputs | Attributable runtime support |
| --- | --- | --- |
| Native-only text / text-free | Astra source | No added output symbols |
| Annotated C reader | Reader declaration and companion object | Companion's own dependencies |
| Hosted output | hosted/text.astra and text-posix.o | write and errno support in hosted libc |
| Output plus assertions | Also base/contracts.astra and one failure provider | Selected failure policy |
| Output plus buffers/math | Also selected buffer uses / hosted/math.vapi and `--link-library m` | calloc/free / libm independently |

Missing or repeated provider definitions fail at the real linker. No provider
is auto-linked, including for an unrelated annotated reader. Link-input order,
repetition, shell-free argv and existing-output preservation retain BASELIB's
rules. Compiler GLib/GObject/LLVM dependencies never become a text-output
runtime. Hosted output is not freestanding; dependency-free reader companions
can still support an internal startup witness. No claim is made about libc's
internal allocation or comparative print performance.

Deferred: argv/process entry, input/file reading, C-returned strings, text C
exports, NUL-terminated c_str adapters, arbitrary text pointers, owned text,
concatenation/interpolation, fields/collections, formatting, source-aware
assertion capture, exception/cancellation recovery, async output, stream
objects, integer widths/size_t, modules and automatic library selection.
