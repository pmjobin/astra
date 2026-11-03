/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "context-provider.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static unsigned entered;
static pthread_t identities[2];
static long kernel_identities[2];
static _Atomic unsigned retired;
static int initial_threads;

static void *calibrate(void *argument) {
	*(long *)argument = syscall(SYS_gettid);
	return NULL;
}

static void await_kernel_retirement(long identity) {
	char path[128];
	assert(snprintf(path, sizeof(path), "/proc/self/task/%ld", identity) > 0);
	struct timespec start, now;
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	struct stat state;
	while (stat(path, &state) == 0) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 2);
		struct timespec delay = {.tv_nsec = 1000000};
		assert(nanosleep(&delay, NULL) == 0);
	}
	assert(errno == ENOENT);
}

static int thread_count(void) {
	DIR *directory = opendir("/proc/self/task");
	assert(directory);
	int count = 0;
	struct dirent *entry;
	while ((entry = readdir(directory)))
		if (entry->d_name[0] != '.') ++count;
	assert(closedir(directory) == 0);
	return count;
}

void context_workers_prepare(void) {
	/* The independent pthread-only probe establishes that TSAN lazily starts
	 * a persistent infrastructure thread on first use. Calibrate before the
	 * product baseline; retain strict equality and never suppress any thread. */
	pthread_t calibration;
	long identity = -1;
	assert(pthread_create(&calibration, NULL, calibrate, &identity) == 0);
	assert(pthread_join(calibration, NULL) == 0 && identity > 0);
	await_kernel_retirement(identity);
	initial_threads = thread_count();
}

int context_worker_enter(int identity) {
	assert(identity == 1 || identity == 2);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(!(entered & (1u << (identity - 1))));
	identities[identity - 1] = pthread_self();
	kernel_identities[identity - 1] = syscall(SYS_gettid);
	entered |= 1u << (identity - 1);
	assert(pthread_cond_broadcast(&changed) == 0);
	struct timespec deadline;
	assert(clock_gettime(CLOCK_REALTIME, &deadline) == 0);
	deadline.tv_sec += 8;
	while (entered != 3)
		assert(pthread_cond_timedwait(&changed, &lock, &deadline) == 0);
	assert(!pthread_equal(identities[0], identities[1]));
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

void context_worker_destroy(int identity) {
	assert(identity == 1 || identity == 2);
	assert(pthread_equal(identities[identity - 1], pthread_self()));
	unsigned bit = 1u << (identity - 1);
	assert(!(atomic_fetch_or(&retired, bit) & bit));
}

int context_workers_finish(void) {
	assert(entered == 3 && atomic_load(&retired) == 3 && m17_custom_provider_retired() == 1);
	/* pthread_join has completed, but Linux can still expose the terminated
	 * task entry briefly. Observe exact worker IDs disappearing, bounded by
	 * two seconds, before comparing the full process inventory. */
	for (unsigned i = 0; i < 2; ++i)
		await_kernel_retirement(kernel_identities[i]);
	assert(thread_count() == initial_threads);
	puts("context workers: two overlapping native threads, exact allocator origins, joined custom backing retirement");
	return 0;
}
