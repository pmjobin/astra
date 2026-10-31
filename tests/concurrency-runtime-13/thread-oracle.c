// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static pthread_t identities[8];
static int arrived;
static int destroyed;

int32_t thread_oracle_arrive(int32_t expected) {
	assert(expected >= 2 && expected <= 8);
	assert(pthread_mutex_lock(&lock) == 0);
	for (int i = 0; i < arrived; ++i)
		assert(!pthread_equal(identities[i], pthread_self()));
	assert(arrived < expected);
	identities[arrived++] = pthread_self();
	assert(pthread_cond_broadcast(&changed) == 0);
	while (arrived < expected)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 1;
}

int32_t thread_oracle_destroy(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	++destroyed;
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t thread_oracle_finish(int32_t expected) {
	assert(arrived == expected && destroyed == expected);
	printf("native threads: %d simultaneous identities, %d exact environment destructions\n", arrived, destroyed);
	return 0;
}
