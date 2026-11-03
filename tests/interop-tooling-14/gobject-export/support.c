// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdatomic.h>
#include <stddef.h>
static _Atomic int32_t constructed;
static _Atomic int32_t destroyed;
static _Atomic int32_t last_created;
static _Atomic int32_t last_destroyed;
static int fail_calloc;
static int fail_cache;
void *__real_calloc(size_t count, size_t bytes);
void *__real_g_try_malloc0(size_t bytes);
void *__real_g_try_malloc0_n(size_t count, size_t bytes);

void *__wrap_calloc(size_t count, size_t bytes) {
	if (fail_calloc && --fail_calloc == 0) return NULL;
	return __real_calloc(count, bytes);
}

void *__wrap_g_try_malloc0(size_t bytes) {
	if (fail_cache && --fail_cache == 0) return NULL;
	return __real_g_try_malloc0(bytes);
}

void *__wrap_g_try_malloc0_n(size_t count, size_t bytes) {
	if (fail_cache && --fail_cache == 0) return NULL;
	return __real_g_try_malloc0_n(count, bytes);
}

void astra14_fault(int32_t allocator, int32_t after) {
	if (allocator == 0)
		fail_calloc = after;
	else
		fail_cache = after;
}

int32_t astra14_created(int32_t value) {
	atomic_store(&last_created, value);
	atomic_fetch_add(&constructed, 1);
	return 0;
}

int32_t astra14_destroyed(int32_t value) {
	atomic_store(&last_destroyed, value);
	atomic_fetch_add(&destroyed, 1);
	return 0;
}

int32_t astra14_stats(int32_t index) {
	switch (index) {
	case 0:
		return atomic_load(&constructed);
	case 1:
		return atomic_load(&destroyed);
	case 2:
		return atomic_load(&last_created);
	case 3:
		return atomic_load(&last_destroyed);
	default:
		return -1;
	}
}
