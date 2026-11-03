/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdio.h>
#include <assert.h>
#include <stddef.h>
static int destroyed[2];
#ifndef SHARED_MEMORY_ONLY
extern void *__libc_calloc(size_t count, size_t size);
extern void __libc_free(void *pointer);

static struct {
	void *pointer;
	int live, payload;
} allocations[16];

static int used, freed, payload_freed, block_freed;

void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	assert(pointer && used < 16);
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
	assert(found >= 0);
	if (allocations[found].payload) {
		assert(destroyed[allocations[found].payload - 1] == 1);
		payload_freed++;
	} else
		block_freed++;
	allocations[found].live = 0;
	freed++;
	__libc_free(pointer);
}

#endif

int shared_event(int kind, int value) {
	if (kind == 1 || kind == 3) {
#ifndef SHARED_MEMORY_ONLY
		assert(used > 0 && allocations[used - 1].live && allocations[used - 1].payload == 0);
		allocations[used - 1].payload = kind == 1 ? 1 : 2;
#endif
	} else if (kind == 2 || kind == 4) {
		int index = kind == 2 ? 0 : 1;
		assert(++destroyed[index] == 1);
	}
	return printf("%d:%d\n", kind, value) < 0;
}

int shared_finish(void) {
	assert(destroyed[0] == 1 && destroyed[1] == 1);
#ifndef SHARED_MEMORY_ONLY
	assert(used == 4 && freed == 4 && payload_freed == 2 && block_freed == 2);
	for (int i = 0; i < used; i++)
		assert(!allocations[i].live);
#endif
#ifndef SHARED_MEMORY_ONLY
	puts("allocations=4 frees=4 payloads=2 blocks=2");
#else
	puts("memory destructors=2");
#endif
	return 0;
}
