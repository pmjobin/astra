# Getting a first program running

Start with an observable calculation, without text I/O or an allocator. This
edition uses the already authenticated current native compiler products. It
does not introduce an installer, package manager or tool download. You need the
qualified GNU/Linux x86-64 environment, exact LLVM 23.1.4 tools, a C linker and
the existing compiler/product identity receipts. A system LLVM upgrade does not
silently replace that environment.

The first complete source program is deliberately small:

```astra example=hello
language astra27b;
int main() {
	return 42;
}
```

The header selects modern syntax. `main` has the required native entry signature,
and `return` supplies its integer result. There is no printing dependency: the
test runner observes exit 42. A shell normally treats this nonzero code as
failure, so inspect the expected exit explicitly instead of using a bare
`set -e` recipe that stops at the successful demonstration.

## Compile, link and observe

Set `ASTRA_HOST` to the authenticated current compiler launcher and
`ASTRA_BOOK_BUILD` to an unused absolute directory beneath the project build
root. These are explicit inputs, not assumed installed commands:

```sh
mkdir -p "$ASTRA_BOOK_BUILD"
"$ASTRA_HOST" --check tests/books/hello.astra
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/hello.o" tests/books/hello.astra
cc -no-pie "$ASTRA_BOOK_BUILD/hello.o" -o "$ASTRA_BOOK_BUILD/hello"
"$ASTRA_BOOK_BUILD/hello"
test "$?" -eq 42
```

O2 is a separately tested target profile, selected by `-O2`; changing the host
compiler's own optimization profile is another dimension. The automated runner
tests both host images and both target modes. It verifies LLVM IR, exact results,
output refusal sentinels and unsuppressed returning memory. Its qualified command
is documented in [Tooling](tooling.md).

If checking fails, read the diagnostic before trying to link. If linking fails,
the source might require an explicitly selected provider; adding unrelated
libraries is not an explanation. If execution disagrees, retain source, tool
hashes, command, stdout/stderr and exit. [Profiles](../reference/profiles.md)
explains the language header, and [ABI](../reference/abi.md) defines the qualified
host boundary. A version banner alone is not a native acceptance receipt.
