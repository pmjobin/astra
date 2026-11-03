// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
static _Atomic int attempts;
static _Atomic int destroyed;

int32_t singleton_attempt(void) {
	atomic_fetch_add(&attempts, 1);
	return 0;
}

int32_t singleton_destroy(void) {
	assert(atomic_fetch_add(&destroyed, 1) == 0);
	return 0;
}

int32_t singleton_finish(void) {
	assert(atomic_load(&attempts) == 2);
	assert(atomic_load(&destroyed) == 1);
	puts("singleton: failed initialization retried, one racing publication, quiescent shutdown");
	return 0;
}
