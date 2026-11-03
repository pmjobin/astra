/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/async/virtual.h"
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static AstraAsyncFrameAllocator observed;
static unsigned attempts, allocations, releases, refusals;
static unsigned guards[5];
static unsigned cancellations;
static void *(*allocate_frame)(void *, size_t, size_t);
static void (*release_frame)(void *, void *);
static void *contexts[2];
#ifdef M17_BORROWED_AFFINE
#define FRAME_THREADING 0
#else
#define FRAME_THREADING 2
#endif

static void *observed_allocate(void *context, size_t size, size_t alignment) {
	assert(context && size && alignment);
	if (!contexts[0]) contexts[0] = context;
	if (context != contexts[0] && !contexts[1]) contexts[1] = context;
	assert(context == contexts[0] || context == contexts[1]);
	void *pointer = allocate_frame(context, size, alignment);
	if (pointer) {
		assert(astra_context17_origin(pointer, UINT64_C(0x6173747261667231)) == context);
		allocations++;
	} else
		refusals++;
	return pointer;
}

static void observed_release(void *context, void *pointer) {
	assert(astra_context17_origin(pointer, UINT64_C(0x6173747261667231)) == context);
	release_frame(context, pointer);
	releases++;
}

static const AstraAsyncFrameAllocator *observe(const AstraAsyncFrameAllocator *allocator) {
	assert(allocator && allocator->abi == 17 && allocator->threading == FRAME_THREADING);
	if (!allocate_frame) {
		allocate_frame = allocator->allocate;
		release_frame = allocator->release;
		observed = *allocator;
		observed.allocate = observed_allocate;
		observed.release = observed_release;
	}
	assert(allocate_frame == allocator->allocate && release_frame == allocator->release);
	attempts++;
	return &observed;
}

AstraAsyncTask *__real_astra_async_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);

AstraAsyncTask *__wrap_astra_async_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context) {
	AstraAsyncTask *task = __real_astra_async_new_allocated(size, alignment, resume, destroy, parent, observe(allocator), context);
	assert(task && astra_context17_origin(astra_async_data(task), UINT64_C(0x6173747261667231)) == context);
	return task;
}

AstraAsyncTask *__real_astra_async_try_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);

AstraAsyncTask *__wrap_astra_async_try_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context) {
	AstraAsyncTask *task = __real_astra_async_try_new_allocated(size, alignment, resume, destroy, parent, observe(allocator), context);
	assert(!task || astra_context17_origin(astra_async_data(task), UINT64_C(0x6173747261667231)) == context);
	return task;
}

void borrowed_frame_guard_retired(int identity) {
	assert(identity == 1 || identity == 3 || identity == 4);
	assert(++guards[identity] <= (identity == 1 ? 2u : 1u));
}

void __real_astra_async_host_cancel(AstraAsyncExecutor *, AstraAsyncTask *);

void __wrap_astra_async_host_cancel(AstraAsyncExecutor *executor, AstraAsyncTask *task) {
	assert(astra_async_phase(task) == ASTRA_ASYNC_WAITING);
	assert(astra_context17_origin(astra_async_data(task), UINT64_C(0x6173747261667231)) == contexts[0]);
	assert(++cancellations == 1);
	__real_astra_async_host_cancel(executor, task);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(contexts[0], &state) == 0 && state.live == 1);
}

int borrowed_frames_finish(void) {
	assert(contexts[0] && contexts[1] && contexts[0] != contexts[1]);
	assert(attempts == 7 && allocations == 6 && releases == 6 && refusals == 1 && cancellations == 1);
	assert(guards[1] == 2 && guards[3] == 1 && guards[4] == 1);
	puts("borrowed frame contexts: 2 instances, 6 actual frames, joined error, suspended cancel, cold drops and 1 refusal");
	return 0;
}

int borrowed_frames_finish_empty_error(void) {
	assert(contexts[0] && !contexts[1]);
	assert(attempts == 3 && allocations == 2 && releases == 2 && refusals == 1 && !cancellations);
	for (size_t i = 0; i < sizeof(guards) / sizeof(guards[0]); ++i)
		assert(!guards[i]);
	puts("scoped empty error: refused admission and checked success retain exact backing ownership");
	return 0;
}

int run_borrowed_frame_contexts(void);

int main(void) {
	return run_borrowed_frame_contexts();
}
