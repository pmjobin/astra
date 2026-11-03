/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#ifdef USE_SDK
#include "imports16.h"
#else

typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;

#endif

typedef struct counted_provider16_handle {
	int32_t seed;
	unsigned references;
} counted_provider16_handle;

static unsigned created, retired, exceptions, constructors;
static bool provisional;
static int deny;
void *__real_calloc(size_t, size_t);

void *__wrap_calloc(size_t count, size_t size) {
	if (deny > 0 && --deny == 0) {
		return NULL;
	}
	return __real_calloc(count, size);
}

int32_t counted16_exception_retired(void) {
	++exceptions;
	return 0;
}

int32_t counted16_error_seen(void) {
	if (provisional) {
		assert(created == retired);
		provisional = false;
	}
	return 0;
}

static void clear(astra_foreign_error *error) {
	assert(error);
	error->domain = 0;
	error->code = 0;
}

static int32_t fail(astra_foreign_error *error) {
	error->domain = 16;
	error->code = -1600;
	return -1600;
}

int32_t counted_provider16_create(const uint8_t *input, int32_t length, uint8_t *output, int32_t capacity, int32_t *count, int32_t mode, counted_provider16_handle **out, astra_foreign_error *error) {
	assert(input && output && count && out && length == 3 && capacity == 4);
	++constructors;
	clear(error);
	*out = NULL;
	*count = 2;
	output[0] = 11;
	output[1] = 12;
	if (mode == 3) {
		return 0;
	}
	*out = calloc(1, sizeof **out);
	assert(*out);
	++created;
	(*out)->references = 1;
	for (int32_t i = 0; i < length; ++i) {
		(*out)->seed += input[i];
	}
	if (mode == 1 || mode == 2) {
		provisional = true;
	}
	if (mode == 1) {
		return fail(error);
	}
	if (mode == 2) {
		*count = capacity + 1;
	}
	return 0;
}

#ifdef EXPECT_SHARED

uint32_t counted_provider16_release(counted_provider16_handle *self) {
	if (!self) return 0;
	unsigned n = --self->references;
	if (!n) {
		++retired;
		free(self);
	}
	return n;
}

#else

int32_t counted_provider16_destroy(counted_provider16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner);
	if (*owner) {
		++retired;
		free(*owner);
		*owner = NULL;
	}
	return 0;
}

#endif

int32_t counted_provider16_fold(counted_provider16_handle *self, const uint8_t *input, int32_t length, int32_t *out, astra_foreign_error *error) {
	assert(self && input && out);
	clear(error);
	*out = 0;
	for (int32_t i = 0; i < length; ++i) {
		*out += input[i];
	}
	if (length) {
		((uint8_t *)input)[0] = 88;
	}
	return 0;
}

int32_t counted_provider16_rewrite(counted_provider16_handle *self, const uint8_t *input, int32_t length, uint8_t *output, int32_t capacity, int32_t *count, int32_t mode, bool *out, astra_foreign_error *error) {
	assert(self && input && output && count && out && length == 3 && capacity >= 2);
	clear(error);
	memset(output, 0xdd, (size_t)capacity);
	output[0] = (uint8_t)(input[0] + self->seed);
	output[1] = (uint8_t)(input[1] + self->seed);
	*count = 2;
	*out = true;
	if (mode == 1) {
		return fail(error);
	}
	if (mode == 2) {
		*count = -1;
	}
	if (mode == 3) {
		*count = capacity + 1;
	}
	return 0;
}

int32_t counted_provider16_named(counted_provider16_handle *self, const uint8_t *input, int32_t length, uint8_t *output, int32_t capacity, int32_t *count, bool *out, astra_foreign_error *error) {
	return counted_provider16_rewrite(self, input, length, output, capacity, count, 0, out, error);
}

int32_t counted_provider16_mutate(counted_provider16_handle *self, uint8_t *data, int32_t capacity, int32_t *out, astra_foreign_error *error) {
	assert(self && data && capacity == 3 && out);
	clear(error);
	for (int32_t i = 0; i < capacity; ++i)
		data[i] ^= 16;
	*out = 2;
	return 0;
}

int32_t counted_provider16_utf8(counted_provider16_handle *self, const char *input, int32_t length, int32_t *out, astra_foreign_error *error) {
	const unsigned char expected[] = {97, 0, 195, 169};
	assert(self && input && length == 4 && out && memcmp(input, expected, 4) == 0);
	clear(error);
	*out = length;
	((char *)input)[0] = 'Z';
	return 0;
}

int32_t counted_provider16_nul(counted_provider16_handle *self, const char *input, int32_t *out, astra_foreign_error *error) {
	assert(self && input && strcmp(input, "caf\xc3\xa9") == 0 && out);
	clear(error);
	*out = (int32_t)strlen(input);
	return 0;
}

int32_t counted_provider16_text_count(counted_provider16_handle *self, const char *input, int32_t count, int32_t *out, astra_foreign_error *error) {
	assert(self && input && count == 2 && (unsigned char)input[0] == 206 && (unsigned char)input[1] == 187);
	clear(error);
	*out = count;
	return 0;
}

extern int32_t import_counted16_run(int32_t mode);

int main(void) {
	for (int32_t mode = 0; mode < 6; ++mode) {
		deny = mode == 4 ? 1 : mode == 5 ? 2
		                                 : 0;
		int32_t result = import_counted16_run(mode);
		if (result) {
			fprintf(stderr, "counted mode %d returned %d\n", mode, result);
			return 1;
		}
	}
	assert(created == 3 && retired == 3 && constructors == 4 && exceptions == 11 && !provisional);
	puts("PASS typed C Class imports and counted data staging");
	return 0;
}
