/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/async/virtual.h"
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

typedef struct Frame {
	int identity;
} Frame;

static AstraAsyncTask *probe;
static const AstraAsyncFrameAllocator *original;
static _Atomic int fail_header, destroyed, entered;
static unsigned attempts, released;
static long home;
static _Atomic long worker;

void *__real_calloc(size_t, size_t);

void *__wrap_calloc(size_t count, size_t size) {
	if (atomic_exchange(&fail_header, 0)) {
		errno = ENOMEM;
		return NULL;
	}
	return __real_calloc(count, size);
}

static void no_resume(AstraAsyncTask *task) {
	(void)task;
	assert(0);
}

static void no_destroy(AstraAsyncTask *task, int discard) {
	(void)task;
	assert(discard);
}

static void *allocate(void *context, size_t size, size_t alignment) {
	assert(astra_async_phase(probe) == ASTRA_ASYNC_NEW);
	++attempts;
	return original->allocate(context, size, alignment);
}

static void release(void *context, void *frame) {
	assert(astra_async_phase(probe) == ASTRA_ASYNC_NEW);
	assert(astra_context17_origin(frame, UINT64_C(0x6173747261667231)) == context);
	original->release(context, frame);
	++released;
}

static void destroy(AstraAsyncTask *task, int discard) {
	(void)discard;
	Frame *frame = astra_async_data(task);
	assert(frame->identity == 17 || frame->identity == 19 || frame->identity == 23);
	atomic_fetch_add(&destroyed, 1);
}

static void resume(AstraAsyncTask *task) {
	Frame *frame = astra_async_data(task);
	assert(frame->identity == 19 || frame->identity == 23);
	long identity = syscall(SYS_gettid);
	if (frame->identity == 19) {
		assert(identity == home);
	} else {
		assert(identity != home);
		atomic_store(&worker, identity);
	}
	atomic_fetch_add(&entered, 1);
	astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
}

int main(void) {
	home = syscall(SYS_gettid);
	probe = astra_async_new(8, 8, no_resume, no_destroy, NULL);
	AstraContext17 *context = astra_context17_open_concurrent(2, 512, 1, 64);
	assert(context);
	original = astra_context17_frame_descriptor(2);
	assert(original);
	AstraAsyncFrameAllocator allocator = *original;
	allocator.allocate = allocate;
	allocator.release = release;
	AstraAsyncTask *first = astra_async_try_new_allocated(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL, &allocator, context);
	assert(first);
	((Frame *)astra_async_data(first))->identity = 17;
	assert(!astra_async_try_new_allocated(sizeof(Frame), _Alignof(Frame), resume, destroy, first, &allocator, context));
	assert(attempts == 2 && atomic_load(&destroyed) == 0 && atomic_load(&entered) == 0);
	atomic_store(&fail_header, 1);
	assert(!astra_async_try_new_allocated(sizeof(Frame), _Alignof(Frame), resume, destroy, first, &allocator, context));
	assert(atomic_load(&fail_header) == 0 && attempts == 2);
	assert(!astra_async_try_new_allocated(SIZE_MAX, 16, resume, destroy, first, &allocator, context));
	assert(!astra_async_try_new_allocated(8, 3, resume, destroy, first, &allocator, context));
	assert(!astra_async_try_new_allocated(8, 8, resume, destroy, first, &allocator, NULL));
	AstraAsyncFrameAllocator malformed = allocator;
	++malformed.abi;
	assert(!astra_async_try_new_allocated(8, 8, resume, destroy, first, &malformed, context));
	assert(attempts == 2 && ((Frame *)astra_async_data(first))->identity == 17);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(context, &state) == 0 && state.live == 1 && state.allocations == 1 && state.releases == 0);
	astra_async_drop(first);
	assert(atomic_load(&destroyed) == 1 && released == 1);
	for (int threaded = 0; threaded < 2; ++threaded) {
		AstraAsyncTask *task = astra_async_try_new_allocated(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL, &allocator, context);
		assert(task);
		((Frame *)astra_async_data(task))->identity = threaded ? 23 : 19;
		AstraAsyncExecutor *executor = threaded ? astra_async_threaded_open(2) : astra_async_virtual_open(4);
		assert(executor);
		void *exception = NULL;
		assert(astra_async_run(executor, task, &exception) == ASTRA_ASYNC_SUCCESS && !exception);
		astra_async_close(executor);
	}
	assert(atomic_load(&entered) == 2 && atomic_load(&destroyed) == 3 && atomic_load(&worker) != 0 && attempts == 4 && released == 3);
	assert(astra_context17_snapshot(context, &state) == 0 && state.live == 0 && state.allocations == 3 && state.releases == 3);
	original = astra_context17_frame_descriptor(3);
	assert(original && original->threading == ASTRA_CONTEXT17_AFFINE);
	assert(!original->allocate(context, sizeof(Frame), _Alignof(Frame)));
	assert(!astra_context17_frame_descriptor(4));
	assert(astra_context17_drop(context) == 0);
	for (uint32_t kind = ASTRA_CONTEXT17_REGION; kind <= ASTRA_CONTEXT17_POOL; ++kind) {
		unsigned char backing[8259];
		memset(backing, 0xa7, sizeof(backing));
		context = astra_context17_borrowed(backing + 1, 8197, 1, kind);
		assert(context);
		assert(!astra_context17_frame_descriptor(2)->allocate(context, sizeof(Frame), _Alignof(Frame)));
		allocator = *original;
		allocator.allocate = allocate;
		allocator.release = release;
		AstraAsyncTask *cold = astra_async_try_new_allocated(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL, &allocator, context);
		assert(cold);
		void *data = astra_async_data(cold);
		assert((unsigned char *)data >= backing + 1 && (unsigned char *)data + sizeof(Frame) <= backing + 8198);
		((Frame *)data)->identity = 17;
		assert(astra_context17_drop(context) == ASTRA_CONTEXT17_LIVE);
		assert(!astra_async_try_new_allocated(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL, &allocator, context));
		assert(astra_context17_snapshot(context, &state) == 0 && state.borrowed && !state.closed && state.live == 1 && state.allocations == 1 && state.releases == 0);
		astra_async_drop(cold);
		for (int threaded = 0; threaded < 2; ++threaded) {
			AstraAsyncTask *task = astra_async_try_new_allocated(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL, &allocator, context);
			assert(task);
			((Frame *)astra_async_data(task))->identity = 19;
			AstraAsyncExecutor *executor = threaded ? astra_async_threaded_open(2) : astra_async_virtual_open(4);
			assert(executor);
			void *exception = NULL;
			assert(astra_async_run(executor, task, &exception) == (threaded ? -ASTRA_ASYNC_ASSOCIATION : ASTRA_ASYNC_SUCCESS) && !exception);
			astra_async_close(executor);
		}
		assert(astra_context17_snapshot(context, &state) == 0 && state.live == 0 && state.allocations == 3 && state.releases == 3);
		assert(astra_context17_drop(context) == 0);
		assert(backing[0] == 0xa7);
		for (size_t i = 8198; i < sizeof(backing); ++i)
			assert(backing[i] == 0xa7);
	}
	assert(atomic_load(&entered) == 4 && atomic_load(&destroyed) == 9 && attempts == 12 && released == 9);
	astra_async_drop(probe);
	puts("frame admission substrate: unpublished refusal, header OOM, exact leases, recovery and joined virtual/worker execution");
	puts("scoped frame substrate: caller-backed region/pool frames, live-drop refusal, reuse, joined virtual execution and worker refusal");
	return 0;
}
