/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdlib.h>
#define main source_observer_main
#include "await-observer.c"
#undef main

typedef struct ObservedAllocation {
	void *pointer;
	unsigned generation;
	unsigned announcements;
	unsigned live;
} ObservedAllocation;
static ObservedAllocation allocations[4096];
static unsigned allocation_count;
static unsigned frees;
static unsigned exception_publications;
static unsigned original_transfers;
extern void *__real_calloc(size_t count, size_t size);
extern void __real_free(void *pointer);
extern void __real_astra_async_complete(AstraAsyncTask *task, int phase, void *exception);

void *__wrap_calloc(size_t count, size_t size) {
	void *pointer = __real_calloc(count, size);
	if (pointer != NULL) {
		assert(allocation_count < 4096);
		allocations[allocation_count] = (ObservedAllocation){pointer, allocation_count + 1, 0, 1};
		allocation_count++;
	}
	return pointer;
}
static ObservedAllocation *live_allocation(void *pointer) {
	for (unsigned n = allocation_count; n != 0; n--) {
		if (allocations[n - 1].pointer == pointer && allocations[n - 1].live) {
			return &allocations[n - 1];
		}
	}
	return NULL;
}
void __wrap_astra_async_complete(AstraAsyncTask *task, int phase, void *exception) {
	if (phase == ASTRA_ASYNC_EXCEPTION) {
		assert(exception != NULL);
		ObservedAllocation *origin = live_allocation(exception);
		assert(origin != NULL && origin->generation != 0);
		if (origin->announcements != 0) {
			original_transfers++;
		}
		origin->announcements++;
		exception_publications++;
	}
	__real_astra_async_complete(task, phase, exception);
}
void __wrap_free(void *pointer) {
	ObservedAllocation *origin = live_allocation(pointer);
	if (origin != NULL) {
		assert(origin->live == 1);
		origin->live = 0;
		frees++;
	}
	__real_free(pointer);
}
int main(void) {
	int result = source_observer_main();
	assert(result == 0 && exception_publications > 16 && original_transfers >= 2);
	assert(frees == allocation_count);
	for (unsigned n = 0; n < allocation_count; n++) {
		assert(allocations[n].live == 0);
	}
	printf("native exception origin: allocations=%u frees=%u publications=%u original-transfers=%u; every announced exception is its live original allocation\n", allocation_count, frees, exception_publications, original_transfers);
	return 0;
}
