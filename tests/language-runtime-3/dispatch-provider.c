// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void *__libc_calloc(size_t, size_t);
extern void __libc_free(void *);
static int seed, stage, bad, drops, selected;
#ifndef DISPATCH_MEMORY_ONLY
static int allocated, released;
static void *first_identity;

static struct {
	void *pointer;
	int live;
} allocation[16];

void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	if (allocated < 16) {
		allocation[allocated].pointer = pointer;
		allocation[allocated].live = 1;
	}
	allocated++;
	return pointer;
}

void free(void *pointer) {
	for (int i = 0; i < allocated && i < 16; i++) {
		if (allocation[i].pointer == pointer && allocation[i].live) {
			allocation[i].live = 0;
			released++;
			break;
		}
	}
	__libc_free(pointer);
}

#endif

int32_t dispatch_input(void) {
	const char *input = getenv("ASTRA_DISPATCH_SEED");
	seed = input == NULL ? 4 : atoi(input);
	return seed;
}

void dispatch_probe(int32_t current, int32_t value) {
	if (current != ++stage) {
		bad = 1;
	}
	int expected = current <= 2 ? seed + 7 : current == 3 ? (seed % 2 == 0 ? seed + 108 : seed * 3 + 201)
	                                                      : seed + 12;
	if (value != expected) {
		bad = 1;
	}
	if (current == 3) {
		selected = value;
	}
#ifndef DISPATCH_MEMORY_ONLY
	if (current == 1) {
		first_identity = allocation[0].pointer;
	}
	if (current <= 2 && (allocated != 1 || released != 0 || !allocation[0].live || allocation[0].pointer != first_identity)) {
		bad = 1;
	}
#endif
}

void dispatch_drop(int32_t rank) {
	drops = drops * 10 + rank;
}

int32_t dispatch_finish(void) {
	int valid = !bad && stage == 4 && drops == 3121;
#ifndef DISPATCH_MEMORY_ONLY
	valid = valid && allocated == 3 && released == 3;
	for (int i = 0; i < allocated && i < 16; i++) {
		if (allocation[i].live) {
			valid = 0;
		}
	}
#endif
	printf("dispatch seed=%d selected=%d moved=1 drops=%d\n", seed, selected, drops);
	return valid ? 0 : 91;
}
