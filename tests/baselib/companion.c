/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <fenv.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xmmintrin.h>
#include "matrix.h"

int32_t test_integer(int32_t type, int32_t row, int32_t column) {
	return integer_cases[type][row][column];
}
int32_t test_integer_count(void) {
	return INTEGER_COUNT;
}

#define FLOAT_TESTS(WIDTH, TYPE, UINT, LIB_SUFFIX) \
TYPE test_input##WIDTH(int32_t row) { TYPE value; memcpy(&value, &inputs##WIDTH[row], sizeof(value)); return value; } \
int32_t test_count##WIDTH(void) { return (int32_t)(sizeof(inputs##WIDTH) / sizeof(inputs##WIDTH[0])); } \
int32_t test_category##WIDTH(int32_t row) { return categories##WIDTH[row]; } \
int32_t test_pair_count##WIDTH(void) { return (int32_t)(sizeof(pairs##WIDTH) / sizeof(pairs##WIDTH[0])); } \
TYPE test_pair_input##WIDTH(int32_t row, int32_t column) { TYPE value; memcpy(&value, &pairs##WIDTH[row][column], sizeof(value)); return value; } \
int32_t test_pair_check##WIDTH(int32_t row, int32_t column, TYPE value) { UINT bits; memcpy(&bits, &value, sizeof(bits)); return bits == pairs##WIDTH[row][column] ? 0 : 1; } \
int32_t test_clamp_count##WIDTH(void) { return (int32_t)(sizeof(clamps##WIDTH) / sizeof(clamps##WIDTH[0])); } \
TYPE test_clamp_input##WIDTH(int32_t row, int32_t column) { TYPE value; memcpy(&value, &clamps##WIDTH[row][column], sizeof(value)); return value; } \
int32_t test_clamp_check##WIDTH(int32_t row, TYPE value) { UINT bits; memcpy(&bits, &value, sizeof(bits)); return bits == clamps##WIDTH[row][3] ? 0 : 1; } \
int32_t test_math_check##WIDTH(int32_t row, int32_t operation, TYPE value) { \
	UINT bits; memcpy(&bits, &value, sizeof(bits)); \
	if (math_nan##WIDTH[row][operation]) { return isnan(value) ? 0 : 1; } \
	return bits == math_bits##WIDTH[row][operation] ? 0 : 1; \
} \
int32_t test_math_provider##WIDTH(int32_t row, int32_t operation, TYPE value) { \
	TYPE input = test_input##WIDTH(row), expected; \
	switch (operation) { \
		case 0: expected = sqrt##LIB_SUFFIX(input); break; \
		case 1: expected = floor##LIB_SUFFIX(input); break; \
		case 2: expected = ceil##LIB_SUFFIX(input); break; \
		case 3: expected = trunc##LIB_SUFFIX(input); break; \
		default: expected = fabs##LIB_SUFFIX(input); break; \
	} \
	if (isnan(expected)) { return isnan(value) ? 0 : 1; } \
	UINT actual_bits, expected_bits; memcpy(&actual_bits, &value, sizeof(actual_bits)); memcpy(&expected_bits, &expected, sizeof(expected_bits)); \
	return actual_bits == expected_bits ? 0 : 1; \
}

FLOAT_TESTS(32, float, uint32_t, f)
FLOAT_TESTS(64, double, uint64_t, )

int32_t test_environment(void) {
	/* Inspect without changing rounding, FTZ, DAZ, masks or locale. */
	unsigned control = _mm_getcsr();
	return fegetround() == FE_TONEAREST && (control & 0xe040u) == 0 && (control & 0x1f80u) == 0x1f80u ? 0 : 1;
}

int32_t test_mark(int32_t value) {
	printf("E%" PRId32 "\n", value);
	fflush(stdout);
	return value;
}
float test_nan32(void) {
	uint32_t bits = UINT32_C(0xffc0005b);
	float value;
	memcpy(&value, &bits, sizeof(value));
	return value;
}
double test_nan64(void) {
	uint64_t bits = UINT64_C(0xfff800000000005b);
	double value;
	memcpy(&value, &bits, sizeof(value));
	return value;
}

struct test_resource {
	int32_t id;
	int live;
};
static struct test_resource test_slot;
void *test_acquire(int32_t id) {
	if (test_slot.live) {
		abort();
	}
	test_slot.id = id;
	test_slot.live = 1;
	test_mark(id);
	return &test_slot;
}
void test_release(void *address) {
	if (address != &test_slot || !test_slot.live) {
		abort();
	}
	test_slot.live = 0;
	test_mark(-test_slot.id);
}

void *__real_calloc(size_t count, size_t width);
void __real_free(void *pointer);
void *__wrap_calloc(size_t count, size_t width) {
	test_mark(90);
	return __real_calloc(count, width);
}
void __wrap_free(void *pointer) {
	test_mark(-90);
	__real_free(pointer);
}
