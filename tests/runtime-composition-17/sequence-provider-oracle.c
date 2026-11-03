/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "../../examples/runtime-composition-17/sequence-provider.h"
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct Work {
	AstraContext17 *context;
	uint64_t tag;
	unsigned char value;
	pthread_barrier_t *start, *held, *retire;
} Work;

static void meet(pthread_barrier_t *barrier) {
	int result = pthread_barrier_wait(barrier);
	assert(result == 0 || result == PTHREAD_BARRIER_SERIAL_THREAD);
}

static void *exercise(void *opaque) {
	Work *work = opaque;
	meet(work->start);
	for (int i = 0; i < 1001; ++i) {
		AstraContext17Token token;
		assert(astra_context17_acquire(work->context, 17, 1, 64, work->tag, &token) == ASTRA_CONTEXT17_OK);
		memset(token.pointer, work->value, 17);
		for (int n = 0; n < 17; ++n) {
			assert(((unsigned char *)token.pointer)[n] == work->value);
		}
		if (i == 0) {
			meet(work->held);
			meet(work->retire);
		}
		assert(astra_context17_release(work->context, &token) == ASTRA_CONTEXT17_OK);
	}
	return NULL;
}

int main(void) {
	AstraContext17 *first = sequence_custom_allocator(1025, 4, 101);
	AstraContext17 *second = sequence_custom_allocator(4099, 4, 103);
	assert(first && second && first != second);
	AstraContext17Token a, b, refused;
	assert(astra_context17_acquire(first, 129, 1, 256, 71, &a) == ASTRA_CONTEXT17_OK);
	assert(astra_context17_acquire(second, 26, 1, 128, 73, &b) == ASTRA_CONTEXT17_OK);
	assert(a.pointer != b.pointer && a.instance != b.instance);
	assert(astra_context17_release(second, &a) == ASTRA_CONTEXT17_ORIGIN);
	memset(a.pointer, 29, 129);
	/* The provider's private guard consumes quota beyond runtime backing
	 * accounting: this refusal must come from the callback, not the core. */
	assert(astra_context17_acquire(first, 1, 1, 256, 79, &refused) == ASTRA_CONTEXT17_EXHAUSTED);
	for (int i = 0; i < 129; ++i) {
		assert(((unsigned char *)a.pointer)[i] == 29);
	}
	assert(sequence_provider_disposed(101) == 0);
	astra_context17_destroy(first);
	assert(sequence_provider_disposed(101) == 0);
	assert(astra_context17_release(first, &a) == ASTRA_CONTEXT17_OK);
	assert(sequence_provider_disposed(101) == 1);
	assert(astra_context17_release(second, &b) == ASTRA_CONTEXT17_OK);
	pthread_barrier_t start, held, retire;
	assert(pthread_barrier_init(&start, NULL, 3) == 0 && pthread_barrier_init(&held, NULL, 3) == 0 && pthread_barrier_init(&retire, NULL, 3) == 0);
	Work work[] = {{second, 211, 17, &start, &held, &retire}, {second, 223, 31, &start, &held, &retire}};
	pthread_t threads[2];
	for (int i = 0; i < 2; ++i) {
		assert(pthread_create(&threads[i], NULL, exercise, &work[i]) == 0);
	}
	meet(&start);
	meet(&held);
	AstraContext17Snapshot simultaneous;
	assert(astra_context17_snapshot(second, &simultaneous) == ASTRA_CONTEXT17_OK && simultaneous.live == 2);
	meet(&retire);
	for (int i = 0; i < 2; ++i) {
		assert(pthread_join(threads[i], NULL) == 0);
	}
	assert(pthread_barrier_destroy(&start) == 0 && pthread_barrier_destroy(&held) == 0 && pthread_barrier_destroy(&retire) == 0);
	AstraContext17Token slots[4];
	for (int i = 0; i < 4; ++i) {
		assert(astra_context17_acquire(second, 1, 1, 8, (uint64_t)(307 + i), &slots[i]) == ASTRA_CONTEXT17_OK);
	}
	assert(astra_context17_acquire(second, 1, 1, 8, 313, &refused) == ASTRA_CONTEXT17_EXHAUSTED);
	for (int i = 0; i < 4; ++i) {
		assert(astra_context17_release(second, &slots[i]) == ASTRA_CONTEXT17_OK);
	}
	AstraContext17Token merged;
	assert(astra_context17_acquire(second, 2501, 1, 256, 317, &merged) == ASTRA_CONTEXT17_OK);
	memset(merged.pointer, 47, 2501);
	assert(astra_context17_release(second, &merged) == ASTRA_CONTEXT17_OK);
	astra_context17_destroy(second);
	assert(sequence_provider_disposed(103) == 1);
	assert(sequence_provider_finish() == 0);
	puts("sequence arena provider: private quotas, concurrent callbacks, distinct origins and last-lease disposal");
	return 0;
}
