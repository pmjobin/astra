/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "braid-provider.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* A callback's opaque instance owns the complete buddy tree and exact origin
 * ledger. Finished reports are observations, never allocation authority. */
enum { ARENA_ALIGNMENT = 4096, MINIMUM_BLOCK = 64, GUARD_BYTES = 64, GUARD_VALUE = 0xc9 };
enum { FREE, SPLIT, BUSY };
typedef struct Extent {
	uint64_t offset, bytes, rounded, node;
	uint32_t alignment;
	int live;
} Extent;
typedef struct Counts {
	int identity;
	uint64_t capacity, reserved, slots, count, live, peak, physical, physical_peak;
	uint64_t allocations, releases, refusals, reused, splits, coalesces;
} Counts;
typedef struct Arena {
	pthread_mutex_t lock;
	unsigned char *backing, *tree, *seen;
	Extent *extents;
	Counts stats;
} Arena;
typedef struct Finished { Counts stats; struct Finished *next; } Finished;
static pthread_mutex_t report_lock = PTHREAD_MUTEX_INITIALIZER;
static Finished *finished;
static uint64_t opened;

static uint64_t take(Arena *arena, uint64_t node, uint64_t span, uint64_t offset, uint64_t wanted, uint64_t *found)
{
	if (arena->tree[node] == BUSY || span < wanted) { return 0; }
	if (span == wanted) {
		if (arena->tree[node] != FREE) { return 0; }
		arena->tree[node] = BUSY; *found = offset; return node;
	}
	if (arena->tree[node] == FREE) {
		assert(span > MINIMUM_BLOCK);
		assert(arena->tree[node * 2] == FREE && arena->tree[node * 2 + 1] == FREE);
		arena->tree[node] = SPLIT; ++arena->stats.splits;
	}
	uint64_t result = take(arena, node * 2, span / 2, offset, wanted, found);
	if (!result) { result = take(arena, node * 2 + 1, span / 2, offset + span / 2, wanted, found); }
	return result;
}
static int allocate(void *opaque, uint64_t bytes, uint32_t alignment, void **out)
{
	Arena *arena = opaque;
	if (!bytes || !out || !alignment || (alignment & (alignment - 1)) || alignment > ARENA_ALIGNMENT) { return ASTRA_CONTEXT17_INVALID; }
	if (bytes > UINT64_MAX - GUARD_BYTES) { return ASTRA_CONTEXT17_OVERFLOW; }
	uint64_t span = bytes + GUARD_BYTES, rounded = MINIMUM_BLOCK, slot = 0, offset = 0;
	while (rounded < span || rounded < alignment) {
		if (rounded > UINT64_MAX / 2) { return ASTRA_CONTEXT17_OVERFLOW; }
		rounded *= 2;
	}
	assert(pthread_mutex_lock(&arena->lock) == 0);
	if (arena->stats.count == arena->stats.slots || span > arena->stats.capacity - arena->stats.live || rounded > arena->stats.reserved) { goto exhausted; }
	while (slot < arena->stats.slots && arena->extents[slot].live) { ++slot; }
	assert(slot < arena->stats.slots);
	uint64_t node = take(arena, 1, arena->stats.reserved, 0, rounded, &offset);
	if (!node) { goto exhausted; }
	arena->extents[slot] = (Extent){offset, bytes, rounded, node, alignment, 1};
	if (arena->seen[offset / MINIMUM_BLOCK]) { ++arena->stats.reused; }
	memset(arena->seen + offset / MINIMUM_BLOCK, 1, (size_t)(rounded / MINIMUM_BLOCK));
	memset(arena->backing + offset + bytes, GUARD_VALUE, GUARD_BYTES);
	++arena->stats.count; ++arena->stats.allocations; arena->stats.live += span; arena->stats.physical += rounded;
	if (arena->stats.live > arena->stats.peak) { arena->stats.peak = arena->stats.live; }
	if (arena->stats.physical > arena->stats.physical_peak) { arena->stats.physical_peak = arena->stats.physical; }
	assert(arena->stats.physical <= arena->stats.reserved);
	*out = arena->backing + offset; assert(pthread_mutex_unlock(&arena->lock) == 0); return ASTRA_CONTEXT17_OK;
exhausted:
	++arena->stats.refusals; assert(pthread_mutex_unlock(&arena->lock) == 0); return ASTRA_CONTEXT17_EXHAUSTED;
}
static void release(void *opaque, void *pointer, uint64_t bytes, uint32_t alignment)
{
	Arena *arena = opaque; assert(pthread_mutex_lock(&arena->lock) == 0);
	uint64_t slot = 0;
	while (slot < arena->stats.slots && (!arena->extents[slot].live || arena->backing + arena->extents[slot].offset != pointer)) { ++slot; }
	assert(slot < arena->stats.slots && pointer);
	Extent value = arena->extents[slot]; assert(value.bytes == bytes && value.alignment == alignment);
	assert(arena->tree[value.node] == BUSY && arena->stats.live >= bytes + GUARD_BYTES && arena->stats.physical >= value.rounded);
	for (unsigned i = 0; i < GUARD_BYTES; ++i) { assert(((unsigned char *)pointer)[bytes + i] == GUARD_VALUE); }
	memset(pointer, 0xa5, (size_t)value.rounded); arena->extents[slot].live = 0;
	uint64_t node = value.node; arena->tree[node] = FREE;
	while (node > 1) {
		uint64_t parent = node / 2;
		if (arena->tree[parent * 2] != FREE || arena->tree[parent * 2 + 1] != FREE) { break; }
		assert(arena->tree[parent] == SPLIT); arena->tree[parent] = FREE; ++arena->stats.coalesces; node = parent;
	}
	--arena->stats.count; ++arena->stats.releases; arena->stats.live -= bytes + GUARD_BYTES; arena->stats.physical -= value.rounded;
	assert(pthread_mutex_unlock(&arena->lock) == 0);
}
static void dispose(void *opaque)
{
	Arena *arena = opaque; assert(pthread_mutex_lock(&arena->lock) == 0);
	assert(arena->stats.count == 0 && arena->stats.live == 0 && arena->stats.physical == 0 && arena->tree[1] == FREE && arena->stats.allocations == arena->stats.releases);
	Finished *report = malloc(sizeof(*report)); assert(report); report->stats = arena->stats;
	assert(pthread_mutex_unlock(&arena->lock) == 0 && pthread_mutex_destroy(&arena->lock) == 0);
	free(arena->backing); free(arena->tree); free(arena->seen); free(arena->extents); free(arena);
	assert(pthread_mutex_lock(&report_lock) == 0); report->next = finished; finished = report; assert(pthread_mutex_unlock(&report_lock) == 0);
}
static const AstraContext17Provider contract = {
	ASTRA_CONTEXT17_ABI, sizeof(AstraContext17Provider), ASTRA_CONTEXT17_CONCURRENT, 0, allocate, release, dispose
};
AstraContext17 *braid_custom_allocator(int64_t capacity, int32_t slots, int32_t identity)
{
	if (capacity <= 0 || slots <= 0 || (uint64_t)capacity > SIZE_MAX / 2 || (uint64_t)slots > SIZE_MAX / sizeof(Extent)) { return NULL; }
	uint64_t reserved = ARENA_ALIGNMENT;
	while (reserved < (uint64_t)capacity * 2) { if (reserved > SIZE_MAX / 2) { return NULL; } reserved *= 2; }
	uint64_t leaves = reserved / MINIMUM_BLOCK;
	Arena *arena = calloc(1, sizeof(*arena)); if (!arena) { return NULL; }
	arena->extents = calloc((size_t)slots, sizeof(Extent));
	arena->tree = calloc((size_t)leaves * 2, 1); arena->seen = calloc((size_t)leaves, 1);
	void *backing = NULL;
	if (!arena->extents || !arena->tree || !arena->seen || posix_memalign(&backing, ARENA_ALIGNMENT, (size_t)reserved) != 0) { free(arena->extents); free(arena->tree); free(arena->seen); free(arena); return NULL; }
	arena->backing = backing;
	if (pthread_mutex_init(&arena->lock, NULL) != 0) { free(backing); free(arena->extents); free(arena->tree); free(arena->seen); free(arena); return NULL; }
	arena->stats = (Counts){.identity=identity, .capacity=(uint64_t)capacity, .reserved=reserved, .slots=(uint64_t)slots};
	AstraContext17 *context = astra_context17_custom(&contract, arena, (uint64_t)capacity, (uint64_t)slots, ASTRA_CONTEXT17_CONCURRENT);
	if (!context) { assert(pthread_mutex_destroy(&arena->lock) == 0); free(backing); free(arena->extents); free(arena->tree); free(arena->seen); free(arena); return NULL; }
	assert(pthread_mutex_lock(&report_lock) == 0); ++opened; assert(pthread_mutex_unlock(&report_lock) == 0); return context;
}
int braid_provider_disposed(int32_t identity)
{
	int count = 0; assert(pthread_mutex_lock(&report_lock) == 0);
	for (Finished *p = finished; p; p = p->next) { if (p->stats.identity == identity) { ++count; } }
	assert(pthread_mutex_unlock(&report_lock) == 0); return count;
}
int braid_provider_finish(void)
{
	assert(pthread_mutex_lock(&report_lock) == 0); uint64_t count = 0;
	printf("{\"arena_contexts\":[");
	while (finished) {
		Finished *report = finished; finished = report->next; Counts *s = &report->stats;
		assert(s->count == 0 && s->live == 0 && s->physical == 0 && s->allocations == s->releases && s->peak <= s->capacity && s->physical_peak <= s->reserved);
		printf("%s{\"identity\":%d,\"arena_bytes\":%llu,\"buddy_reserved_bytes\":%llu,\"slots\":%llu,\"peak_live_bytes\":%llu,\"peak_reserved_live_bytes\":%llu,\"allocations\":%llu,\"releases\":%llu,\"refusals\":%llu,\"gap_reuses\":%llu,\"buddy_splits\":%llu,\"buddy_coalesces\":%llu}", count ? "," : "", s->identity, (unsigned long long)s->capacity, (unsigned long long)s->reserved, (unsigned long long)s->slots, (unsigned long long)s->peak, (unsigned long long)s->physical_peak, (unsigned long long)s->allocations, (unsigned long long)s->releases, (unsigned long long)s->refusals, (unsigned long long)s->reused, (unsigned long long)s->splits, (unsigned long long)s->coalesces);
		++count; free(report);
	}
	printf("],\"guard_bytes_per_allocation\":%d,\"opened\":%llu,\"disposed\":%llu}\n", GUARD_BYTES, (unsigned long long)opened, (unsigned long long)count);
	int result = count == opened ? 0 : 1; opened = 0; assert(pthread_mutex_unlock(&report_lock) == 0); return result;
}
