// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static void *allocations[1024];
static int allocation_failure, worker_failure, injected, checks, failures;
void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);
int __real_pthread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);

void *__wrap_calloc(size_t count, size_t size) {
	assert(pthread_mutex_lock(&lock) == 0);
	if (allocation_failure && --allocation_failure == 0) {
		++injected;
		assert(pthread_mutex_unlock(&lock) == 0);
		errno = ENOMEM;
		return NULL;
	}
	void *result = __real_calloc(count, size);
	if (result) {
		int slot = 0;
		while (slot < 1024 && allocations[slot])
			++slot;
		assert(slot < 1024);
		allocations[slot] = result;
	}
	assert(pthread_mutex_unlock(&lock) == 0);
	return result;
}

void __wrap_free(void *pointer) {
	assert(pthread_mutex_lock(&lock) == 0);
	if (pointer)
		for (int i = 0; i < 1024; ++i)
			if (allocations[i] == pointer) {
				allocations[i] = NULL;
				break;
			}
	assert(pthread_mutex_unlock(&lock) == 0);
	__real_free(pointer);
}

int __wrap_pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*function)(void *), void *context) {
	assert(pthread_mutex_lock(&lock) == 0);
	int fail = worker_failure && --worker_failure == 0;
	if (fail) ++injected;
	assert(pthread_mutex_unlock(&lock) == 0);
	return fail ? EAGAIN : __real_pthread_create(thread, attr, function, context);
}

int32_t pool_fault_arm(int32_t allocation, int32_t worker) {
	assert(allocation >= 0 && allocation <= 3 && worker >= 0 && worker <= 2);
	assert((allocation == 0) != (worker == 0));
	assert(pthread_mutex_lock(&lock) == 0);
	assert(allocation_failure == 0 && worker_failure == 0 && injected == 0);
	allocation_failure = allocation;
	worker_failure = worker;
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t pool_fault_observe(int32_t expected) {
	assert(pthread_mutex_lock(&lock) == 0);
	assert(injected == expected && allocation_failure == 0 && worker_failure == 0);
	for (int i = 0; i < 1024; ++i)
		assert(allocations[i] == NULL);
	failures += injected;
	injected = 0;
	++checks;
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t pool_fault_finish(void) {
	assert(checks == 12 && failures == 5);
	puts("pool failures: two invalid counts, three allocation faults, two worker-start faults, five recovered runs, exact retirement");
	return 0;
}
