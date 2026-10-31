// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);
static struct {
	void *pointer;
	int alive;
} allocations[4096];
static struct {
	int32_t id;
	int alive;
} resources[256];
static int next_id;
static int fail_allocation;
static int marker;

void *__wrap_calloc(size_t count, size_t size) {
	assert(count > 0 && size > 0 && next_id < 4095);
	if (fail_allocation) {
		fail_allocation = 0;
		puts("OOM");
		fflush(stdout);
		return NULL;
	}
	void *pointer = __real_calloc(count, size);
	assert(pointer && (uintptr_t)pointer % 16 == 0);
	int id = ++next_id;
	allocations[id].pointer = pointer;
	allocations[id].alive = 1;
	printf("A%d:%zu:%zu\n", id, count, size);
	fflush(stdout);
	return pointer;
}
void __wrap_free(void *pointer) {
	assert(pointer);
	for (int i = next_id; i > 0; i--) {
		if (allocations[i].pointer != pointer || !allocations[i].alive) {
			continue;
		}
		allocations[i].alive = 0;
		printf("F%d\n", i);
		fflush(stdout);
		__real_free(pointer);
		return;
	}
	assert(!"free of a nonlive or untracked buffer");
}
void *bb_resource(int32_t id) {
	assert(id > 0 && id < 256 && !resources[id].alive);
	resources[id].id = id;
	resources[id].alive = 1;
	printf("R+%d\n", id);
	fflush(stdout);
	return &resources[id];
}
int32_t bb_id(void *pointer) {
	for (int i = 1; i < 256; i++) {
		if (pointer == &resources[i]) {
			assert(resources[i].alive);
			return i;
		}
	}
	assert(!"invalid resource");
	return 0;
}
void bb_release(void *pointer) {
	int id = bb_id(pointer);
	resources[id].alive = 0;
	printf("R-%d\n", id);
	fflush(stdout);
}
int32_t bb_mark(int32_t value) {
	printf("M%d\n", value);
	fflush(stdout);
	return value;
}
int32_t bb_live(void) {
	int count = 0;
	for (int i = 1; i <= next_id; i++) {
		count += allocations[i].alive;
	}
	return count;
}
void bb_fail_next(void) {
	fail_allocation = 1;
}
void *bb_pointer(void) {
	return &marker;
}
int32_t bb_f32_zero(float value) {
	uint32_t bits;
	memcpy(&bits, &value, sizeof bits);
	return bits == 0;
}
int32_t bb_f64_zero(double value) {
	uint64_t bits;
	memcpy(&bits, &value, sizeof bits);
	return bits == 0;
}
__attribute__((destructor)) static void verify_final_owners(void) {
	for (int i = 1; i <= next_id; i++) {
		assert(!allocations[i].alive);
	}
	for (int i = 1; i < 256; i++) {
		assert(!resources[i].alive);
	}
}
