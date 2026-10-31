/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <assert.h>
#ifdef USE_SDK
#include "imports16.h"
typedef RECORD_MIXED MixedSample;
typedef RECORD_PACKED PackedScalars;
typedef RECORD_DUO Duo;
typedef RECORD_SINGLE Single;
#define COUNT astra_field_0_count
#define SCALE astra_field_1_scale
#define ENABLED astra_field_2_enabled
#define STAMP astra_field_3_stamp
#define WEIGHT astra_field_4_weight
#define LEFT astra_field_0_left
#define RIGHT astra_field_1_right
#define BIAS astra_field_2_bias
#define SELECT_FIRST astra_field_3_select_first
#define FIRST astra_field_0_first
#define SECOND astra_field_1_second
#define VALUE astra_field_0_value
#define WIDE astra_field_4_wide
#else
/* Independent target-C declarations, including mixed and adjacent fields. */
typedef struct MixedSample {
	int32_t count;
	double scale;
	bool enabled;
	uint64_t stamp;
	float weight;
} MixedSample;
typedef struct PackedScalars {
	int32_t left;
	uint32_t right;
	float bias;
	bool select_first;
	int64_t wide;
} PackedScalars;
typedef struct Duo {
	double first;
	int32_t second;
} Duo;
typedef struct Single {
	double value;
} Single;
typedef struct pod_provider16_handle pod_provider16_handle;
typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
#define COUNT count
#define SCALE scale
#define ENABLED enabled
#define STAMP stamp
#define WEIGHT weight
#define LEFT left
#define RIGHT right
#define BIAS bias
#define SELECT_FIRST select_first
#define FIRST first
#define SECOND second
#define VALUE value
#define WIDE wide
#endif

struct pod_provider16_handle {
	double factor;
	int32_t calls;
	unsigned references;
};
static unsigned created, retired, produced, released;
static void clear(astra_foreign_error *error) {
	assert(error);
	error->domain = 0;
	error->code = 0;
}
static int32_t fail(astra_foreign_error *error) {
	error->domain = 16;
	error->code = -1600;
	return -1600;
}
int32_t pod_provider16_create(MixedSample seed, int32_t offset, pod_provider16_handle **out, astra_foreign_error *error) {
	clear(error);
	assert(seed.COUNT == 3 && seed.ENABLED && seed.STAMP == UINT64_C(9223372036854775809));
	*out = calloc(1, sizeof **out);
	assert(*out);
	(*out)->factor = seed.SCALE;
	(*out)->calls = seed.COUNT + offset;
	(*out)->references = 1;
	++created;
	return 0;
}
#ifdef EXPECT_SHARED
uint32_t pod_provider16_release(pod_provider16_handle *self) {
	unsigned n = --self->references;
	if (!n) {
		++retired;
		free(self);
	}
	return n;
}
#else
int32_t pod_provider16_destroy(pod_provider16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner && *owner);
	++retired;
	free(*owner);
	*owner = NULL;
	return 0;
}
#endif
int32_t pod_provider16_adjust(pod_provider16_handle *self, MixedSample input, double delta, PackedScalars offsets, int32_t *calls, int32_t mode, MixedSample *out, astra_foreign_error *error) {
	assert(self && calls && out && offsets.RIGHT == UINT32_C(4000000000) && offsets.WIDE == INT64_C(-5000000000) && offsets.SELECT_FIRST);
	clear(error);
	*out = input;
	out->COUNT = input.COUNT + offsets.LEFT + self->calls;
	out->SCALE = input.SCALE * self->factor + delta;
	out->ENABLED = !input.ENABLED;
	out->WEIGHT = input.WEIGHT + offsets.BIAS;
	*calls = ++self->calls;
	if (mode) {
		return fail(error);
	}
	return 0;
}
int32_t pod_provider16_pair(pod_provider16_handle *self, Duo input, int32_t extra, Duo *out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = input;
	out->FIRST += self->factor;
	out->SECOND += extra;
	return 0;
}
int32_t pod_provider16_one(pod_provider16_handle *self, Single input, Single *out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	out->VALUE = input.VALUE + self->factor;
	return 0;
}
int32_t pod_provider16_snapshot(pod_provider16_handle *self, MixedSample input, const uint8_t *bytes, int32_t length, uint8_t *output, int32_t capacity, int32_t *count, int32_t mode, uint8_t **out, int32_t *out_length, astra_foreign_error *error) {
	assert(self && bytes && length == 3 && output && capacity == 4 && count && out && out_length);
	clear(error);
	*out = malloc(3);
	assert(*out);
	++produced;
	for (int32_t i = 0; i < length; ++i) {
		(*out)[i] = (uint8_t)(bytes[i] + input.COUNT);
	}
	*out_length = 3;
	output[0] = 31;
	output[1] = 32;
	*count = 2;
	if (mode == 1) {
		return fail(error);
	}
	if (mode == 2) {
		*count = capacity + 1;
	}
	return 0;
}
int32_t pod_provider16_bytes_release(uint8_t **out, int32_t *length, astra_foreign_error *error) {
	clear(error);
	assert(out && length && *out);
	memset(*out, 0xdd, 3);
	free(*out);
	*out = NULL;
	*length = 0;
	++released;
	return 0;
}
extern int32_t import_records16_run(void);
int main(void) {
	int32_t result = import_records16_run();
	if (result) {
		fprintf(stderr, "POD imports returned %d\n", result);
		return 1;
	}
	assert(created == 1 && retired == 1 && produced == 3 && released == 3);
	puts("PASS typed C Class imports and independent scalar POD values");
	return 0;
}
