/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "sequence-provider.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Each callback receives its owning arena directly. Sorted live extents define
 * reusable first-fit gaps; no external identity table authorizes allocation. */
enum { ARENA_ALIGNMENT = 4096,
	   GUARD_BYTES = 32,
	   GUARD_VALUE = 0xb7 };

typedef struct Extent {
	uint64_t offset, bytes, span;
	uint32_t alignment;
} Extent;

typedef struct Counts {
	int identity;
	uint64_t capacity, slots, count, live, peak, allocations, releases, refusals, reused;
} Counts;

typedef struct Arena {
	pthread_mutex_t lock;
	unsigned char *backing;
	Extent *extents;
	Counts stats;
	uint64_t high_water;
} Arena;

typedef struct Finished {
	Counts stats;
	struct Finished *next;
} Finished;

static pthread_mutex_t report_lock = PTHREAD_MUTEX_INITIALIZER;
static Finished *finished;
static uint64_t opened;

static int allocate(void *opaque, uint64_t bytes, uint32_t alignment, void **out) {
	Arena *arena = opaque;
	if (!bytes || !alignment || (alignment & (alignment - 1)) || alignment > ARENA_ALIGNMENT) {
		return ASTRA_CONTEXT17_INVALID;
	}
	if (bytes > UINT64_MAX - GUARD_BYTES) {
		return ASTRA_CONTEXT17_OVERFLOW;
	}
	uint64_t span = bytes + GUARD_BYTES, offset = 0, slot = 0;
	assert(pthread_mutex_lock(&arena->lock) == 0);
	if (arena->stats.count == arena->stats.slots || span > arena->stats.capacity - arena->stats.live) {
		goto exhausted;
	}
	while (slot < arena->stats.count) {
		if (offset > UINT64_MAX - alignment + 1) {
			goto exhausted;
		}
		offset = (offset + alignment - 1) & ~((uint64_t)alignment - 1);
		if (offset <= arena->extents[slot].offset && span <= arena->extents[slot].offset - offset) {
			break;
		}
		offset = arena->extents[slot].offset + arena->extents[slot].span;
		++slot;
	}
	if (offset > UINT64_MAX - alignment + 1) {
		goto exhausted;
	}
	offset = (offset + alignment - 1) & ~((uint64_t)alignment - 1);
	if (offset > arena->stats.capacity || span > arena->stats.capacity - offset) {
		goto exhausted;
	}
	memmove(arena->extents + slot + 1, arena->extents + slot, (size_t)(arena->stats.count - slot) * sizeof(Extent));
	arena->extents[slot] = (Extent){offset, bytes, span, alignment};
	if (offset < arena->high_water) {
		++arena->stats.reused;
	}
	if (offset + span > arena->high_water) {
		arena->high_water = offset + span;
	}
	memset(arena->backing + offset + bytes, GUARD_VALUE, GUARD_BYTES);
	++arena->stats.count;
	++arena->stats.allocations;
	arena->stats.live += span;
	if (arena->stats.live > arena->stats.peak) {
		arena->stats.peak = arena->stats.live;
	}
	*out = arena->backing + offset;
	assert(pthread_mutex_unlock(&arena->lock) == 0);
	return ASTRA_CONTEXT17_OK;
exhausted:
	++arena->stats.refusals;
	assert(pthread_mutex_unlock(&arena->lock) == 0);
	return ASTRA_CONTEXT17_EXHAUSTED;
}

static void release(void *opaque, void *pointer, uint64_t bytes, uint32_t alignment) {
	Arena *arena = opaque;
	assert(pthread_mutex_lock(&arena->lock) == 0);
	uint64_t slot = 0;
	while (slot < arena->stats.count && arena->backing + arena->extents[slot].offset != pointer) {
		++slot;
	}
	assert(slot < arena->stats.count && pointer && arena->extents[slot].bytes == bytes && arena->extents[slot].alignment == alignment);
	Extent value = arena->extents[slot];
	assert(arena->stats.live >= value.span);
	for (unsigned i = 0; i < GUARD_BYTES; ++i) {
		assert(((unsigned char *)pointer)[bytes + i] == GUARD_VALUE);
	}
	memset(pointer, 0xa5, (size_t)value.span);
	memmove(arena->extents + slot, arena->extents + slot + 1, (size_t)(arena->stats.count - slot - 1) * sizeof(Extent));
	--arena->stats.count;
	++arena->stats.releases;
	arena->stats.live -= value.span;
	assert(pthread_mutex_unlock(&arena->lock) == 0);
}

static void dispose(void *opaque) {
	Arena *arena = opaque;
	assert(pthread_mutex_lock(&arena->lock) == 0);
	assert(arena->stats.count == 0 && arena->stats.live == 0 && arena->stats.allocations == arena->stats.releases);
	Finished *report = malloc(sizeof(*report));
	assert(report);
	report->stats = arena->stats;
	assert(pthread_mutex_unlock(&arena->lock) == 0 && pthread_mutex_destroy(&arena->lock) == 0);
	free(arena->backing);
	free(arena->extents);
	free(arena);
	assert(pthread_mutex_lock(&report_lock) == 0);
	report->next = finished;
	finished = report;
	assert(pthread_mutex_unlock(&report_lock) == 0);
}

static const AstraContext17Provider contract = {
    ASTRA_CONTEXT17_ABI, sizeof(AstraContext17Provider), ASTRA_CONTEXT17_CONCURRENT, 0, allocate, release, dispose};

AstraContext17 *sequence_custom_allocator(int64_t capacity, int32_t slots, int32_t identity) {
	if (capacity <= 0 || slots <= 0 || (uint64_t)capacity > SIZE_MAX || (uint64_t)slots > SIZE_MAX / sizeof(Extent)) {
		return NULL;
	}
	Arena *arena = calloc(1, sizeof(*arena));
	if (!arena) {
		return NULL;
	}
	arena->extents = calloc((size_t)slots, sizeof(Extent));
	void *backing = NULL;
	if (!arena->extents || posix_memalign(&backing, ARENA_ALIGNMENT, (size_t)capacity) != 0) {
		free(arena->extents);
		free(arena);
		return NULL;
	}
	arena->backing = backing;
	if (pthread_mutex_init(&arena->lock, NULL) != 0) {
		free(backing);
		free(arena->extents);
		free(arena);
		return NULL;
	}
	arena->stats = (Counts){.identity = identity, .capacity = (uint64_t)capacity, .slots = (uint64_t)slots};
	AstraContext17 *context = astra_context17_custom(&contract, arena, (uint64_t)capacity, (uint64_t)slots, ASTRA_CONTEXT17_CONCURRENT);
	if (!context) {
		assert(pthread_mutex_destroy(&arena->lock) == 0);
		free(backing);
		free(arena->extents);
		free(arena);
		return NULL;
	}
	assert(pthread_mutex_lock(&report_lock) == 0);
	++opened;
	assert(pthread_mutex_unlock(&report_lock) == 0);
	return context;
}

int sequence_provider_disposed(int32_t identity) {
	int count = 0;
	assert(pthread_mutex_lock(&report_lock) == 0);
	for (Finished *p = finished; p; p = p->next) {
		if (p->stats.identity == identity) {
			++count;
		}
	}
	assert(pthread_mutex_unlock(&report_lock) == 0);
	return count;
}

int sequence_provider_finish(void) {
	assert(pthread_mutex_lock(&report_lock) == 0);
	uint64_t count = 0;
	printf("{\"arena_contexts\":[");
	while (finished) {
		Finished *report = finished;
		finished = report->next;
		Counts *s = &report->stats;
		assert(s->count == 0 && s->live == 0 && s->allocations == s->releases && s->peak <= s->capacity);
		printf("%s{\"identity\":%d,\"arena_bytes\":%llu,\"slots\":%llu,\"peak_live_bytes\":%llu,\"allocations\":%llu,\"releases\":%llu,\"refusals\":%llu,\"gap_reuses\":%llu}", count ? "," : "", s->identity, (unsigned long long)s->capacity, (unsigned long long)s->slots, (unsigned long long)s->peak, (unsigned long long)s->allocations, (unsigned long long)s->releases, (unsigned long long)s->refusals, (unsigned long long)s->reused);
		++count;
		free(report);
	}
	printf("],\"guard_bytes_per_allocation\":%d,\"opened\":%llu,\"disposed\":%llu}\n", GUARD_BYTES, (unsigned long long)opened, (unsigned long long)count);
	int result = count == opened ? 0 : 1;
	opened = 0;
	assert(pthread_mutex_unlock(&report_lock) == 0);
	return result;
}
