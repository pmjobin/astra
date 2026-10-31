/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "query-provider.h"
#include <assert.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

/* Allocation authority is the callback's private state, never a global lookup.
 * Each instance owns its quota, slot ledger and individually aligned backing.
 * The separate finished list contains telemetry only. */
enum { GUARD_BYTES = 64,
	   GUARD_VALUE = 0xd3 };
typedef struct Block {
	void *pointer;
	uint64_t requested, rounded, charged;
	uint32_t alignment;
} Block;
typedef struct Snapshot {
	int identity;
	uint64_t capacity, slots, live, peak, allocations, releases, refusals;
} Snapshot;
typedef struct State {
	pthread_mutex_t lock;
	Snapshot count;
	Block *blocks;
} State;
typedef struct Finished {
	Snapshot count;
	struct Finished *next;
} Finished;
static pthread_mutex_t report_lock = PTHREAD_MUTEX_INITIALIZER;
static Finished *finished;
static uint64_t opened;

static int allocate(void *opaque, uint64_t bytes, uint32_t alignment, void **out) {
	State *state = opaque;
	if (!bytes || !alignment || (alignment & (alignment - 1))) {
		return ASTRA_CONTEXT17_INVALID;
	}
	uint64_t effective = alignment < sizeof(void *) ? sizeof(void *) : alignment;
	if (bytes > UINT64_MAX - effective + 1) {
		return ASTRA_CONTEXT17_OVERFLOW;
	}
	uint64_t rounded = (bytes + effective - 1) & ~(effective - 1);
	if (rounded > SIZE_MAX - GUARD_BYTES) {
		return ASTRA_CONTEXT17_OVERFLOW;
	}
	uint64_t charged = rounded + GUARD_BYTES;
	assert(pthread_mutex_lock(&state->lock) == 0);
	uint64_t slot = 0;
	while (slot < state->count.slots && state->blocks[slot].pointer) {
		++slot;
	}
	if (slot == state->count.slots || charged > state->count.capacity - state->count.live) {
		++state->count.refusals;
		assert(pthread_mutex_unlock(&state->lock) == 0);
		return ASTRA_CONTEXT17_EXHAUSTED;
	}
	void *pointer = NULL;
	if (posix_memalign(&pointer, (size_t)effective, (size_t)charged) != 0) {
		++state->count.refusals;
		assert(pthread_mutex_unlock(&state->lock) == 0);
		return ASTRA_CONTEXT17_OOM;
	}
	for (unsigned i = 0; i < GUARD_BYTES; ++i) {
		((unsigned char *)pointer)[rounded + i] = GUARD_VALUE;
	}
	state->blocks[slot] = (Block){pointer, bytes, rounded, charged, alignment};
	state->count.live += charged;
	++state->count.allocations;
	if (state->count.live > state->count.peak) {
		state->count.peak = state->count.live;
	}
	*out = pointer;
	assert(pthread_mutex_unlock(&state->lock) == 0);
	return ASTRA_CONTEXT17_OK;
}
static void release(void *opaque, void *pointer, uint64_t bytes, uint32_t alignment) {
	State *state = opaque;
	assert(pthread_mutex_lock(&state->lock) == 0);
	uint64_t slot = 0;
	while (slot < state->count.slots && state->blocks[slot].pointer != pointer) {
		++slot;
	}
	assert(slot < state->count.slots && pointer && state->blocks[slot].requested == bytes && state->blocks[slot].alignment == alignment);
	assert(state->count.live >= state->blocks[slot].charged);
	for (unsigned i = 0; i < GUARD_BYTES; ++i) {
		assert(((unsigned char *)pointer)[state->blocks[slot].rounded + i] == GUARD_VALUE);
	}
	state->count.live -= state->blocks[slot].charged;
	++state->count.releases;
	free(pointer);
	state->blocks[slot] = (Block){0};
	assert(pthread_mutex_unlock(&state->lock) == 0);
}
static void dispose(void *opaque) {
	State *state = opaque;
	assert(pthread_mutex_lock(&state->lock) == 0);
	assert(state->count.live == 0 && state->count.allocations == state->count.releases);
	for (uint64_t i = 0; i < state->count.slots; ++i) {
		assert(!state->blocks[i].pointer);
	}
	Finished *report = malloc(sizeof(*report));
	assert(report);
	report->count = state->count;
	assert(pthread_mutex_unlock(&state->lock) == 0);
	assert(pthread_mutex_destroy(&state->lock) == 0);
	assert(pthread_mutex_lock(&report_lock) == 0);
	report->next = finished;
	finished = report;
	assert(pthread_mutex_unlock(&report_lock) == 0);
	free(state->blocks);
	free(state);
}
static const AstraContext17Provider contract = {
    ASTRA_CONTEXT17_ABI, sizeof(AstraContext17Provider), ASTRA_CONTEXT17_CONCURRENT, 0, allocate, release, dispose};
AstraContext17 *query_custom_allocator(int64_t capacity, int32_t slots, int32_t identity) {
	if (capacity <= 0 || slots <= 0 || (uint64_t)slots > SIZE_MAX / sizeof(Block)) {
		return NULL;
	}
	State *state = calloc(1, sizeof(*state));
	if (!state) {
		return NULL;
	}
	state->blocks = calloc((size_t)slots, sizeof(Block));
	if (!state->blocks) {
		free(state);
		return NULL;
	}
	if (pthread_mutex_init(&state->lock, NULL) != 0) {
		free(state->blocks);
		free(state);
		return NULL;
	}
	state->count = (Snapshot){.identity = identity, .capacity = (uint64_t)capacity, .slots = (uint64_t)slots};
	AstraContext17 *context = astra_context17_custom(&contract, state, (uint64_t)capacity, (uint64_t)slots, ASTRA_CONTEXT17_CONCURRENT);
	if (!context) {
		assert(pthread_mutex_destroy(&state->lock) == 0);
		free(state->blocks);
		free(state);
		return NULL;
	}
	assert(pthread_mutex_lock(&report_lock) == 0);
	++opened;
	assert(pthread_mutex_unlock(&report_lock) == 0);
	return context;
}
int query_provider_disposed(int32_t identity) {
	int count = 0;
	assert(pthread_mutex_lock(&report_lock) == 0);
	for (Finished *p = finished; p; p = p->next) {
		if (p->count.identity == identity) {
			++count;
		}
	}
	assert(pthread_mutex_unlock(&report_lock) == 0);
	return count;
}
int query_provider_finish(void) {
	assert(pthread_mutex_lock(&report_lock) == 0);
	uint64_t count = 0;
	printf("{\"custom_contexts\":[");
	while (finished) {
		Finished *report = finished;
		finished = report->next;
		Snapshot *s = &report->count;
		assert(s->live == 0 && s->allocations == s->releases && s->peak <= s->capacity);
		printf("%s{\"identity\":%d,\"capacity\":%llu,\"slots\":%llu,\"peak\":%llu,\"allocations\":%llu,\"releases\":%llu,\"refusals\":%llu}", count ? "," : "", s->identity, (unsigned long long)s->capacity, (unsigned long long)s->slots, (unsigned long long)s->peak, (unsigned long long)s->allocations, (unsigned long long)s->releases, (unsigned long long)s->refusals);
		++count;
		free(report);
	}
	printf("],\"guard_bytes_per_allocation\":%d,\"opened\":%llu,\"disposed\":%llu}\n", GUARD_BYTES, (unsigned long long)opened, (unsigned long long)count);
	int result = count == opened ? 0 : 1;
	opened = 0;
	assert(pthread_mutex_unlock(&report_lock) == 0);
	return result;
}
