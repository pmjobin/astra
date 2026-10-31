/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
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
typedef struct handle_provider16_handle {
	int32_t value;
	unsigned references;
} handle_provider16_handle;
typedef struct child_provider16_handle {
	int32_t value;
} child_provider16_handle;
static unsigned roots, root_retired, children, child_retired, exceptions, expected_retirement, acquires;
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
int32_t handles16_error_seen(void) {
	++exceptions;
	if (expected_retirement) {
		assert(child_retired == expected_retirement);
		expected_retirement = 0;
	}
	return 0;
}
int32_t handle_provider16_create(int32_t value, handle_provider16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = calloc(1, sizeof **out);
	assert(*out);
	(*out)->value = value;
	(*out)->references = 1;
	++roots;
	return 0;
}
#ifdef EXPECT_SHARED
uint32_t handle_provider16_release(handle_provider16_handle *self) {
	assert(self && self->references);
	unsigned n = --self->references;
	if (!n) {
		++root_retired;
		free(self);
	}
	return n;
}
#else
int32_t handle_provider16_destroy(handle_provider16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner && *owner);
	++root_retired;
	free(*owner);
	*owner = NULL;
	return 0;
}
#endif
int32_t child_provider16_create(int32_t value, child_provider16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = malloc(sizeof **out);
	assert(*out);
	(*out)->value = value;
	++children;
	return 0;
}
int32_t child_provider16_destroy(child_provider16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner && *owner);
	++child_retired;
	(*owner)->value = -999;
	free(*owner);
	*owner = NULL;
	return 0;
}
int32_t child_provider16_code(child_provider16_handle *self, int32_t *out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = self->value;
	return 0;
}
int32_t handle_provider16_combine(handle_provider16_handle *self, child_provider16_handle *input, int32_t extra, int32_t *out, astra_foreign_error *error) {
	assert(self && input && out);
	clear(error);
	*out = self->value + input->value + extra;
	return 0;
}
int32_t handle_provider16_optional(handle_provider16_handle *self, child_provider16_handle *input, int32_t *out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = self->value + (input ? input->value : 0);
	return 0;
}
int32_t handle_provider16_make(handle_provider16_handle *self, int32_t mode, uint8_t *output, int32_t capacity, int32_t *count, child_provider16_handle **out, astra_foreign_error *error) {
	assert(self && output && capacity == 3 && count && out);
	clear(error);
	*count = 2;
	output[0] = 41;
	output[1] = 42;
	*out = NULL;
	if (mode == 2) {
		return 0;
	}
	child_provider16_create(self->value + 10, out, error);
	if (mode == 1 || mode == 3) {
		expected_retirement = child_retired + 1;
	}
	if (mode == 1) {
		return fail(error);
	}
	if (mode == 3) {
		*count = capacity + 1;
	}
	return 0;
}
int32_t handle_provider16_lookup(handle_provider16_handle *self, int32_t mode, child_provider16_handle **out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = NULL;
	if (mode == 0) {
		return 1;
	}
	if (mode == 3) {
		return 0;
	}
	child_provider16_create(self->value + 20, out, error);
	if (mode == 1) {
		expected_retirement = child_retired + 1;
		return 1;
	}
	return 0;
}
int32_t handle_provider16_duplicate(handle_provider16_handle *self, handle_provider16_handle **out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
#ifdef EXPECT_SHARED
	++self->references;
	++acquires;
	*out = self;
	return 0;
#else
	return handle_provider16_create(self->value, out, error);
#endif
}
extern int32_t import_handles16_run(void);
int main(void) {
	int32_t result = import_handles16_run();
	if (result) {
		fprintf(stderr, "handle imports returned %d\n", result);
		return 1;
	}
	assert(children == 6 && child_retired == 6 && roots == root_retired && exceptions == 6 && expected_retirement == 0);
#ifdef EXPECT_SHARED
	assert(roots == 1 && acquires == 1);
#else
	assert(roots == 2 && acquires == 0);
#endif
	puts("PASS typed C Class imports and exact cross-root owner cleanup");
	return 0;
}
