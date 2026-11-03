/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Independent external provider: actual private runtime-sized backing, not a
 * compiler-generated static domain or an offset returned into runtime backing. */
#include "context-provider.h"
#include <assert.h>
#include <stdlib.h>

TestContextProvider *test_context_provider(uint64_t capacity, _Atomic int *disposed) {
	TestContextProvider *state = calloc(1, sizeof(*state));
	assert(state && capacity <= SIZE_MAX - 4095);
	state->backing = aligned_alloc(4096, (size_t)((capacity + 4095) & ~(uint64_t)4095));
	assert(state->backing);
	state->capacity = capacity;
	state->disposed = disposed;
	return state;
}

static int allocate(void *opaque, uint64_t bytes, uint32_t alignment, void **out) {
	TestContextProvider *state = opaque;
	++state->attempts;
	if (state->test_reentry) assert(astra_context17_reset(state->context) == ASTRA_CONTEXT17_REENTRY);
	if (state->attempts == state->fail_at) return ASTRA_CONTEXT17_OOM;
	uint64_t offset = (state->used + alignment - 1) & ~((uint64_t)alignment - 1);
	if (offset > state->capacity || bytes > state->capacity - offset) return ASTRA_CONTEXT17_EXHAUSTED;
	*out = state->backing + offset;
	state->used = offset + bytes;
	++state->live;
	return ASTRA_CONTEXT17_OK;
}

static void release(void *opaque, void *pointer, uint64_t bytes, uint32_t alignment) {
	TestContextProvider *state = opaque;
	assert(state->live && (uintptr_t)pointer >= (uintptr_t)state->backing);
	uint64_t offset = (uintptr_t)pointer - (uintptr_t)state->backing;
	assert(offset <= state->capacity && bytes <= state->capacity - offset && !((uintptr_t)pointer & (alignment - 1)));
	if (state->test_reentry) assert(astra_context17_reset(state->context) == ASTRA_CONTEXT17_REENTRY);
	++state->releases;
	if (!--state->live) state->used = 0;
}

static void dispose(void *opaque) {
	TestContextProvider *state = opaque;
	assert(!state->live);
	++*state->disposed;
	free(state->backing);
	free(state);
}

const AstraContext17Provider test_context_contract = {
    ASTRA_CONTEXT17_ABI, sizeof(AstraContext17Provider), ASTRA_CONTEXT17_CONCURRENT, 0,
    allocate, release, dispose};
static _Atomic int source_disposed;

AstraContext17 *m17_custom_allocator(int64_t capacity, int32_t slots) {
	if (capacity <= 0 || slots <= 0) return NULL;
	TestContextProvider *state = test_context_provider((uint64_t)capacity, &source_disposed);
	AstraContext17 *context = astra_context17_custom(&test_context_contract, state, (uint64_t)capacity, (uint64_t)slots, ASTRA_CONTEXT17_CONCURRENT);
	if (!context) {
		free(state->backing);
		free(state);
		return NULL;
	}
	state->context = context;
	return context;
}

int m17_custom_provider_retired(void) {
	return atomic_load(&source_disposed);
}
