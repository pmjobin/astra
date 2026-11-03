/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/async/virtual.h"
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static _Atomic unsigned started, active, ended, retired, submitted, completed, closed, joined;
static long owner, identities[2];

static unsigned bit_for(int identity) {
	assert(identity == 17 || identity == 29);
	return identity == 17 ? 1u : 2u;
}

void bridge_public_prepare(void) {
	owner = syscall(SYS_gettid);
}

int bridge_workers_started(void) {
	return (int)atomic_load(&started);
}

void bridge_worker_begin(int identity) {
	unsigned bit = bit_for(identity);
	assert(pthread_mutex_lock(&lock) == 0);
	long current = syscall(SYS_gettid);
	assert(current != owner);
	identities[bit == 1 ? 0 : 1] = current;
	assert(!(atomic_fetch_or(&started, bit) & bit));
	assert(!(atomic_fetch_or(&active, bit) & bit));
	assert(pthread_cond_broadcast(&changed) == 0);
	struct timespec deadline;
	assert(clock_gettime(CLOCK_REALTIME, &deadline) == 0);
	deadline.tv_sec += 8;
	while (atomic_load(&started) != 3)
		assert(pthread_cond_timedwait(&changed, &lock, &deadline) == 0);
	assert(identities[0] != identities[1]);
	assert(pthread_mutex_unlock(&lock) == 0);
}

void bridge_worker_end(int identity) {
	unsigned bit = bit_for(identity);
	assert(atomic_fetch_and(&active, ~bit) & bit);
	assert(!(atomic_fetch_or(&ended, bit) & bit));
}

void bridge_job_retired(int identity) {
	unsigned bit = bit_for(identity);
	assert(atomic_load(&ended) & bit);
	assert(!(atomic_fetch_or(&retired, bit) & bit));
}

void astra_payload_test_submitted(void) {
	assert(syscall(SYS_gettid) == owner);
	unsigned ordinal = atomic_fetch_add(&submitted, 1);
	assert(ordinal < 3);
	if (ordinal == 1) assert(atomic_load(&active) != 0);
}

void astra_payload_test_completed(uint64_t target, uint64_t cancel, int result, int cancel_result, int cancel_seen) {
	(void)cancel_result;
	assert(syscall(SYS_gettid) == owner && target && cancel && target != cancel && !cancel_seen);
	unsigned ordinal = atomic_fetch_add(&completed, 1);
	assert(ordinal < 3 && result == (ordinal == 2 ? 8 : 67));
	if (ordinal == 1) assert(atomic_load(&active) != 0);
}

void astra_payload_test_closed(void) {
	assert(atomic_fetch_add(&closed, 1) < 3);
}

void __real_astra_async_worker_pool_close(AstraAsyncExecutor *);

void __wrap_astra_async_worker_pool_close(AstraAsyncExecutor *pool) {
	assert(syscall(SYS_gettid) == owner && pool);
	__real_astra_async_worker_pool_close(pool);
	assert(atomic_fetch_add(&joined, 1) == 0);
}

static void await_retirement(long identity) {
	char path[128];
	assert(snprintf(path, sizeof(path), "/proc/self/task/%ld", identity) > 0);
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	struct stat state;
	while (stat(path, &state) == 0) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 2);
		assert(nanosleep(&delay, NULL) == 0);
	}
	assert(errno == ENOENT);
}

int bridge_public_finish(void) {
	assert(atomic_load(&started) == 3 && atomic_load(&active) == 0 && atomic_load(&ended) == 3 && atomic_load(&retired) == 3);
	assert(atomic_load(&submitted) == 3 && atomic_load(&completed) == 3 && atomic_load(&closed) == 3 && atomic_load(&joined) == 1);
	for (int i = 0; i < 2; ++i)
		await_retirement(identities[i]);
	puts("public bridge: Astra owning buffers and contexts round-trip through two workers and real overlapping file completions; all joined");
	return 0;
}
