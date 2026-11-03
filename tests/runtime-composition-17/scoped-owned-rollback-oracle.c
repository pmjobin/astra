/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static AstraContext17 *context;
static void *backing, *cell;
static uint64_t tag;
static unsigned allocations, releases, refusals, clock_tick;
static unsigned entered[7], parent_retired[7], errors[7], caught[7], error_retired[7];
static unsigned child_entered[1000], child_retired[1000], child_order[1000];
static int live, closed, freed;

static int failed(unsigned id) {
	return id != 2 && id != 4;
}

static void children_retired(unsigned id) {
	for (unsigned member = 1; member <= 3; ++member)
		assert(child_entered[id * 10 + member] == 1 && child_retired[id * 10 + member] == 1);
	assert(child_order[id * 10 + 3] < child_order[id * 10 + 2]);
	if (id == 5 || id == 6) assert(child_order[id * 10 + 2] < child_order[id * 10 + 1]);
}

AstraContext17 *__real_astra_context17_open_scoped(void *, int32_t, int32_t, int32_t);

AstraContext17 *__wrap_astra_context17_open_scoped(void *base, int32_t length, int32_t kind, int32_t slots) {
	assert(base && length == 8197 && kind == ASTRA_CONTEXT17_POOL && slots == 1 && !context);
	backing = base;
	context = __real_astra_context17_open_scoped(base, length, kind, slots);
	assert(context);
	return context;
}

void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);

void *__wrap_astra_context17_allocate_mode(AstraContext17 *selected, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t selected_tag, uint32_t mode) {
	assert(selected == context && !closed && count == 1 && size == 24 && alignment == 8 && selected_tag && mode == 3);
	void *pointer = __real_astra_context17_allocate_mode(selected, count, size, alignment, selected_tag, mode);
	if (!pointer) {
		assert(live && allocations == 2 && releases == 1 && !refusals);
		++refusals;
		return pointer;
	}
	assert(!live && allocations == releases && allocations < 6);
	if (cell) assert(pointer == cell && selected_tag == tag);
	uintptr_t address = (uintptr_t)pointer, start = (uintptr_t)backing;
	assert(address >= start && address - start <= 8197 - size && !(address & (alignment - 1)));
	cell = pointer;
	tag = selected_tag;
	++allocations;
	live = 1;
	return pointer;
}

void scoped_owned_rollback_event(int event, int identity) {
	assert(identity > 0 && !closed);
	unsigned id = (unsigned)identity;
	if (event >= 6) {
		assert(id < 1000 && (id / 10 <= 6 || id / 10 == 99));
		unsigned member = id % 10;
		assert((member == 3) == (event == 8 || event == 9));
		if (event == 6 || event == 8) {
			assert(!child_entered[id]);
			++child_entered[id];
		} else {
			assert((event == 7 || event == 9) && child_entered[id] == 1 && !child_retired[id]);
			if (member == 3) assert(!child_retired[id - 1]);
			if (member == 2) assert(child_retired[id + 1] == 1);
			++child_retired[id];
			child_order[id] = ++clock_tick;
		}
		return;
	}
	assert(id <= 6);
	if (event == 1) {
		assert(live && allocations == id && !entered[id]);
		for (unsigned member = 1; member <= 3; ++member)
			assert(child_entered[id * 10 + member] == 1 && !child_retired[id * 10 + member]);
		++entered[id];
	} else if (event == 2) {
		assert(failed(id) && live && entered[id] == 1 && !errors[id]);
		++errors[id];
	} else if (event == 3) {
		assert(failed(id) && !live && releases == id && errors[id] == 1 && caught[id] == 1 && !error_retired[id]);
		children_retired(id);
		++error_retired[id];
	} else if (event == 4) {
		assert(!failed(id) && live && allocations == id && entered[id] == 1 && !parent_retired[id]);
		++parent_retired[id];
	} else {
		assert(event == 5 && failed(id) && !live && releases == id && errors[id] == 1 && !caught[id] && !error_retired[id]);
		children_retired(id);
		++caught[id];
	}
}

int __real_astra_context17_release_origin_checked(void *, uint64_t);

int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t selected_tag) {
	if (!pointer) return __real_astra_context17_release_origin_checked(pointer, selected_tag);
	assert(pointer == cell && selected_tag == tag && live && allocations == releases + 1 && !closed);
	assert(entered[allocations] == 1);
	children_retired(allocations);
	if (failed(allocations))
		assert(!parent_retired[allocations] && errors[allocations] == 1 && !caught[allocations]);
	else
		assert(parent_retired[allocations] == 1 && !errors[allocations]);
	int result = __real_astra_context17_release_origin_checked(pointer, selected_tag);
	assert(result == 1);
	live = 0;
	++releases;
	return result;
}

void __real_astra_context17_destroy(AstraContext17 *);

void __wrap_astra_context17_destroy(AstraContext17 *selected) {
	assert(selected == context && !closed && !live && allocations == 6 && releases == 6 && refusals == 1);
	for (unsigned id = 1; id <= 6; ++id) {
		assert(entered[id] == 1);
		children_retired(id);
		if (failed(id))
			assert(!parent_retired[id] && errors[id] == 1 && caught[id] == 1 && error_retired[id] == 1);
		else
			assert(parent_retired[id] == 1 && !errors[id] && !caught[id] && !error_retired[id]);
	}
	children_retired(99);
	closed = 1;
	__real_astra_context17_destroy(selected);
}

void __real_free(void *);

void __wrap_free(void *pointer) {
	if (backing && pointer == backing) {
		assert(closed && !freed);
		freed = 1;
	}
	__real_free(pointer);
}

extern int scoped_owned_rollback_run(void);

int main(void) {
	int result = scoped_owned_rollback_run();
	if (result) return result;
	assert(closed && freed);
	puts("scoped owned rollback: 6 placements, 4 prefix failures, 21 child retirements and retained refusal inputs");
	return 0;
}
