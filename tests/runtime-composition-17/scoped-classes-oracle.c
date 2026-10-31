/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static unsigned retired[7];
static struct {
	void *base;
	int32_t length;
	AstraContext17 *context;
	unsigned allocations, releases;
	int closed, freed;
} backing[3];
static struct {
	void *pointer;
	uint64_t tag;
	unsigned context;
	int live;
} allocation[7];
static unsigned allocations, refusals;

AstraContext17 *__real_astra_context17_open_scoped(void *, int32_t, int32_t, int32_t);
AstraContext17 *__wrap_astra_context17_open_scoped(void *base, int32_t length, int32_t kind, int32_t slots) {
	unsigned identity = length == 8197 ? 1 : 2;
	assert(base && length == (identity == 1 ? 8197 : 12289) && !backing[identity].base);
	assert(!backing[identity].context && !backing[identity].freed);
	backing[identity].base = base;
	backing[identity].length = length;
	assert(kind == (identity == 1 ? ASTRA_CONTEXT17_POOL : ASTRA_CONTEXT17_REGION));
	assert(slots == (identity == 1 ? 1 : 7));
	AstraContext17 *context = __real_astra_context17_open_scoped(base, length, kind, slots);
	assert(context);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
	assert(state.borrowed && state.threading == ASTRA_CONTEXT17_AFFINE && !state.live);
	if (identity == 2) {
		uintptr_t first = (uintptr_t)backing[1].base, second = (uintptr_t)base;
		assert(first + (uint32_t)backing[1].length <= second || second + (uint32_t)length <= first);
		AstraContext17Snapshot prior;
		assert(astra_context17_snapshot(backing[1].context, &prior) == ASTRA_CONTEXT17_OK && prior.instance != state.instance);
	}
	backing[identity].context = context;
	return context;
}

void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);
void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	unsigned identity = context == backing[1].context ? 1 : 2;
	assert(context == backing[identity].context && !backing[identity].closed);
	assert(mode == 3 && count == 1 && size == (allocations == 5 ? 16u : 8u));
	assert(alignment == (allocations == 5 ? 8u : 4u) && tag);
	void *pointer = __real_astra_context17_allocate_mode(context, count, size, alignment, tag, mode);
	if (!pointer) {
		assert(identity == 1 && backing[1].allocations == 1 && !backing[1].releases);
		++refusals;
		return pointer;
	}
	uintptr_t start = (uintptr_t)backing[identity].base;
	uintptr_t address = (uintptr_t)pointer;
	assert(address >= start && address - start <= (uint32_t)backing[identity].length - size);
	assert((address & (alignment - 1)) == 0);
	assert(++allocations <= 6 && identity == (allocations % 2 ? 1u : 2u));
	if (allocations == 3 || allocations == 5) assert(pointer == allocation[1].pointer && !allocation[1].live);
	for (unsigned prior = 1; prior < allocations; ++prior) {
		assert(!allocation[prior].live || allocation[prior].pointer != pointer);
		if (allocations <= 4)
			assert(allocation[prior].tag == tag);
		else
			assert(allocation[prior].tag != tag);
	}
	allocation[allocations].pointer = pointer;
	allocation[allocations].tag = tag;
	allocation[allocations].context = identity;
	allocation[allocations].live = 1;
	++backing[identity].allocations;
	return pointer;
}

void scoped_class_retired(int identity) {
	assert(identity > 0 && identity <= 6 && allocation[identity].live);
	assert(!retired[identity] && !backing[allocation[identity].context].closed);
	retired[identity]++;
}

int __real_astra_context17_release_origin_checked(void *, uint64_t);
int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	for (unsigned identity = 1; identity <= allocations; ++identity) {
		if (!allocation[identity].live || allocation[identity].pointer != pointer) continue;
		unsigned context = allocation[identity].context;
		assert(retired[identity] == 1 && allocation[identity].tag == tag && !backing[context].closed);
		int result = __real_astra_context17_release_origin_checked(pointer, tag);
		assert(result == 1);
		allocation[identity].live = 0;
		++backing[context].releases;
		return result;
	}
	assert(!pointer);
	return __real_astra_context17_release_origin_checked(pointer, tag);
}

void __real_astra_context17_destroy(AstraContext17 *);
void __wrap_astra_context17_destroy(AstraContext17 *context) {
	unsigned identity = context == backing[1].context ? 1 : 2;
	assert(context == backing[identity].context && !backing[identity].closed);
	assert(backing[identity].allocations == 3 && backing[identity].releases == 3);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK && !state.live && state.borrowed);
	backing[identity].closed = 1;
	__real_astra_context17_destroy(context);
}

void __real_free(void *);
void __wrap_free(void *pointer) {
	for (unsigned identity = 1; identity < 3; ++identity) {
		if (!backing[identity].base || backing[identity].base != pointer) continue;
		assert(backing[identity].closed && !backing[identity].freed);
		backing[identity].freed = 1;
	}
	__real_free(pointer);
}

extern int scoped_classes_run(void);
int main(void) {
	int result = scoped_classes_run();
	if (result) return result;
	assert(allocations == 6 && refusals == 1);
	for (unsigned identity = 1; identity <= 6; ++identity)
		assert(retired[identity] == 1 && !allocation[identity].live);
	for (unsigned identity = 1; identity < 3; ++identity)
		assert(backing[identity].closed && backing[identity].freed);
	puts("scoped Classes: distinct caller backing, pool refusal/reuse, record handoff, two generic layouts and 6 exact retirements");
	return 0;
}
