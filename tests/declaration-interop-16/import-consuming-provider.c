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
typedef struct consume_child16_handle {
	int32_t value;
	unsigned references;
} consume_child16_handle;
typedef struct consume_provider16_handle {
	consume_child16_handle *held;
	unsigned references;
} consume_provider16_handle;
static unsigned roots, root_retired, children, child_retired, exceptions, takes, expected_retirement, expected_deferred;
static int deny;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	if (deny > 0 && --deny == 0) {
		return NULL;
	}
	return __real_calloc(count, size);
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
int32_t consume16_arm(int32_t mode) {
	deny = mode == 5 ? 1 : mode == 6 ? 2
	                                 : 0;
	expected_retirement = mode == 9 ? 0 : child_retired + 1;
	expected_deferred = mode == 9 ? child_retired + 1 : 0;
	return 0;
}
int32_t consume16_seen(void) {
	if (expected_retirement) {
		assert(child_retired == expected_retirement);
		expected_retirement = 0;
	}
	if (expected_deferred) {
		assert(child_retired + 1 == expected_deferred);
		expected_deferred = 0;
	}
	return 0;
}
int32_t consume16_error_seen(void) {
	++exceptions;
	consume16_seen();
	return 0;
}
int32_t consume_child16_create(int32_t value, consume_child16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = malloc(sizeof **out);
	assert(*out);
	(*out)->value = value;
	(*out)->references = 1;
	++children;
	return 0;
}
#ifdef CHILD_SHARED
uint32_t consume_child16_release(consume_child16_handle *self) {
	assert(self && self->references);
	unsigned n = --self->references;
	if (!n) {
		++child_retired;
		self->value = -999;
		free(self);
	}
	return n;
}
static void drop(consume_child16_handle **owner) {
	consume_child16_handle *self = *owner;
	*owner = NULL;
	if (self) {
		consume_child16_release(self);
	}
}
#else
int32_t consume_child16_destroy(consume_child16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner && *owner);
	consume_child16_handle *self = *owner;
	*owner = NULL;
	++child_retired;
	self->value = -999;
	free(self);
	return 0;
}
static void drop(consume_child16_handle **owner) {
	if (*owner) {
		astra_foreign_error error;
		assert(consume_child16_destroy(owner, &error) == 0);
	}
}
#endif
int32_t consume_child16_code(consume_child16_handle *self, int32_t *out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = self->value;
	return 0;
}
int32_t consume_child16_duplicate(consume_child16_handle *self, consume_child16_handle **out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
#ifdef CHILD_SHARED
	++self->references;
	*out = self;
	return 0;
#else
	return consume_child16_create(self->value, out, error);
#endif
}
int32_t consume_provider16_create(consume_provider16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = calloc(1, sizeof **out);
	assert(*out);
	(*out)->references = 1;
	++roots;
	return 0;
}
#ifdef EXPECT_SHARED
uint32_t consume_provider16_release(consume_provider16_handle *self) {
	assert(self && self->references);
	unsigned n = --self->references;
	if (!n) {
		drop(&self->held);
		++root_retired;
		free(self);
	}
	return n;
}
#else
int32_t consume_provider16_destroy(consume_provider16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner && *owner);
	consume_provider16_handle *self = *owner;
	*owner = NULL;
	drop(&self->held);
	++root_retired;
	free(self);
	return 0;
}
#endif
int32_t consume_provider16_take(consume_provider16_handle *self, consume_child16_handle **input, const uint8_t *seed, int32_t length, uint8_t *output, int32_t capacity, int32_t *count, int32_t mode, int32_t *out, astra_foreign_error *error) {
	assert(self && input && *input && seed && length == 3 && output && capacity == 4 && count && out);
	++takes;
	clear(error);
	*out = (*input)->value;
	for (int32_t i = 0; i < length; ++i) {
		*out += seed[i];
	}
	output[0] = 31;
	output[1] = 32;
	*count = 2;
	if (mode == 0 || mode == 2) {
		drop(input);
	}
	if (mode == 1 || mode == 2) {
		return fail(error);
	}
	if (mode == 4) {
		*count = capacity + 1;
	}
	if (mode == 9) {
		assert(!self->held);
		self->held = *input;
		*input = NULL;
	}
	return 0;
}
int32_t consume_provider16_relay(consume_provider16_handle *self, consume_child16_handle **input, consume_child16_handle **out, astra_foreign_error *error) {
	assert(self && input && *input && out);
	clear(error);
	*out = *input;
	*input = NULL;
	return 0;
}
int32_t consume_provider16_pair(consume_provider16_handle *self, consume_child16_handle **first, consume_child16_handle **second, int32_t *out, astra_foreign_error *error) {
	assert(self && first && *first && second && *second && out);
	clear(error);
	*out = (*first)->value + (*second)->value;
	drop(first);
	drop(second);
	return 0;
}
int32_t consume_provider16_empty(consume_provider16_handle *self, consume_provider16_handle **out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = NULL;
	return 1;
}
int32_t consume_provider16_empty_child(consume_provider16_handle *self, consume_child16_handle **out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = NULL;
	return 1;
}
extern int32_t import_consuming16_run(int32_t mode);
int main(void) {
	for (int32_t mode = 0; mode < 11; ++mode) {
		int32_t result = import_consuming16_run(mode);
		if (result) {
			fprintf(stderr, "consuming mode %d returned %d\n", mode, result);
			return 1;
		}
		assert(roots == root_retired && children == child_retired && expected_retirement == 0 && expected_deferred == 0);
	}
	assert(roots == 11 && takes == 6 && exceptions == 8);
#ifdef CHILD_SHARED
	assert(children == 12);
#else
	assert(children == 13);
#endif
	puts("PASS typed C Class imports and consuming owner-slot rollback");
	return 0;
}
