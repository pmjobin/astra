# A multi-file readings application

We can finally replace generated readings with a real file. The finished tool
loads bounded integer data, copies it into an Astra-owned array, computes a
summary, and reports the result through C. Each part has a small job: the model
calculates, the entry point coordinates ownership and failure, and the provider
talks to the host environment.

The input [readings.txt](../../tests/books/readings.txt) contains one value per
line: 2, 4, 6, 8, 10. Before building, predict the output: count 5, total 30.
Later in the chapter we will change the model while preserving both the entry
point and the provider.

## Keep the calculation independent of I/O

The complete [model](../../tests/books/app-model.astra) borrows the input and
returns a copied record:

```astra example=app-model
language astra27b;
namespace Readings;
struct Summary {
	int count;
	int total;
}

Summary summarize(borrowed int[] values) {
	int total = 0;
	int at = 0;
	while (at < len(values)) {
		total += values[at];
		at += 1;
	}
	return Summary {count = len(values), total};
}
```

`namespace Readings;` gives the declarations a namespace. It does not discover
source files or install a package. The compile command below explicitly supplies
this file. `Summary` is the same kind of scalar record introduced earlier; its
count and total can outlive the input array because they are copied integers.

The model has no file path, C call or allocation. Its caller keeps the array
alive throughout `summarize`. An empty array naturally produces count zero and
total zero, because the loop body never runs.

## Coordinate the boundaries in the entry point

The complete [entry point](../../tests/books/app-main.astra) is:

```astra example=app-main
language astra27b;
[CCode(text_abi = "utf8-i32")]
extern(C) int report_readings(borrowed string label, int count, int total);

extern(C) int reading_count();

extern(C) int read_reading(int index);

int main() {
	int count = reading_count();
	if (count < 0) return 64;
	var readings = new int[count];
	int at = 0;
	while (at < count) {
		readings[at] = read_reading(at);
		at += 1;
	}
	var summary = Readings.summarize(readings);
	if (report_readings("readings", summary.count, summary.total) != 0) return 2;
	return 42;
}
```

First, `reading_count()` tries to load the file. A negative result ends the
program with status 64 before allocation or reporting. This is a C status
protocol, not the throwing Error channel from the validation lesson.

After a successful load, `new int[count]` creates an owning runtime array.
The loop copies each provider value into it. The owner stays in `main` while
`Readings.summarize` borrows it. The returned summary then crosses the scalar
reporting boundary, alongside the borrowed literal label. Normal return cleans
up the array.

This design carries forward the ownership lesson without allocating a separate
class object for each integer. One array owner is enough for these stored values.
The model also stays concrete: its input domain is always `int`, so the earlier
generic's second-type use case does not arise here. Choose those abstractions
when their requirements appear, rather than adding every learned feature to
one program.

This existing application uses **exit 42 as its successful test sentinel**.
That convention is deliberately preserved. A caller must capture it explicitly;
it is not ordinary command success, and it is not the number printed as the
total. Reporting failure returns 2; input failure returns 64.

## Inspect the complete provider

The third source file is [app-report.c](../../tests/books/app-report.c):

```c example=app-report
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int readings[128];
static int count;

int reading_count(void) {
	const char *path = getenv("ASTRA_READINGS_INPUT");
	if (!path) return -1;
	FILE *input = fopen(path, "r");
	if (!input) return -1;
	char line[128];
	count = 0;
	int failed = 0;
	while (fgets(line, sizeof line, input)) {
		char *end;
		errno = 0;
		long value = strtol(line, &end, 10);
		if (end == line || errno || value < -100000 || value > 100000 || count == 128) {
			failed = 1;
			break;
		}
		while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')
			++end;
		if (*end) {
			failed = 1;
			break;
		}
		readings[count++] = (int)value;
	}
	if (ferror(input)) failed = 1;
	if (fclose(input) != 0) failed = 1;
	return failed ? -1 : count;
}

int read_reading(int index) {
	if (index < 0 || index >= count) abort();
	return readings[index];
}

int report_readings(const unsigned char *label, int32_t length, int count, int total) {
	if (length != 8 || memcmp(label, "readings", 8) != 0 || count < 0 || count > 128) return 1;
	return printf("readings: count=%d total=%d\n", count, total) < 0;
}
```

The input policy bounds each parsed value to -100000 through 100000 and the
count to 128. Therefore the largest magnitude of a sum is 12,800,000, safely
inside `int`'s signed 32-bit range. This reasoning establishes a bound for the
calculation instead of relying on wrapping to happen harmlessly.

`fclose` runs after normal reading and after a malformed record; failures are
reported as -1. The fixed C buffer and `fgets`/`strtol` parsing are deliberately
small development-provider code, not a general CSV parser. Use the demonstrated
short, one-integer-per-line format. The loader accepts negative values within
its bounds; the [Text/Errors chapter's](text-errors.md) nonnegative policy was a separate validation
example, not an implicit language rule applied to this file.

## Build all three inputs

Use the authenticated environment from Getting started. The Astra compiler
receives both Astra sources in one invocation; the C compiler builds the
provider, and the linker combines the objects:

```sh tutorial=application
"$ASTRA_HOST" -c -O2 -o "$ASTRA_BOOK_BUILD/readings.o" \
    tests/books/app-model.astra tests/books/app-main.astra
cc -std=c11 -O2 -Wall -Wextra -Werror -c tests/books/app-report.c \
    -o "$ASTRA_BOOK_BUILD/readings-provider.o"
cc -no-pie "$ASTRA_BOOK_BUILD/readings.o" "$ASTRA_BOOK_BUILD/readings-provider.o" \
    -o "$ASTRA_BOOK_BUILD/readings"
ASTRA_STATUS=0
ASTRA_READINGS_INPUT="$PWD/tests/books/readings.txt" "$ASTRA_BOOK_BUILD/readings" \
    || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 42
```

Expected stdout is exactly:

```text
readings: count=5 total=30
```

There is a final newline and no stderr. `ASTRA_READINGS_INPUT` belongs to this
C provider's environment interface; it is not a compiler option or a package
configuration file.

## Observe input failures and the empty case

A missing file and [malformed data](../../tests/books/readings-invalid.txt)
should both return 64 without a report. An [empty file](../../tests/books/guide-readings-empty.txt)
is different: it is valid input with no readings. Run all three cases:

```sh tutorial=application-inputs
for ASTRA_INPUT in "$PWD/tests/books/readings-invalid.txt" "$ASTRA_BOOK_BUILD/missing-readings.txt"; do
    ASTRA_STATUS=0
    ASTRA_READINGS_INPUT="$ASTRA_INPUT" "$ASTRA_BOOK_BUILD/readings" \
        > "$ASTRA_BOOK_BUILD/refused-report.txt" 2> "$ASTRA_BOOK_BUILD/refused-error.txt" \
        || ASTRA_STATUS=$?
    test "$ASTRA_STATUS" -eq 64
    test ! -s "$ASTRA_BOOK_BUILD/refused-report.txt"
    test ! -s "$ASTRA_BOOK_BUILD/refused-error.txt"
done
ASTRA_STATUS=0
ASTRA_READINGS_INPUT="$PWD/tests/books/guide-readings-empty.txt" "$ASTRA_BOOK_BUILD/readings" \
    || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 42
```

Only the last run prints: `readings: count=0 total=0` plus a newline. The first
two runs have no summary to report. The full application checks also exercise
[128 maximum readings](../../tests/books/guide-readings-maximum.txt), totaling
12,800,000, and refuse both [129 readings](../../tests/books/guide-readings-too-many.txt)
and an [out-of-range value](../../tests/books/guide-readings-out-of-range.txt).

If loading fails, inspect the path and input format before changing the arithmetic.
If linking fails, inspect the provider object. If the program reports a wrong
summary, inspect the model and data. These are different boundaries with different
repairs.

## Exercise: remove calibration readings from the summary

Return to the early exercise that excluded six. This time, leave the input
file, entry point and C provider unchanged. Change only the model so count and
total describe the retained values, not the original array length. What must
happen to the index when a value is excluded?

Here is the [complete alternative model](../../tests/books/guide-app-filter.astra):

```astra example=guide-app-filter
language astra27b;
namespace Readings;
struct Summary {
	int count;
	int total;
}

Summary summarize(borrowed int[] values) {
	int count = 0;
	int total = 0;
	int at = 0;
	while (at < len(values)) {
		if (values[at] != 6) {
			count += 1;
			total += values[at];
		}
		at += 1;
	}
	return Summary {count, total};
}
```

The index advances on every iteration. The accepted count advances only inside
the condition, just like the total. For the original file the result is count
4, total 24. Compile the alternative model **instead of** `app-model.astra`;
including both would define the same namespace members twice.

```sh tutorial=application-answer
"$ASTRA_HOST" -c -O2 -o "$ASTRA_BOOK_BUILD/filtered-readings.o" \
    tests/books/guide-app-filter.astra tests/books/app-main.astra
cc -no-pie "$ASTRA_BOOK_BUILD/filtered-readings.o" "$ASTRA_BOOK_BUILD/readings-provider.o" \
    -o "$ASTRA_BOOK_BUILD/filtered-readings"
ASTRA_STATUS=0
ASTRA_READINGS_INPUT="$PWD/tests/books/readings.txt" "$ASTRA_BOOK_BUILD/filtered-readings" \
    || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 42
```

Expected stdout is `readings: count=4 total=24` with a newline. The original
application remains available for comparison. Both versions keep the same
malformed/missing-input behavior and ownership boundary.

You have a complete program whose parts you can change deliberately. Next,
[Tooling](tooling.md) uses that program to inspect a checked API and repeat a
focused edit/check cycle without turning every small change into a full test campaign.
