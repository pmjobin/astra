/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#ifdef USE_SDK
#include "foreign16.h"
#else
typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
typedef struct foreign_item16_handle foreign_item16_handle;
typedef struct foreign_container16_handle foreign_container16_handle;
int32_t foreign_container16_create(foreign_item16_handle **, int32_t, foreign_container16_handle **, astra_foreign_error *);
int32_t foreign_container16_stored(foreign_container16_handle *, int32_t *, astra_foreign_error *);
int32_t foreign_container16_observe(foreign_container16_handle *, foreign_item16_handle *, int32_t, int32_t *, astra_foreign_error *);
int32_t foreign_container16_optional(foreign_container16_handle *, foreign_item16_handle *, int32_t *, astra_foreign_error *);
int32_t foreign_container16_burn(foreign_container16_handle *, foreign_item16_handle **, foreign_item16_handle *, int32_t, int32_t *, astra_foreign_error *);
int32_t foreign_container16_relay(foreign_container16_handle *, foreign_item16_handle **, foreign_item16_handle **, astra_foreign_error *);
int32_t foreign_container16_produce(foreign_container16_handle *, uint8_t *, int32_t, int32_t *, int32_t, foreign_item16_handle **, astra_foreign_error *);
int32_t foreign_container16_absent(foreign_container16_handle *, foreign_item16_handle **, astra_foreign_error *);
#ifdef EXPECT_SHARED
uint32_t foreign_container16_release(foreign_container16_handle *);
#else
int32_t foreign_container16_destroy(foreign_container16_handle **, astra_foreign_error *);
#endif
#endif
struct foreign_item16_handle {
	int32_t value;
	unsigned references;
};
static unsigned created, retired, exceptions, destructors, acquires;
static unsigned reads;
#ifdef ITEM_SHARED
static int refuse_acquire;
#endif
static int deny;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	if (deny > 0 && --deny == 0) {
		return NULL;
	}
	return __real_calloc(count, size);
}
int32_t foreign16_retired(int32_t kind) {
	if (kind == 1) {
		++exceptions;
	} else {
		assert(kind == 2);
		++destructors;
	}
	return 0;
}
static void clear(astra_foreign_error *error) {
	assert(error);
	error->domain = 0;
	error->code = 0;
}
int32_t foreign_item16_create(int32_t value, foreign_item16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = malloc(sizeof **out);
	assert(*out);
	(*out)->value = value;
	(*out)->references = 1;
	++created;
	return 0;
}
int32_t foreign_item16_code(foreign_item16_handle *self, int32_t *out, astra_foreign_error *error) {
	assert(self && self->references && out);
	++reads;
	clear(error);
	*out = self->value;
	return 0;
}
#ifdef ITEM_SHARED
uint32_t foreign_item16_acquire(foreign_item16_handle *self) {
	assert(self && self->references);
	if (refuse_acquire) {
		return 0;
	}
	++acquires;
	return ++self->references;
}
uint32_t foreign_item16_release(foreign_item16_handle *self) {
	assert(self && self->references);
	unsigned n = --self->references;
	if (!n) {
		++retired;
		self->value = -999;
		free(self);
	}
	return n;
}
static void drop(foreign_item16_handle **owner) {
	foreign_item16_handle *self = *owner;
	*owner = NULL;
	if (self) {
		foreign_item16_release(self);
	}
}
#else
int32_t foreign_item16_destroy(foreign_item16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner && *owner);
	foreign_item16_handle *self = *owner;
	*owner = NULL;
	++retired;
	self->value = -999;
	free(self);
	return 0;
}
static void drop(foreign_item16_handle **owner) {
	if (*owner) {
		astra_foreign_error error;
		assert(foreign_item16_destroy(owner, &error) == 0);
	}
}
#endif
static foreign_item16_handle *item(int32_t value) {
	foreign_item16_handle *result = NULL;
	astra_foreign_error error;
	assert(foreign_item16_create(value, &result, &error) == 0);
	return result;
}
static void close_container(foreign_container16_handle **owner) {
	assert(owner && *owner);
#ifdef EXPECT_SHARED
	assert(foreign_container16_release(*owner) == 0);
	*owner = NULL;
#else
	astra_foreign_error error;
	assert(foreign_container16_destroy(owner, &error) == 0 && !*owner);
#endif
}
#define STATUS(v) ((int32_t)UINT32_C(v))
int main(void) {
	astra_foreign_error error;
	foreign_item16_handle *seed = item(10);
	foreign_container16_handle *self = NULL;
	int32_t value = -1;
	assert(foreign_container16_create(&seed, 0, &self, &error) == 0 && !seed && self);
	assert(foreign_container16_stored(self, &value, &error) == 0 && value == 10);
	foreign_item16_handle *input = item(20);
	assert(foreign_container16_observe(self, input, 3, &value, &error) == 0 && value == 23);
	assert(foreign_container16_optional(self, NULL, &value, &error) == 0 && value == -1);
	assert(foreign_container16_optional(self, input, &value, &error) == 0 && value == 20);
#ifdef ITEM_SHARED
	unsigned prior_reads = reads;
	refuse_acquire = 1;
	assert(foreign_container16_observe(self, input, 0, &value, &error) == STATUS(0x8000ffff) && value == 0 && reads == prior_reads && input->references == 1);
	refuse_acquire = 0;
#endif
	assert(foreign_container16_observe(self, NULL, 0, &value, &error) == STATUS(0x80004003) && value == 0);
	foreign_item16_handle *returned = NULL;
	assert(foreign_container16_relay(self, &input, &input, &error) == STATUS(0x80070057) && input);
	assert(foreign_container16_relay(self, &input, &returned, &error) == 0 && !input && returned);
	drop(&returned);
	input = item(30);
#ifdef ITEM_SHARED
	assert(foreign_container16_burn(self, &input, input, 0, &value, &error) == 0 && !input && value == 60);
#else
	assert(foreign_container16_burn(self, &input, input, 0, &value, &error) == STATUS(0x80010001) && input && value == 0);
	foreign_item16_handle *view = item(31);
	assert(foreign_container16_burn(self, &input, view, 0, &value, &error) == 0 && !input && value == 61);
	drop(&view);
#endif
	input = item(32);
	foreign_item16_handle *view2 = item(33);
	assert(foreign_container16_burn(self, &input, view2, 1, &value, &error) == -1600 && !input && value == 0 && error.domain == 16);
	drop(&view2);
	uint8_t output[4] = {77, 77, 77, 77};
	int32_t count = -1;
	assert(foreign_container16_produce(self, output, 4, &count, 0, &returned, &error) == 0 && returned && count == 2 && output[0] == 11 && output[1] == 12 && output[2] == 77);
	assert(foreign_item16_code(returned, &value, &error) == 0 && value == 40);
	drop(&returned);
	for (int32_t mode = 1; mode < 3; ++mode) {
		unsigned before = retired;
		output[0] = 77;
		output[1] = 77;
		count = -1;
		int32_t status = foreign_container16_produce(self, output, 4, &count, mode, &returned, &error);
		assert(status == (mode == 1 ? STATUS(0x8000ffff) : -1600) && !returned && count == 0 && output[0] == 77 && output[1] == 77 && retired == before + 1);
	}
	assert(foreign_container16_absent(self, &returned, &error) == 1 && !returned && error.domain == 0 && error.code == 0);
	close_container(&self);
	assert(created == retired && destructors == 1 && exceptions == 2);
	seed = item(50);
	unsigned before = retired;
	assert(foreign_container16_create(&seed, 1, &self, &error) == -1600 && !seed && !self && retired == before + 1 && destructors == 1 && exceptions == 3);
	seed = item(60);
	deny = 1;
	assert(foreign_container16_create(&seed, 0, &self, &error) == STATUS(0x8007000e) && seed && !self);
	drop(&seed);
	seed = item(70);
	deny = 2;
	assert(foreign_container16_create(&seed, 0, &self, &error) == STATUS(0x8007000e) && !seed && !self && destructors == 2);
	assert(created == retired);
#ifdef ITEM_SHARED
	assert(acquires == 4);
#else
	assert(acquires == 0);
#endif
	puts("PASS native Class exports of typed foreign Resource handles");
	return 0;
}
