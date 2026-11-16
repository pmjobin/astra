# A multi-file readings application

Build a small real tool that reads bounded integer data from a file, computes a
summary in Astra, and reports it through an explicit native interface. Splitting
the model from the entry point makes the reusable calculation visible without
inventing a package manager. The input is selected by `ASTRA_READINGS_INPUT`;
its environment/file interface is a deliberate property of this example's C
provider, not a new compiler command-line feature.

The model owns no input storage. It borrows the caller's array and returns a
copied summary record:

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

The entry point obtains the provider's bounded count, allocates the owning
array, copies validated values and invokes the qualified calculation:

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

The array remains owned by `main`; `summarize` borrows it for the call.
The result is a copied record rather than an escaping view. The counted-label
C provider is shown in [Calling native C code](ffi.md). All three source files
form one tested program; no archived source is copied into the live compiler.

## Build and run

Use the exact authenticated compiler environment described in
[Getting started](getting-started.md), and an unused external build leaf:

```sh
"$ASTRA_HOST" -c -O2 -o "$ASTRA_BOOK_BUILD/readings.o" tests/books/app-model.astra tests/books/app-main.astra
cc -std=c11 -O2 -Wall -Wextra -Werror -c tests/books/app-report.c -o "$ASTRA_BOOK_BUILD/report.o"
cc -no-pie "$ASTRA_BOOK_BUILD/readings.o" "$ASTRA_BOOK_BUILD/report.o" -o "$ASTRA_BOOK_BUILD/readings"
ASTRA_READINGS_INPUT="$PWD/tests/books/readings.txt" "$ASTRA_BOOK_BUILD/readings"
test "$?" -eq 42
```

The checked [input data](../../tests/books/readings.txt) contains 2, 4, 6, 8 and
10. Expected stdout is exactly `readings: count=5 total=30` followed by a newline.
The automated runner tests host O0/O2 and target O0/O2, verifies emitted LLVM,
checks exact stdout and runs compiler/program strict memory. It also invokes a
missing file and the [malformed input](../../tests/books/readings-invalid.txt):
both must return 64 with no report. The provider checks values/count bounds
before Astra computes, so the documented input domain cannot overflow the sum.

If a file fails to load, check its path and one-integer-per-line format. If the
link fails, check the real provider object and counted ABI, not a guessed string
termination convention. If a result differs, keep the source/data hashes and
raw execution receipt. There is no network service, deployment, benchmark or
release implication. This is a modest synchronous native file-processing tool
with explicit inputs, useful failure behavior and independently checked output.
