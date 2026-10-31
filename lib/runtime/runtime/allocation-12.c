/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Small explicit allocation substrate. It never initializes/destroys an Astra
 * value, acquires ownership, throws, unwinds or selects a process-wide heap. */
#include "allocation-12.h"

typedef struct HeapNode {
	struct HeapNode *next;
	void *payload;
	uint64_t bytes, generation, tag;
} HeapNode;

_Static_assert(sizeof(void *) == 8, "selected allocation ABI requires 64-bit addresses");
_Static_assert(sizeof(AstraAlloc12Block) == 40, "allocation block ABI");
_Static_assert(_Alignof(AstraAlloc12Block) == 8, "allocation block alignment");
_Static_assert(sizeof(AstraAlloc12Domain) == 144, "allocation domain ABI");
_Static_assert(offsetof(AstraAlloc12Domain, kind) == 88, "allocation domain kind offset");
_Static_assert(offsetof(AstraAlloc12Domain, placement) == 104, "allocation callback offset");

static int enter(AstraAlloc12Domain *domain) {
	if (!domain) {
		return 0;
	}
	if (domain->busy) {
		domain->error = ASTRA_ALLOC12_REENTRY;
		return 0;
	}
	domain->busy = 1;
	domain->error = ASTRA_ALLOC12_OK;
	return 1;
}
static void *failure(AstraAlloc12Domain *domain, uint32_t error) {
	domain->error = error;
	domain->busy = 0;
	return NULL;
}
static void zero_bytes(void *pointer, uint64_t bytes) {
	/* Volatile here prevents a hidden libc memset dependency in this runtime. */
	volatile unsigned char *target = pointer;
	for (uint64_t i = 0; i < bytes; ++i) {
		target[i] = 0;
	}
}
static int valid_alignment(uint32_t alignment) {
	return alignment && alignment <= 4096 && !(alignment & (alignment - 1));
}
static int admit_counters(AstraAlloc12Domain *domain) {
	return domain->generation != UINT64_MAX && domain->allocations != UINT64_MAX && domain->live != UINT64_MAX;
}
static void publish(AstraAlloc12Domain *domain, uint64_t end) {
	++domain->generation;
	++domain->allocations;
	++domain->live;
	if (end > domain->used) {
		domain->used = end;
	}
	if (domain->live > domain->peak_live) {
		domain->peak_live = domain->live;
	}
	if (domain->used > domain->peak_used) {
		domain->peak_used = domain->used;
	}
	domain->busy = 0;
}
void *astra_alloc12_allocate(AstraAlloc12Domain *domain, uint64_t count,
                             uint64_t extent, uint32_t alignment, uint64_t tag) {
	if (!enter(domain)) {
		return NULL;
	}
	if (!valid_alignment(alignment)) {
		return failure(domain, ASTRA_ALLOC12_ALIGNMENT);
	}
	if (!tag || domain->kind > ASTRA_ALLOC12_CUSTOM) {
		return failure(domain, ASTRA_ALLOC12_INVALID);
	}
	if (!count) {
		domain->busy = 0;
		return NULL;
	}
	if (extent && count > UINT64_MAX / extent) {
		return failure(domain, ASTRA_ALLOC12_OVERFLOW);
	}
	uint64_t bytes = count * extent;
	/* A nonempty zero-size value still gets a unique live aligned allocation. */
	if (!bytes) {
		bytes = 1;
	}
	if (!admit_counters(domain)) {
		return failure(domain, ASTRA_ALLOC12_GENERATION);
	}
	if (domain->kind == ASTRA_ALLOC12_HEAP) {
		if (!domain->heap_allocate || !domain->heap_release || bytes > UINT64_MAX - sizeof(HeapNode) - alignment || bytes > UINT64_MAX - domain->used) {
			return failure(domain, ASTRA_ALLOC12_OVERFLOW);
		}
		uint64_t total = bytes + sizeof(HeapNode) + alignment;
		uint32_t heap_alignment = alignment < _Alignof(HeapNode) ? _Alignof(HeapNode) : alignment;
		HeapNode *node = domain->heap_allocate(total, heap_alignment);
		if (!node) {
			return failure(domain, ASTRA_ALLOC12_OOM);
		}
		uintptr_t address = (uintptr_t)(node + 1);
		if (address > UINTPTR_MAX - alignment + 1) {
			domain->heap_release(node);
			return failure(domain, ASTRA_ALLOC12_OVERFLOW);
		}
		address = (address + alignment - 1) & ~((uintptr_t)alignment - 1);
		zero_bytes((void *)address, bytes);
		node->payload = (void *)address;
		node->bytes = bytes;
		node->generation = domain->generation + 1;
		node->tag = tag;
		node->next = domain->heap_head;
		domain->heap_head = node;
		publish(domain, domain->used + bytes);
		return (void *)address;
	}
	if (!domain->backing || !domain->blocks || !domain->capacity || domain->capacity > 16777216 || !domain->block_capacity || domain->block_capacity > 4096 || domain->block_capacity > domain->capacity || domain->live >= domain->block_capacity) {
		return failure(domain, ASTRA_ALLOC12_EXHAUSTED);
	}
	uint64_t slot = 0;
	while (slot < domain->block_capacity && domain->blocks[slot].live) {
		++slot;
	}
	if (slot == domain->block_capacity) {
		return failure(domain, ASTRA_ALLOC12_EXHAUSTED);
	}
	uint64_t offset;
	if (domain->kind == ASTRA_ALLOC12_POOL || domain->kind == ASTRA_ALLOC12_STATIC) {
		if (domain->capacity % domain->block_capacity) {
			return failure(domain, ASTRA_ALLOC12_INVALID);
		}
		uint64_t stride = domain->capacity / domain->block_capacity;
		if (bytes > stride || stride % alignment) {
			return failure(domain, ASTRA_ALLOC12_EXHAUSTED);
		}
		offset = slot * stride;
	} else {
		if (domain->used > domain->capacity || domain->used > UINT64_MAX - alignment + 1) {
			return failure(domain, ASTRA_ALLOC12_OVERFLOW);
		}
		offset = (domain->used + alignment - 1) & ~((uint64_t)alignment - 1);
	}
	if (domain->kind == ASTRA_ALLOC12_CUSTOM) {
		if (!domain->placement || !domain->released || bytes > INT32_MAX) {
			return failure(domain, ASTRA_ALLOC12_INVALID);
		}
		int32_t proposed = domain->placement((int32_t)bytes, (int32_t)alignment,
		                                     (int32_t)offset, (int32_t)domain->capacity);
		if (domain->error != ASTRA_ALLOC12_OK) {
			return failure(domain, domain->error);
		}
		if (proposed < 0) {
			return failure(domain, ASTRA_ALLOC12_EXHAUSTED);
		}
		offset = (uint64_t)proposed;
	}
	if (offset > domain->capacity || bytes > domain->capacity - offset) {
		return failure(domain, ASTRA_ALLOC12_EXHAUSTED);
	}
	uintptr_t address = (uintptr_t)domain->backing;
	if (address > UINTPTR_MAX - offset || ((address + offset) & (alignment - 1))) {
		return failure(domain, ASTRA_ALLOC12_ALIGNMENT);
	}
	for (uint64_t i = 0; i < domain->block_capacity; ++i) {
		AstraAlloc12Block *other = &domain->blocks[i];
		if (other->live && (other->offset > domain->capacity || other->bytes > domain->capacity - other->offset || (offset < other->offset + other->bytes && other->offset < offset + bytes))) {
			return failure(domain, ASTRA_ALLOC12_ORIGIN);
		}
	}
	zero_bytes((void *)(address + offset), bytes);
	AstraAlloc12Block *block = &domain->blocks[slot];
	block->offset = offset;
	block->bytes = bytes;
	block->generation = domain->generation + 1;
	block->tag = tag;
	block->live = 1;
	publish(domain, offset + bytes);
	return (void *)(address + offset);
}

int32_t astra_alloc12_release(AstraAlloc12Domain *domain, void *pointer,
                              uint64_t tag, uint64_t expected_generation) {
	if (!enter(domain)) {
		return 0;
	}
	if (!pointer) {
		domain->busy = 0;
		return 1;
	}
	if (!domain->live || domain->releases == UINT64_MAX) {
		failure(domain, ASTRA_ALLOC12_ORIGIN);
		return 0;
	}
	if (domain->kind == ASTRA_ALLOC12_HEAP) {
		HeapNode *head = domain->heap_head;
		HeapNode **previous = &head;
		while (*previous && (*previous)->payload != pointer) {
			previous = &(*previous)->next;
		}
		HeapNode *node = *previous;
		if (!node || node->tag != tag) {
			failure(domain, ASTRA_ALLOC12_ORIGIN);
			return 0;
		}
		if (expected_generation && expected_generation != node->generation) {
			failure(domain, ASTRA_ALLOC12_GENERATION);
			return 0;
		}
		if (!domain->heap_release || node->bytes > domain->used) {
			failure(domain, ASTRA_ALLOC12_INVALID);
			return 0;
		}
		*previous = node->next;
		domain->heap_head = head;
		domain->used -= node->bytes;
		domain->heap_release(node);
	} else {
		uintptr_t address = (uintptr_t)pointer;
		uintptr_t base = (uintptr_t)domain->backing;
		if (!base || address < base || address - base >= domain->capacity) {
			failure(domain, ASTRA_ALLOC12_ORIGIN);
			return 0;
		}
		uint64_t offset = address - base;
		AstraAlloc12Block *block = NULL;
		for (uint64_t i = 0; i < domain->block_capacity; ++i) {
			if (domain->blocks[i].live && domain->blocks[i].offset == offset) {
				block = &domain->blocks[i];
				break;
			}
		}
		if (!block || block->tag != tag) {
			failure(domain, ASTRA_ALLOC12_ORIGIN);
			return 0;
		}
		if (expected_generation && expected_generation != block->generation) {
			failure(domain, ASTRA_ALLOC12_GENERATION);
			return 0;
		}
		if (domain->kind == ASTRA_ALLOC12_CUSTOM) {
			if (!domain->released) {
				failure(domain, ASTRA_ALLOC12_INVALID);
				return 0;
			}
			domain->released((int32_t)offset, (int32_t)block->bytes);
			if (domain->error != ASTRA_ALLOC12_OK) {
				failure(domain, domain->error);
				return 0;
			}
		}
		block->live = 0;
	}
	--domain->live;
	++domain->releases;
	if (!domain->live) {
		domain->used = 0;
	}
	domain->busy = 0;
	return 1;
}

int32_t astra_alloc12_reset(AstraAlloc12Domain *domain) {
	if (!enter(domain)) {
		return 0;
	}
	if (domain->live) {
		failure(domain, ASTRA_ALLOC12_LIVE);
		return 0;
	}
	domain->used = 0;
	/* Generations and cumulative counters are never reset or recycled. */
	domain->busy = 0;
	return 1;
}
uint64_t astra_alloc12_token(AstraAlloc12Domain *domain, void *pointer, uint64_t tag) {
	if (!domain || !pointer || domain->busy) {
		return 0;
	}
	if (domain->kind == ASTRA_ALLOC12_HEAP) {
		for (HeapNode *node = domain->heap_head; node; node = node->next) {
			if (node->payload == pointer && node->tag == tag) {
				return node->generation;
			}
		}
		return 0;
	}
	uintptr_t address = (uintptr_t)pointer, base = (uintptr_t)domain->backing;
	if (address < base || address - base >= domain->capacity) {
		return 0;
	}
	for (uint64_t i = 0; i < domain->block_capacity; ++i) {
		AstraAlloc12Block *block = &domain->blocks[i];
		if (block->live && block->offset == address - base && block->tag == tag) {
			return block->generation;
		}
	}
	return 0;
}
int32_t astra_alloc12_query(AstraAlloc12Domain *domain, int32_t query) {
	if (!domain) {
		return -1;
	}
	uint64_t value;
	switch (query) {
	case 0:
		value = domain->live;
		break;
	case 1:
		value = domain->used;
		break;
	case 2:
		value = domain->allocations;
		break;
	case 3:
		value = domain->releases;
		break;
	case 4:
		value = domain->error;
		break;
	case 5:
		value = domain->peak_live;
		break;
	case 6:
		value = domain->peak_used;
		break;
	default:
		return -1;
	}
	return value <= INT32_MAX ? (int32_t)value : -1;
}
