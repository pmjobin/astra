/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct {
	void *backing;
	int32_t length;
	AstraContext17 *context;
	int remembered, admitted, retired, freed, probed;
} owners[4];
static int refusals, null_drops;

void scoped_backing_remember(void *backing, int32_t length, int32_t id) {
	assert(id > 0 && id < 4 && !owners[id].remembered);
	assert(length == (id == 1 ? 8197 : id == 2 ? 12341
	                                           : 0));
	owners[id].remembered = 1;
	owners[id].backing = backing;
	owners[id].length = length;
}
AstraContext17 *__real_astra_context17_open_scoped(void *, int32_t, int32_t, int32_t);
AstraContext17 *__wrap_astra_context17_open_scoped(void *backing, int32_t length, int32_t kind, int32_t slots) {
	int id = length == 8197 ? 1 : length == 12341 ? 2
	                                              : 3;
	assert(owners[id].remembered && owners[id].backing == backing && owners[id].length == length);
	assert(!owners[id].context && !owners[id].admitted && !owners[id].freed);
	assert(kind == (id == 2 ? ASTRA_CONTEXT17_POOL : ASTRA_CONTEXT17_REGION) && slots == (id == 1 ? 7 : id == 2 ? 5
	                                                                                                            : 3));
	AstraContext17 *context = __real_astra_context17_open_scoped(backing, length, kind, slots);
	if (id == 3) {
		assert(!context);
		++refusals;
	} else {
		assert(context);
		owners[id].context = context;
		owners[id].admitted = 1;
	}
	return context;
}
int32_t scoped_backing_probe(AstraContext17 *context, int32_t id) {
	assert(id > 0 && id < 3 && owners[id].context == context && owners[id].admitted && !owners[id].retired && !owners[id].freed && !owners[id].probed);
	AstraContext17Snapshot before, after;
	assert(astra_context17_snapshot(context, &before) == ASTRA_CONTEXT17_OK && before.borrowed == 1 && before.threading == ASTRA_CONTEXT17_AFFINE && before.live == 0);
	assert(astra_context17_retain(context) != ASTRA_CONTEXT17_OK);
	uint64_t tag = UINT64_C(0x73636f7065640000) + (uint64_t)id;
	void *value = astra_context17_allocate_mode(context, 3, 1, 16, tag, 3);
	assert(value && (uintptr_t)value >= (uintptr_t)owners[id].backing && (uintptr_t)value + 3 <= (uintptr_t)owners[id].backing + (uint32_t)owners[id].length);
	memset(value, 77, 3);
	assert(astra_context17_reset(context) == ASTRA_CONTEXT17_LIVE);
	assert(astra_context17_release_origin_checked(value, tag) == 1);
	assert(astra_context17_snapshot(context, &after) == ASTRA_CONTEXT17_OK && after.live == 0 && after.allocations == 1 && after.releases == 1 && after.instance == before.instance);
	owners[id].probed = 1;
	return 0;
}
void __real_astra_context17_destroy(AstraContext17 *);
void __wrap_astra_context17_destroy(AstraContext17 *context) {
	if (!context) {
		++null_drops;
		__real_astra_context17_destroy(context);
		return;
	}
	for (int id = 1; id < 3; ++id) {
		if (owners[id].context != context || owners[id].retired) {
			continue;
		}
		assert(owners[id].probed && !owners[id].freed);
		AstraContext17Snapshot state;
		assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK && state.live == 0 && state.borrowed == 1);
		owners[id].retired = 1;
	}
	__real_astra_context17_destroy(context);
}
void __real_free(void *);
void __wrap_free(void *pointer) {
	if (pointer) {
		for (int id = 1; id < 4; ++id) {
			if (!owners[id].remembered || owners[id].freed || owners[id].backing != pointer) {
				continue;
			}
			assert(id != 2 && (id == 3 || owners[id].retired));
			owners[id].freed = 1;
		}
	}
	__real_free(pointer);
}
int __real_astra_context17_release_origin_checked(void *, uint64_t);
int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	if (owners[2].remembered && !owners[2].freed && owners[2].backing == pointer) {
		assert(owners[2].retired);
		owners[2].freed = 1;
	}
	return __real_astra_context17_release_origin_checked(pointer, tag);
}
int scoped_backing_finish(void) {
	for (int id = 1; id < 3; ++id) {
		assert(owners[id].remembered && owners[id].admitted && owners[id].probed && owners[id].retired && owners[id].freed);
	}
	assert(owners[3].remembered && (!owners[3].backing || owners[3].freed) && refusals == 1 && null_drops == 1);
	puts("scoped backing: exact caller buffers, exclusive lexical loans, original storage and ordered retirement");
	return 0;
}
extern int scoped_backing_run(void);
int main(void) {
	return scoped_backing_run();
}
