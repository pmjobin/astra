// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	const char *data;
	int32_t length;
} SourceString;

_Static_assert(sizeof(SourceString) == 16, "string descriptor extent");
_Static_assert(offsetof(SourceString, length) == 8, "string descriptor length");

extern int32_t m26_source_strings(void *data, int32_t count);

int main(int argc, char **argv) {
	if (argc == 1) return m26_source_strings(NULL, 0);
	SourceString *values = calloc((size_t)argc, sizeof(SourceString));
	if (values == NULL) return 4;
	for (int i = 0; i < argc; i++) {
		size_t length = strlen(argv[i]);
		if (length > INT32_MAX) {
			free(values);
			return 5;
		}
		values[i].data = argv[i];
		values[i].length = (int32_t)length;
	}
	int result = m26_source_strings(values, argc);
	free(values);
	return result;
}
