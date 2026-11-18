# Hosted and freestanding calculations

Our application needs files, output, owning array storage and the host C runtime.
Its arithmetic does not need all of those facilities. If the readings are known
in advance, can we build just the fixed calculation with a much smaller set of
runtime dependencies? This chapter answers that question on the qualified
GNU/Linux x86-64 host.

First keep two meanings of “profile” separate. `language astra27b;` selects the
syntax and language defaults for one source file. The libraries, providers,
startup code and target selected when building determine the executable's runtime
environment. The modern header alone neither adds libc nor removes an allocator.

## A fixed calculation

This [complete program](../../tests/books/guide-fixed.astra) stores the same
five readings in a fixed array and checks their total:

```astra example=guide-fixed
language astra27b;
int main() {
	int[5] readings = (2..=10).step_by(2).collect_fixed();
	int total = 0;
	int at = 0;
	while (at < 5) {
		total += readings[at];
		at += 1;
	}
	if (total != 30) return 1;
	return 0;
}
```

The exact count follows from the literal range and stride. The array is fixed
local storage; no owning runtime collection is requested. Start with a normal
hosted link, using the C toolchain's startup:

```sh tutorial=fixed-hosted
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/fixed-readings.o" tests/books/guide-fixed.astra
cc -no-pie "$ASTRA_BOOK_BUILD/fixed-readings.o" -o "$ASTRA_BOOK_BUILD/fixed-hosted"
"$ASTRA_BOOK_BUILD/fixed-hosted"
printf '%s\n' 'Fixed readings total 30 (hosted exit 0).'
```

The Astra program is silent and returns 0. A hosted link is convenient even
when the calculation itself needs no file or text service.

## Supply a minimal startup instead

For this Linux x86-64 demonstration, a small assembly entry calls `main`, then
passes its returned status to Linux's exit syscall. It supplies no file service,
allocator or C library initialization. The following complete recipe writes
that startup under the external build directory and links the same object:

```sh tutorial=fixed-freestanding
cat > "$ASTRA_BOOK_BUILD/guide-start.S" <<'START'
.text
.globl _start
_start:
 call main
 mov %eax,%edi
 mov $60,%eax
 syscall
.section .note.GNU-stack,"",@progbits
START
cc -nostdlib -static -no-pie -Wl,-e,_start \
    "$ASTRA_BOOK_BUILD/guide-start.S" "$ASTRA_BOOK_BUILD/fixed-readings.o" \
    -o "$ASTRA_BOOK_BUILD/fixed-freestanding"
"$ASTRA_BOOK_BUILD/fixed-freestanding"
nm -u "$ASTRA_BOOK_BUILD/fixed-freestanding" > "$ASTRA_BOOK_BUILD/fixed-undefined.txt"
readelf -l "$ASTRA_BOOK_BUILD/fixed-freestanding" > "$ASTRA_BOOK_BUILD/fixed-segments.txt"
"$ASTRA_PYTHON" - "$ASTRA_BOOK_BUILD/fixed-undefined.txt" "$ASTRA_BOOK_BUILD/fixed-segments.txt" <<'CHECK'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_bytes() == b''
assert 'INTERP' not in Path(sys.argv[2]).read_text()
CHECK
printf '%s\n' 'Fixed readings total 30; no undefined symbols or dynamic interpreter (exit 0).'
```

The executable returns 0. `nm` observes no undefined symbols, and `readelf`
shows no dynamic interpreter. These are concrete properties of the resulting
executable, not a conclusion drawn only from the source's absence of `new`.
The recipe needs the host's `nm` and `readelf` tools as well as `cc`.

This is what “freestanding” means in this bounded example. The syscall number,
registers and entry convention belong to Linux x86-64. It is not a firmware
startup, interrupt handler or portable operating-system interface. The original
[fixed-array experiment](../../tests/books/fixed.astra) tests the same link
choices with its preserved exit-42 calculation.

## Changing storage changes the link requirements

Predict what happens if a calculation requests `collect_array()` instead of
fixed storage. That operation creates an owner for runtime allocation. Our
[sequences program](../../tests/books/guide-sequences.astra) uses such storage;
its ordinary hosted link succeeds, but this startup cannot supply its allocation
and retirement dependencies.

Run the expected failed no-runtime link using the sequence object built earlier:

```sh tutorial=allocator-link-error
ASTRA_STATUS=0
cc -nostdlib -static -no-pie -Wl,-e,_start \
    "$ASTRA_BOOK_BUILD/guide-start.S" "$ASTRA_BOOK_BUILD/sequences.o" \
    -o "$ASTRA_BOOK_BUILD/array-no-runtime" \
    2> "$ASTRA_BOOK_BUILD/allocator-link-error.txt" || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/array-no-runtime"
"$ASTRA_PYTHON" - "$ASTRA_BOOK_BUILD/allocator-link-error.txt" <<'CHECK'
from pathlib import Path
import sys
assert 'undefined reference' in Path(sys.argv[1]).read_text()
CHECK
printf '%s\n' 'Owning array requires runtime providers (expected link failure).'
```

The saved diagnostic identifies the missing runtime symbols. The complete
working hosted repair is the Sequences build recipe. Keep fixed storage only
when its fixed-size contract actually meets the program's needs; do not remove
an owner or falsify an allocator declaration to obtain a smaller link.

Text formatting and recoverable errors select further source/provider inputs.
The file application needs its real C provider. Conversely, the compiler's own
LLVM dependency does not imply that every emitted scalar program links LLVM.
Inspect the actual program inputs and final imports.

## Exercise: choose the source profile deliberately

The [legacy-profile mistake](../../tests/books/negative-profile.astra) uses an
expression-bodied `main` under `language legacy27a;`. Compile it and observe
the expected parser refusal:

```sh tutorial=profile-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-profile.o" \
    tests/books/negative-profile.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/rejected-profile.o"
```

Exercise: select the modern profile and make this tiny command return ordinary
success. The [complete answer](../../tests/books/guide-profile-answer.astra) is:

```astra example=guide-profile-answer
language astra27b;
int main() => 0;
```

```sh tutorial=profile-answer
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/profile-answer.o" tests/books/guide-profile-answer.astra
cc -no-pie "$ASTRA_BOOK_BUILD/profile-answer.o" -o "$ASTRA_BOOK_BUILD/profile-answer"
"$ASTRA_BOOK_BUILD/profile-answer"
printf '%s\n' 'Modern expression body checked (exit 0).'
```

A block-bodied function is the alternative if a file must remain legacy.
Choosing a header is per-source; it does not rewrite library files or repair
later ownership failures. [Language profiles](../reference/profiles.md) gives
the exact rules. Current native vector refusals also remain separate from
historical SIMD experiments; see [Limits](../reference/limits.md).

You can now explain both the source contract and the runtime dependencies of
the readings program. The [glossary and next steps](glossary.md) provide routes
back to the first example of each idea and a few bounded projects to try next.
