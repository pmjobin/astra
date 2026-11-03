/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_CONTEXT_17_H
#define ASTRA_CONTEXT_17_H
#include <stddef.h>
#include <stdint.h>

#define ASTRA_CONTEXT17_ABI 1u
typedef struct AstraContext17 AstraContext17;

enum AstraContext17Kind { ASTRA_CONTEXT17_HEAP,
	                      ASTRA_CONTEXT17_REGION,
	                      ASTRA_CONTEXT17_POOL,
	                      ASTRA_CONTEXT17_CUSTOM };

enum AstraContext17Threading { ASTRA_CONTEXT17_AFFINE,
	                           ASTRA_CONTEXT17_TRANSFER,
	                           ASTRA_CONTEXT17_CONCURRENT };

enum AstraContext17Status {
	ASTRA_CONTEXT17_OK,
	ASTRA_CONTEXT17_INVALID,
	ASTRA_CONTEXT17_EXHAUSTED,
	ASTRA_CONTEXT17_OVERFLOW,
	ASTRA_CONTEXT17_ALIGNMENT,
	ASTRA_CONTEXT17_ORIGIN,
	ASTRA_CONTEXT17_LIVE,
	ASTRA_CONTEXT17_REENTRY,
	ASTRA_CONTEXT17_GENERATION,
	ASTRA_CONTEXT17_OOM,
	ASTRA_CONTEXT17_THREAD,
	ASTRA_CONTEXT17_CLOSED,
	ASTRA_CONTEXT17_PROVIDER
};

/* Foreign provider trust: callbacks must supply valid nonoverlapping storage,
 * honor threading, never unwind and never reenter this context's mutation.
 * On successful construction the context owns state until dispose(state).
 * Descriptor/code lifetime must span the context; callbacks are copied here. */
typedef struct AstraContext17Provider {
	uint32_t abi, size, threading, reserved;
	int (*allocate)(void *state, uint64_t bytes, uint32_t alignment, void **out);
	void (*release)(void *state, void *pointer, uint64_t bytes, uint32_t alignment);
	void (*dispose)(void *state);
} AstraContext17Provider;

typedef struct AstraContext17Token {
	void *pointer;
	uint64_t instance, generation, tag, slot;
} AstraContext17Token;

typedef struct AstraContext17Snapshot {
	uint64_t instance, anchors, live, live_bytes, peak_bytes;
	uint64_t allocations, releases, generation, reserved_bytes;
	uint32_t kind, threading, closed, borrowed;
} AstraContext17Snapshot;

/* Hosted, opt-in state. The finite slot budget is a runtime value. Heap/custom
 * capacity zero means explicitly unbounded bytes, never fallback after failure. */
AstraContext17 *astra_context17_owned(uint32_t kind, uint64_t capacity,
                                      uint64_t slots, uint32_t alignment, uint32_t threading);
AstraContext17 *astra_context17_borrowed(void *backing, uint64_t capacity,
                                         uint64_t slots, uint32_t kind);
AstraContext17 *astra_context17_custom(const AstraContext17Provider *, void *state,
                                       uint64_t capacity, uint64_t slots, uint32_t threading);
/* A fresh region/pool with actual backing leased from an owned concurrent
 * parent. The parent allocation pins the entire ancestry through retirement.
 * No child can adopt an existing allocation or create an ancestry cycle. */
AstraContext17 *astra_context17_nested(AstraContext17 *parent, uint32_t kind,
                                       uint64_t capacity, uint64_t slots, uint32_t alignment);
int astra_context17_retain(AstraContext17 *);
int astra_context17_drop(AstraContext17 *);
int astra_context17_close(AstraContext17 *);
int astra_context17_reset(AstraContext17 *);
int astra_context17_transfer(AstraContext17 *);
int astra_context17_snapshot(AstraContext17 *, AstraContext17Snapshot *);
int astra_context17_acquire(AstraContext17 *, uint64_t count, uint64_t extent,
                            uint32_t alignment, uint64_t tag, AstraContext17Token *);
int astra_context17_release(AstraContext17 *, const AstraContext17Token *);
/* Compiler owner glue. Source cannot manufacture an allocation header. Use the
 * token API for safe wrong-instance/stale controls without touching freed bytes. */
void *astra_context17_allocate(AstraContext17 *, uint64_t count, uint64_t extent,
                               uint32_t alignment, uint64_t tag);
int astra_context17_release_origin(void *, uint64_t tag);
void *astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);
int astra_context17_release_origin_checked(void *, uint64_t);
AstraContext17 *astra_context17_origin(void *, uint64_t);
void astra_context17_destroy(AstraContext17 *);
AstraContext17 *astra_context17_open_concurrent(int32_t, int64_t, int32_t, int32_t);
AstraContext17 *astra_context17_open_affine(int32_t, int64_t, int32_t, int32_t);
AstraContext17 *astra_context17_open_transfer(int32_t, int64_t, int32_t, int32_t);
/* Compiler intrinsic only: the complete byte owner remains exclusively loaned
 * through the context's lexical destruction. It is never a C/VAPI factory. */
AstraContext17 *astra_context17_open_scoped(void *, int32_t, int32_t, int32_t);
AstraContext17 *astra_context17_open_nested(AstraContext17 *, int32_t, int64_t, int32_t, int32_t);
int64_t astra_context17_query(AstraContext17 *, int32_t);
int64_t astra_context17_query_affine(AstraContext17 *, int32_t);
int64_t astra_context17_query_scoped(AstraContext17 *, int32_t);
struct AstraAsyncFrameAllocator;
const struct AstraAsyncFrameAllocator *astra_context17_frame_descriptor(uint32_t);
#endif
