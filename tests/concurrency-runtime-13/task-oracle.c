// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static pthread_t threads[8];
static int identities;
static int entered;
static int visits[4];
static pthread_t first_worker[4];

int32_t task_oracle_step(int32_t id) {
	assert(id >= 1 && id <= 4);
	assert(pthread_mutex_lock(&lock) == 0);
	int known = 0;
	for (int i = 0; i < identities; ++i)
		known |= pthread_equal(threads[i], pthread_self());
	if (!known) {
		assert(identities < 8);
		threads[identities++] = pthread_self();
	}
	if (visits[id - 1]++ == 0) {
		first_worker[id - 1] = pthread_self();
		++entered;
		assert(pthread_cond_broadcast(&changed) == 0);
		while (entered < 4)
			assert(pthread_cond_wait(&changed, &lock) == 0);
	} else {
		assert(!pthread_equal(first_worker[id - 1], pthread_self()));
	}
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t task_oracle_finish(void) {
	assert(identities == 4 && entered == 4);
	for (int i = 0; i < 4; ++i)
		assert(visits[i] == 2);
	puts("executor: four concurrent native frames, eight observed steps, joined shutdown");
	return 0;
}
