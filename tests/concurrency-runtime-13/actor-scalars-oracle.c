// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int seen[13], destroyed;

static void observed(int id) {
	char name[16];
	assert(pthread_getname_np(pthread_self(), name, sizeof(name)) == 0);
	assert(strcmp(name, "actor-scalars") == 0);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(id >= 0 && id < 13 && seen[id]++ == 0);
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
}

int32_t actor_scalar_signed(int32_t id, int64_t value) {
	const int64_t expected[13] = {INT8_MIN, UINT8_MAX, INT16_MIN, UINT16_MAX,
	                              INT32_MIN, 0, INT64_MIN, 0, INT64_MIN, 0, 1, 0, 0};
	assert(id >= 0 && id < 13 && value == expected[id]);
	observed(id);
	return 0;
}

int32_t actor_scalar_unsigned(int32_t id, uint64_t value) {
	assert((id == 5 && value == UINT32_MAX) || ((id == 7 || id == 9) && value == UINT64_MAX));
	observed(id);
	return 0;
}

int32_t actor_scalar_float(int32_t id, double value) {
	uint64_t bits;
	memcpy(&bits, &value, sizeof(bits));
	assert((id == 11 && bits == UINT64_C(0x8000000000000000)) ||
	       (id == 12 && bits == UINT64_C(0xbff4000000000000)));
	observed(id);
	return 0;
}

int32_t actor_scalar_wait(int32_t id) {
	assert(id >= 0 && id < 13);
	assert(pthread_mutex_lock(&lock) == 0);
	while (!seen[id])
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t actor_scalar_drop(void) {
	assert(destroyed++ < 13);
	return 0;
}

int32_t actor_scalar_finish(void) {
	assert(destroyed == 13);
	for (int i = 0; i < 13; ++i)
		assert(seen[i] == 1);
	puts("native Actor scalars: 13 exact numeric/bool types, signed zero, 64-bit extrema, joined cleanup");
	return 0;
}
