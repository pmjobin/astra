/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#ifdef USE_SDK
#include "imports16.h"
#else
typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
#endif
typedef struct provider16_handle {
	int32_t value;
	unsigned references;
} provider16_handle;
static unsigned constructed, retired, exceptions;
int32_t imports16_exception_retired(void) {
	++exceptions;
	return 0;
}
static int32_t failure(astra_foreign_error *error) {
	if (error) {
		error->domain = 16;
		error->code = -1600;
	}
	return -1600;
}
static void clear(astra_foreign_error *error) {
	if (error) {
		error->domain = 0;
		error->code = 0;
	}
}
int32_t provider16_create(int32_t initial, provider16_handle **out, astra_foreign_error *error) {
	assert(out);
	*out = NULL;
	clear(error);
	if (initial == -1) return failure(error);
	if (initial == -3) return 0;
	*out = calloc(1, sizeof **out);
	assert(*out);
	++constructed;
	(*out)->value = initial;
	(*out)->references = 1;
	if (initial == -4) return 1;
	if (initial == -5) {
		failure(error);
		error->domain = 17;
		return -1600;
	}
	if (initial == -6) {
		failure(error);
		error->code = -1601;
		return -1600;
	}
	if (initial == -7) {
		failure(error);
		return 0;
	}
	return initial == -2 ? failure(error) : 0;
}
#ifdef EXPECT_SHARED
uint32_t provider16_release(provider16_handle *self) {
	if (!self) return 0;
	unsigned n = --self->references;
	if (!n) {
		++retired;
		free(self);
	}
	return n;
}
#else
int32_t provider16_destroy(provider16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner);
	if (*owner) {
		assert((*owner)->references == 1);
		++retired;
		free(*owner);
		*owner = NULL;
	}
	return 0;
}
#endif
#define COPIED(NAME, TYPE, EXPR) \
int32_t provider16_##NAME(provider16_handle *self, TYPE input, TYPE *out, astra_foreign_error *error) { assert(self && out); clear(error); *out=(EXPR); return 0; }
COPIED(unsigned32, uint32_t, input + (uint32_t)self->value)
COPIED(signed64, int64_t, input + self->value)
COPIED(unsigned64, uint64_t, input + (uint64_t)self->value)
COPIED(single, float, input + (float)self->value)
COPIED(double_value, double, input + self->value)
COPIED(choose, bool, !input)
int32_t provider16_sum(provider16_handle *self, int32_t input, int32_t *out, astra_foreign_error *error) {
	assert(self && out);
	*out = 999;
	if (input < 0) return failure(error);
	clear(error);
	*out = self->value + input;
	return 0;
}
int32_t provider16_update(provider16_handle *self, int32_t input, astra_foreign_error *error) {
	assert(self);
	clear(error);
	self->value = input;
	return 0;
}
extern int32_t imported16_run(int32_t mode);
int main(void) {
	for (int32_t mode = 0; mode < 8; ++mode) {
		int32_t code = imported16_run(mode);
		if (code) {
			fprintf(stderr, "mode %d returned %d\n", mode, code);
			return 1;
		}
	}
	assert(constructed == 6 && retired == 6 && exceptions == 8);
	puts("PASS typed C Class imports and checked native errors");
	return 0;
}
