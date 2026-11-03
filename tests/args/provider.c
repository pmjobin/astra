/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdlib.h>
#include <string.h>

static size_t allocations;
static size_t disposals;
static int fail_allocation;
static char *change_during_allocation;

static void *capture_malloc(size_t bytes) {
	if (change_during_allocation != NULL) {
		strcpy(change_during_allocation, "changed-longer-than-planned");
	}
	if (fail_allocation) {
		return NULL;
	}
	void *result = malloc(bytes);
	if (result != NULL) {
		allocations++;
	}
	return result;
}

static void capture_free(void *pointer) {
	assert(pointer != NULL);
	disposals++;
	free(pointer);
}

#define malloc capture_malloc
#define free capture_free
#include "../../lib/runtime/platform/args-posix.c"
#undef malloc
#undef free

int test_utf8(const unsigned char *data, size_t length) {
	return args_valid_utf8(data, length);
}

int test_size(size_t left, size_t right, size_t *result, int multiply) {
	return multiply ? args_table_size(left, result) : args_add_size(left, right, result);
}

int main(void) {
	const struct AstraArgsTextV0 *items = (void *)1;
	assert(astra_host_args_prepare_v0(0, (char *const *)1, &items) == 0 && items == NULL);
	astra_host_args_dispose_v0(items);
	assert(allocations == 0 && disposals == 0);
	assert(astra_host_args_prepare_v0(-1, NULL, &items) == 2 && items == NULL);
	assert(astra_host_args_prepare_v0(1, NULL, &items) == 2 && items == NULL);
	assert(astra_host_args_prepare_v0(0, NULL, NULL) == 2);
	char empty[] = "";
	char original[64] = "a\xc3\xa9";
	char *argv[] = {empty, original, NULL};
	assert(astra_host_args_prepare_v0(1, argv, &items) == 2 && items == NULL);
	char *missing[] = {NULL, NULL};
	assert(astra_host_args_prepare_v0(1, missing, &items) == 2 && items == NULL);
	fail_allocation = 1;
	assert(astra_host_args_prepare_v0(2, argv, &items) == 3 && items == NULL && allocations == 0);
	fail_allocation = 0;
	for (int cycle = 0; cycle < 4096; cycle++) {
		strcpy(original, "a\xc3\xa9");
		argv[1] = original;
		assert(astra_host_args_prepare_v0(2, argv, &items) == 0);
		assert(items[0].data == NULL && items[0].byte_length == 0);
		strcpy(original, "changed");
		argv[0] = original;
		argv[1] = empty;
		assert(items[1].byte_length == 3 && memcmp(items[1].data, "a\xc3\xa9", 3) == 0);
		astra_host_args_dispose_v0(items);
		argv[0] = empty;
		assert(allocations == disposals);
	}
	char invalid[] = "\xed\xa0\x80";
	argv[1] = invalid;
	items = (void *)1;
	assert(astra_host_args_prepare_v0(2, argv, &items) == 2 && items == NULL && allocations == disposals);
	strcpy(original, "a");
	argv[1] = original;
	change_during_allocation = original;
	assert(astra_host_args_prepare_v0(2, argv, &items) == 2 && items == NULL && allocations == disposals);
	change_during_allocation = NULL;
	size_t result;
	assert(args_add_size(0, 0, &result) && result == 0);
	assert(args_add_size(PTRDIFF_MAX - 1, 1, &result) && result == PTRDIFF_MAX);
	assert(!args_add_size(PTRDIFF_MAX, 1, &result) && !args_add_size(SIZE_MAX, 0, &result));
	assert(args_table_size(PTRDIFF_MAX / 16, &result) && result == (size_t)(PTRDIFF_MAX / 16) * 16);
	assert(!args_table_size((size_t)(PTRDIFF_MAX / 16) + 1, &result) && !args_table_size(SIZE_MAX, &result));
	assert(args_table_size(INT32_MAX, &result) && result == (size_t)INT32_MAX * 16);
	return 0;
}
