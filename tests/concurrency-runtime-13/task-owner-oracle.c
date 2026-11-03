// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
static _Atomic int acquired[256];
static _Atomic int destroyed[256];

int32_t task_owner_acquire(int32_t id) {
	assert(id > 0 && id < 256);
	assert(atomic_fetch_add(&acquired[id], 1) == 0);
	return 0;
}

int32_t task_owner_destroy(int32_t id) {
	assert(id > 0 && id < 256);
	assert(atomic_load(&acquired[id]) == 1);
	assert(atomic_fetch_add(&destroyed[id], 1) == 0);
	return 0;
}

int32_t task_owner_finish(int32_t count) {
	assert(count > 0 && count < 256);
	for (int i = 1; i <= count; ++i) {
		assert(atomic_load(&acquired[i]) == 1);
		assert(atomic_load(&destroyed[i]) == 1);
	}
	printf("task owners: %d exact acquisitions and destructions after join\n", count);
	return 0;
}
