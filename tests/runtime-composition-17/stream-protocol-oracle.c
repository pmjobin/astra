/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/async/virtual.h"
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

typedef struct Allocation {
	void *pointer;
	uint64_t tag, bytes;
} Allocation;

static Allocation allocations[512];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned allocated, released, active_allocations, peak_allocations, worker_count;
static _Atomic unsigned queue_peak, queue_limit;
static uint64_t live_bytes, peak_bytes;
static AstraContext17Snapshot context_peaks[16];
static unsigned contexts;
static _Atomic unsigned states[64], active, peak_active, network_overlap, io_overlap;
static _Atomic unsigned io_submitted, io_completed, payload_closed, pool_joined, frames;
static _Atomic long calibrated;
static long owner, workers[8];
static int baseline_fds, baseline_threads;
static unsigned driver_observed;
static int profile, trace, serialized;
static _Atomic unsigned stopped_while_computing;

static int inventory(const char *path) {
	DIR *directory = opendir(path);
	assert(directory);
	int count = 0;
	struct dirent *entry;
	while ((entry = readdir(directory))) {
		if (entry->d_name[0] != '.') {
			++count;
		}
	}
	assert(closedir(directory) == 0);
	return count;
}

static void wait_gone(long identity) {
	char path[128];
	assert(snprintf(path, sizeof(path), "/proc/self/task/%ld", identity) > 0);
	struct timespec began, now, delay = {.tv_nsec = 1000000};
	struct stat state;
	assert(clock_gettime(CLOCK_MONOTONIC, &began) == 0);
	while (stat(path, &state) == 0) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - began.tv_sec < 8);
		assert(nanosleep(&delay, NULL) == 0);
	}
	assert(errno == ENOENT);
}

static void wait_threads(void) {
	struct timespec began, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &began) == 0);
	if (inventory("/proc/self/task") != baseline_threads) {
		DIR *directory = opendir("/proc/self/task");
		assert(directory);
		struct dirent *entry;
		while ((entry = readdir(directory))) {
			if (entry->d_name[0] != '.') {
				char path[512], name[128];
				assert(snprintf(path, sizeof(path), "/proc/self/task/%s/comm", entry->d_name) < (int)sizeof(path));
				FILE *file = fopen(path, "r");
				if (file) {
					if (fgets(name, sizeof(name), file)) {
						fprintf(stderr, "shutdown inventory task %s: %s", entry->d_name, name);
					}
					assert(fclose(file) == 0);
				}
			}
		}
		assert(closedir(directory) == 0);
	}
	while (inventory("/proc/self/task") != baseline_threads) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - began.tv_sec < 8);
		assert(nanosleep(&delay, NULL) == 0);
	}
}

static void *calibrate(void *value) {
	atomic_store(&calibrated, syscall(SYS_gettid));
	return value;
}

extern void __real_stream_prepare(void);

void __wrap_stream_prepare(void) {
	const char *mode = getenv("M17_STREAM_MODE");
	profile = mode && strcmp(mode, "cancel") == 0 ? 1 : mode && strcmp(mode, "success") != 0 ? 2
	                                                                                         : 0;
	trace = getenv("M17_STREAM_TRACE") != NULL;
	serialized = getenv("M17_STREAM_SERIALIZED_TOOL") != NULL;
	pthread_t thread;
	assert(pthread_create(&thread, NULL, calibrate, NULL) == 0);
	assert(pthread_join(thread, NULL) == 0);
	wait_gone(atomic_load(&calibrated));
	owner = syscall(SYS_gettid);
	baseline_fds = inventory("/proc/self/fd");
	baseline_threads = inventory("/proc/self/task");
	__real_stream_prepare();
}

extern void __real_stream_event(int, int, int);

void __wrap_stream_event(int kind, int sequence, int value) {
	assert(sequence >= 0 && sequence < 64);
	if (kind == 7) {
		assert(atomic_fetch_or(&states[sequence], 1) == 0 && value > 0 && value <= 4093);
	}
	if (kind == 2) {
		assert(atomic_fetch_or(&states[sequence], 2) == 1);
		long identity = syscall(SYS_gettid);
		assert(identity != owner);
		assert(pthread_mutex_lock(&lock) == 0);
		unsigned worker = 0;
		while (worker < worker_count && workers[worker] != identity) {
			++worker;
		}
		if (worker == worker_count) {
			assert(worker_count < 8);
			workers[worker_count++] = identity;
		}
		assert(pthread_mutex_unlock(&lock) == 0);
		unsigned count = atomic_fetch_add(&active, 1) + 1, peak = atomic_load(&peak_active);
		while (peak < count && !atomic_compare_exchange_weak(&peak_active, &peak, count)) {
		}
	}
	if (kind == 3) {
		assert(atomic_fetch_or(&states[sequence], 4) == 3 && value >= 0 && value < 65521);
		assert(atomic_fetch_sub(&active, 1) > 0);
	}
	if (kind == 5) {
		assert(syscall(SYS_gettid) == owner && atomic_fetch_or(&states[sequence], 8) == 7 && value > 0);
	}
	if (kind == 8) {
		assert((atomic_fetch_or(&states[sequence], 16) & 17U) == 1U);
	}
	if (kind == 4) {
		assert(syscall(SYS_gettid) == owner && sequence <= 8 && (profile != 0 || sequence == 8) && value == 0 && driver_observed++ == 0);
	}
	if (kind == 10) {
		assert(value > 0 && sequence <= value);
		unsigned empty = 0;
		assert(atomic_compare_exchange_strong(&queue_limit, &empty, (unsigned)value) || empty == (unsigned)value);
		unsigned peak = atomic_load(&queue_peak);
		while (peak < (unsigned)sequence && !atomic_compare_exchange_weak(&queue_peak, &peak, (unsigned)sequence)) {
		}
	}
	__real_stream_event(kind, sequence, value);
}

extern int __real_astra_net_read(int, unsigned char *, int, int, int);

int __wrap_astra_net_read(int fd, unsigned char *bytes, int length, int offset, int count) {
	assert(syscall(SYS_gettid) == owner && length >= 0 && offset >= 0 && count >= 0 && offset <= length && count <= length - offset);
	assert(pthread_mutex_lock(&lock) == 0);
	unsigned slot = 0;
	while (slot < 512 && allocations[slot].pointer != bytes) {
		++slot;
	}
	assert(slot < 512 && allocations[slot].bytes == (uint64_t)length);
	assert(pthread_mutex_unlock(&lock) == 0);
	int result = __real_astra_net_read(fd, bytes, length, offset, count);
	if (result > 0 && atomic_load(&active) != 0) {
		atomic_fetch_add(&network_overlap, 1);
	}
	return result;
}

extern void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);

void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count, uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	void *pointer = __real_astra_context17_allocate_mode(context, count, size, alignment, tag, mode);
	assert(pointer && mode == 2 && count > 0 && size > 0 && count <= UINT64_MAX / size);
	assert(astra_context17_origin(pointer, tag) == context);
	assert(pthread_mutex_lock(&lock) == 0);
	unsigned slot = 0;
	while (slot < 512 && allocations[slot].pointer) {
		++slot;
	}
	assert(slot < 512);
	allocations[slot] = (Allocation){pointer, tag, count * size};
	++allocated;
	++active_allocations;
	live_bytes += count * size;
	if (active_allocations > peak_allocations) {
		peak_allocations = active_allocations;
	}
	if (live_bytes > peak_bytes) {
		peak_bytes = live_bytes;
	}
	assert(pthread_mutex_unlock(&lock) == 0);
	return pointer;
}

extern int __real_astra_context17_release_origin_checked(void *, uint64_t);

int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	assert(pthread_mutex_lock(&lock) == 0);
	unsigned slot = 0;
	while (slot < 512 && allocations[slot].pointer != pointer) {
		++slot;
	}
	assert(slot < 512 && allocations[slot].tag == tag && active_allocations > 0 && live_bytes >= allocations[slot].bytes);
	live_bytes -= allocations[slot].bytes;
	allocations[slot] = (Allocation){0};
	++released;
	--active_allocations;
	assert(pthread_mutex_unlock(&lock) == 0);
	int result = __real_astra_context17_release_origin_checked(pointer, tag);
	assert(result == 1);
	return result;
}

extern void __real_astra_context17_destroy(AstraContext17 *);

void __wrap_astra_context17_destroy(AstraContext17 *context) {
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
	assert(state.threading == 2 && state.anchors == 1);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(contexts < 16);
	context_peaks[contexts++] = state;
	assert(pthread_mutex_unlock(&lock) == 0);
	__real_astra_context17_destroy(context);
}

extern AstraAsyncTask *__real_astra_async_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);

AstraAsyncTask *__wrap_astra_async_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context) {
	assert(context && allocator && allocator->abi == ASTRA_ASYNC_TASK_ABI && allocator->threading == 2);
	AstraAsyncTask *task = __real_astra_async_new_allocated(size, alignment, resume, destroy, parent, allocator, context);
	assert(task && astra_context17_origin(astra_async_data(task), UINT64_C(0x6173747261667231)) == context);
	atomic_fetch_add(&frames, 1);
	return task;
}

void astra_payload_test_submitted(void) {
	assert(syscall(SYS_gettid) == owner);
	atomic_fetch_add(&io_submitted, 1);
}

void astra_payload_test_completed(uint64_t target, uint64_t cancel, int result, int cancel_result, int cancel_seen) {
	assert(syscall(SYS_gettid) == owner && target && cancel && target != cancel);
	assert(profile == 0 ? !cancel_seen && result > 0 : result >= 0 || result == -ECANCELED);
	if (cancel_seen) {
		assert(cancel_result == 0 || cancel_result == -ENOENT || cancel_result == -EALREADY);
	}
	atomic_fetch_add(&io_completed, 1);
	if (atomic_load(&active) != 0) {
		atomic_fetch_add(&io_overlap, 1);
	}
	if (trace) {
		printf("{\"file_completion\":%d,\"cpu_active\":%u}\n", result, atomic_load(&active));
		assert(fflush(stdout) == 0);
	}
}

void astra_payload_test_closed(void) {
	assert(atomic_fetch_add(&payload_closed, 1) == 0);
}

extern void __real_astra_async_worker_pool_close(AstraAsyncExecutor *);

void __wrap_astra_async_worker_pool_close(AstraAsyncExecutor *pool) {
	assert(syscall(SYS_gettid) == owner);
	__real_astra_async_worker_pool_close(pool);
	assert(atomic_fetch_add(&pool_joined, 1) == 0);
}

extern int __real_stream_stop_requested(void);

int __wrap_stream_stop_requested(void) {
	int result = __real_stream_stop_requested();
	if (result && atomic_load(&active) != 0) {
		atomic_store(&stopped_while_computing, 1);
	}
	return result;
}

extern int __real_stream_finish(int);

int __wrap_stream_finish(int result) {
	fprintf(stderr, "stream observed: result=%d active=%u peak=%u workers=%ld,%ld network=%u io=%u allocations=%u/%u contexts=%u frames=%u\n", result, atomic_load(&active), atomic_load(&peak_active), workers[0], workers[1], atomic_load(&network_overlap), atomic_load(&io_overlap), allocated, released, contexts, atomic_load(&frames));
	assert(result == (profile == 0 ? 0 : profile == 1 ? 130
	                                                  : 1) &&
	       atomic_load(&active) == 0);
	for (int i = 0; i < 64; ++i) {
		unsigned state = atomic_load(&states[i]);
		if (profile == 0) {
			assert(state == (i < 8 ? 31U : 0U));
		} else if (profile == 2) {
			assert(state == 0);
		} else {
			assert(state == 0 || state == 17 || state == 23 || state == 31);
		}
	}
	assert(atomic_load(&io_submitted) == atomic_load(&io_completed));
	if (profile == 0 || profile == 1) {
		assert(worker_count >= 2 && workers[0] && workers[1] && workers[0] != workers[1]);
		if (!serialized) {
			assert(atomic_load(&peak_active) == 2 && atomic_load(&network_overlap) > 0 && atomic_load(&io_overlap) > 0);
		}
		assert(atomic_load(&frames) == 3);
		assert(atomic_load(&payload_closed) == 1 && atomic_load(&pool_joined) == 1);
	}
	if (profile == 0) {
		assert(driver_observed == 1 && atomic_load(&io_completed) >= 8 && contexts == 5);
	}
	if (profile == 1) {
		assert(atomic_load(&stopped_while_computing) == 1);
	}
	assert(allocated == released && active_allocations == 0 && live_bytes == 0 && contexts <= 5);
	for (unsigned worker = 0; worker < worker_count; ++worker) {
		wait_gone(workers[worker]);
	}
	wait_threads();
	fprintf(stderr, "stream final inventory: fds=%d/%d threads=%d/%d\n", inventory("/proc/self/fd"), baseline_fds, inventory("/proc/self/task"), baseline_threads);
	assert(inventory("/proc/self/fd") == baseline_fds && inventory("/proc/self/task") == baseline_threads);
	printf("{\"workers\":[%ld,%ld],\"worker_count\":%u,\"queue_peak\":%u,\"queue_limit\":%u,\"cpu_peak\":%u,\"network_overlap\":%u,\"io_overlap\":%u,\"io_completed\":%u,\"compiler_allocation_peak\":%u,\"compiler_live_peak_bytes\":%llu,\"context_peaks\":[", workers[0], workers[1], worker_count, atomic_load(&queue_peak), atomic_load(&queue_limit), atomic_load(&peak_active), atomic_load(&network_overlap), atomic_load(&io_overlap), atomic_load(&io_completed), peak_allocations, (unsigned long long)peak_bytes);
	for (unsigned i = 0; i < contexts; ++i) {
		AstraContext17Snapshot *state = &context_peaks[i];
		printf("%s{\"instance\":%llu,\"kind\":%u,\"reserved\":%llu,\"peak\":%llu,\"allocations\":%llu,\"releases_at_close\":%llu,\"live_at_close\":%llu}", i ? "," : "", (unsigned long long)state->instance, state->kind, (unsigned long long)state->reserved_bytes, (unsigned long long)state->peak_bytes, (unsigned long long)state->allocations, (unsigned long long)state->releases, (unsigned long long)state->live);
	}
	puts("]}");
	return __real_stream_finish(result);
}
