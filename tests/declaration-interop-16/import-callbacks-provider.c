/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#ifdef USE_SDK
#include "imports16.h"
#else

typedef struct RECORD_READING {
	int64_t astra_field_0_total;
	double astra_field_1_scale;
	int32_t astra_field_2_count;
} RECORD_READING;

typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
typedef struct callback_relay16_handle callback_relay16_handle;
extern int32_t callback_relay16_create(callback_relay16_handle **, astra_foreign_error *);
extern int32_t callback_relay16_invoke(callback_relay16_handle *, int32_t, int64_t (*)(void *, int32_t, uint32_t, int64_t, uint64_t, float, double, bool), void *, bool, int64_t *, astra_foreign_error *);
extern int32_t callback_relay16_destroy(callback_relay16_handle **, astra_foreign_error *);
#endif

typedef struct callback_provider16_handle {
	int32_t seed;
	unsigned references;
} callback_provider16_handle;

static unsigned made, retired, exceptions, wide_calls, notifications, choices, checked_calls, external_calls;

static void clear(astra_foreign_error *error) {
	assert(error);
	error->domain = 0;
	error->code = 0;
}

int32_t importcallbacks16_exception_retired(void) {
	++exceptions;
	return 0;
}

void importcallbacks16_seen(int32_t value) {
	assert(value == 11);
	++notifications;
}

int32_t callback_provider16_create(int32_t seed, callback_provider16_handle **out, astra_foreign_error *error) {
	assert(out);
	clear(error);
	*out = calloc(1, sizeof **out);
	assert(*out);
	(*out)->seed = seed;
	(*out)->references = 1;
	++made;
	return 0;
}

#ifdef EXPECT_SHARED

uint32_t callback_provider16_release(callback_provider16_handle *self) {
	if (!self) {
		return 0;
	}
	unsigned remaining = --self->references;
	if (!remaining) {
		++retired;
		free(self);
	}
	return remaining;
}

#else

int32_t callback_provider16_destroy(callback_provider16_handle **owner, astra_foreign_error *error) {
	assert(owner);
	clear(error);
	if (*owner) {
		assert((*owner)->references == 1);
		++retired;
		free(*owner);
		*owner = NULL;
	}
	return 0;
}

#endif

int32_t callback_provider16_invoke(callback_provider16_handle *self, int32_t offset, int64_t (*code)(void *, int32_t, uint32_t, int64_t, uint64_t, float, double, bool), void *data, bool enabled, int64_t *out, astra_foreign_error *error) {
	assert(self && code && data && out);
	clear(error);
	++wide_calls;
	*out = code(data, self->seed + offset, UINT32_C(4000000000), INT64_C(-5000000000), UINT64_C(9223372036854775809), 1.25f, 2.5, enabled) + 11;
	return 0;
}

int32_t callback_provider16_notify(callback_provider16_handle *self, void (*code)(void *, int32_t), void *data, int32_t delta, astra_foreign_error *error) {
	assert(self && code && data);
	clear(error);
	code(data, self->seed + delta);
	return 0;
}

int32_t callback_provider16_choose(callback_provider16_handle *self, bool input, bool (*code)(void *, bool), void *data, bool *out, astra_foreign_error *error) {
	assert(self && code && data && out);
	clear(error);
	++choices;
	*out = code(data, input);
	return 0;
}

int32_t callback_provider16_checked(callback_provider16_handle *self, int32_t (*code)(void *, int32_t), void *data, int32_t input, int32_t *out, astra_foreign_error *error) {
	assert(self && code && data && out);
	clear(error);
	++checked_calls;
	int32_t value = code(data, input);
	*out = 999;
	if (input < 0) {
		error->domain = 16;
		error->code = -1600;
		return -1600;
	}
	*out = value + self->seed;
	return 0;
}

int32_t callback_provider16_aggregate(callback_provider16_handle *self, RECORD_READING input, int64_t (*code)(void *, int64_t), void *data, int64_t *out, astra_foreign_error *error) {
	assert(self && code && data && out && input.astra_field_1_scale == 2.5);
	clear(error);
	*out = code(data, input.astra_field_0_total) + input.astra_field_2_count;
	return 0;
}

int32_t callback_provider16_optional(callback_provider16_handle *self, void (*code)(void *, int32_t), void *data, int32_t delta, astra_foreign_error *error) {
	assert(self);
	clear(error);
	if (code) {
		assert(data);
		code(data, self->seed + delta);
	} else {
		assert(data == NULL);
	}
	return 0;
}

typedef struct context {
	int32_t offset, extra;
	callback_relay16_handle *root;
} context;

static int64_t external(void *data, int32_t a, uint32_t b, int64_t c, uint64_t d, float e, double f, bool g) {
	context *state = data;
	assert(state && a == 7 + state->offset && b == UINT32_C(4000000000) && c == INT64_C(-5000000000) && d == UINT64_C(9223372036854775809) && e == 1.25f && f == 2.5 && g);
	++external_calls;
	callback_relay16_handle *alias = state->root;
	astra_foreign_error error = {0, 0};
	assert(callback_relay16_destroy(&alias, &error) == (int32_t)UINT32_C(0x80010001) && alias == state->root);
	return c + state->extra;
}

extern int32_t importcallbacks16_run(void);

int main(void) {
	assert(importcallbacks16_run() == 0);
	callback_relay16_handle *root = NULL;
	astra_foreign_error error = {0, 0};
	assert(callback_relay16_create(&root, &error) == 0 && root);
	context first = {3, 21, root}, second = {5, 33, root};
	int64_t value = 0;
	assert(callback_relay16_invoke(root, first.offset, external, &first, true, &value, &error) == 0 && value == INT64_C(-4999999968));
	assert(callback_relay16_invoke(root, second.offset, external, &second, true, &value, &error) == 0 && value == INT64_C(-4999999956));
	assert(callback_relay16_destroy(&root, &error) == 0 && !root);
	assert(made == 3 && retired == 3 && exceptions == 1 && wide_calls == 3 && notifications == 2 && choices == 2 && checked_calls == 2 && external_calls == 2);
	puts("PASS typed C callback imports and exact roundtrip userdata");
	return 0;
}
