/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "context-provider.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>

static _Atomic int disposed;
static const uint64_t tag = UINT64_C(0x6e65737465643137);

static AstraContext17 *custom(uint64_t capacity, uint64_t slots, TestContextProvider **provider) {
	*provider = test_context_provider(capacity, &disposed);
	AstraContext17 *context = astra_context17_custom(&test_context_contract, *provider, capacity, slots, ASTRA_CONTEXT17_CONCURRENT);
	assert(context);
	(*provider)->context = context;
	return context;
}

static void check(AstraContext17 *context, uint64_t anchors, uint64_t live) {
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
	assert(state.anchors == anchors && state.live == live);
}

typedef struct Release {
	AstraContext17 *context;
	AstraContext17Token token;
} Release;

static void *retire(void *opaque) {
	Release *owner = opaque;
	assert(astra_context17_release(owner->context, &owner->token) == ASTRA_CONTEXT17_OK);
	return NULL;
}

int main(void) {
	assert(!astra_context17_nested(NULL, ASTRA_CONTEXT17_REGION, 4099, 7, 64));
	_Alignas(64) unsigned char backing[8192];
	AstraContext17 *scoped = astra_context17_borrowed(backing, sizeof(backing), 7, ASTRA_CONTEXT17_REGION);
	AstraContext17 *affine = astra_context17_owned(ASTRA_CONTEXT17_REGION, 8192, 7, 64, ASTRA_CONTEXT17_AFFINE);
	AstraContext17 *transfer = astra_context17_owned(ASTRA_CONTEXT17_REGION, 8192, 7, 64, ASTRA_CONTEXT17_TRANSFER);
	assert(scoped && affine && transfer);
	assert(!astra_context17_nested(scoped, ASTRA_CONTEXT17_REGION, 4099, 7, 64));
	assert(!astra_context17_nested(affine, ASTRA_CONTEXT17_POOL, 4099, 7, 64));
	assert(!astra_context17_nested(transfer, ASTRA_CONTEXT17_POOL, 4099, 7, 64));
	assert(!astra_context17_drop(scoped) && !astra_context17_drop(affine) && !astra_context17_drop(transfer));
	TestContextProvider *provider;
	AstraContext17 *parent = custom(262147, 17, &provider);
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_HEAP, 4099, 7, 64));
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_CUSTOM, 4099, 7, 64));
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, 0, 7, 64));
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, 4099, 0, 64));
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, 4099, 7, 3));
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, UINT64_MAX, 7, 64));
	assert(provider->attempts == 0);
	provider->fail_at = 1;
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, 65543, 7, 64));
	assert(provider->attempts == 1 && provider->live == 0 && provider->releases == 0);
	check(parent, 1, 0);
	AstraContext17 *middle = astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, 131101, 7, 128);
	AstraContext17 *leaf = astra_context17_nested(middle, ASTRA_CONTEXT17_POOL, 65543, 5, 256);
	assert(middle && leaf && provider->live == 1 && provider->attempts == 2);
	check(parent, 1, 1);
	check(middle, 1, 1);
	check(leaf, 1, 0);
	AstraContext17Token first, second;
	assert(!astra_context17_acquire(leaf, 97, 1, 256, tag, &first));
	assert(!astra_context17_acquire(leaf, 103, 1, 64, tag + 1, &second));
	/* Both actual payload pointers are inside the external top-level backing. */
	assert((uintptr_t)first.pointer >= (uintptr_t)provider->backing && (uintptr_t)first.pointer + 97 <= (uintptr_t)provider->backing + provider->capacity);
	assert((uintptr_t)second.pointer >= (uintptr_t)provider->backing && (uintptr_t)second.pointer + 103 <= (uintptr_t)provider->backing + provider->capacity);
	assert(!((uintptr_t)first.pointer & 255));
	((unsigned char *)first.pointer)[96] = 0x6d;
	assert(astra_context17_reset(parent) == ASTRA_CONTEXT17_LIVE && astra_context17_reset(middle) == ASTRA_CONTEXT17_LIVE);
	assert(!astra_context17_drop(parent) && !astra_context17_drop(middle) && !astra_context17_drop(leaf));
	check(parent, 0, 1);
	check(middle, 0, 1);
	check(leaf, 0, 2);
	assert(!astra_context17_release(leaf, &second) && atomic_load(&disposed) == 0);
	assert(((unsigned char *)first.pointer)[96] == 0x6d);
	Release owner = {leaf, first};
	pthread_t worker;
	assert(!pthread_create(&worker, NULL, retire, &owner));
	assert(!pthread_join(worker, NULL) && atomic_load(&disposed) == 1);
	/* A capacity failure does not consume the caller's parent handle or cause
	 * a fallback allocation. A closed parent likewise admits no new backing. */
	parent = custom(257, 1, &provider);
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, 65543, 7, 64));
	assert(provider->attempts == 0);
	check(parent, 1, 0);
	assert(!astra_context17_close(parent));
	assert(!astra_context17_nested(parent, ASTRA_CONTEXT17_REGION, 17, 1, 8));
	assert(provider->attempts == 0 && !astra_context17_drop(parent));
	assert(atomic_load(&disposed) == 2);
	/* Fresh-child construction makes ancestry acyclic. A declared depth bound
	 * also bounds recursive final disposal; refusal leaves all parents valid. */
	AstraContext17 *chain[257];
	chain[0] = custom(2097169, 1, &provider);
	for (uint32_t i = 1; i <= 256; ++i) {
		chain[i] = astra_context17_nested(chain[i - 1], ASTRA_CONTEXT17_REGION, 1048583 - i * 257, 1, 64);
		assert(chain[i]);
	}
	assert(!astra_context17_nested(chain[256], ASTRA_CONTEXT17_POOL, 4099, 1, 64));
	check(chain[256], 1, 0);
	for (unsigned i = 0; i <= 256; ++i)
		assert(!astra_context17_drop(chain[i]));
	assert(atomic_load(&disposed) == 3);
	puts("nested contexts: actual parent backing, closed-anchor ancestry leases, worker final release, refusal conservation and bounded acyclic disposal");
	return 0;
}
