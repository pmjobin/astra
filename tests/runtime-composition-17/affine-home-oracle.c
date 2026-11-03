/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/async/virtual.h"
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <sys/eventfd.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static long home_thread;
static int identity, wake_fd = -1;
static AstraContext17 *objects, *frames;
static AstraAsyncTask *root, *child;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static _Atomic unsigned armed, worker_entered, posted, child_observed, destroyed, released, joined, observed;
static AstraAsyncFrameAllocator allocator;
static void *(*frame_allocate)(void *, size_t, size_t);
static void (*frame_release)(void *, void *);
static AstraAsyncDestroy child_destroy;

static void on_home(void) {
	assert(syscall(SYS_gettid) == home_thread);
}

static void live(AstraContext17 *context, uint64_t expected) {
	AstraContext17Snapshot snapshot;
	on_home();
	assert(astra_context17_snapshot(context, &snapshot) == ASTRA_CONTEXT17_OK);
	assert(snapshot.live == expected && snapshot.threading == ASTRA_CONTEXT17_AFFINE);
}

void affine_home_prepare(int selected) {
	if (identity) assert(atomic_load(&observed) == 1 && wake_fd == -1);
	home_thread = syscall(SYS_gettid);
	identity = selected;
	objects = frames = NULL;
	root = child = NULL;
	atomic_store(&armed, 0);
	atomic_store(&worker_entered, 0);
	atomic_store(&posted, 0);
	atomic_store(&child_observed, 0);
	atomic_store(&destroyed, 0);
	atomic_store(&released, 0);
	atomic_store(&joined, 0);
	atomic_store(&observed, 0);
}

AstraContext17 *__real_astra_context17_open_affine(int32_t, int64_t, int32_t, int32_t);

AstraContext17 *__wrap_astra_context17_open_affine(int32_t kind, int64_t capacity, int32_t slots, int32_t alignment) {
	on_home();
	AstraContext17 *context = __real_astra_context17_open_affine(kind, capacity, slots, alignment);
	assert(context);
	if (kind == 1) {
		assert(!objects);
		objects = context;
	} else {
		assert(kind == 2 && !frames && context != objects);
		frames = context;
	}
	return context;
}

int __real_eventfd(unsigned, int);

int __wrap_eventfd(unsigned value, int flags) {
	on_home();
	assert(wake_fd == -1 && value == 0 && (flags & EFD_NONBLOCK));
	wake_fd = __real_eventfd(value, flags);
	assert(wake_fd >= 0);
	return wake_fd;
}

ssize_t __real_write(int, const void *, size_t);

ssize_t __wrap_write(int fd, const void *data, size_t size) {
	if (fd == wake_fd && syscall(SYS_gettid) != home_thread) {
		/* This is the actual home-executor queue notification under the core
		 * lock. Do not reenter runtime APIs from the notification boundary. */
		assert(atomic_load(&armed) && atomic_load(&worker_entered) == 1);
		assert(!atomic_load(&destroyed) && !atomic_load(&released) && !atomic_load(&observed));
		assert(size == sizeof(uint64_t));
		atomic_fetch_add(&posted, 1);
	}
	return __real_write(fd, data, size);
}

int __real_close(int);

int __wrap_close(int fd) {
	if (fd == wake_fd) {
		on_home();
		assert(atomic_load(&observed) == 1);
		wake_fd = -1;
	}
	return __real_close(fd);
}

static void *allocate_frame(void *context, size_t size, size_t alignment) {
	on_home();
	assert(context == frames);
	void *result = frame_allocate(context, size, alignment);
	assert(result);
	return result;
}

static void release_frame(void *context, void *pointer) {
	on_home();
	assert(context == frames && atomic_load(&destroyed) == 1 && atomic_load(&joined) == 1);
	assert(atomic_load(&posted) != 0 && !atomic_load(&observed));
	live(objects, 0);
	live(frames, 1);
	frame_release(context, pointer);
	live(frames, 0);
	assert(atomic_fetch_add(&released, 1) == 0);
}

AstraAsyncTask *__real_astra_async_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);

AstraAsyncTask *__wrap_astra_async_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *selected, void *context) {
	on_home();
	assert(!root && !parent && context == frames && selected && selected->threading == ASTRA_CONTEXT17_AFFINE);
	allocator = *selected;
	frame_allocate = selected->allocate;
	frame_release = selected->release;
	allocator.allocate = allocate_frame;
	allocator.release = release_frame;
	root = __real_astra_async_new_allocated(size, alignment, resume, destroy, parent, &allocator, context);
	assert(root);
	return root;
}

AstraAsyncTask *__real_astra_async_new(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *);

static void observe_child_destroy(AstraAsyncTask *task, int discard) {
	on_home();
	assert(task == child && atomic_load(&posted) != 0);
	assert(astra_async_phase(task) >= ASTRA_ASYNC_SUCCESS);
	child_destroy(task, discard);
	assert(atomic_fetch_add(&child_observed, 1) == 0);
}

AstraAsyncTask *__wrap_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent) {
	on_home();
	assert(parent == root && !child);
	child_destroy = destroy;
	child = __real_astra_async_new(size, alignment, resume, observe_child_destroy, parent);
	assert(child);
	return child;
}

int __real_astra_async_bridge_wait(AstraAsyncTask *, AstraAsyncTask *, AstraAsyncExecutor *, int);

int __wrap_astra_async_bridge_wait(AstraAsyncTask *parent, AstraAsyncTask *task, AstraAsyncExecutor *target, int discard) {
	on_home();
	assert(parent == root && task == child && !discard);
	int result = __real_astra_async_bridge_wait(parent, task, target, discard);
	assert(astra_async_phase(parent) == ASTRA_ASYNC_WAITING);
	live(objects, 1);
	live(frames, 1);
	assert(pthread_mutex_lock(&lock) == 0);
	atomic_store(&armed, 1);
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return result;
}

void affine_home_worker(int selected) {
	assert(selected == identity && syscall(SYS_gettid) != home_thread);
	assert(atomic_fetch_add(&worker_entered, 1) == 0);
	assert(pthread_mutex_lock(&lock) == 0);
	struct timespec deadline;
	assert(clock_gettime(CLOCK_REALTIME, &deadline) == 0);
	deadline.tv_sec += 5;
	while (!atomic_load(&armed))
		assert(pthread_cond_timedwait(&changed, &lock, &deadline) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	assert(astra_context17_drop(objects) == ASTRA_CONTEXT17_THREAD);
	assert(astra_context17_drop(frames) == ASTRA_CONTEXT17_THREAD);
	if (selected == 3) astra_async_cancel(root);
}

void affine_home_retired(int selected) {
	on_home();
	assert(selected == identity && atomic_load(&posted) != 0);
	assert(atomic_load(&child_observed) == 1);
	int phase = astra_async_phase(root);
	assert(phase == ASTRA_ASYNC_RUNNING || (identity == 3 && phase == ASTRA_ASYNC_CANCELLED));
	live(objects, 1);
	live(frames, 1);
	assert(atomic_fetch_add(&destroyed, 1) == 0);
}

int __real_astra_async_release_wait(AstraAsyncTask *, int);

int __wrap_astra_async_release_wait(AstraAsyncTask *parent, int transfer) {
	on_home();
	assert(parent == root && atomic_load(&posted) != 0);
	assert(astra_async_phase(child) >= ASTRA_ASYNC_SUCCESS);
	int result = __real_astra_async_release_wait(parent, transfer);
	assert(atomic_load(&child_observed) == 1);
	return result;
}

void __real_astra_async_worker_pool_close(AstraAsyncExecutor *);

void __wrap_astra_async_worker_pool_close(AstraAsyncExecutor *pool) {
	on_home();
	assert(atomic_load(&destroyed) == 1 && !atomic_load(&released));
	__real_astra_async_worker_pool_close(pool);
	assert(atomic_fetch_add(&joined, 1) == 0);
}

int __real_astra_async_run(AstraAsyncExecutor *, AstraAsyncTask *, void **);

int __wrap_astra_async_run(AstraAsyncExecutor *executor, AstraAsyncTask *task, void **error) {
	on_home();
	assert(task == root);
	int result = __real_astra_async_run(executor, task, error);
	assert(atomic_load(&destroyed) == 1 && atomic_load(&released) == 1 && atomic_load(&joined) == 1);
	live(objects, 0);
	live(frames, 0);
	assert(atomic_fetch_add(&observed, 1) == 0);
	return result;
}

int affine_home_observed(int selected) {
	on_home();
	assert(selected == identity && wake_fd == -1 && atomic_load(&observed) == 1);
	return 0;
}

int affine_home_finish(void) {
	assert(identity == 3 && atomic_load(&observed) == 1);
	puts("affine home retirement: real worker notification, home owner/frame release and observed joined shutdown");
	return 0;
}

#ifndef M17_EMITTED_ENTRY
extern int run_affine_home(void);

int main(void) {
	int result = run_affine_home();
	assert(result == 0);
	return affine_home_finish();
}

#endif
