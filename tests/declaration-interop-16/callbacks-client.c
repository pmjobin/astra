/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <assert.h>
#ifdef USE_SDK
#include "callbacks16.h"
#else
typedef struct callbacks16_handle callbacks16_handle;

typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;

extern int32_t callbacks16_create(int32_t, callbacks16_handle **, astra_foreign_error *);
extern int32_t callbacks16_transform(callbacks16_handle *, int32_t, int64_t (*)(void *, int32_t, uint32_t, int64_t, uint64_t, float, double, bool), void *, bool, int64_t *, astra_foreign_error *);
extern int32_t callbacks16_notify(callbacks16_handle *, void (*)(void *, int32_t), void *, int32_t, astra_foreign_error *);
extern int32_t callbacks16_choose(callbacks16_handle *, bool, bool (*)(void *, bool), void *, bool *, astra_foreign_error *);
extern int32_t callbacks16_checked(callbacks16_handle *, int32_t (*)(void *, int32_t), void *, int32_t, int32_t *, astra_foreign_error *);

typedef struct RECORD_READING {
	int64_t total;
	double scale;
	int32_t count;
} RECORD_READING;

extern int32_t callbacks16_aggregate(callbacks16_handle *, RECORD_READING, int64_t (*)(void *, int64_t), void *, int64_t *, astra_foreign_error *);
extern int32_t callbacks16_optional(callbacks16_handle *, void (*)(void *, int32_t), void *, int32_t, astra_foreign_error *);
extern int32_t callbacks16_read(callbacks16_handle *, int32_t *, astra_foreign_error *);
#ifdef EXPECT_SHARED
extern uint32_t callbacks16_release(callbacks16_handle *);
#else
extern int32_t callbacks16_destroy(callbacks16_handle **, astra_foreign_error *);
#endif
#endif

typedef struct callback_data {
	unsigned wide, notified, chosen, checked;
	int32_t expected, extra;
	callbacks16_handle *root;
} callback_data;

static void cleared(astra_foreign_error error) {
	assert(error.domain == 0 && error.code == 0);
}

static int64_t transform(void *opaque, int32_t a, uint32_t b, int64_t c, uint64_t d, float e, double f, bool g) {
	callback_data *data = opaque;
	assert(data && a == data->expected && b == UINT32_C(4000000000) && c == INT64_C(-5000000000) && d == UINT64_C(9223372036854775809) && e == 1.25f && f == 2.5 && g);
	++data->wide;
	return c + data->extra;
}

static void notify(void *opaque, int32_t value) {
	callback_data *data = opaque;
	assert(data && value == data->expected);
	++data->notified;
#ifndef EXPECT_SHARED
	callbacks16_handle *alias = data->root;
	astra_foreign_error error = {0, 0};
	assert(callbacks16_destroy(&alias, &error) == (int32_t)UINT32_C(0x80010001));
	assert(alias == data->root);
	assert(error.domain == 0 && error.code == (int32_t)UINT32_C(0x80010001));
#endif
}

static bool choose(void *opaque, bool input) {
	callback_data *data = opaque;
	assert(data);
	++data->chosen;
	return !input;
}

static int64_t aggregate(void *opaque, int64_t input) {
	callback_data *data = opaque;
	assert(data && input == 42);
	return input + data->extra;
}

static int32_t checked(void *opaque, int32_t input) {
	callback_data *data = opaque;
	assert(data);
	++data->checked;
	return input < 0 ? -1 : input + data->extra;
}

int main(void) {
	callbacks16_handle *root = NULL;
	astra_foreign_error error = {99, 99};
	assert(callbacks16_create(7, &root, &error) == 0 && root);
	cleared(error);
	callback_data first = {0, 0, 0, 0, 10, 21, root}, second = {0, 0, 0, 0, 12, 33, root};
	int64_t wide = 0;
	assert(callbacks16_transform(root, 3, transform, &first, true, &wide, &error) == 0 && wide == INT64_C(-4999999968));
	cleared(error);
	assert(callbacks16_transform(root, 5, transform, &second, true, &wide, &error) == 0 && wide == INT64_C(-4999999956));
	cleared(error);
	wide = 999;
	assert(callbacks16_transform(root, 0, NULL, &first, true, &wide, &error) == (int32_t)UINT32_C(0x80004003));
	assert(wide == 0 && error.domain == 0 && error.code == (int32_t)UINT32_C(0x80004003));
	first.expected = 11;
	assert(callbacks16_notify(root, notify, &first, 4, &error) == 0);
	cleared(error);
	bool result = false;
	assert(callbacks16_choose(root, false, choose, &first, &result, &error) == 0 && result);
	assert(callbacks16_choose(root, true, choose, &second, &result, &error) == 0 && !result);
	int32_t value = 0;
	assert(callbacks16_checked(root, checked, &first, 3, &value, &error) == 0 && value == 31);
	value = 99;
	assert(callbacks16_checked(root, checked, &second, -1, &value, &error) == -1600 && value == 0 && error.domain == 16 && error.code == -1600);
	RECORD_READING record = {42, 2.5, 3};
	assert(callbacks16_aggregate(root, record, aggregate, &first, &wide, &error) == 0 && wide == 66);
	assert(callbacks16_optional(root, NULL, &first, 4, &error) == 0);
	assert(callbacks16_optional(root, notify, &first, 4, &error) == 0);
	assert(callbacks16_read(root, &value, &error) == 0 && value == 7);
	assert(first.wide == 1 && second.wide == 1 && first.notified == 2 && second.notified == 0 && first.chosen == 1 && second.chosen == 1 && first.checked == 1 && second.checked == 1);
#ifdef EXPECT_SHARED
	assert(callbacks16_release(root) == 0);
#else
	assert(callbacks16_destroy(&root, &error) == 0 && !root);
	cleared(error);
#endif
	puts("PASS typed C callbacks with exact userdata and native algorithms");
	return 0;
}
