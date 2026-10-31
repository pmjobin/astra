/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static AstraContext17 *context;
static void *backing, *cell;
static uint64_t cell_tag;
static unsigned allocations, releases, refusals, entered[7], retired[7];
static unsigned errors[7], caught[7], errors_retired[7];
static int live, closed, freed;

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
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	assert(selected == context && !closed && count == 1 && size == 8 && alignment == 4 && tag && mode == 3);
	void *pointer = __real_astra_context17_allocate_mode(selected, count, size, alignment, tag, mode);
	if (!pointer) {
		assert(live && allocations == 2 && releases == 1 && !refusals);
		++refusals;
		return pointer;
	}
	assert(!live && allocations == releases && allocations < 6);
	uintptr_t address = (uintptr_t)pointer, start = (uintptr_t)backing;
	assert(address >= start && address - start <= 8197 - size && !(address & (alignment - 1)));
	if (cell) assert(pointer == cell && tag == cell_tag);
	cell = pointer;
	cell_tag = tag;
	++allocations;
	live = 1;
	return pointer;
}

void scoped_rollback_event(int event, int identity) {
	assert(identity >= 1 && identity <= 6 && !closed);
	unsigned id = (unsigned)identity;
	int failed = id != 2 && id != 4;
	if (event == 1) {
		assert(live && allocations == id && !entered[id]);
		++entered[id];
	} else if (event == 2) {
		assert(failed && live && allocations == id && entered[id] == 1 && !errors[id]);
		++errors[id];
	} else if (event == 3) {
		assert(failed && !live && releases == id && errors[id] == 1 && caught[id] == 1 && !errors_retired[id]);
		++errors_retired[id];
	} else if (event == 4) {
		assert(!failed && live && allocations == id && entered[id] == 1 && !retired[id]);
		++retired[id];
	} else {
		assert(event == 5 && failed && !live && releases == id && errors[id] == 1 && !caught[id] && !errors_retired[id]);
		AstraContext17Snapshot state;
		assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK && !state.live);
		++caught[id];
	}
}

int __real_astra_context17_release_origin_checked(void *, uint64_t);
int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	if (!pointer) return __real_astra_context17_release_origin_checked(pointer, tag);
	assert(pointer == cell && tag == cell_tag && live && allocations == releases + 1 && !closed);
	assert(entered[allocations] == 1);
	if (allocations == 2 || allocations == 4)
		assert(retired[allocations] == 1 && !errors[allocations]);
	else
		assert(!retired[allocations] && errors[allocations] == 1 && !caught[allocations]);
	int result = __real_astra_context17_release_origin_checked(pointer, tag);
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
		if (id == 2 || id == 4)
			assert(retired[id] == 1 && !errors[id] && !caught[id] && !errors_retired[id]);
		else
			assert(!retired[id] && errors[id] == 1 && caught[id] == 1 && errors_retired[id] == 1);
	}
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

extern int scoped_constructor_rollback_run(void);
int main(void) {
	int result = scoped_constructor_rollback_run();
	if (result) return result;
	assert(closed && freed);
	puts("scoped constructor rollback: 6 placements, 4 caught failures, refusal and exact backing reuse");
	return 0;
}
