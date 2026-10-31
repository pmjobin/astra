/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../../lib/astra/async/virtual.h"
#include "../../../lib/astra/async/linux.h"
#include "../../../lib/astra/runtime/context-17.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

typedef struct Allocation { void *pointer; uint64_t tag, bytes; } Allocation;
static Allocation allocations[256];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned acquired, released, live, peak_live, worker_count, contexts;
static uint64_t live_bytes, peak_bytes;
static long owner, workers[6];
static int baseline_fds, baseline_threads, profile;
static _Atomic long warmup_identity;
static _Atomic unsigned active, peak_active, submitted, completed, closed, joined, frames, signal_in_worker, io_gate;
static int inventory(const char *path)
{
	DIR *directory = opendir(path); assert(directory); int count = 0; struct dirent *entry;
	while ((entry = readdir(directory))) { if (entry->d_name[0] != '.') { ++count; } }
	assert(closedir(directory) == 0); return count;
}
extern int __real_braid_prepare(const unsigned char *, int);
extern int braid_stop_requested(void);
static void *warmup(void *value) { atomic_store(&warmup_identity, syscall(SYS_gettid)); return value; }
int __wrap_braid_prepare(const unsigned char *path, int length)
{
	pthread_t thread; assert(pthread_create(&thread, NULL, warmup, NULL) == 0 && pthread_join(thread, NULL) == 0);
	char departed[128]; assert(snprintf(departed, sizeof(departed), "/proc/self/task/%ld", atomic_load(&warmup_identity)) > 0);
	struct timespec start, now, delay = {.tv_nsec=1000000}; assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (access(departed, F_OK) == 0) { assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8); assert(nanosleep(&delay, NULL) == 0); }
	assert(errno == ENOENT);
	owner = syscall(SYS_gettid); baseline_fds = inventory("/proc/self/fd"); baseline_threads = inventory("/proc/self/task");
	const char *mode = getenv("M17_BRAID_MODE");
	profile = mode && !strcmp(mode, "cpu") ? 1 : mode && !strcmp(mode, "io") ? 2 : mode && !strcmp(mode, "bad-fd") ? 3 : mode && !strcmp(mode, "eof") ? 4 : 0;
	return __real_braid_prepare(path, length);
}
static void gate(const char *name)
{
	printf("{\"gate\":\"%s\"}\n", name); assert(fflush(stdout) == 0);
	struct timespec start, now, delay = {.tv_nsec=1000000}; assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (!braid_stop_requested()) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 10);
		if (nanosleep(&delay, NULL) != 0) { assert(errno == EINTR); }
	}
}
extern void __real_braid_event(int, int, int);
void __wrap_braid_event(int kind, int identity, int value)
{
	if (kind == 2) {
		long worker = syscall(SYS_gettid); assert(worker != owner);
		assert(pthread_mutex_lock(&lock) == 0); unsigned i = 0;
		while (i < worker_count && workers[i] != worker) { ++i; }
		if (i == worker_count) { assert(worker_count < 6); workers[worker_count++] = worker; }
		unsigned count = atomic_fetch_add(&active, 1) + 1;
		if (count > atomic_load(&peak_active)) { atomic_store(&peak_active, count); }
		assert(pthread_mutex_unlock(&lock) == 0);
		if (profile == 1) { gate("cpu"); atomic_store(&signal_in_worker, 1); }
	}
	if (kind == 3) { assert(atomic_fetch_sub(&active, 1) > 0); }
	__real_braid_event(kind, identity, value);
}
extern void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);
void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count, uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode)
{
	void *pointer = __real_astra_context17_allocate_mode(context, count, size, alignment, tag, mode);
	assert(pointer && count && size && count <= UINT64_MAX / size && mode <= 3 && astra_context17_origin(pointer, tag) == context);
	AstraContext17Snapshot state; assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
	assert(mode == 3 ? state.borrowed && state.threading == ASTRA_CONTEXT17_AFFINE : !state.borrowed && state.threading == mode);
	assert(pthread_mutex_lock(&lock) == 0); unsigned i = 0;
	while (i < 256 && allocations[i].pointer) { ++i; } assert(i < 256);
	allocations[i] = (Allocation){pointer, tag, count * size}; ++acquired; ++live; live_bytes += count * size;
	if (live > peak_live) { peak_live = live; } if (live_bytes > peak_bytes) { peak_bytes = live_bytes; }
	assert(pthread_mutex_unlock(&lock) == 0); return pointer;
}
extern int __real_astra_context17_release_origin_checked(void *, uint64_t);
int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag)
{
	assert(pthread_mutex_lock(&lock) == 0); unsigned i = 0;
	while (i < 256 && allocations[i].pointer != pointer) { ++i; }
	assert(i < 256 && allocations[i].tag == tag && live && live_bytes >= allocations[i].bytes);
	live_bytes -= allocations[i].bytes; --live; ++released; allocations[i] = (Allocation){0};
	assert(pthread_mutex_unlock(&lock) == 0);
	int result = __real_astra_context17_release_origin_checked(pointer, tag); assert(result == 1); return result;
}
extern void __real_astra_context17_destroy(AstraContext17 *);
void __wrap_astra_context17_destroy(AstraContext17 *context)
{
	AstraContext17Snapshot state; assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK && state.anchors == 1);
	assert(pthread_mutex_lock(&lock) == 0); ++contexts; assert(pthread_mutex_unlock(&lock) == 0); __real_astra_context17_destroy(context);
}
extern AstraAsyncTask *__real_astra_async_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);
AstraAsyncTask *__wrap_astra_async_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context)
{
	assert(context && allocator && allocator->abi == ASTRA_ASYNC_TASK_ABI && allocator->threading == 2);
	AstraAsyncTask *task = __real_astra_async_new_allocated(size, alignment, resume, destroy, parent, allocator, context);
	assert(task && astra_context17_origin(astra_async_data(task), UINT64_C(0x6173747261667231)) == context); atomic_fetch_add(&frames, 1); return task;
}
void astra_payload_test_submitted(void) { assert(syscall(SYS_gettid) == owner); atomic_fetch_add(&submitted, 1); }
void astra_payload_test_completed(uint64_t target, uint64_t cancel, int result, int cancel_result, int cancel_seen)
{
	assert(syscall(SYS_gettid) == owner && target && cancel && target != cancel);
	assert(result >= 0 || result == -ECANCELED || (profile == 3 && result == -EBADF));
	if (cancel_seen) { assert(cancel_result == 0 || cancel_result == -ENOENT || cancel_result == -EALREADY); }
	atomic_fetch_add(&completed, 1);
}
void astra_payload_test_closed(void) { assert(atomic_fetch_add(&closed, 1) == 0); }
extern int __real_astra_async_linux_payload(AstraAsyncTask *, AstraLinuxPayload *);
int __wrap_astra_async_linux_payload(AstraAsyncTask *task, AstraLinuxPayload *payload)
{
	if (profile == 3 && atomic_load(&submitted) == 0) { astra_linux_payload_test_bad_fd(payload); }
	int result = __real_astra_async_linux_payload(task, payload);
	if (profile == 2 && atomic_exchange(&io_gate, 1) == 0) { assert(result == 1); gate("io-submitted"); }
	return result;
}
extern void __real_astra_async_worker_pool_close(AstraAsyncExecutor *);
void __wrap_astra_async_worker_pool_close(AstraAsyncExecutor *pool)
{
	assert(syscall(SYS_gettid) == owner); __real_astra_async_worker_pool_close(pool); assert(atomic_fetch_add(&joined, 1) == 0);
}
extern int __real_braid_finish(int);
int __wrap_braid_finish(int result)
{
	assert(result == (profile == 0 ? 0 : profile <= 2 ? 130 : 1));
	assert(atomic_load(&active) == 0 && atomic_load(&submitted) == atomic_load(&completed));
	assert(atomic_load(&closed) == 1 && atomic_load(&joined) == 1);
	assert(acquired == released && live == 0 && live_bytes == 0);
	if (profile == 0) { assert(worker_count >= 2 && atomic_load(&peak_active) == 2 && atomic_load(&frames) == 3 && atomic_load(&completed) == 27); }
	if (profile == 1) { assert(atomic_load(&signal_in_worker) == 1 && atomic_load(&frames) == 3); }
	if (profile == 2) { assert(atomic_load(&io_gate) == 1 && atomic_load(&submitted) > 0); }
	struct timespec start, now, delay = {.tv_nsec=1000000}; assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (inventory("/proc/self/task") != baseline_threads) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8); assert(nanosleep(&delay, NULL) == 0);
	}
	assert(inventory("/proc/self/fd") == baseline_fds);
	printf("{\"observed_profile\":%d,\"worker_identities\":%u,\"observed_cpu_peak\":%u,\"selected_frames\":%u,\"io_submitted\":%u,\"io_retired\":%u,\"allocations\":%u,\"releases\":%u,\"live_peak\":%u,\"payload_peak_bytes\":%llu,\"closed_contexts\":%u,\"fd_baseline\":%d,\"thread_baseline\":%d}\n", profile, worker_count, atomic_load(&peak_active), atomic_load(&frames), atomic_load(&submitted), atomic_load(&completed), acquired, released, peak_live, (unsigned long long)peak_bytes, contexts, baseline_fds, baseline_threads);
	return __real_braid_finish(result);
}
