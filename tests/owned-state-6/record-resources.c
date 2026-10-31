// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Host Resource observer: real independent allocations and distinct destructors.
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

struct resource {
	int32_t id;
	int domain;
};
static struct resource *active[256];

static void *acquire(int32_t id, int domain) {
	printf("+%d\n", id);
	if (id == 0) {
		return NULL;
	}
	assert(id > 0 && id < 256 && active[id] == NULL);
	struct resource *value = malloc(sizeof *value);
	assert(value != NULL);
	*value = (struct resource){id, domain};
	active[id] = value;
	return value;
}
void *of_make(int32_t id) {
	return acquire(id, 0);
}
void *of_make_other(int32_t id) {
	return acquire(id, 1);
}
static void retire(void *pointer, int domain) {
	struct resource *value = pointer;
	assert(value && value->domain == domain && active[value->id] == value);
	printf("-%d\n", value->id);
	active[value->id] = NULL;
	free(value);
}
void of_release(void *value) {
	retire(value, 0);
}
void of_release_other(void *value) {
	retire(value, 1);
}
int32_t of_id(void *pointer) {
	struct resource *value = pointer;
	assert(value && active[value->id] == value);
	return value->id;
}
int32_t of_other_id(void *pointer) {
	return of_id(pointer);
}
int32_t of_live(void) {
	int32_t result = 0;
	for (int i = 0; i < 256; i++) {
		result += active[i] != NULL;
	}
	return result;
}
int32_t of_mark(int32_t code) {
	printf("D%d\n", code);
	return code;
}
