// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only interposition: production allocation remains direct calloc/free.
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);

static struct {
	void *pointer;
	int live;
} allocations[128];

static int generation, failing;

static struct {
	int id;
	int live;
} resources[4];

static int live_count(void) {
	int count = 0;
	for (int i = 1; i <= generation; ++i) {
		count += allocations[i].live;
	}
	return count;
}

void *__wrap_calloc(size_t count, size_t size) {
	assert(count && size && generation < 127);
	printf("Q%zu:%zu\n", count, size);
	fflush(stdout);
	if (failing) {
		failing = 0;
		puts("NULL");
		fflush(stdout);
		return NULL;
	}
	void *pointer = __real_calloc(count, size);
	assert(pointer);
	++generation;
	allocations[generation].pointer = pointer;
	allocations[generation].live = 1;
	printf("A%d\n", generation);
	fflush(stdout);
	return pointer;
}

void __wrap_free(void *pointer) {
	assert(pointer);
	for (int i = generation; i > 0; --i) {
		if (allocations[i].pointer != pointer || !allocations[i].live) {
			continue;
		}
		allocations[i].live = 0;
		printf("F%d\n", i);
		fflush(stdout);
		__real_free(pointer);
		return;
	}
	assert(!"free of dead/untracked owner");
}

int32_t af_case(void) {
	const char *value = getenv("ASTRA_ALLOC_CASE");
	assert(value);
	return (int32_t)strtol(value, NULL, 10);
}

void af_fail(void) {
	failing = 1;
}

int32_t af_count(int32_t value) {
	printf("C%d\n", value);
	fflush(stdout);
	return value;
}

int32_t af_arg(int32_t index, int32_t value) {
	printf("G%d:%d\n", index, value);
	fflush(stdout);
	return value;
}

void af_action(int32_t code, int32_t count) {
	printf("H%d:%d:L%d\n", code, count, live_count());
	fflush(stdout);
}

void af_return(void) {
	puts("RET");
	fflush(stdout);
}

void af_next(void) {
	puts("NEXT");
	fflush(stdout);
}

void af_assert(int32_t actual, int32_t expected) {
	assert(actual == expected);
}

void af_c_report(int32_t code, int32_t count) {
	af_action(code, count);
	af_return();
}

void af_exit(int32_t code, int32_t count) {
	af_action(code, count);
	_Exit(23);
}

void *af_resource(int32_t id) {
	assert(id > 0 && id < 4 && !resources[id].live);
	resources[id].id = id;
	resources[id].live = 1;
	printf("R+%d\n", id);
	fflush(stdout);
	return &resources[id];
}

void af_drop(void *pointer) {
	for (int i = 1; i < 4; ++i) {
		if (pointer == &resources[i]) {
			assert(resources[i].live);
			resources[i].live = 0;
			printf("R-%d\n", i);
			fflush(stdout);
			return;
		}
	}
	assert(!"unknown resource");
}

__attribute__((destructor)) static void normal_cleanup(void) {
	assert(live_count() == 0);
	for (int i = 1; i < 4; ++i) {
		assert(!resources[i].live);
	}
}
