# Calling native C code

The calculation is ready, but the outside world speaks in files and bytes.
Astra can call an existing C implementation through an explicit foreign function
interface, or FFI. The useful habit is to inspect both sides: what does Astra
promise to supply, and what does the C function actually do with it?

We already used a lifecycle observer and a text sink. This chapter explains that
boundary by reporting the familiar count and total through the real provider
that the next chapter will also use to load a file.

## A declaration needs an implementation

The [complete Astra caller](../../tests/books/guide-ffi.astra) declares an imported
function and calls it:

```astra example=guide-ffi
language astra27b;
[CCode(text_abi = "utf8-i32")]
extern(C) int report_readings(borrowed string label, int count, int total);

int main() {
	return report_readings("readings", 5, 2 + 4 + 6 + 8 + 10);
}
```

`extern(C)` says that the implementation comes from outside this Astra source
with the admitted C calling convention. It does not provide the implementation,
read a header, or prove that the foreign body honors a lifetime promise.
The CCode annotation selects a counted UTF-8 boundary for the borrowed label.
The result is a scalar status: the provider returns zero after successful output.

The real [app-report.c](../../tests/books/app-report.c) defines `report_readings`
with four C parameters. Its byte pointer and `int32_t` length together implement
the single Astra string parameter:

| Astra argument | C receives | Required relationship |
| --- | --- | --- |
| `"readings"` | Byte pointer, then `int32_t` length 8 | Read eight bytes during the call; retain none |
| Count 5 | C `int` count | Within the provider's range 0 through 128 on this target |
| Total 30 | C `int` total | The computed bounded total |

The C body checks that the label is exactly eight bytes spelling `readings` and
that the count is within its bound. It then prints the count and total. The
annotation does not add a NUL terminator or tell a foreign function it may keep
the pointer. We are qualifying this concrete GNU/Linux x86-64 interface.

Compile each language, then link the two objects:

```sh tutorial=ffi
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/ffi.o" tests/books/guide-ffi.astra
cc -std=c11 -O0 -Wall -Wextra -Werror -c tests/books/app-report.c \
    -o "$ASTRA_BOOK_BUILD/report.o"
cc -no-pie "$ASTRA_BOOK_BUILD/ffi.o" "$ASTRA_BOOK_BUILD/report.o" \
    -o "$ASTRA_BOOK_BUILD/ffi"
"$ASTRA_BOOK_BUILD/ffi"
```

Expected stdout is `readings: count=5 total=30` plus a newline, with exit 0 and
empty stderr. The C provider produced those bytes after an actual Astra call;
no shell message substitutes for program output.

## Diagnose the boundary that failed

Try linking the caller with the lifecycle observer object instead of the reporting
provider. Both are valid C objects, but the observer does not define the required
symbol. This is an intentional link failure:

```sh tutorial=wrong-provider
ASTRA_STATUS=0
cc -no-pie "$ASTRA_BOOK_BUILD/ffi.o" "$ASTRA_BOOK_BUILD/lifecycle.o" \
    -o "$ASTRA_BOOK_BUILD/ffi-wrong" 2> "$ASTRA_BOOK_BUILD/ffi-link-error.txt" \
    || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/ffi-wrong"
python3 - "$ASTRA_BOOK_BUILD/ffi-link-error.txt" <<'CHECK'
from pathlib import Path
import sys
message = Path(sys.argv[1]).read_text()
assert 'undefined reference' in message and 'report_readings' in message
CHECK
printf '%s\n' 'Missing provider: report_readings (expected link failure).'
```

Inspect `ffi-link-error.txt` to see the linker's diagnostic. The Astra declaration
was accepted; the required external implementation was absent. Restore the
`report.o` input from the working recipe. Adding a second declaration would not
supply executable code.

A still more dangerous mismatch is a provider exporting the right symbol with
the wrong signature or lifetime behavior. A linker can match a symbol without
checking those promises. That is why we use exact provider sources and observe
the bytes and argument order, rather than trusting a successful link alone.

## Exercise: count bytes, including NUL

The word `readings` is ASCII, so its character and byte counts coincide. Predict
the byte count for `é` followed by a NUL byte. UTF-8 encodes this `é` as `c3 a9`;
the embedded NUL contributes one more byte. The answer is three, not one or two.

The [complete caller](../../tests/books/guide-counted.astra) sends that exact
literal to a C check:

```astra example=guide-counted
language astra27b;
[CCode(text_abi = "utf8-i32")]
extern(C) int check_counted(borrowed string text);

int main() {
	return check_counted("é\0");
}
```

Here is the complete [provider](../../tests/books/guide-text.c), including the
`show_text` sink used in Text/Errors. `check_counted` first checks the length,
then the three bytes. C short-circuit evaluation prevents those byte reads if
the length is wrong.

```c example=guide-text-provider
#include <stdint.h>
#include <stdio.h>

int show_text(const unsigned char *text, int32_t length) {
	if (length < 0 || length > 1024) return 1;
	if (fwrite(text, 1, (size_t)length, stdout) != (size_t)length) return 2;
	return fputc('\n', stdout) == EOF;
}

int check_counted(const unsigned char *text, int32_t length) {
	return length != 3 || text[0] != 0xc3 || text[1] != 0xa9 || text[2] != 0;
}
```

The byte-count check supplies a complete executable answer without asking a
terminal to display NUL visibly. Compile and run it:

```sh tutorial=counted-answer
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/counted.o" tests/books/guide-counted.astra
cc -std=c11 -O0 -Wall -Wextra -Werror -c tests/books/guide-text.c \
    -o "$ASTRA_BOOK_BUILD/counted-provider.o"
cc -no-pie "$ASTRA_BOOK_BUILD/counted.o" "$ASTRA_BOOK_BUILD/counted-provider.o" \
    -o "$ASTRA_BOOK_BUILD/counted"
"$ASTRA_BOOK_BUILD/counted"
printf '%s\n' 'Counted UTF-8: c3 a9 00, length 3 (exit 0).'
```

The Astra/C program is silent and returns 0 after observing all three bytes.
Treating this as a C string and calling `strlen` would apply a different contract.
Counted text also does not imply Unicode normalization, character indexing or
grapheme segmentation.

## From a reporter to a file provider

The same `app-report.c` also supplies `reading_count()` and `read_reading(index)`.
Its load operation obtains a path from `ASTRA_READINGS_INPUT`, opens the file,
parses bounded integer records into a fixed C array, closes the file, and returns
the count or -1 on failure. Only after a successful load may the caller request
indices from zero through count minus one. An out-of-range request aborts; it is
not a recoverable Astra exception.

That provider storage is C state. The next chapter copies validated values into
an Astra-owned array so the calculation can borrow ordinary Astra data. The
provider retains neither the reporting label nor an Astra array pointer, and
its single static input buffer is not a thread-safe file service.

[ABI](../reference/abi.md) states the supported counted/scalar boundary. This
example does not establish general typed-pointer, varargs, C aggregate or callback
support. The [typed-pointer refusal](../../tests/books/negative-pointer.astra)
remains a separate native limitation. With the actual boundary understood,
continue to [the multi-file application](application.md).
