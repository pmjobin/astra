/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Explicit hosted strategy, never linked by the no-OS bounded strategies. */
#include "allocation-12.h"
#include <stdlib.h>

void *astra_alloc12_heap_allocate(uint64_t bytes, uint32_t alignment) {
	if (!alignment || alignment > 4096 || (alignment & (alignment - 1)) || bytes > SIZE_MAX) {
		return NULL;
	}
	if (alignment < sizeof(void *)) {
		alignment = sizeof(void *);
	}
	if (bytes > SIZE_MAX - alignment + 1) {
		return NULL;
	}
	size_t rounded = ((size_t)bytes + alignment - 1) & ~((size_t)alignment - 1);
	return aligned_alloc(alignment, rounded);
}

void astra_alloc12_heap_release(void *pointer) {
	free(pointer);
}
