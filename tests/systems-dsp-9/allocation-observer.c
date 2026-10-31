/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stddef.h>
#include <stdlib.h>

void *__real_malloc(size_t);
void *__real_calloc(size_t, size_t);
void *__real_realloc(void *, size_t);
static int allocations;
void *__wrap_malloc(size_t bytes) {
	allocations++;
	return __real_malloc(bytes);
}
void *__wrap_calloc(size_t number, size_t size) {
	allocations++;
	return __real_calloc(number, size);
}
void *__wrap_realloc(void *pointer, size_t bytes) {
	allocations++;
	return __real_realloc(pointer, bytes);
}
int packet_heap_epoch(void) {
	return allocations;
}
int packet_heap_unchanged(int epoch) {
	assert(allocations == epoch);
	return 0;
}
