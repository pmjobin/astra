// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Independent observer only: no descriptor dispatch or application cleanup.
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int generated_run(int flag, int seed, float single, double wide, int count);
extern void *__real_calloc(size_t count, size_t size);
extern void __real_free(void *pointer);
static void *allocations[32];
static int live[32], allocated, observed, seed_value, flag_value;
static uint32_t expected_small;
static uint64_t expected_large;
struct bits {
	float single;
	double wide;
};
struct state {
	int count;
	struct bits bits;
};
struct environment {
	struct state state;
	int *buffer;
	int count;
};

void *__wrap_calloc(size_t count, size_t size) {
	assert(allocated < 32);
	void *pointer = __real_calloc(count, size);
	assert(pointer);
	allocations[++allocated] = pointer;
	live[allocated] = 1;
	printf("A%d:%zu:%zu:%p\n", allocated, count, size, pointer);
	return pointer;
}
void __wrap_free(void *pointer) {
	int id = 0;
	for (int i = 1; i <= allocated; i++) {
		if (allocations[i] == pointer && live[i]) {
			id = i;
			break;
		}
	}
	assert(id && live[id]);
	if (id == 2 || id == 4) {
		struct environment *environment = allocations[id - 1];
		int extra = flag_value ? 0 : 1;
		assert(live[id - 1] && environment->state.count == (id == 2 ? seed_value * 3 + extra * 3 : seed_value * 2 + extra));
		assert(environment->buffer[0] == (id == 2 ? seed_value * 3 : seed_value));
	}
	live[id] = 0;
	printf("F%d\n", id);
	__real_free(pointer);
}
void observe_state(int count, float single, double wide, int buffer) {
	uint32_t small;
	uint64_t large;
	memcpy(&small, &single, sizeof small);
	memcpy(&large, &wide, sizeof large);
	assert(small == expected_small && large == expected_large);
	int index = observed++;
	assert(index < 5);
	int extra = flag_value ? 0 : 1;
	int expected[] = {seed_value, seed_value * 2 + extra, seed_value * 3 + extra * 2, seed_value * 2 + extra * 2, seed_value};
	int expected_buffer[] = {0, seed_value, seed_value * 2, seed_value * 2, 0};
	int id = index < 4 ? 1 : 3;
	struct environment *environment = allocations[id];
	assert(live[id] && live[id + 1] && environment->buffer == allocations[id + 1] && environment->count == 3);
	assert(count == expected[index] && buffer == expected_buffer[index] && environment->state.count == count);
	// A whole-record input is a snapshot: changing backing during the body's
	// observer must not change its already captured parameter/result computation.
	environment->state.count = -123456;
	printf("S%d:%d:%d:%08x:%016llx:%p\n", id, count, buffer, small, (unsigned long long)large, (void *)environment);
}
void observe_int(int value) {
	printf("I:%d\n", value);
}
int main(int argc, char **argv) {
	assert(argc == 3);
	flag_value = atoi(argv[1]);
	seed_value = atoi(argv[2]);
	float single;
	double wide;
	uint32_t small = seed_value == 3 ? UINT32_C(0x80000000) : seed_value == 7 ? UINT32_C(0x7fc12345)
	                                                                          : UINT32_C(1);
	uint64_t large = seed_value == 3 ? UINT64_C(0x8000000000000000) : seed_value == 7 ? UINT64_C(0x7ff8123456789abc)
	                                                                                  : UINT64_C(1);
	expected_small = small;
	expected_large = large;
	memcpy(&single, &small, sizeof single);
	memcpy(&wide, &large, sizeof wide);
	int result = generated_run(flag_value, seed_value, single, wide, 3);
	assert(result == seed_value + (flag_value ? 5 : 6) && observed == 5 && allocated == 5);
	for (int i = 1; i <= allocated; i++) {
		assert(!live[i]);
	}
	printf("R:%d\n", result);
	return 0;
}
