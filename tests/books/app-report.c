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
