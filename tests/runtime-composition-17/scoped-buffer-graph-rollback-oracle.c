/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static AstraContext17 *context, *leaf_context;
static void *leaf_backing, *pending_leaf, *leaves[100];
static uint64_t leaf_tag;
static unsigned leaf_allocations, leaf_releases, leaf_retired[100], leaf_released[100];
static int leaf_closed, leaf_freed, leaf_live;
static void *backing, *cell, *buffers[100][2];
static uint64_t tag;
static unsigned allocations, releases, refusals, clock_tick;
static unsigned entered[7], parent_retired[7], errors[7], caught[7], error_retired[7];
static unsigned buffer_retired[100][2], buffer_order[100][2];
static int live, closed, freed;

static int failed(unsigned id) {
	return id != 2 && id != 4;
}

static void buffers_gone(unsigned id) {
	for (unsigned member = 0; member < 2; ++member)
		assert(buffers[id][member] && buffer_retired[id][member] == 1);
	if (id == 5 || id == 6) assert(buffer_order[id][1] < buffer_order[id][0]);
}

void *__real_calloc(size_t, size_t);

void *__wrap_calloc(size_t count, size_t size) {
	void *pointer = __real_calloc(count, size);
	if (size == 1 || size == 4) {
		unsigned member = size == 4;
		unsigned suffix = member ? 3 : 1;
		if (count % 10 == suffix && count / 10 < 100) {
			unsigned id = (unsigned)(count / 10);
			if ((id >= 1 && id <= 6) || id == 99) {
				assert(pointer && !buffers[id][member] && !closed);
				buffers[id][member] = pointer;
			}
		}
	}
	return pointer;
}

AstraContext17 *__real_astra_context17_open_scoped(void *, int32_t, int32_t, int32_t);

AstraContext17 *__wrap_astra_context17_open_scoped(void *base, int32_t length, int32_t kind, int32_t slots) {
	if (length == 12289) {
		assert(base && kind == ASTRA_CONTEXT17_POOL && slots == 2 && !leaf_context);
		leaf_backing = base;
		leaf_context = __real_astra_context17_open_scoped(base, length, kind, slots);
		assert(leaf_context);
		return leaf_context;
	}
	assert(base && length == 8197 && kind == ASTRA_CONTEXT17_POOL && slots == 1 && !context);
	backing = base;
	context = __real_astra_context17_open_scoped(base, length, kind, slots);
	assert(context);
	return context;
}

void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t, uint64_t, uint32_t, uint64_t, uint32_t);

void *__wrap_astra_context17_allocate_mode(AstraContext17 *selected, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t selected_tag, uint32_t mode) {
	if (selected == leaf_context) {
		assert(!leaf_closed && count == 1 && size == 4 && alignment == 4 && selected_tag && mode == 3 && !pending_leaf && leaf_live < 2);
		pending_leaf = __real_astra_context17_allocate_mode(selected, count, size, alignment, selected_tag, mode);
		assert(pending_leaf);
		if (leaf_tag) assert(selected_tag == leaf_tag);
		leaf_tag = selected_tag;
		++leaf_allocations;
		++leaf_live;
		return pending_leaf;
	}
	assert(selected == context && !closed && count == 1 && size == 48 && alignment == 8 && selected_tag && mode == 3);
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

void scoped_buffer_graph_rollback_event(int event, int identity) {
	assert(identity > 0 && identity < 100 && !closed && !leaf_closed);
	if (event == 6) {
		assert(pending_leaf && !leaves[identity]);
		leaves[identity] = pending_leaf;
		pending_leaf = NULL;
		return;
	}
	if (event == 7) {
		assert(leaves[identity] && !leaf_retired[identity] && !leaf_released[identity]);
		buffers_gone((unsigned)identity);
		leaf_retired[identity] = 1;
		return;
	}
	assert(identity <= 6);
	unsigned id = (unsigned)identity;
	if (event == 1) {
		assert(live && allocations == id && !entered[id]);
		for (unsigned member = 0; member < 2; ++member)
			assert(buffers[id][member] && !buffer_retired[id][member]);
		++entered[id];
	} else if (event == 2) {
		assert(failed(id) && live && entered[id] == 1 && !errors[id]);
		++errors[id];
	} else if (event == 3) {
		assert(failed(id) && !live && releases == id && errors[id] == 1 && caught[id] == 1 && !error_retired[id]);
		buffers_gone(id);
		++error_retired[id];
	} else if (event == 4) {
		assert(!failed(id) && live && allocations == id && entered[id] == 1 && !parent_retired[id]);
		for (unsigned member = 0; member < 2; ++member)
			assert(!buffer_retired[id][member]);
		++parent_retired[id];
	} else {
		assert(event == 5 && failed(id) && !live && releases == id && errors[id] == 1 && !caught[id] && !error_retired[id]);
		buffers_gone(id);
		++caught[id];
	}
}

int __real_astra_context17_release_origin_checked(void *, uint64_t);

int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t selected_tag) {
	if (!pointer) return __real_astra_context17_release_origin_checked(pointer, selected_tag);
	if (pointer != cell) {
		assert(!leaf_closed && selected_tag == leaf_tag && leaf_live > 0);
		unsigned found = 0;
		for (unsigned id = 1; id < 100; ++id)
			if (pointer == leaves[id] && !leaf_released[id]) {
				assert(!found && leaf_retired[id] == 1);
				found = id;
			}
		assert(found);
		int result = __real_astra_context17_release_origin_checked(pointer, selected_tag);
		assert(result == 1);
		leaf_released[found] = 1;
		++leaf_releases;
		--leaf_live;
		return result;
	}
	assert(pointer == cell && selected_tag == tag && live && allocations == releases + 1 && !closed);
	assert(entered[allocations] == 1);
	buffers_gone(allocations);
	assert(leaf_retired[allocations] == 1 && leaf_released[allocations] == 1);
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
	if (selected == leaf_context) {
		assert(!leaf_closed && !leaf_live && !pending_leaf && leaf_allocations == 7 && leaf_releases == 7);
		for (unsigned id = 1; id <= 6; ++id)
			assert(leaf_retired[id] == 1 && leaf_released[id] == 1);
		assert(leaf_retired[99] == 1 && leaf_released[99] == 1);
		leaf_closed = 1;
		__real_astra_context17_destroy(selected);
		return;
	}
	assert(selected == context && !closed && !live && allocations == 6 && releases == 6 && refusals == 1);
	for (unsigned id = 1; id <= 6; ++id) {
		assert(entered[id] == 1);
		buffers_gone(id);
		if (failed(id))
			assert(!parent_retired[id] && errors[id] == 1 && caught[id] == 1 && error_retired[id] == 1);
		else
			assert(parent_retired[id] == 1 && !errors[id] && !caught[id] && !error_retired[id]);
	}
	buffers_gone(99);
	closed = 1;
	__real_astra_context17_destroy(selected);
}

void __real_free(void *);

void __wrap_free(void *pointer) {
	if (leaf_backing && pointer == leaf_backing) {
		assert(leaf_closed && !leaf_freed);
		leaf_freed = 1;
	}
	if (backing && pointer == backing) {
		assert(closed && !freed);
		freed = 1;
	}
	if (pointer)
		for (unsigned id = 1; id < 100; ++id)
			for (unsigned member = 0; member < 2; ++member) {
				if (pointer == buffers[id][member] && !buffer_retired[id][member]) {
					assert(!closed);
					buffer_retired[id][member] = 1;
					buffer_order[id][member] = ++clock_tick;
					/* Allocators may immediately reuse a previously retired address. */
					goto retired;
				}
			}
retired:
	__real_free(pointer);
}

extern int scoped_buffer_graph_rollback_run(void);

int main(void) {
	int result = scoped_buffer_graph_rollback_run();
	if (result) return result;
	assert(closed && freed && leaf_closed && leaf_freed);
	puts("scoped buffer graph rollback: 13 placements, 4 prefix failures, 7 scoped children and 14 buffers retired before backing");
	return 0;
}
