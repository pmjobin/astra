# Getting a first program running

A small measuring tool has collected five readings: 2, 4, 6, 8 and 10. Before
building a file reader or a reporting interface, we can check the calculation
at its center. The five readings should add up to thirty. Our first Astra
program will check that result and tell the shell whether it agrees.

Over the next two chapters, we will replace this hand-written sum with a loop
and give each reading a record of its own. Later, the same data will come from
[a real input file](application.md). For now, the whole program fits on a few
lines. Its exact source is [pilot-total.astra](../../tests/books/pilot-total.astra):

```astra example=pilot-total
language astra27b;
int main() {
	int total = 2 + 4 + 6 + 8 + 10;
	if (total != 30) return 1;
	return 0;
}
```

Read this from the inside out. `int total` declares an integer variable, and
`=` gives it the sum on the right. The `if` asks whether that sum differs from
30. If it does, `return 1` ends the program with a failure status. Otherwise,
execution reaches `return 0`, the usual successful status for a command.

The surrounding `int main()` declares the function where this native program
starts. The braces contain its statements; semicolons end them. The first line,
`language astra27b;`, selects the modern source profile used throughout these
lessons. Keep it when copying a complete example. Omitting it selects the
legacy profile, which has different syntax and some different defaults.

This program prints nothing. Its integer result goes to the shell as an exit
status. We will let the shell display a message; text output from Astra will
come later, with its actual library or C-provider dependencies.

## Prepare the development environment

This edition runs on GNU/Linux x86-64 with LLVM **23.1.4**, an authenticated
Astra compiler, Python 3.11 or later for the setup helper, and a host C linker
(`cc`). A fresh Git working tree also needs
the project's qualified external compiler products and their manifests. Cloning
the sources alone does not create them. There is no installer supplied by this
chapter; [Tooling](tooling.md) identifies the existing build and linking recipes
if you need to reproduce the development environment.

The following commands use the established workspace layout. Run them in a
terminal and keep that terminal open for the next chapters. This recipe assumes
the checkout and external products are already at the paths shown below; a
relocated environment needs its own qualified paths and build recipe.

Use a dedicated POSIX-compatible shell for these lessons. The first line enables
`set -eu`, so an unhandled failed command or unset variable stops the recipe.
The deliberate failure examples capture their statuses explicitly. If a real
setup or build failure ends the shell, correct it and start a fresh lesson session.

```sh tutorial=setup
set -eu
cd "$HOME/Workspace/astra"
export ASTRA_WORK="$HOME/Workspace/codex/work/astra"
export ASTRA_PRODUCTS="$ASTRA_WORK/runtime/api-docs28a1-products.json"
export ASTRA_TOOLCHAIN="$ASTRA_WORK/runtime/selfhost27c-dev21/build-identity.json"
ASTRA_BOOK_BUILD=$(mktemp -d "$ASTRA_WORK/build/guide-pilot.XXXXXX")
export ASTRA_BOOK_BUILD
python3 -B tests/books/environment.py \
    --products "$ASTRA_PRODUCTS" --toolchain "$ASTRA_TOOLCHAIN" \
    --output "$ASTRA_BOOK_BUILD/environment.sh" &&
    . "$ASTRA_BOOK_BUILD/environment.sh"
```

The [setup helper](../../tests/books/environment.py) checks the selected manifest,
compiler and tool bytes, then writes a small shell environment file in the new
build directory. The final line loads it and sets `ASTRA_HOST` to the selected
compiler. It neither installs a compiler nor chooses an unverified substitute.
If it reports an unavailable environment, stop here and resolve the named
missing file or identity mismatch. That is a setup problem, not an error in
our six-line Astra program.

`ASTRA_BOOK_BUILD` is an unused directory outside the source tree. Each invocation
of the setup commands creates another one, so earlier work is preserved.

## Compile, link and observe

There are two build steps. Astra compiles source into an object file; `cc` links
that object into an executable. Here `-c` selects object output, `-O0` selects
its optimization level, and `-o` names the output file. `&&` tells the shell to
continue only if the preceding command succeeds.

```sh tutorial=first
"$ASTRA_HOST" --check tests/books/pilot-total.astra &&
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/total.o" \
    tests/books/pilot-total.astra &&
cc -no-pie "$ASTRA_BOOK_BUILD/total.o" -o "$ASTRA_BOOK_BUILD/total" &&
if "$ASTRA_BOOK_BUILD/total"; then
    printf '%s\n' 'Readings check passed (exit 0).'
else
    printf '%s\n' 'Readings check failed.' >&2
    false
fi
```

Expected terminal output is `Readings check passed (exit 0).` followed by a
newline. That sentence comes from the shell's `printf`, not from an Astra
printing function. `--check` checks the source without producing the executable;
it does not replace compilation, linking or running the result.

You can select `-O2` instead of `-O0` and keep its outputs separate:

```sh tutorial=first-o2
"$ASTRA_HOST" -c -O2 -o "$ASTRA_BOOK_BUILD/total-O2.o" \
    tests/books/pilot-total.astra &&
cc -no-pie "$ASTRA_BOOK_BUILD/total-O2.o" -o "$ASTRA_BOOK_BUILD/total-O2" &&
"$ASTRA_BOOK_BUILD/total-O2" &&
printf '%s\n' 'Optimized readings check passed (exit 0).'
```

The calculation and expected status stay the same. The book's tests exercise both
optimization levels with both qualified compiler hosts. You do not need to
understand that test matrix to run this first program.

## Make a check fail on purpose

Before running the next example, predict its exit status. It computes the same
sum but compares it with 31. The calculation is unchanged; the expectation is
wrong. This is a valid program with an intentionally failing check:

```astra example=pilot-total-failure
language astra27b;
int main() {
	int total = 2 + 4 + 6 + 8 + 10;
	if (total != 31) return 1;
	return 0;
}
```

The [complete exercise answer](../../tests/books/pilot-total-failure.astra) is
already in the checkout. Build it and capture the expected nonzero result:

```sh tutorial=failed-check
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/bad-total.o" \
    tests/books/pilot-total-failure.astra &&
cc -no-pie "$ASTRA_BOOK_BUILD/bad-total.o" -o "$ASTRA_BOOK_BUILD/bad-total" &&
{
    ASTRA_STATUS=0
    "$ASTRA_BOOK_BUILD/bad-total" || ASTRA_STATUS=$?
    printf 'check exit: %s\n' "$ASTRA_STATUS"
    test "$ASTRA_STATUS" -eq 1
}
```

The output is `check exit: 1`. The `||` captures the failure without letting a
shell configured to stop on errors terminate the exercise early. Change the
expectation back to 30 to obtain the first program again. A useful check must
be able to fail: a successful compile alone says nothing about our expected sum.

## A compile error is a different event

This separate example is intentionally invalid:

```astra example=negative-type
language astra27b;
int main() {
	bool value = 42;
	return value;
}
```

Its [source file](../../tests/books/negative-type.astra) tries to initialize a
`bool` with the integer 42. Compile it, but do not try to run an output:

```sh tutorial=type-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected.o" \
    tests/books/negative-type.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
```

The diagnostic includes `expected initializer of type 'bool', found 'int'`.
Read that message as a description of the incompatible values, not as a request
to change the linker. If you wanted an integer, declare `int`; if you wanted a
truth value, use a Boolean expression. The numbers after the filename are
currently UTF-8 byte offsets, not line and column numbers.

Our first program compiles and succeeds. The second compiles and reports a
failed check. This third program fails compilation. Keep those three events
separate when investigating a problem.

## Where to go next

In [Values, decisions and progress](values.md), the shell setup stays the same
while the calculation becomes a loop. You will no longer have to write every
addition by hand.

Some later chapters and earlier experiments deliberately return 42 as a test
sentinel. The tiny [original entry-point example](../../tests/books/hello.astra)
is one of them. Those programs need their documented status checks; exit 42 is
not ordinary command success and is not printed output. The opening pilot uses
0 for successful checks. For precise source-profile and entry-boundary rules,
see [Profiles](../reference/profiles.md) and [ABI](../reference/abi.md).
