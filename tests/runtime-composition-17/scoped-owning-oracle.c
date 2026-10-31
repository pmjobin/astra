/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static unsigned born[11], retired[11], parent_born[5], parent_retired[5];
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
} allocation[5];
static unsigned allocations, refusals;

AstraContext17 *__real_astra_context17_open_scoped(void *, int32_t, int32_t, int32_t);
AstraContext17 *__wrap_astra_context17_open_scoped(void *base, int32_t length, int32_t kind, int32_t slots) {
	unsigned identity = length == 8197 ? 1 : 2;
	assert(base && length == (identity == 1 ? 8197 : 12289) && !backing[identity].base);
	assert(kind == (identity == 1 ? ASTRA_CONTEXT17_POOL : ASTRA_CONTEXT17_REGION));
	assert(slots == (identity == 1 ? 1 : 7));
	AstraContext17 *context = __real_astra_context17_open_scoped(base, length, kind, slots);
	AstraContext17Snapshot state;
	assert(context && astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
	assert(state.borrowed && state.threading == ASTRA_CONTEXT17_AFFINE && !state.live);
	if (identity == 2) {
		uintptr_t first = (uintptr_t)backing[1].base, second = (uintptr_t)base;
		assert(first + (uint32_t)backing[1].length <= second || second + (uint32_t)length <= first);
		AstraContext17Snapshot prior;
		assert(astra_context17_snapshot(backing[1].context, &prior) == ASTRA_CONTEXT17_OK && prior.instance != state.instance);
	}
	backing[identity].base = base;
	backing[identity].length = length;
	backing[identity].context = context;
	return context;
}

void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);
void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	unsigned identity = context == backing[1].context ? 1 : 2;
	assert(context == backing[identity].context && !backing[identity].closed);
	assert(mode == 3 && count == 1 && size == 24 && alignment == 8 && tag);
	void *pointer = __real_astra_context17_allocate_mode(context, count, size, alignment, tag, mode);
	if (!pointer) {
		assert(identity == 1 && allocations == 1 && refusals < 2 && born[3] && born[4] && !retired[3] && !retired[4]);
		if (refusals == 1) assert(born[9] && born[10] && !retired[9] && !retired[10]);
		++refusals;
		return pointer;
	}
	assert(++allocations <= 4 && identity == (allocations % 2 ? 1u : 2u));
	if (allocations == 2) assert(retired[9] == 1 && retired[10] == 1);
	uintptr_t start = (uintptr_t)backing[identity].base, address = (uintptr_t)pointer;
	assert(address >= start && address - start <= (uint32_t)backing[identity].length - size);
	assert((address & (alignment - 1)) == 0);
	if (allocations == 3) assert(pointer == allocation[1].pointer && !allocation[1].live);
	for (unsigned prior = 1; prior < allocations; ++prior) {
		assert(!allocation[prior].live || allocation[prior].pointer != pointer);
		assert(allocation[prior].tag == tag);
	}
	allocation[allocations].pointer = pointer;
	allocation[allocations].tag = tag;
	allocation[allocations].context = identity;
	allocation[allocations].live = 1;
	++backing[identity].allocations;
	return pointer;
}

void scoped_owning_event(int kind, int identity) {
	if (kind <= 2) {
		assert(identity > 0 && identity <= 10 && (kind == 1 || born[identity]));
		if (kind == 1)
			assert(!born[identity]++);
		else
			assert(!retired[identity]++);
	} else {
		assert(identity > 0 && identity <= 4 && allocation[identity].live);
		assert(born[identity * 2 - 1] && born[identity * 2]);
		if (kind == 3)
			assert(!parent_born[identity]++);
		else {
			assert(kind == 4 && parent_born[identity]);
			assert(!parent_retired[identity]++);
		}
	}
}

int __real_astra_context17_release_origin_checked(void *, uint64_t);
int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	for (unsigned identity = 1; identity <= allocations; ++identity) {
		if (!allocation[identity].live || allocation[identity].pointer != pointer) continue;
		unsigned context = allocation[identity].context;
		assert(parent_retired[identity] == 1 && retired[identity * 2 - 1] == 1 && retired[identity * 2] == 1);
		assert(tag == allocation[identity].tag && !backing[context].closed);
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
	assert(backing[identity].allocations == 2);
	assert(backing[identity].releases == backing[identity].allocations);
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

extern int scoped_owning_run(void);
int main(void) {
	int result = scoped_owning_run();
	if (result) return result;
	assert(allocations == 4 && refusals == 2);
	for (unsigned identity = 1; identity <= 10; ++identity)
		assert(born[identity] == 1 && retired[identity] == 1);
	for (unsigned identity = 1; identity <= 4; ++identity)
		assert(parent_born[identity] == 1 && parent_retired[identity] == 1 && !allocation[identity].live);
	for (unsigned identity = 1; identity < 3; ++identity)
		assert(backing[identity].closed && backing[identity].freed);
	puts("scoped owning Classes: 4 parents, 10 heap leaves, factory rollback and exact retirement");
	return 0;
}
