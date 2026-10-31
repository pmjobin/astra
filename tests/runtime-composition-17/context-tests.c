/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "../../lib/runtime/runtime/context-17.h"
#include "context-provider.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static AstraContext17Snapshot snapshot(AstraContext17 *context) {
	AstraContext17Snapshot result;
	assert(astra_context17_snapshot(context, &result) == ASTRA_CONTEXT17_OK);
	return result;
}
static void instances(uint32_t kind) {
	AstraContext17 *first = astra_context17_owned(kind, 32771, 17, 64, ASTRA_CONTEXT17_AFFINE);
	AstraContext17 *second = astra_context17_owned(kind, 40963, 19, 128, ASTRA_CONTEXT17_AFFINE);
	assert(first && second && snapshot(first).instance != snapshot(second).instance);
	AstraContext17Token a, b;
	assert(!astra_context17_acquire(first, 13, 7, 64, 71, &a));
	assert(!astra_context17_acquire(second, 17, 11, 128, 71, &b));
	assert(a.pointer != b.pointer && !((uintptr_t)a.pointer & 63) && !((uintptr_t)b.pointer & 127));
	for (int i = 0; i < 91; ++i)
		assert(((unsigned char *)a.pointer)[i] == 0);
	memset(a.pointer, 49, 91);
	memset(b.pointer, 83, 187);
	assert(astra_context17_release(second, &a) == ASTRA_CONTEXT17_ORIGIN);
	assert(astra_context17_reset(first) == ASTRA_CONTEXT17_LIVE);
	AstraContext17Token wrong = a;
	++wrong.generation;
	assert(astra_context17_release(first, &wrong) == ASTRA_CONTEXT17_GENERATION);
	assert(!astra_context17_release(first, &a));
	assert(!astra_context17_acquire(first, 13, 7, 64, 71, &wrong));
	assert(wrong.generation > a.generation);
	if (wrong.pointer == a.pointer)
		assert(astra_context17_release(first, &a) == ASTRA_CONTEXT17_GENERATION);
	else
		assert(astra_context17_release(first, &a) == ASTRA_CONTEXT17_ORIGIN);
	assert(!astra_context17_release(first, &wrong));
	assert(!astra_context17_release(second, &b));
	assert(!snapshot(first).live && snapshot(first).allocations == snapshot(first).releases);
	assert(!astra_context17_reset(first));
	assert(!astra_context17_drop(first));
	assert(!astra_context17_drop(second));
}
static void failures(void) {
	AstraContext17 *context = astra_context17_owned(ASTRA_CONTEXT17_POOL, 4099, 3, 64, ASTRA_CONTEXT17_AFFINE);
	assert(context);
	AstraContext17Token tokens[4], invalid;
	assert(astra_context17_acquire(context, UINT64_MAX, 2, 8, 71, &invalid) == ASTRA_CONTEXT17_OVERFLOW);
	assert(!invalid.pointer);
	assert(astra_context17_acquire(context, 1, 8, 3, 71, &invalid) == ASTRA_CONTEXT17_ALIGNMENT);
	assert(astra_context17_acquire(context, 1, 8, 8192, 71, &invalid) == ASTRA_CONTEXT17_ALIGNMENT);
	assert(astra_context17_acquire(context, 1, UINT64_MAX, 8, 71, &invalid) == ASTRA_CONTEXT17_OVERFLOW);
	assert(astra_context17_acquire(context, 1, 8, 8, 0, &invalid) == ASTRA_CONTEXT17_INVALID);
	assert(!astra_context17_acquire(context, 0, 8, 8, 71, &invalid) && !invalid.pointer);
	for (int i = 0; i < 3; ++i)
		assert(!astra_context17_acquire(context, 1, 33 + (uint64_t)i, 32, 71, &tokens[i]));
	assert(astra_context17_acquire(context, 1, 1, 8, 71, &tokens[3]) == ASTRA_CONTEXT17_EXHAUSTED);
	assert(snapshot(context).live == 3);
	assert(astra_context17_close(context) == ASTRA_CONTEXT17_LIVE);
	assert(astra_context17_acquire(context, 1, 1, 8, 71, &invalid) == ASTRA_CONTEXT17_CLOSED);
	for (int i = 0; i < 3; ++i)
		assert(!astra_context17_release(context, &tokens[i]));
	assert(!astra_context17_close(context));
	assert(!astra_context17_drop(context));
}
static void backing(void) {
	_Alignas(128) unsigned char bytes[8197];
	AstraContext17 *borrow = astra_context17_borrowed(bytes + 1, sizeof(bytes) - 1, 7, ASTRA_CONTEXT17_REGION);
	assert(borrow);
	AstraContext17Token token;
	assert(!astra_context17_acquire(borrow, 1, 137, 128, 71, &token));
	assert((uintptr_t)token.pointer >= (uintptr_t)bytes && (uintptr_t)token.pointer + 137 <= (uintptr_t)bytes + sizeof(bytes));
	assert(astra_context17_retain(borrow) == ASTRA_CONTEXT17_INVALID);
	assert(astra_context17_drop(borrow) == ASTRA_CONTEXT17_LIVE);
	assert(!astra_context17_release(borrow, &token));
	assert(!astra_context17_drop(borrow));
	/* An owned backing allocation outlives the last admission handle. */
	AstraContext17 *owned = astra_context17_owned(ASTRA_CONTEXT17_REGION, 8197, 7, 128, ASTRA_CONTEXT17_AFFINE);
	assert(owned && !astra_context17_acquire(owned, 1, 137, 128, 71, &token));
	assert(!astra_context17_drop(owned));
	memset(token.pointer, 0x5a, 137);
	assert(astra_context17_acquire(owned, 1, 1, 8, 71, &(AstraContext17Token){0}) == ASTRA_CONTEXT17_CLOSED);
	assert(!astra_context17_release_origin(token.pointer, 71));
}
static void custom(void) {
	_Atomic int disposed = 0;
	TestContextProvider *state = test_context_provider(12299, &disposed);
	AstraContext17Provider invalid = test_context_contract;
	++invalid.abi;
	assert(!astra_context17_custom(&invalid, state, 12299, 11, ASTRA_CONTEXT17_CONCURRENT));
	assert(!disposed);
	AstraContext17 *context = astra_context17_custom(&test_context_contract, state, 12299, 11, ASTRA_CONTEXT17_CONCURRENT);
	assert(context);
	state->context = context;
	state->test_reentry = 1;
	AstraContext17Token first, second;
	assert(!astra_context17_acquire(context, 13, 17, 256, 71, &first));
	assert((uintptr_t)first.pointer >= (uintptr_t)state->backing && (uintptr_t)first.pointer < (uintptr_t)state->backing + state->capacity);
	state->fail_at = 2;
	assert(astra_context17_acquire(context, 23, 7, 64, 72, &second) == ASTRA_CONTEXT17_OOM);
	assert(snapshot(context).live == 1 && state->live == 1);
	assert(!astra_context17_acquire(context, 23, 7, 64, 72, &second));
	assert(!astra_context17_release(context, &first));
	assert(state->releases == 1);
	assert(!astra_context17_drop(context));
	assert(!disposed && ((unsigned char *)second.pointer)[0] == 0);
	assert(!astra_context17_release_origin(second.pointer, 72));
	assert(disposed == 1);
}
typedef struct ThreadWork {
	AstraContext17 *context;
	pthread_barrier_t *barrier;
	int affine;
} ThreadWork;
static void *worker(void *opaque) {
	ThreadWork *work = opaque;
	AstraContext17Token token;
	if (work->affine) {
		assert(astra_context17_acquire(work->context, 1, 17, 8, 71, &token) == ASTRA_CONTEXT17_THREAD);
		assert(astra_context17_drop(work->context) == ASTRA_CONTEXT17_THREAD);
		return NULL;
	}
	for (int i = 0; i < 201; ++i) {
		assert(!astra_context17_acquire(work->context, 3, (uint64_t)(17 + i % 37), 64, 71, &token));
		if (i == 0) {
			int result = pthread_barrier_wait(work->barrier);
			assert(result == 0 || result == PTHREAD_BARRIER_SERIAL_THREAD);
		}
		memset(token.pointer, i, (size_t)(3 * (17 + i % 37)));
		assert(!astra_context17_release(work->context, &token));
	}
	return NULL;
}
static void threads(void) {
	AstraContext17 *context = astra_context17_owned(ASTRA_CONTEXT17_HEAP, 0, 13, 64, ASTRA_CONTEXT17_CONCURRENT);
	assert(context);
	pthread_barrier_t barrier;
	assert(!pthread_barrier_init(&barrier, NULL, 4));
	ThreadWork work = {context, &barrier, 0};
	pthread_t workers[4];
	for (int i = 0; i < 4; ++i)
		assert(!pthread_create(&workers[i], NULL, worker, &work));
	for (int i = 0; i < 4; ++i)
		assert(!pthread_join(workers[i], NULL));
	AstraContext17Snapshot result = snapshot(context);
	assert(result.allocations == 804 && result.releases == 804 && !result.live && !result.reserved_bytes && result.peak_bytes >= 204);
	assert(!astra_context17_drop(context));
	assert(!pthread_barrier_destroy(&barrier));
	context = astra_context17_owned(ASTRA_CONTEXT17_HEAP, 0, 3, 8, ASTRA_CONTEXT17_AFFINE);
	assert(context);
	work = (ThreadWork){context, NULL, 1};
	assert(!pthread_create(&workers[0], NULL, worker, &work));
	assert(!pthread_join(workers[0], NULL));
	assert(!astra_context17_drop(context));
}
int main(void) {
	for (uint32_t kind = ASTRA_CONTEXT17_HEAP; kind <= ASTRA_CONTEXT17_POOL; ++kind)
		instances(kind);
	failures();
	backing();
	custom();
	threads();
	puts("context substrate: distinct instances, backing leases, external provider, checked failures, generations, reentry and 804 concurrent allocations");
	return 0;
}
