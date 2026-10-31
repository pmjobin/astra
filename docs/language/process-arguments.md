# Validated process arguments

Hosted executables accept `int main()` or `int main(string[] args)`.
`borrowed string[]` is the equivalent explicit parameter spelling. The argument
list includes the supplied invocation text at index zero when the count is
positive. That text is not proof of the executable's path or identity.

```astra
int main(string[] args) {
	var index = 1;
	while (index < len(args)) {
		var argument = args[index];
		if (!println(argument)) { return 1; }
		index = index + 1;
	}
	return 0;
}
```

Select the source library and platform objects explicitly:

```sh
build/astrac examples/args/echo.astra lib/astra/hosted/text.astra \
	--link-object build/lib/astra/args-posix.o \
	--link-object build/lib/astra/text-posix.o -o build/args-1/echo
build/args-1/echo 'two words' '' 'é é 😀' -- '%s%n'
```

An argument program without output needs only `args-posix.o`. A native helper
with a `string[]` parameter needs no snapshot provider by itself. `int main()`
does not allocate or validate unused process arguments.

`len(args)` is the exact `int` element count. Each `args[index]` is an ordinary
immutable string; its `.byte_length` counts bytes. Empty arguments retain their
positions. Spaces, quotes, backslashes, dashes and percent sequences are just
payload bytes after the host has constructed argv. Astra does not split,
unquote, expand globs, remove `--`, parse options or read the environment.

The text entry copies the table and all payload bytes into one private startup
allocation. Every argument, including index zero and unused entries, must be
strict shortest-form scalar UTF-8. Invalid bytes are rejected without repair,
normalization, case folding or locale conversion. Valid noncharacters,
unassigned scalars, combining sequences and U+FEFF are preserved. This policy
can reject argument bytes that the OS accepts. OS NUL terminators delimit input
and are excluded from lengths; embedded-NUL native strings remain legal.

Preparation status 2 means invalid shape, encoding or unrepresentable size;
status 3 means allocation failure. Either prevents native main from running.
The initial provider emits no diagnostics. On success the wrapper returns the
native result, which can independently be 2 or 3. A true zero-count invocation
at the private adapter seam yields an empty view without allocating or reading
argv; qualification does not claim a kernel supplied that count.

Ordinary functions, struct/class methods and constructors can accept the same
type: `int run(string[] values)`. Local `var` or explicit views may be copied,
aliased, rebound and forwarded. Parameters retain existing binding immutability.
Reads check integer bounds before loading either descriptor component; negative
indices, index equal to count, and every access into an empty list trap.
Descriptor-slot assignment and address-taking are unsupported. Numeric slices
remain writable. `slice(...)` subrange construction is not added for text views.

The borrow covers both table and text payload lifetimes. Copies keep the backing
origin present at the time of the copy, even when the original local is rebound.
Extracted text is borrowed, including empty elements and literal-backed internal
test tables. Returning it, a saved borrowed copy, or a mixed static/borrowed join
through a static-only string result is rejected. Returning a genuine literal
after using arguments is legal. The snapshot is freed once after native normal
return and lexical cleanup, including a handled output failure. Traps, signals,
foreign `exit`/`longjmp` and other nonreturn paths do not gain unwinding cleanup.

Initial hosted entry and native text-table object qualification is x86-64 Linux.
See [ADR 0075](../decisions/0075-validated-process-arguments.md),
[native layout](../abi/native-text-slice-v10.md), and
[startup protocol](../backend/hosted-arguments-v0.md).

Deferred: raw OS-byte/path entry, lossy/locale conversion, environment APIs,
option parsing, diagnostic formatting/source capture, string allocation or
concatenation, writable/general string collections, fixed/local string arrays,
fields/properties, owned or borrowed slice results, C-returned/exported text,
generic slice admission, wider source integers, modules and async. The echo
example is an Astra feature example, not CAD requalification.
