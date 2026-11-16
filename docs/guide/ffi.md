# Calling native C code

An existing C library may already know how to open a file or report a result.
Declare the exact admitted interface, compile its real provider and make the
lifetime contract explicit. Astra does not infer correctness from the foreign
symbol's spelling. It also does not translate an arbitrary header into a safe
native API automatically.

The readings application uses a deliberately small C boundary. Two scalar
functions load a bounded file and read its validated values. A counted-string
function prints the result. The full Astra declarations appear in
[the application chapter](application.md), alongside the owning array that
copies those values into Astra-managed storage.

`text_abi = "utf8-i32"` passes counted bytes and an i32 byte length for the
borrowed label. The following C implementation independently checks both before
printing. It does not keep the borrowed label after returning:

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

The provider limits file values to a range whose 128-element sum fits int.
It closes the file on normal and malformed-input paths and returns failure to
the Astra entry point. Its fixed C array is provider state, not an Astra owner.
`read_reading` requires a successful load and an in-range index; the Astra loop
supplies that protocol. The provider is synchronous and not a thread-safe file
service. Missing paths and malformed input are separately executed failures.

## Build and portability

Compile the provider with the host C toolchain under the qualified environment,
then link its object with the Astra object. The [application recipe](application.md)
shows explicit paths and expected output. A failed foreign link identifies a
missing or mismatched implementation; adding a declaration alone cannot provide
one. Foreign contracts are trust boundaries and need independent tests, as this
provider's byte/count checks illustrate.

This scope is GNU/Linux x86-64. General typed pointers, C aggregate layouts,
varargs, callbacks, GObject and COM policies are not granted by this example.
Some have older historical manuals or frontend representation. Consult
[ABI](../reference/abi.md) and the current feature matrix before selecting them.
No general ownership promise, alias attribute or string terminator is inferred
from a borrowed counted string channel.
