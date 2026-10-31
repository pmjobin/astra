// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stddef.h>

static char trace[1024];
static size_t length;
static int destructors, pointer_checks;
static void *identity[16];
static void event(char code, int tag) {
	int written = tag < 0 ? snprintf(trace + length, sizeof trace - length, "%c ", code)
	                      : snprintf(trace + length, sizeof trace - length, "%c%d ", code, tag);
	assert(written > 0 && (size_t)written < sizeof trace - length);
	length += (size_t)written;
}
#ifndef ALLOC_MEMORY_ONLY
extern void *__libc_calloc(size_t count, size_t size);
extern void __libc_free(void *pointer);
static struct {
	void *pointer;
	int tag, live;
} allocations[128];
static int used;
void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	assert(pointer != NULL && used < 128);
	allocations[used].pointer = pointer;
	allocations[used].live = 1;
	used++;
	event('A', -1);
	return pointer;
}
void free(void *pointer) {
	if (pointer == NULL) {
		return;
	}
	int found = -1;
	for (int i = 0; i < used; i++) {
		if (allocations[i].live && allocations[i].pointer == pointer) {
			found = i;
			break;
		}
	}
	assert(found >= 0);
	if (allocations[found].tag != 0) {
		assert(destructors == 1);
		destructors = 0;
	}
	allocations[found].live = 0;
	event('F', allocations[found].tag);
	__libc_free(pointer);
}
#endif
int32_t alloc_event(int32_t tag, int32_t stage) {
	if (stage == 1) {
#ifndef ALLOC_MEMORY_ONLY
		assert(used > 0 && allocations[used - 1].live && allocations[used - 1].tag == 0);
		allocations[used - 1].tag = tag;
#endif
		event('I', tag);
	} else if (stage == 2) {
		destructors++;
		event('D', -1);
	} else if (stage == 3) {
		event('P', tag);
	} else {
		event('X', tag);
	}
	return 0;
}
// Called only by the independently compiled test IR at the real probe entry.
void alloc_pointer(void *pointer, int32_t tag) {
	assert(tag > 0 && tag < 16 && pointer != NULL);
	if (identity[tag] == NULL) {
		identity[tag] = pointer;
	}
	assert(identity[tag] == pointer);
	if (identity[1] != NULL && identity[2] != NULL) {
		assert(identity[1] != identity[2]);
	}
#ifndef ALLOC_MEMORY_ONLY
	int found = 0;
	for (int i = 0; i < used; i++) {
		if (allocations[i].live && allocations[i].tag == tag && allocations[i].pointer == pointer) {
			found++;
		}
	}
	assert(found == 1);
#endif
	pointer_checks++;
}
int32_t alloc_ok(void) {
#ifndef ALLOC_MEMORY_ONLY
	for (int i = 0; i < used; i++) {
		assert(!allocations[i].live);
	}
	assert(destructors == 0);
#endif
	printf("%spointers=%d\n", trace, pointer_checks);
	return 1;
}
