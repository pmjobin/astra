/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
extern void *__libc_calloc(size_t count, size_t size);
extern void __libc_free(void *pointer);

static struct {
	void *pointer;
	int live, tag;
} allocations[4];

static int used, freed, destroyed[3];

void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	assert(pointer && used < 4);
	allocations[used].pointer = pointer;
	allocations[used].live = 1;
	used++;
	return pointer;
}

void free(void *pointer) {
	if (!pointer) return;
	int found = -1;
	for (int i = 0; i < used; i++)
		if (allocations[i].live && allocations[i].pointer == pointer) {
			found = i;
			break;
		}
	assert(found >= 0 && allocations[found].tag > 0 && destroyed[allocations[found].tag] == 1);
	allocations[found].live = 0;
	freed++;
	__libc_free(pointer);
}

int unique_event(int stage, int tag) {
	assert(tag == 1 || tag == 2);
	if (stage == 1) {
		assert(used > 0 && allocations[used - 1].tag == 0);
		allocations[used - 1].tag = tag;
	} else {
		assert(stage == 2 && ++destroyed[tag] == 1);
	}
	return printf("%d:%d\n", stage, tag) < 0;
}

int unique_finish(void) {
	assert(used == 2 && freed == 2 && destroyed[1] == 1 && destroyed[2] == 1);
	for (int i = 0; i < used; i++)
		assert(!allocations[i].live);
	puts("unique allocations=2 frees=2 controls=0");
	return 0;
}
