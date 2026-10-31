/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#ifdef USE_SDK
#include "imports16.h"
#else
typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
#endif
typedef struct reference_provider16_handle {
	unsigned references;
} reference_provider16_handle;
static unsigned created, retired, calls, exceptions;
int32_t reference16_exception_retired(void) {
	++exceptions;
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
int32_t reference_provider16_create(reference_provider16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = calloc(1, sizeof **out);
	assert(*out);
	(*out)->references = 1;
	++created;
	return 0;
}
#ifdef EXPECT_SHARED
uint32_t reference_provider16_release(reference_provider16_handle *self) {
	if (!self) return 0;
	unsigned n = --self->references;
	if (!n) {
		++retired;
		free(self);
	}
	return n;
}
#else
int32_t reference_provider16_destroy(reference_provider16_handle **owner, astra_foreign_error *error) {
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
int32_t reference_provider16_change(reference_provider16_handle *self, int32_t *a, uint32_t *b, int64_t *c, uint64_t *d, float *e, double *f, int32_t *produced, int32_t mode, bool *out, astra_foreign_error *error) {
	assert(self && a && b && c && d && e && f && produced && out);
	++calls;
	clear(error);
	*a += 10;
	*b += 10;
	*c += 10;
	*d += 10;
	*e *= 2;
	*f *= 2;
	*produced = 13;
	*out = true;
	if (mode == 1) return fail(error);
	if (mode == 2) return 1;
	return 0;
}
int32_t reference_provider16_combine(reference_provider16_handle *self, const int32_t *input, int32_t *left, int32_t *right, int32_t mode, int32_t *out, astra_foreign_error *error) {
	assert(self && input && left && right && out);
	++calls;
	clear(error);
	*left += 7;
	*right = *input + *left;
	*out = *right;
	*(int32_t *)input = 99;
	return mode ? fail(error) : 0;
}
int32_t reference_provider16_observe(reference_provider16_handle *self, const int32_t *input, int32_t *out, astra_foreign_error *error) {
	assert(self && input && out);
	++calls;
	clear(error);
	*out = *input;
	*(int32_t *)input = 22;
	return 0;
}
extern int32_t import_references16_run(void);
int main(void) {
	int32_t result = import_references16_run();
	if (result) {
		fprintf(stderr, "native reference client returned %d\n", result);
		return 1;
	}
	assert(created == 1 && retired == 1 && calls == 6 && exceptions == 4);
	puts("PASS typed C Class imports and staged scalar references");
	return 0;
}
