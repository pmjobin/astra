// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

struct resource {
	int32_t id;
	int alive;
	int domain;
};
static struct resource resources[256];

static void *acquire(int32_t id, int domain) {
	printf("+%d\n", id);
	fflush(stdout);
	if (id == 0) {
		return NULL;
	}
	assert(id > 0 && id < 256 && !resources[id].alive);
	resources[id] = (struct resource){id, 1, domain};
	return &resources[id];
}
void *of_make(int32_t id) {
	return acquire(id, 0);
}
void *of_make_other(int32_t id) {
	return acquire(id, 1);
}
static void release(void *pointer, int domain) {
	struct resource *resource = pointer;
	assert(resource && resource->alive && resource->domain == domain);
	printf("-%d\n", resource->id);
	fflush(stdout);
	resource->alive = 0;
}
void of_release(void *pointer) {
	release(pointer, 0);
}
void of_release_other(void *pointer) {
	release(pointer, 1);
}
int32_t of_id(void *pointer) {
	struct resource *resource = pointer;
	assert(resource && resource->alive);
	return resource->id;
}
int32_t of_other_id(void *pointer) {
	return of_id(pointer);
}
int32_t of_live(void) {
	int32_t count = 0;
	for (int i = 0; i < 256; i++) {
		count += resources[i].alive;
	}
	return count;
}
int32_t of_mark(int32_t code) {
	printf("D%d\n", code);
	fflush(stdout);
	return code;
}
