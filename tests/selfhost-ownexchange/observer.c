// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);
static void *allocations[64];
static size_t extents[64];
static int used;

void *__wrap_calloc(size_t count, size_t size) {
#ifdef FAIL_REPLACEMENT
	if (count * size == 36) {
		fputs("FAIL 36\n", stderr);
		return NULL;
	}
#endif
	void *pointer = __real_calloc(count, size);
	if (used >= 64 || !pointer) abort();
	allocations[used] = pointer;
	extents[used] = count * size;
	fprintf(stderr, "A %d %zu\n", used + 1, extents[used]);
	used++;
	return pointer;
}

void __wrap_free(void *pointer) {
	if (!pointer) return;
	for (int i = 0; i < used; i++) {
		if (allocations[i] == pointer) {
			fprintf(stderr, "F %d %zu\n", i + 1, extents[i]);
			allocations[i] = NULL;
			__real_free(pointer);
			return;
		}
	}
	abort();
}
