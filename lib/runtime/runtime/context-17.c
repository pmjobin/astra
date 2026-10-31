/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "context-17.h"
#include "../async/virtual.h"
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct ContextBlock {
	void *raw;
	AstraContext17Token token;
	uint64_t bytes, raw_bytes;
	uint32_t alignment;
} ContextBlock;
typedef struct ContextHeader {
	AstraContext17 *context;
	AstraContext17Token token;
} ContextHeader;
struct AstraContext17 {
	pthread_mutex_t lock;
	pthread_t home;
	AstraContext17Snapshot stats;
	AstraContext17Provider provider;
	void *provider_state;
	unsigned char *backing;
	ContextBlock *blocks;
	uint64_t capacity, slots, used;
	AstraContext17 *parent;
	AstraContext17Token parent_backing;
	uint32_t ancestry_depth;
};

/* Identity is observational, never a global lookup or allocation authority. */
static _Atomic uint64_t next_instance = 1;

static int alignment_valid(uint32_t alignment) {
	return alignment && alignment <= 4096 && !(alignment & (alignment - 1));
}
static int enter(AstraContext17 *context, int mutate) {
	if (!context) return ASTRA_CONTEXT17_INVALID;
	int status = pthread_mutex_lock(&context->lock);
	if (status == EDEADLK) return ASTRA_CONTEXT17_REENTRY;
	if (status) abort();
	if (mutate && context->stats.threading != ASTRA_CONTEXT17_CONCURRENT &&
	    !pthread_equal(context->home, pthread_self())) {
		pthread_mutex_unlock(&context->lock);
		return ASTRA_CONTEXT17_THREAD;
	}
	return ASTRA_CONTEXT17_OK;
}
static int leave(AstraContext17 *context, int status) {
	if (pthread_mutex_unlock(&context->lock)) abort();
	return status;
}
static void dispose(AstraContext17 *context) {
	if (context->stats.live || context->stats.anchors) abort();
	if (context->stats.kind == ASTRA_CONTEXT17_CUSTOM) context->provider.dispose(context->provider_state);
	AstraContext17 *parent = context->parent;
	AstraContext17Token backing = context->parent_backing;
	if (!parent && !context->stats.borrowed) free(context->backing);
	free(context->blocks);
	if (pthread_mutex_destroy(&context->lock)) abort();
	free(context);
	/* Every child lock and payload obligation is gone before touching its
	 * ancestor. Final parent release can recursively retire owned ancestry. */
	if (parent && astra_context17_release(parent, &backing)) abort();
}
static AstraContext17 *create(uint32_t kind, uint64_t capacity, uint64_t slots, uint32_t threading) {
	if (kind > ASTRA_CONTEXT17_CUSTOM || threading > ASTRA_CONTEXT17_CONCURRENT ||
	    !slots || slots > SIZE_MAX / sizeof(ContextBlock) || capacity > SIZE_MAX ||
	    ((kind == ASTRA_CONTEXT17_REGION || kind == ASTRA_CONTEXT17_POOL) && !capacity)) return NULL;
	AstraContext17 *context = calloc(1, sizeof(*context));
	if (!context) return NULL;
	context->blocks = calloc((size_t)slots, sizeof(ContextBlock));
	if (!context->blocks) {
		free(context);
		return NULL;
	}
	pthread_mutexattr_t attributes;
	if (pthread_mutexattr_init(&attributes) || pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_ERRORCHECK) ||
	    pthread_mutex_init(&context->lock, &attributes) || pthread_mutexattr_destroy(&attributes)) abort();
	uint64_t identity = atomic_load_explicit(&next_instance, memory_order_relaxed);
	for (;;) {
		if (identity == UINT64_MAX) {
			pthread_mutex_destroy(&context->lock);
			free(context->blocks);
			free(context);
			return NULL;
		}
		if (atomic_compare_exchange_weak_explicit(&next_instance, &identity, identity + 1,
		                                          memory_order_relaxed, memory_order_relaxed)) break;
	}
	context->stats.instance = identity;
	context->stats.anchors = 1;
	context->stats.kind = kind;
	context->stats.threading = threading;
	context->capacity = capacity;
	context->slots = slots;
	context->home = pthread_self();
	return context;
}

AstraContext17 *astra_context17_owned(uint32_t kind, uint64_t capacity,
                                      uint64_t slots, uint32_t alignment, uint32_t threading) {
	if (kind >= ASTRA_CONTEXT17_CUSTOM || !alignment_valid(alignment)) return NULL;
	AstraContext17 *context = create(kind, capacity, slots, threading);
	if (!context) return NULL;
	if (kind != ASTRA_CONTEXT17_HEAP) {
		if (alignment < _Alignof(max_align_t)) alignment = _Alignof(max_align_t);
		if (capacity > SIZE_MAX - alignment + 1) {
			astra_context17_drop(context);
			return NULL;
		}
		size_t bytes = ((size_t)capacity + alignment - 1) & ~((size_t)alignment - 1);
		context->backing = aligned_alloc(alignment, bytes);
		if (!context->backing) {
			astra_context17_drop(context);
			return NULL;
		}
	}
	return context;
}
AstraContext17 *astra_context17_borrowed(void *backing, uint64_t capacity,
                                         uint64_t slots, uint32_t kind) {
	if (!backing || (kind != ASTRA_CONTEXT17_REGION && kind != ASTRA_CONTEXT17_POOL) ||
	    capacity > UINTPTR_MAX - (uintptr_t)backing) return NULL;
	AstraContext17 *context = create(kind, capacity, slots, ASTRA_CONTEXT17_AFFINE);
	if (context) {
		context->backing = backing;
		context->stats.borrowed = 1;
	}
	return context;
}
AstraContext17 *astra_context17_custom(const AstraContext17Provider *provider,
                                       void *state, uint64_t capacity, uint64_t slots, uint32_t threading) {
	if (!provider || provider->abi != ASTRA_CONTEXT17_ABI || provider->size != sizeof(*provider) ||
	    provider->reserved || !provider->allocate || !provider->release || !provider->dispose ||
	    provider->threading > ASTRA_CONTEXT17_CONCURRENT || threading > provider->threading) return NULL;
	AstraContext17 *context = create(ASTRA_CONTEXT17_CUSTOM, capacity, slots, threading);
	if (context) {
		context->provider = *provider;
		context->provider_state = state;
	}
	return context;
}
AstraContext17 *astra_context17_nested(AstraContext17 *parent, uint32_t kind,
                                       uint64_t capacity, uint64_t slots, uint32_t alignment) {
	if (!alignment_valid(alignment) || !capacity ||
	    (kind != ASTRA_CONTEXT17_REGION && kind != ASTRA_CONTEXT17_POOL)) return NULL;
	if (enter(parent, 0)) return NULL;
	/* A nested concurrent allocator must not launder scoped/affine backing.
	 * Closed or exhausted parents are rechecked atomically by acquisition. */
	int admitted = !parent->stats.borrowed && parent->stats.threading == ASTRA_CONTEXT17_CONCURRENT && parent->ancestry_depth < 256;
	uint32_t depth = parent->ancestry_depth;
	leave(parent, ASTRA_CONTEXT17_OK);
	if (!admitted) return NULL;
	AstraContext17 *child = create(kind, capacity, slots, ASTRA_CONTEXT17_CONCURRENT);
	if (!child) return NULL;
	AstraContext17Token token;
	if (astra_context17_acquire(parent, 1, capacity, alignment, UINT64_C(0x6173747261637478), &token)) {
		astra_context17_destroy(child);
		return NULL;
	}
	child->parent = parent;
	child->parent_backing = token;
	child->backing = token.pointer;
	child->ancestry_depth = depth + 1;
	return child;
}
int astra_context17_retain(AstraContext17 *context) {
	int status = enter(context, 1);
	if (status) return status;
	if (context->stats.closed || !context->stats.anchors) return leave(context, ASTRA_CONTEXT17_CLOSED);
	if (context->stats.anchors == UINT64_MAX) return leave(context, ASTRA_CONTEXT17_OVERFLOW);
	if (context->stats.borrowed) return leave(context, ASTRA_CONTEXT17_INVALID);
	++context->stats.anchors;
	return leave(context, ASTRA_CONTEXT17_OK);
}
int astra_context17_drop(AstraContext17 *context) {
	int status = enter(context, 1);
	if (status) return status;
	if (!context->stats.anchors) return leave(context, ASTRA_CONTEXT17_ORIGIN);
	/* A scoped caller buffer cannot acquire an implicit escaping backing lease. */
	if (context->stats.borrowed && context->stats.live) return leave(context, ASTRA_CONTEXT17_LIVE);
	if (--context->stats.anchors == 0) context->stats.closed = 1;
	int final = !context->stats.anchors && !context->stats.live;
	leave(context, ASTRA_CONTEXT17_OK);
	if (final) dispose(context);
	return ASTRA_CONTEXT17_OK;
}
int astra_context17_close(AstraContext17 *context) {
	int status = enter(context, 1);
	if (status) return status;
	context->stats.closed = 1;
	return leave(context, context->stats.live ? ASTRA_CONTEXT17_LIVE : ASTRA_CONTEXT17_OK);
}
int astra_context17_reset(AstraContext17 *context) {
	int status = enter(context, 1);
	if (status) return status;
	if (context->stats.live) return leave(context, ASTRA_CONTEXT17_LIVE);
	if (context->stats.closed) return leave(context, ASTRA_CONTEXT17_CLOSED);
	context->used = 0;
	return leave(context, ASTRA_CONTEXT17_OK);
}
int astra_context17_transfer(AstraContext17 *context) {
	int status = enter(context, 0);
	if (status) return status;
	if (context->stats.threading != ASTRA_CONTEXT17_TRANSFER || context->stats.anchors != 1 || context->stats.borrowed)
		return leave(context, ASTRA_CONTEXT17_THREAD);
	/* The compiler must prove unique transfer of the entire live lease graph. */
	context->home = pthread_self();
	return leave(context, ASTRA_CONTEXT17_OK);
}
int astra_context17_snapshot(AstraContext17 *context, AstraContext17Snapshot *out) {
	if (!out) return ASTRA_CONTEXT17_INVALID;
	int status = enter(context, 0);
	if (status) return status;
	*out = context->stats;
	return leave(context, ASTRA_CONTEXT17_OK);
}

int astra_context17_acquire(AstraContext17 *context, uint64_t count,
                            uint64_t extent, uint32_t alignment, uint64_t tag, AstraContext17Token *out) {
	if (!out) return ASTRA_CONTEXT17_INVALID;
	*out = (AstraContext17Token){0};
	int status = enter(context, 1);
	if (status) return status;
	if (context->stats.closed || !context->stats.anchors) return leave(context, ASTRA_CONTEXT17_CLOSED);
	if (!tag) return leave(context, ASTRA_CONTEXT17_INVALID);
	if (!alignment_valid(alignment)) return leave(context, ASTRA_CONTEXT17_ALIGNMENT);
	if (extent && count > UINT64_MAX / extent) return leave(context, ASTRA_CONTEXT17_OVERFLOW);
	uint64_t bytes = count * extent;
	if (!count) return leave(context, ASTRA_CONTEXT17_OK);
	if (!bytes) bytes = 1;
	if (alignment < _Alignof(ContextHeader)) alignment = _Alignof(ContextHeader);
	if (bytes > SIZE_MAX - sizeof(ContextHeader) - alignment + 1 || bytes > UINT64_MAX - context->stats.live_bytes)
		return leave(context, ASTRA_CONTEXT17_OVERFLOW);
	uint64_t total = bytes + sizeof(ContextHeader) + alignment - 1;
	if (total > SIZE_MAX - alignment + 1) return leave(context, ASTRA_CONTEXT17_OVERFLOW);
	total = (total + alignment - 1) & ~((uint64_t)alignment - 1);
	if (total > UINT64_MAX - context->stats.reserved_bytes) return leave(context, ASTRA_CONTEXT17_OVERFLOW);
	if (context->stats.generation == UINT64_MAX || context->stats.allocations == UINT64_MAX) return leave(context, ASTRA_CONTEXT17_GENERATION);
	if (context->stats.live == context->slots) return leave(context, ASTRA_CONTEXT17_EXHAUSTED);
	uint64_t slot = 0;
	while (slot < context->slots && context->blocks[slot].raw)
		++slot;
	if (slot == context->slots) return leave(context, ASTRA_CONTEXT17_EXHAUSTED);
	void *raw = NULL;
	uint64_t next_used = context->used;
	if (context->stats.kind == ASTRA_CONTEXT17_HEAP || context->stats.kind == ASTRA_CONTEXT17_CUSTOM) {
		if (context->capacity && (context->stats.reserved_bytes > context->capacity || total > context->capacity - context->stats.reserved_bytes))
			return leave(context, ASTRA_CONTEXT17_EXHAUSTED);
		if (context->stats.kind == ASTRA_CONTEXT17_HEAP) {
			raw = aligned_alloc(alignment, (size_t)total);
			if (!raw) return leave(context, ASTRA_CONTEXT17_OOM);
		} else {
			status = context->provider.allocate(context->provider_state, total, alignment, &raw);
			if (status) {
				if (raw) abort(); /* A failed callback cannot transfer storage. */
				return leave(context, status == ASTRA_CONTEXT17_EXHAUSTED || status == ASTRA_CONTEXT17_OOM ? status : ASTRA_CONTEXT17_PROVIDER);
			}
			if (!raw) return leave(context, ASTRA_CONTEXT17_PROVIDER);
		}
	} else {
		uint64_t begin = context->stats.kind == ASTRA_CONTEXT17_POOL ? slot * (context->capacity / context->slots) : context->used;
		uint64_t end = context->stats.kind == ASTRA_CONTEXT17_POOL ? (slot + 1) * (context->capacity / context->slots) : context->capacity;
		uintptr_t base = (uintptr_t)context->backing;
		if (begin > UINTPTR_MAX - base || base + begin > UINTPTR_MAX - alignment + 1) return leave(context, ASTRA_CONTEXT17_OVERFLOW);
		uintptr_t aligned = (base + begin + alignment - 1) & ~((uintptr_t)alignment - 1);
		uint64_t offset = aligned - base;
		if (offset > end || total > end - offset) return leave(context, ASTRA_CONTEXT17_EXHAUSTED);
		raw = (void *)aligned;
		next_used = offset + total;
	}
	/* Foreign pointer validity remains a trust obligation; reject observable
	 * alignment/extent/overlap errors before writing any header or payload. */
	uintptr_t address = (uintptr_t)raw;
	if ((address & (alignment - 1)) || total > UINTPTR_MAX - address) {
		if (context->stats.kind == ASTRA_CONTEXT17_HEAP)
			free(raw);
		else if (context->stats.kind == ASTRA_CONTEXT17_CUSTOM)
			context->provider.release(context->provider_state, raw, total, alignment);
		return leave(context, ASTRA_CONTEXT17_ALIGNMENT);
	}
	for (uint64_t i = 0; i < context->slots; ++i) {
		ContextBlock *prior = &context->blocks[i];
		if (prior->raw && address < (uintptr_t)prior->raw + prior->raw_bytes && (uintptr_t)prior->raw < address + total) {
			/* Do not free an alias of a live allocation supplied by a broken provider. */
			return leave(context, ASTRA_CONTEXT17_ORIGIN);
		}
	}
	uintptr_t payload = (address + sizeof(ContextHeader) + alignment - 1) & ~((uintptr_t)alignment - 1);
	AstraContext17Token token = {(void *)payload, context->stats.instance, context->stats.generation + 1, tag, slot};
	ContextHeader *header = (ContextHeader *)(payload - sizeof(ContextHeader));
	header->context = context;
	header->token = token;
	memset((void *)payload, 0, (size_t)bytes);
	context->blocks[slot] = (ContextBlock){raw, token, bytes, total, alignment};
	context->used = next_used;
	++context->stats.live;
	++context->stats.generation;
	++context->stats.allocations;
	context->stats.live_bytes += bytes;
	context->stats.reserved_bytes += total;
	if (context->stats.live_bytes > context->stats.peak_bytes) context->stats.peak_bytes = context->stats.live_bytes;
	*out = token;
	return leave(context, ASTRA_CONTEXT17_OK);
}

int astra_context17_release(AstraContext17 *context, const AstraContext17Token *token) {
	if (!token) return ASTRA_CONTEXT17_INVALID;
	int status = enter(context, 1);
	if (status) return status;
	if (token->instance != context->stats.instance || token->slot >= context->slots) return leave(context, ASTRA_CONTEXT17_ORIGIN);
	ContextBlock *block = &context->blocks[token->slot];
	if (!block->raw || block->token.pointer != token->pointer || block->token.tag != token->tag) return leave(context, ASTRA_CONTEXT17_ORIGIN);
	if (block->token.generation != token->generation) return leave(context, ASTRA_CONTEXT17_GENERATION);
	if (context->stats.releases == UINT64_MAX) return leave(context, ASTRA_CONTEXT17_OVERFLOW);
	if (context->stats.kind == ASTRA_CONTEXT17_HEAP)
		free(block->raw);
	else if (context->stats.kind == ASTRA_CONTEXT17_CUSTOM)
		context->provider.release(context->provider_state, block->raw, block->raw_bytes, block->alignment);
	context->stats.live_bytes -= block->bytes;
	context->stats.reserved_bytes -= block->raw_bytes;
	--context->stats.live;
	++context->stats.releases;
	memset(block, 0, sizeof(*block));
	if (!context->stats.live) context->used = 0;
	int final = !context->stats.live && !context->stats.anchors;
	leave(context, ASTRA_CONTEXT17_OK);
	if (final) dispose(context);
	return ASTRA_CONTEXT17_OK;
}
void *astra_context17_allocate(AstraContext17 *context, uint64_t count,
                               uint64_t extent, uint32_t alignment, uint64_t tag) {
	AstraContext17Token token;
	return astra_context17_acquire(context, count, extent, alignment, tag, &token) ? NULL : token.pointer;
}
int astra_context17_release_origin(void *pointer, uint64_t tag) {
	if (!pointer) return ASTRA_CONTEXT17_OK;
	ContextHeader *header = (ContextHeader *)((unsigned char *)pointer - sizeof(ContextHeader));
	if (header->token.pointer != pointer || header->token.tag != tag) return ASTRA_CONTEXT17_ORIGIN;
	return astra_context17_release(header->context, &header->token);
}
void *astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                    uint64_t extent, uint32_t alignment, uint64_t tag, uint32_t mode) {
	AstraContext17Snapshot state;
	if (astra_context17_snapshot(context, &state) || mode > 3 ||
	    (mode == 3 ? !state.borrowed || state.threading != ASTRA_CONTEXT17_AFFINE : state.borrowed || state.threading != mode)) return NULL;
	return astra_context17_allocate(context, count, extent, alignment, tag);
}
int astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	return astra_context17_release_origin(pointer, tag) == ASTRA_CONTEXT17_OK;
}
AstraContext17 *astra_context17_origin(void *pointer, uint64_t tag) {
	if (!pointer) return NULL;
	ContextHeader *header = (ContextHeader *)((unsigned char *)pointer - sizeof(ContextHeader));
	AstraContext17Token token = header->token;
	AstraContext17 *context = header->context;
	if (token.pointer != pointer || token.tag != tag || enter(context, 0)) return NULL;
	int valid = token.instance == context->stats.instance && token.slot < context->slots;
	if (valid) {
		ContextBlock *block = &context->blocks[token.slot];
		valid = block->raw && block->token.pointer == pointer && block->token.tag == tag && block->token.generation == token.generation;
	}
	leave(context, ASTRA_CONTEXT17_OK);
	/* Caller retains the owner allocation throughout this noescape borrow. */
	return valid ? context : NULL;
}
void astra_context17_destroy(AstraContext17 *context) {
	if (context && astra_context17_drop(context) != ASTRA_CONTEXT17_OK) abort();
}
static AstraContext17 *open_mode(int32_t kind, int64_t capacity, int32_t slots, int32_t alignment, uint32_t threading) {
	if (kind < 0 || capacity < 0 || slots <= 0 || alignment <= 0) return NULL;
	return astra_context17_owned((uint32_t)kind, (uint64_t)capacity, (uint64_t)slots, (uint32_t)alignment, threading);
}
AstraContext17 *astra_context17_open_concurrent(int32_t kind, int64_t capacity, int32_t slots, int32_t alignment) {
	return open_mode(kind, capacity, slots, alignment, ASTRA_CONTEXT17_CONCURRENT);
}
AstraContext17 *astra_context17_open_affine(int32_t kind, int64_t capacity, int32_t slots, int32_t alignment) {
	return open_mode(kind, capacity, slots, alignment, ASTRA_CONTEXT17_AFFINE);
}
AstraContext17 *astra_context17_open_transfer(int32_t kind, int64_t capacity, int32_t slots, int32_t alignment) {
	return open_mode(kind, capacity, slots, alignment, ASTRA_CONTEXT17_TRANSFER);
}
AstraContext17 *astra_context17_open_scoped(void *backing, int32_t capacity, int32_t kind, int32_t slots) {
	if (capacity <= 0 || kind < 0 || slots <= 0) return NULL;
	return astra_context17_borrowed(backing, (uint64_t)capacity, (uint64_t)slots, (uint32_t)kind);
}
AstraContext17 *astra_context17_open_nested(AstraContext17 *parent, int32_t kind, int64_t capacity, int32_t slots, int32_t alignment) {
	if (kind < 0 || capacity <= 0 || slots <= 0 || alignment <= 0) return NULL;
	return astra_context17_nested(parent, (uint32_t)kind, (uint64_t)capacity, (uint64_t)slots, (uint32_t)alignment);
}
int64_t astra_context17_query(AstraContext17 *context, int32_t query) {
	AstraContext17Snapshot state;
	if (astra_context17_snapshot(context, &state)) return -1;
	uint64_t result;
	switch (query) {
	case 0:
		result = state.instance;
		break;
	case 1:
		result = state.live;
		break;
	case 2:
		result = state.live_bytes;
		break;
	case 3:
		result = state.peak_bytes;
		break;
	case 4:
		result = state.allocations;
		break;
	case 5:
		result = state.releases;
		break;
	default:
		return -1;
	}
	return result <= INT64_MAX ? (int64_t)result : -1;
}
int64_t astra_context17_query_affine(AstraContext17 *context, int32_t query) {
	return astra_context17_query(context, query);
}
int64_t astra_context17_query_scoped(AstraContext17 *context, int32_t query) {
	if (query < 6) return astra_context17_query(context, query);
	AstraContext17Snapshot state;
	if (astra_context17_snapshot(context, &state)) return -1;
	if (query == 6) return state.reserved_bytes <= INT64_MAX ? (int64_t)state.reserved_bytes : -1;
	if (query == 7) return state.borrowed;
	if (query == 8) return state.threading;
	return -1;
}

/* One explicit lease is the actual frame allocation. The public task core
 * depends only on the descriptor protocol, never on this optional provider. */
#define FRAME_TAG UINT64_C(0x6173747261667231)
static void *frame_affine(void *context, size_t size, size_t alignment) {
	return astra_context17_allocate_mode(context, 1, size, (uint32_t)alignment, FRAME_TAG, ASTRA_CONTEXT17_AFFINE);
}
static void *frame_transfer(void *context, size_t size, size_t alignment) {
	return astra_context17_allocate_mode(context, 1, size, (uint32_t)alignment, FRAME_TAG, ASTRA_CONTEXT17_TRANSFER);
}
static void *frame_concurrent(void *context, size_t size, size_t alignment) {
	return astra_context17_allocate_mode(context, 1, size, (uint32_t)alignment, FRAME_TAG, ASTRA_CONTEXT17_CONCURRENT);
}
static void *frame_scoped(void *context, size_t size, size_t alignment) {
	return astra_context17_allocate_mode(context, 1, size, (uint32_t)alignment, FRAME_TAG, 3);
}
static void frame_release(void *context, void *pointer) {
	if (astra_context17_origin(pointer, FRAME_TAG) != context || astra_context17_release_origin(pointer, FRAME_TAG)) abort();
}
const AstraAsyncFrameAllocator *astra_context17_frame_descriptor(uint32_t mode) {
	static const AstraAsyncFrameAllocator descriptors[] = {
	    {ASTRA_ASYNC_TASK_ABI, sizeof(AstraAsyncFrameAllocator), ASTRA_CONTEXT17_AFFINE, 0, frame_affine, frame_release},
	    {ASTRA_ASYNC_TASK_ABI, sizeof(AstraAsyncFrameAllocator), ASTRA_CONTEXT17_TRANSFER, 0, frame_transfer, frame_release},
	    {ASTRA_ASYNC_TASK_ABI, sizeof(AstraAsyncFrameAllocator), ASTRA_CONTEXT17_CONCURRENT, 0, frame_concurrent, frame_release},
	    /* Caller-backed frames have affine execution and no escaping backing lease. */
	    {ASTRA_ASYNC_TASK_ABI, sizeof(AstraAsyncFrameAllocator), ASTRA_CONTEXT17_AFFINE, 0, frame_scoped, frame_release}};
	return mode < sizeof(descriptors) / sizeof(descriptors[0]) ? &descriptors[mode] : NULL;
}
