/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/async/virtual.h"
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>

static AstraAsyncTask *probe;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static AstraAsyncFrameAllocator observed;
static void *(*allocate_frame)(void *, size_t, size_t);
static void (*release_frame)(void *, void *);
static _Atomic unsigned allocations, releases, guards, pending;
static void no_resume(AstraAsyncTask *task) {
	(void)task;
	assert(0);
}
static void no_destroy(AstraAsyncTask *task, int discard) {
	(void)task;
	assert(discard);
}

void context_frames_prepare(void) {
	probe = astra_async_new(8, 8, no_resume, no_destroy, NULL);
	assert(probe);
}
static void *observed_allocate(void *context, size_t size, size_t alignment) {
	/* These public reads acquire the real scheduler lock. Calling them inside
	 * allocator callbacks would deadlock if production retained that lock. */
	assert(astra_async_phase(probe) == ASTRA_ASYNC_NEW);
	void *pointer = allocate_frame(context, size, alignment);
	assert(pointer && astra_context17_origin(pointer, UINT64_C(0x6173747261667231)) == context);
	atomic_fetch_add(&allocations, 1);
	return pointer;
}
static void observed_release(void *context, void *pointer) {
	assert(astra_async_phase(probe) == ASTRA_ASYNC_NEW);
	assert(astra_context17_origin(pointer, UINT64_C(0x6173747261667231)) == context);
	release_frame(context, pointer);
	atomic_fetch_add(&releases, 1);
}
AstraAsyncTask *__real_astra_async_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);
AstraAsyncTask *__wrap_astra_async_new_allocated(size_t size, size_t alignment,
                                                 AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent,
                                                 const AstraAsyncFrameAllocator *allocator, void *context) {
	assert(allocator && allocator->abi == 17 && allocator->threading == 2 && context);
	assert(pthread_mutex_lock(&lock) == 0);
	if (!allocate_frame) {
		allocate_frame = allocator->allocate;
		release_frame = allocator->release;
		observed = *allocator;
		observed.allocate = observed_allocate;
		observed.release = observed_release;
	}
	assert(allocate_frame == allocator->allocate && release_frame == allocator->release);
	assert(pthread_mutex_unlock(&lock) == 0);
	AstraAsyncTask *task = __real_astra_async_new_allocated(size, alignment, resume, destroy, parent, &observed, context);
	/* Check the actual protocol frame, not a neighboring marker allocation. */
	assert(astra_context17_origin(astra_async_data(task), UINT64_C(0x6173747261667231)) == context);
	return task;
}
void context_frame_guard_retired(int identity) {
	assert(identity >= 1 && identity <= 3);
	unsigned bit = 1u << (identity - 1);
	assert(!(atomic_fetch_or(&guards, bit) & bit));
}
void context_frame_pending(void) {
	assert(atomic_fetch_add(&pending, 1) == 0);
}
int context_frame_is_pending(void) {
	return (int)atomic_load(&pending);
}
int context_frames_finish(void) {
	assert(atomic_load(&allocations) == 6 && atomic_load(&releases) == 6);
	assert(atomic_load(&guards) == 7 && atomic_load(&pending) == 1);
	astra_async_drop(probe);
	puts("context frames: six actual selected allocations/releases, cold drop, suspended cancel, checked failure, backing lease, unlocked callbacks");
	return 0;
}
