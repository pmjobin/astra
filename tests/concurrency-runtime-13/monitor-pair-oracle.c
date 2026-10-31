// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int entered[2], visits[2], dropped[2];
int32_t monitor_pair_visit(int32_t id) {
	assert(id >= 0 && id < 2);
	assert(pthread_mutex_lock(&lock) == 0);
	if (visits[id]++ == 0) {
		entered[id] = 1;
		assert(pthread_cond_broadcast(&changed) == 0);
		while (!entered[1 - id])
			assert(pthread_cond_wait(&changed, &lock) == 0);
	}
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t monitor_pair_drop(int32_t id) {
	assert(id >= 0 && id < 2 && visits[id] == 2000 && dropped[id]++ == 0);
	return 0;
}
int32_t monitor_pair_finish(void) {
	assert(entered[0] && entered[1] && dropped[0] == 1 && dropped[1] == 1);
	puts("monitors: two independently progressing protected objects, exact counters and cleanup");
	return 0;
}
