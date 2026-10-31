// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void *slot;
static size_t extent;
static int allocations, disposals;
extern void *__real_calloc(size_t count, size_t bytes);
extern void __real_free(void *pointer);
void *__wrap_calloc(size_t count, size_t bytes) {
	assert(count == 1 && bytes >= 12);
	if (!slot) {
		slot = __real_calloc(count, bytes);
		assert(slot);
		extent = bytes;
	} else {
		assert(disposals == 1 && allocations == 1 && bytes == extent);
		memset(slot, 0, extent);
	}
	allocations++;
	return slot;
}
void __wrap_free(void *pointer) {
	if (pointer == slot) {
		disposals++;
		assert(disposals <= allocations);
	} else {
		__real_free(pointer);
	}
}
int32_t lazy_reused(void) {
	assert(allocations == 2 && disposals == 2);
	__real_free(slot);
	slot = NULL;
	return 1;
}
