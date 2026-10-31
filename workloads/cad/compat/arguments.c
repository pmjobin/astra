// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Application-only transport to CAD's retained C argv parser. No numeric state.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	int32_t count;
	char *values[];
} CadArguments;

void *cad_arguments_new(int32_t count) {
	if (count < 0 || (size_t)count + 1 > (SIZE_MAX - sizeof(CadArguments)) / sizeof(char *)) {
		fputs("astra-cad: invalid argument count\n", stderr);
		return NULL;
	}
	CadArguments *arguments = calloc(1, sizeof(*arguments) + ((size_t)count + 1) * sizeof(char *));
	if (!arguments) {
		fputs("astra-cad: argument allocation failed\n", stderr);
		return NULL;
	}
	arguments->count = count;
	return arguments;
}

int32_t cad_arguments_copy(void *raw, int32_t index, const unsigned char *data, int32_t length) {
	CadArguments *arguments = raw;
	if (!arguments || index < 0 || index >= arguments->count || arguments->values[index] || length < 0 || (length && (!data || memchr(data, 0, (size_t)length)))) {
		fputs("astra-cad: invalid argument text view\n", stderr);
		return 1;
	}
	char *copy = malloc((size_t)length + 1);
	if (!copy) {
		fputs("astra-cad: argument allocation failed\n", stderr);
		return 1;
	}
	if (length) {
		memcpy(copy, data, (size_t)length);
	}
	copy[length] = '\0';
	arguments->values[index] = copy;
	return 0;
}

void *cad_arguments_values(void *raw) {
	CadArguments *arguments = raw;
	return arguments->values;
}

void cad_arguments_free(void *raw) {
	CadArguments *arguments = raw;
	if (!arguments) {
		return;
	}
	for (int32_t i = 0; i < arguments->count; ++i) {
		free(arguments->values[i]);
	}
	free(arguments);
}
