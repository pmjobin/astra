// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int arrived;
static int released;
static int destroyed;
static int expected_workers = 4, schedule_seed;

int32_t race_prepare(int32_t workers, int32_t seed) {
	assert(workers >= 2 && workers <= 8 && arrived == 0);
	expected_workers = workers;
	schedule_seed = seed;
	return 0;
}

int32_t race_worker_ready(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	int arrival = ++arrived;
	assert(pthread_cond_broadcast(&changed) == 0);
	while (!released)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	for (int i = 0; i < (schedule_seed + arrival) % 3; ++i)
		assert(sched_yield() == 0);
	return 0;
}

int32_t race_parent_release(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	while (arrived != expected_workers)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	released = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t race_parent_ready(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	while (arrived != expected_workers)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t race_destroy(int32_t value) {
	assert(pthread_mutex_lock(&lock) == 0);
	assert(value == 17 && destroyed == 0);
	++destroyed;
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t race_finish(void) {
	assert(arrived == expected_workers && destroyed == 1);
	if (expected_workers == 4)
		puts("weak race: four native workers, one payload destruction, expired upgrade");
	else
		printf("weak race: %d native workers, one payload destruction, expired upgrade\n", expected_workers);
	return 0;
}
