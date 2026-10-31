/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/async/virtual.h"
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <unistd.h>

static _Atomic int fail_header, entered[5], retired[5];
static int attempts, refused, accepted;
static long home;
static _Atomic long observed;
extern int run_checked_frames(void);
int main(void) {
	return run_checked_frames();
}
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	if (atomic_exchange(&fail_header, 0)) {
		errno = ENOMEM;
		return NULL;
	}
	return __real_calloc(count, size);
}
void checked_frame_header_failure(void) {
	assert(!atomic_load(&fail_header));
	home = syscall(SYS_gettid);
	atomic_store(&fail_header, 1);
}
AstraAsyncTask *__real_astra_async_try_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);
AstraAsyncTask *__wrap_astra_async_try_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context) {
	assert(allocator && context);
	++attempts;
	AstraAsyncTask *task = __real_astra_async_try_new_allocated(size, alignment, resume, destroy, parent, allocator, context);
	if (task) {
		++accepted;
	} else {
		++refused;
	}
	return task;
}
void checked_frame_event(int kind, int identity) {
	assert(identity > 0 && identity < 5);
	if (kind == 1) {
		assert(identity != 2);
		atomic_fetch_add(&entered[identity], 1);
		atomic_store(&observed, syscall(SYS_gettid));
	} else {
		assert(kind == 2);
		atomic_fetch_add(&retired[identity], 1);
	}
}
int checked_frame_finish(void) {
	assert(attempts == 7 && refused == 3 && accepted == 4 && !atomic_load(&fail_header));
	for (int i = 1; i < 5; ++i) {
		assert(atomic_load(&retired[i]) == 1 && atomic_load(&entered[i]) == (i == 2 ? 0 : 1));
	}
#ifndef M17_VIRTUAL
	assert(atomic_load(&observed) != home);
#else
	assert(atomic_load(&observed) == home);
#endif
	puts("checked Source frames: pool/header refusal retains captures, admission empties slots, cold/error retirement and real executor recovery");
	return 0;
}
