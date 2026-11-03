// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static volatile int32_t inputs[] = {17, 20, 42};
static int live_resources;

int32_t lazy_input(int32_t rank) {
	assert(rank >= 0 && rank < 3);
	return inputs[rank];
}

int32_t lazy_event(int32_t code, int32_t value) {
	assert(putchar(code) != EOF);
	assert(fflush(stdout) == 0);
	return value;
}

void *lazy_create(int32_t code) {
	int32_t *value = malloc(sizeof *value);
	assert(value);
	*value = code;
	live_resources++;
	return value;
}

void lazy_destroy(void *pointer) {
	int32_t *value = pointer;
	assert(value && live_resources > 0);
	lazy_event(*value, 0);
	live_resources--;
	free(value);
}

int32_t lazy_live(void) {
	return live_resources;
}

float lazy_f32(int32_t rank) {
	const uint32_t bits[] = {0x80000000U, 1U, 0x7f800000U, 0x7fc12345U};
	float value;
	assert(rank >= 0 && rank < 4);
	memcpy(&value, &bits[rank], sizeof value);
	return value;
}

double lazy_f64(int32_t rank) {
	const uint64_t bits[] = {UINT64_C(0x8000000000000000), 1U, UINT64_C(0x7ff0000000000000), UINT64_C(0x7ff8123456789abc)};
	double value;
	assert(rank >= 0 && rank < 4);
	memcpy(&value, &bits[rank], sizeof value);
	return value;
}

int32_t lazy_f32_bits(float value, int32_t rank) {
	const uint32_t bits[] = {0x80000000U, 1U, 0x7f800000U, 0x7fc12345U};
	uint32_t actual;
	memcpy(&actual, &value, sizeof actual);
	return actual == bits[rank];
}

int32_t lazy_f64_bits(double value, int32_t rank) {
	const uint64_t bits[] = {UINT64_C(0x8000000000000000), 1U, UINT64_C(0x7ff0000000000000), UINT64_C(0x7ff8123456789abc)};
	uint64_t actual;
	memcpy(&actual, &value, sizeof actual);
	return actual == bits[rank];
}
