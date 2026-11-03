/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "context-provider.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

static AstraContext17 *contexts[2];
static void *payloads[2];
static uint64_t tags[2];
static unsigned acquired, released, envelopes;
static _Atomic int failure_disposed;
#ifdef CONTEXT_BYTES_FAILURE
static unsigned refused;
#endif
#ifdef CONTEXT_BYTES_WORKER
static pthread_t home;
static _Atomic unsigned workers;
extern int context_bytes_worker_run(void);

int main(void) {
	home = pthread_self();
	return context_bytes_worker_run();
}

void context_bytes_worker_observed(int checksum) {
	assert(!pthread_equal(home, pthread_self()) && checksum == 17);
	assert(atomic_fetch_add(&workers, 1) < 2);
}

#elif defined(CONTEXT_BYTES_FAILURE)
extern int context_bytes_failure_run(void);

int main(void) {
	return context_bytes_failure_run();
}

#else
extern int context_bytes_run(void);

int main(void) {
	int result = context_bytes_run();
#ifdef CONTEXT_BYTES_EMPTY
	assert(acquired == 0 && released == 0 && envelopes == 0);
	assert(m17_custom_provider_retired() == 0);
#endif
	return result;
}

#endif
extern void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t,
                                                  uint64_t, uint32_t, uint64_t, uint32_t);
extern int __real_astra_context17_release_origin_checked(void *, uint64_t);

void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	assert(acquired < 2 && count == (acquired ? 23U : 19U));
	uint32_t expected_mode = 2;
#ifdef CONTEXT_BYTES_AFFINE
	expected_mode = 0;
#endif
#ifdef CONTEXT_BYTES_TRANSFER
	expected_mode = 1;
#endif
	assert(size == 1 && alignment >= 1 && mode == expected_mode && tag != 0);
	void *payload = __real_astra_context17_allocate_mode(context, count, size,
	                                                     alignment, tag, mode);
	if (payload == NULL) {
#ifdef CONTEXT_BYTES_FAILURE
		AstraContext17Snapshot state;
		assert(acquired == 1 && count == 23 && refused++ == 0);
		assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK && state.live == 0);
		return NULL;
#else
		abort();
#endif
	}
	assert(payload != NULL && astra_context17_origin(payload, tag) == context);
	if (acquired != 0) {
		assert(contexts[0] != context && payloads[0] != payload && tags[0] == tag);
	}
	for (uint64_t index = 0; index < count; ++index) {
		assert(((const unsigned char *)payload)[index] == 0);
	}
	contexts[acquired] = context;
	payloads[acquired] = payload;
	tags[acquired++] = tag;
	return payload;
}

int __wrap_astra_context17_release_origin_checked(void *payload, uint64_t tag) {
	unsigned slot = 0;
	while (slot < acquired && payloads[slot] != payload) {
		++slot;
	}
	assert(slot < acquired && tags[slot] == tag);
	assert(astra_context17_origin(payload, tag) == contexts[slot]);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(contexts[slot], &state) == ASTRA_CONTEXT17_OK);
	assert(state.closed == 1 && state.anchors == 0 && state.live != 0);
	payloads[slot] = NULL;
	int result = __real_astra_context17_release_origin_checked(payload, tag);
	assert(result == 1);
	++released;
	return result;
}

void context_bytes_zero_failed(void) {
	abort();
}

void context_bytes_envelope_retired(void) {
	assert(envelopes++ == 0);
}

int context_bytes_finish(void) {
#ifdef CONTEXT_BYTES_FAILURE
	assert(acquired == 2 && released == 2 && envelopes == 0 && refused == 1);
	assert(m17_custom_provider_retired() == 1 && atomic_load(&failure_disposed) == 1);
	puts("context bytes: actual exhaustion, caller input cleanup, recovery and exact backing release");
#else
	assert(acquired == 2 && released == 2 && envelopes == 1);
#if defined(CONTEXT_BYTES_AFFINE) || defined(CONTEXT_BYTES_TRANSFER)
	assert(m17_custom_provider_retired() == 0);
#else
	assert(m17_custom_provider_retired() == 2);
#endif
#ifdef CONTEXT_BYTES_WORKER
	assert(atomic_load(&workers) == 2);
#endif
	puts("context bytes: actual independent backing, zeroing, result/field/record moves and original release");
#endif
	return 0;
}

AstraContext17 *context_bytes_failure_allocator(int64_t capacity, int32_t slots,
                                                int32_t fail_at) {
	if (capacity <= 0 || slots <= 0 || fail_at <= 0) {
		return NULL;
	}
	TestContextProvider *provider = test_context_provider((uint64_t)capacity,
	                                                      &failure_disposed);
	assert(provider != NULL);
	provider->fail_at = (uint64_t)fail_at;
	AstraContext17 *context = astra_context17_custom(&test_context_contract,
	                                                 provider, (uint64_t)capacity, (uint64_t)slots, 2);
	assert(context != NULL);
	provider->context = context;
	return context;
}
