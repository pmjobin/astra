/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_ALLOCATION_12_H
#define ASTRA_ALLOCATION_12_H
#include <stdint.h>
#include <stddef.h>

enum AstraAlloc12Kind {
	ASTRA_ALLOC12_HEAP,
	ASTRA_ALLOC12_REGION,
	ASTRA_ALLOC12_POOL,
	ASTRA_ALLOC12_STATIC,
	ASTRA_ALLOC12_CUSTOM
};
enum AstraAlloc12Error {
	ASTRA_ALLOC12_OK,
	ASTRA_ALLOC12_INVALID,
	ASTRA_ALLOC12_EXHAUSTED,
	ASTRA_ALLOC12_OVERFLOW,
	ASTRA_ALLOC12_ALIGNMENT,
	ASTRA_ALLOC12_ORIGIN,
	ASTRA_ALLOC12_LIVE,
	ASTRA_ALLOC12_REENTRY,
	ASTRA_ALLOC12_GENERATION,
	ASTRA_ALLOC12_OOM
};
typedef struct AstraAlloc12Block {
	uint64_t offset, bytes, generation, tag;
	uint32_t live;
} AstraAlloc12Block;
typedef int32_t (*AstraAlloc12Placement)(int32_t, int32_t, int32_t, int32_t);
typedef void (*AstraAlloc12Released)(int32_t, int32_t);
typedef void *(*AstraAlloc12HeapAllocate)(uint64_t, uint32_t);
typedef void (*AstraAlloc12HeapRelease)(void *);
typedef struct AstraAlloc12Domain {
	unsigned char *backing;
	AstraAlloc12Block *blocks;
	uint64_t capacity, block_capacity, used, live, generation;
	uint64_t allocations, releases, peak_live, peak_used;
	uint32_t kind, busy, error;
	AstraAlloc12Placement placement;
	AstraAlloc12Released released;
	AstraAlloc12HeapAllocate heap_allocate;
	AstraAlloc12HeapRelease heap_release;
	void *heap_head;
} AstraAlloc12Domain;

/* Compiler-internal ABI. Source cannot declare these reserved symbols. */
void *astra_alloc12_allocate(AstraAlloc12Domain *, uint64_t, uint64_t, uint32_t, uint64_t);
int32_t astra_alloc12_release(AstraAlloc12Domain *, void *, uint64_t, uint64_t);
int32_t astra_alloc12_reset(AstraAlloc12Domain *);
uint64_t astra_alloc12_token(AstraAlloc12Domain *, void *, uint64_t);
int32_t astra_alloc12_query(AstraAlloc12Domain *, int32_t);
void *astra_alloc12_heap_allocate(uint64_t, uint32_t);
void astra_alloc12_heap_release(void *);
#endif
