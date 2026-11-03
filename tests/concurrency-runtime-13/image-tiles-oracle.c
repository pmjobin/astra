// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int workers, sampled[8];

int32_t app_tile_prepare(int32_t count) {
	assert(count == 2 || count == 4 || count == 8);
	workers = count;
	return 0;
}

int32_t app_sample(int32_t app, int32_t tag, int32_t value) {
	int expected = 0;
	for (int i = 0; i < 512; ++i)
		expected += (i * 17 + 5) % 251;
	assert(app == 109 && tag >= 0 && tag < workers && value == expected);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(sampled[tag]++ == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t app_finish(int32_t app) {
	assert(app == 109);
	for (int i = 0; i < workers; ++i)
		assert(sampled[i] == 1);
	printf("image tiles: %d independently checked native worker checksums\n", workers);
	return 0;
}
