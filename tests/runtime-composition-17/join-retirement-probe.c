/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static void *empty(void *argument) {
	*(long *)argument = syscall(SYS_gettid);
	return NULL;
}

static uint64_t nanoseconds(void) {
	struct timespec now;
	assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
	return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}

int main(void) {
	unsigned visible = 0;
	uint64_t longest = 0;
	for (unsigned iteration = 0; iteration < 500; ++iteration) {
		pthread_t worker;
		long identity = -1;
		assert(pthread_create(&worker, NULL, empty, &identity) == 0);
		assert(pthread_join(worker, NULL) == 0 && identity > 0);
		char path[128];
		assert(snprintf(path, sizeof(path), "/proc/self/task/%ld", identity) > 0);
		struct stat state;
		uint64_t before = nanoseconds();
		if (stat(path, &state) == 0)
			++visible;
		else
			assert(errno == ENOENT);
		while (stat(path, &state) == 0) {
			assert(nanoseconds() - before < UINT64_C(2000000000));
			struct timespec delay = {.tv_nsec = 100000};
			assert(nanosleep(&delay, NULL) == 0);
		}
		assert(errno == ENOENT);
		uint64_t elapsed = nanoseconds() - before;
		if (elapsed > longest) longest = elapsed;
	}
	printf("{\"joined\":500,\"still_visible_immediately_after_join\":%u,\"longest_observation_ns\":%llu}\n", visible, (unsigned long long)longest);
	return 0;
}
