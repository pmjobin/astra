// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);

static struct {
	unsigned char *raw;
	size_t bytes;
	int live;
} owners[4096];

static int next_owner, expected_stride, fail_next, token;

static struct {
	int32_t id;
	int live;
} resources[8];

static const uint32_t f32_bits[] = {0, 0x80000000, 1, 0x007fffff, 0x00800000, 0x3f800001, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc01234, 0xffc04321};
static const uint64_t f64_bits[] = {0, UINT64_C(0x8000000000000000), 1, UINT64_C(0x000fffffffffffff), UINT64_C(0x0010000000000000), UINT64_C(0x3ff0000000000001), UINT64_C(0x7fefffffffffffff), UINT64_C(0xffefffffffffffff), UINT64_C(0x7ff0000000000000), UINT64_C(0xfff0000000000000), UINT64_C(0x7ff8000000001234), UINT64_C(0xfff8000000004321)};

void se_expect(int32_t stride) {
	assert(stride > 0);
	expected_stride = stride;
}

void se_fail(void) {
	fail_next = 1;
}

int32_t se_mark(int32_t value) {
	printf("M%d\n", value);
	fflush(stdout);
	return value;
}

void *se_pointer(void) {
	return &token;
}

void *se_resource(int32_t id) {
	assert(id > 0 && id < 8 && !resources[id].live);
	resources[id].id = id;
	resources[id].live = 1;
	printf("R+%d\n", id);
	return &resources[id];
}

void se_drop(void *pointer) {
	for (int i = 1; i < 8; i++) {
		if (pointer == &resources[i]) {
			assert(resources[i].live);
			resources[i].live = 0;
			printf("R-%d\n", i);
			return;
		}
	}
	assert(!"unknown resource");
}

int32_t se_count(int32_t index) {
	const int32_t counts[] = {0, 1, 2, 17};
	assert(index >= 0 && index < 4);
	return counts[index];
}

float se_f32(int32_t index) {
	assert(index >= 0 && index < 12);
	float value;
	memcpy(&value, &f32_bits[index], sizeof value);
	return value;
}

double se_f64(int32_t index) {
	assert(index >= 0 && index < 12);
	double value;
	memcpy(&value, &f64_bits[index], sizeof value);
	return value;
}

int32_t se_check32(float value, int32_t index) {
	uint32_t bits;
	assert(index >= 0 && index < 12);
	memcpy(&bits, &value, sizeof bits);
	return bits == f32_bits[index];
}

int32_t se_check64(double value, int32_t index) {
	uint64_t bits;
	assert(index >= 0 && index < 12);
	memcpy(&bits, &value, sizeof bits);
	return bits == f64_bits[index];
}

void *__wrap_calloc(size_t count, size_t stride) {
	assert(count > 0 && stride > 0 && count <= SIZE_MAX / stride && count * stride < SIZE_MAX - 64);
	assert(next_owner < 4095 && (!expected_stride || stride == (size_t)expected_stride));
	expected_stride = 0;
	if (fail_next) {
		puts("OOM");
		fflush(stdout);
		return NULL;
	}
	unsigned char *raw = __real_calloc(1, count * stride + 64);
	assert(raw && (uintptr_t)raw % 16 == 0);
	memset(raw, 0xa7, 32);
	memset(raw + 32 + count * stride, 0x5b, 32);
	owners[++next_owner].raw = raw;
	owners[next_owner].bytes = count * stride;
	owners[next_owner].live = 1;
	printf("A%d:%zu:%zu\n", next_owner, count, stride);
	fflush(stdout);
	return raw + 32;
}

void __wrap_free(void *pointer) {
	assert(pointer);
	for (int i = next_owner; i > 0; i--) {
		if (!owners[i].live || owners[i].raw + 32 != pointer) {
			continue;
		}
		for (int j = 0; j < 32; j++) {
			assert(owners[i].raw[j] == 0xa7 && owners[i].raw[32 + owners[i].bytes + j] == 0x5b);
		}
		owners[i].live = 0;
		printf("F%d\n", i);
		fflush(stdout);
		__real_free(owners[i].raw);
		return;
	}
	assert(!"free of an untracked or nonlive owner");
}

__attribute__((destructor)) static void verify_final_owners(void) {
	for (int i = 1; i <= next_owner; i++) {
		assert(!owners[i].live);
	}
	for (int i = 1; i < 8; i++) {
		assert(!resources[i].live);
	}
}
