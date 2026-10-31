// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int sampled[4], dropped[3];
int32_t app_sample(int32_t app, int32_t tag, int32_t value) {
	int expected = 0;
	if (app == 109) {
		for (int i = 0; i < 512; ++i)
			expected += (i * 17 + 5) % 251;
	} else if (app == 110)
		expected = 19;
	else if (app == 111)
		expected = 17;
	else if (app == 120)
		expected = 14;
	else {
		assert(app == 113);
		expected = 1000;
	}
	assert(tag >= 0 && tag < 4 && value == expected);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(sampled[tag]++ == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t app_drop(int32_t app, int32_t tag) {
	assert(tag >= 0 && tag < 3 && (app == 110 || app == 111 || app == 113 || app == 120));
	assert(pthread_mutex_lock(&lock) == 0);
	if (app != 111 && tag != 0) assert(dropped[0] == 1);
	assert(++dropped[tag] <= (app == 111 ? 2 : 1));
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t app_finish(int32_t app) {
	if (app == 109 || app == 111) {
		for (int i = 0; i < 4; ++i)
			assert(sampled[i] == 1);
	} else if (app == 110)
		assert(sampled[0] == 1 && dropped[0] == 1 && dropped[1] == 1);
	else if (app == 120)
		assert(sampled[0] == 1 && dropped[0] == 1 && dropped[1] == 1);
	else {
		assert(app == 113 && sampled[0] == 1 && sampled[1] == 1);
		for (int i = 0; i < 3; ++i)
			assert(dropped[i] == 1);
	}
	if (app == 111) assert(dropped[0] == 2);
	printf("application A%d: independent values and exact owned lifetimes\n", app);
	return 0;
}
