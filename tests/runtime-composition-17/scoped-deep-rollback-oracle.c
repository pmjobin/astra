/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static struct {
	AstraContext17 *context;
	void *base;
	uint64_t tag;
	unsigned allocations, releases;
	int closed, freed;
} backing[4];
static struct {
	void *pointer;
	uint64_t tag;
	unsigned context, identity, entered, retired, order;
	int live;
} allocation[35];
static struct {
	unsigned leaf, leaf_retired, node, node_retired;
} child[1000];
static unsigned allocations, refusals, clock_tick, errors[7], caught[7], error_retired[7];

static int failed(unsigned identity) {
	return identity != 2 && identity != 4;
}
static unsigned find(unsigned context, unsigned identity) {
	for (unsigned i = 1; i <= allocations; ++i)
		if (allocation[i].context == context && allocation[i].identity == identity) return i;
	assert(0);
	return 0;
}
static void children_retired(unsigned identity) {
	unsigned left = find(2, identity * 10 + 1), right = find(2, identity * 10 + 2);
	assert(!allocation[left].live && !allocation[right].live && allocation[left].retired == 1 && allocation[right].retired == 1);
	if (identity == 5 || identity == 6) assert(allocation[right].order < allocation[left].order);
}
AstraContext17 *__real_astra_context17_open_scoped(void *, int32_t, int32_t, int32_t);
AstraContext17 *__wrap_astra_context17_open_scoped(void *base, int32_t length, int32_t kind, int32_t slots) {
	unsigned context = length == 8197 ? 1 : length == 12289 ? 2
	                                                        : 3;
	assert(base && length == (context == 1 ? 8197 : context == 2 ? 12289
	                                                             : 16385) &&
	       !backing[context].context);
	assert(kind == (context == 1 ? ASTRA_CONTEXT17_POOL : ASTRA_CONTEXT17_REGION) && slots == (context == 1 ? 1 : 7));
	backing[context].base = base;
	backing[context].context = __real_astra_context17_open_scoped(base, length, kind, slots);
	assert(backing[context].context);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(backing[context].context, &state) == ASTRA_CONTEXT17_OK && state.borrowed && !state.live);
	return backing[context].context;
}
void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);
void *__wrap_astra_context17_allocate_mode(AstraContext17 *selected, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	unsigned context = selected == backing[1].context ? 1 : selected == backing[2].context ? 2
	                                                                                       : 3;
	assert(selected == backing[context].context && !backing[context].closed && count == 1 && size == (context == 1 ? 24u : 16u) && alignment == 8 && tag && mode == 3);
	void *pointer = __real_astra_context17_allocate_mode(selected, count, size, alignment, tag, mode);
	if (!pointer) {
		assert(context == 1 && backing[1].allocations == 2 && backing[1].releases == 1 && !refusals);
		++refusals;
		return pointer;
	}
	uintptr_t address = (uintptr_t)pointer, start = (uintptr_t)backing[context].base;
	assert(address >= start && address - start <= (context == 1 ? 8197u : context == 2 ? 12289u
	                                                                                   : 16385u) -
	                                                  size &&
	       !(address & 7));
	assert(allocations < 34);
	for (unsigned i = 1; i <= allocations; ++i)
		assert(!allocation[i].live || allocation[i].pointer != pointer);
	if (backing[context].tag)
		assert(tag == backing[context].tag);
	else
		backing[context].tag = tag;
	for (unsigned other = 1; other <= 3; ++other)
		if (other != context && backing[other].tag) assert(tag != backing[other].tag);
	if (context == 1 && backing[1].allocations) assert(pointer == allocation[find(1, 1)].pointer);
	++allocations;
	allocation[allocations].pointer = pointer;
	allocation[allocations].tag = tag;
	allocation[allocations].context = context;
	allocation[allocations].live = 1;
	++backing[context].allocations;
	return pointer;
}
void scoped_deep_rollback_event(int event, int identity) {
	assert(identity > 0);
	unsigned id = (unsigned)identity;
	if (event >= 8 && event <= 11) {
		assert(id < 1000 && !backing[2].closed && (id % 10 == 1 || id % 10 == 2));
		if (event == 10) {
			assert(!child[id].leaf);
			++child[id].leaf;
		} else if (event == 8) {
			assert(child[id].leaf == 1 && !child[id].node);
			++child[id].node;
		} else if (event == 9) {
			assert(child[id].node == 1 && !child[id].node_retired && !child[id].leaf_retired);
			++child[id].node_retired;
		} else {
			assert(event == 11 && child[id].leaf == 1 && child[id].node_retired == 1 && !child[id].leaf_retired);
			++child[id].leaf_retired;
		}
		return;
	}
	if (event == 1 || event == 6 || event == 12) {
		unsigned context = event == 1 ? 1 : event == 6 ? 2
		                                               : 3;
		assert(allocation[allocations].context == context && allocation[allocations].live && !allocation[allocations].entered && !allocation[allocations].identity);
		allocation[allocations].identity = id;
		allocation[allocations].entered = 1;
		if (context == 2) {
			unsigned tip = find(3, id);
			assert(allocation[tip].live && allocation[tip].entered && !allocation[tip].retired);
		}
		if (context == 3) assert(child[id].node == 1 && child[id].leaf == 1 && !child[id].node_retired && !child[id].leaf_retired);
		return;
	}
	if (event == 7 || event == 13) {
		unsigned record = find(event == 7 ? 2 : 3, id);
		assert(allocation[record].live && allocation[record].entered == 1 && !allocation[record].retired && !child[id].node_retired && !child[id].leaf_retired);
		++allocation[record].retired;
		return;
	}
	assert(id <= 6 && !backing[1].closed);
	unsigned record = find(1, id);
	if (event == 2) {
		assert(failed(id) && allocation[record].live && !errors[id]);
		assert(allocation[find(2, id * 10 + 1)].live && allocation[find(2, id * 10 + 2)].live);
		++errors[id];
	} else if (event == 3) {
		assert(failed(id) && !allocation[record].live && errors[id] == 1 && caught[id] == 1 && !error_retired[id]);
		children_retired(id);
		++error_retired[id];
	} else if (event == 4) {
		assert(!failed(id) && allocation[record].live && !allocation[record].retired);
		++allocation[record].retired;
	} else {
		assert(event == 5 && failed(id) && !allocation[record].live && errors[id] == 1 && !caught[id] && !error_retired[id]);
		children_retired(id);
		++caught[id];
	}
}
int __real_astra_context17_release_origin_checked(void *, uint64_t);
int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	if (!pointer) return __real_astra_context17_release_origin_checked(pointer, tag);
	unsigned record = 0;
	for (unsigned i = 1; i <= allocations; ++i)
		if (allocation[i].live && allocation[i].pointer == pointer) {
			record = i;
			break;
		}
	assert(record && allocation[record].tag == tag && allocation[record].entered == 1);
	unsigned context = allocation[record].context, id = allocation[record].identity;
	assert(!backing[context].closed);
	if (context == 1) {
		children_retired(id);
		if (failed(id))
			assert(!allocation[record].retired && errors[id] == 1 && !caught[id]);
		else
			assert(allocation[record].retired == 1 && !errors[id]);
	} else {
		assert(allocation[record].retired == 1 && child[id].node_retired == 1 && child[id].leaf_retired == 1);
		if (context == 2) {
			unsigned tip = find(3, id);
			assert(!allocation[tip].live && allocation[tip].retired == 1);
		}
	}
	int result = __real_astra_context17_release_origin_checked(pointer, tag);
	assert(result == 1);
	allocation[record].live = 0;
	allocation[record].order = ++clock_tick;
	++backing[context].releases;
	return result;
}
void __real_astra_context17_destroy(AstraContext17 *);
void __wrap_astra_context17_destroy(AstraContext17 *selected) {
	unsigned context = selected == backing[1].context ? 1 : selected == backing[2].context ? 2
	                                                                                       : 3;
	assert(selected == backing[context].context && !backing[context].closed && backing[context].allocations == (context == 1 ? 6u : 14u) && backing[context].releases == backing[context].allocations);
	for (unsigned i = 1; i <= allocations; ++i)
		assert(!allocation[i].live);
	for (unsigned id = 1; id <= 6; ++id)
		if (failed(id)) assert(errors[id] == 1 && caught[id] == 1 && error_retired[id] == 1);
	children_retired(99);
	backing[context].closed = 1;
	__real_astra_context17_destroy(selected);
}
void __real_free(void *);
void __wrap_free(void *pointer) {
	for (unsigned context = 1; context <= 3; ++context)
		if (backing[context].base && pointer == backing[context].base) {
			assert(backing[context].closed && !backing[context].freed);
			backing[context].freed = 1;
		}
	__real_free(pointer);
}
extern int scoped_deep_rollback_run(void);
int main(void) {
	int result = scoped_deep_rollback_run();
	if (result) return result;
	assert(allocations == 34 && refusals == 1 && backing[1].freed && backing[2].freed && backing[3].freed);
	puts("scoped deep rollback: 3 contexts, 34 placements, 28 heap child retirements and 4 prefix failures");
	return 0;
}
