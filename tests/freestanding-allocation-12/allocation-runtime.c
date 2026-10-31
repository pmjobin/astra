/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Substrate probe only; Astra owner/application qualification is separate. */
#include "../../lib/runtime/runtime/allocation-12.h"
#include <assert.h>
#include <stdio.h>

static _Alignas(4096) unsigned char region_bytes[4096], pool_bytes[1024];
static _Alignas(4096) unsigned char custom_bytes[4096], static_bytes[128];
static AstraAlloc12Block region_blocks[16], pool_blocks[4], custom_blocks[8], static_blocks[1];
static AstraAlloc12Domain region = {.backing = region_bytes, .blocks = region_blocks, .capacity = 4096, .block_capacity = 16, .kind = ASTRA_ALLOC12_REGION};
static AstraAlloc12Domain pool = {.backing = pool_bytes, .blocks = pool_blocks, .capacity = 1024, .block_capacity = 4, .kind = ASTRA_ALLOC12_POOL};
static AstraAlloc12Domain one = {.backing = static_bytes, .blocks = static_blocks, .capacity = 128, .block_capacity = 1, .kind = ASTRA_ALLOC12_STATIC};
static AstraAlloc12Domain heap = {.kind = ASTRA_ALLOC12_HEAP,
                                  .heap_allocate = astra_alloc12_heap_allocate,
                                  .heap_release = astra_alloc12_heap_release};
static AstraAlloc12Domain custom;
static int mode, notifications;

static int32_t place(int32_t bytes, int32_t align, int32_t proposed, int32_t capacity) {
	assert(bytes > 0 && align > 0 && capacity == 4096);
	if (mode == 1) {
		return 1;
	}
	if (mode == 2) {
		return capacity;
	}
	if (mode == 3) {
		return 0;
	}
	if (mode == 4) {
		assert(!astra_alloc12_allocate(&custom, 1, 8, 8, 9));
		assert(custom.error == ASTRA_ALLOC12_REENTRY);
	}
	return proposed;
}
static void returned(int32_t offset, int32_t bytes) {
	assert(offset >= 0 && bytes > 0);
	++notifications;
}
static void aligned_zero(void *pointer, uint64_t bytes, uint32_t alignment) {
	assert(pointer && (uintptr_t)pointer % alignment == 0);
	for (uint64_t i = 0; i < bytes; ++i) {
		assert(((unsigned char *)pointer)[i] == 0);
	}
}
static void release(AstraAlloc12Domain *domain, void *pointer, uint64_t tag) {
	uint64_t token = astra_alloc12_token(domain, pointer, tag);
	assert(token && astra_alloc12_release(domain, pointer, tag, token));
}
static void region_probe(void) {
	unsigned char *first = astra_alloc12_allocate(&region, 1, 24, 64, 11);
	unsigned char *second = astra_alloc12_allocate(&region, 2, 40, 16, 12);
	aligned_zero(first, 24, 64);
	aligned_zero(second, 80, 16);
	first[0] = 42;
	assert(!astra_alloc12_reset(&region) && region.error == ASTRA_ALLOC12_LIVE);
	assert(first[0] == 42 && region.live == 2);
	assert(!astra_alloc12_allocate(&region, UINT64_MAX, 2, 8, 13));
	assert(region.error == ASTRA_ALLOC12_OVERFLOW && region.live == 2);
	assert(!astra_alloc12_allocate(&region, 1, 8, 3, 13));
	assert(region.error == ASTRA_ALLOC12_ALIGNMENT && region.live == 2);
	assert(!astra_alloc12_release(&pool, first, 11, 0));
	assert(!astra_alloc12_release(&region, first, 12, 0));
	uint64_t old = astra_alloc12_token(&region, first, 11);
	release(&region, first, 11);
	release(&region, second, 12);
	unsigned char *again = astra_alloc12_allocate(&region, 1, 24, 64, 11);
	assert(again == first);
	aligned_zero(again, 24, 64);
	assert(!astra_alloc12_release(&region, again, 11, old) && region.live == 1);
	release(&region, again, 11);
	void *values[16];
	for (uint64_t i = 0; i < 16; ++i) {
		uint32_t alignment = 1U << (i % 7);
		values[i] = astra_alloc12_allocate(&region, 1, 9 + i, alignment, 100 + i);
		aligned_zero(values[i], 9 + i, alignment);
	}
	assert(!astra_alloc12_allocate(&region, 1, 1, 1, 999));
	assert(region.live == 16 && region.error == ASTRA_ALLOC12_EXHAUSTED);
	for (uint64_t i = 16; i > 0; --i) {
		release(&region, values[i - 1], 100 + i - 1);
	}
	assert(astra_alloc12_reset(&region) && !region.used && !region.live);
	assert(region.allocations == region.releases && region.peak_live == 16);
}
static void pool_probe(void) {
	void *values[4];
	for (uint64_t i = 0; i < 4; ++i) {
		values[i] = astra_alloc12_allocate(&pool, 1, 65 + i, 64, 20 + i);
		aligned_zero(values[i], 65 + i, 64);
	}
	assert(!astra_alloc12_allocate(&pool, 1, 8, 8, 99));
	uint64_t old = astra_alloc12_token(&pool, values[1], 21);
	release(&pool, values[1], 21);
	void *again = astra_alloc12_allocate(&pool, 1, 66, 64, 21);
	assert(again == values[1]);
	assert(!astra_alloc12_release(&pool, again, 21, old));
	for (uint64_t i = 0; i < 4; ++i) {
		release(&pool, values[i], 20 + i);
	}
	assert(!astra_alloc12_release(&pool, again, 21, 0));
	pool.generation = UINT64_MAX;
	assert(!astra_alloc12_allocate(&pool, 1, 8, 8, 20));
	assert(pool.error == ASTRA_ALLOC12_GENERATION && !pool.live);
}
static void custom_probe(void) {
	custom = (AstraAlloc12Domain){.backing = custom_bytes, .blocks = custom_blocks, .capacity = 4096, .block_capacity = 8, .kind = ASTRA_ALLOC12_CUSTOM, .placement = place, .released = returned};
	void *first = astra_alloc12_allocate(&custom, 1, 32, 64, 31);
	aligned_zero(first, 32, 64);
	for (mode = 1; mode <= 4; ++mode) {
		assert(!astra_alloc12_allocate(&custom, 1, 32, 64, 32));
		assert(custom.live == 1 && custom.allocations == 1 && !custom.busy);
	}
	mode = 0;
	void *second = astra_alloc12_allocate(&custom, 1, 32, 64, 32);
	assert(second && second != first);
	release(&custom, second, 32);
	release(&custom, first, 31);
	assert(notifications == 2 && custom.releases == 2 && !custom.live);
}
static void heap_and_static_probe(void) {
	void *first = astra_alloc12_allocate(&heap, 1, 17, 4096, 41);
	void *second = astra_alloc12_allocate(&heap, 1, 33, 64, 42);
	aligned_zero(first, 17, 4096);
	aligned_zero(second, 33, 64);
	assert(!astra_alloc12_release(&heap, first, 42, 0));
	release(&heap, first, 41);
	release(&heap, second, 42);
	assert(!heap.live && !heap.used && !heap.heap_head);
	void *zero = astra_alloc12_allocate(&one, 1, 0, 64, 51);
	aligned_zero(zero, 1, 64);
	assert(!astra_alloc12_allocate(&one, 1, 1, 64, 52));
	release(&one, zero, 51);
	assert(!astra_alloc12_allocate(&one, 0, 1, 64, 52));
	assert(one.allocations == 1 && one.releases == 1);
	assert(astra_alloc12_query(&one, 2) == 1 && astra_alloc12_query(&one, 100) == -1);
}
int main(void) {
	region_probe();
	pool_probe();
	custom_probe();
	heap_and_static_probe();
	puts("allocator substrate: region,pool,custom,heap,static; align,overflow,origin,generation,reentry: OK");
	return 0;
}
