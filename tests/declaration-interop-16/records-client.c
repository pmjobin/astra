/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <pthread.h>
#ifdef USE_SDK
#include "record16.h"
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
#else
/* Independent target-C declarations, including mixed and adjacent fields. */
typedef struct MixedSample { int32_t count; double scale; bool enabled; uint64_t stamp; float weight; } MixedSample;
typedef struct PackedScalars { int32_t left; uint32_t right; float bias; bool select_first; } PackedScalars;
typedef struct Duo { double first; int32_t second; } Duo;
typedef struct Single { double value; } Single;
typedef struct record16_handle record16_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t record16_create(MixedSample, int32_t, record16_handle **, astra_foreign_error *);
int32_t record16_adjust(record16_handle *, MixedSample, double, PackedScalars, MixedSample *, astra_foreign_error *);
int32_t record16_pair(record16_handle *, Duo, int32_t, Duo *, astra_foreign_error *);
int32_t record16_one(record16_handle *, Single, Single *, astra_foreign_error *);
int32_t record16_get_processed(record16_handle *, int32_t *, astra_foreign_error *);
#ifdef EXPECT_SHARED
uint32_t record16_release(record16_handle *);
#else
int32_t record16_destroy(record16_handle **, astra_foreign_error *);
#endif
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
#endif
_Static_assert(sizeof(MixedSample) == 40 && _Alignof(MixedSample) == 8, "independent mixed layout");
_Static_assert(offsetof(MixedSample, SCALE) == 8 && offsetof(MixedSample, ENABLED) == 16 && offsetof(MixedSample, STAMP) == 24 && offsetof(MixedSample, WEIGHT) == 32, "independent mixed offsets");
_Static_assert(sizeof(PackedScalars) == 16 && _Alignof(PackedScalars) == 4 && offsetof(PackedScalars, BIAS) == 8 && offsetof(PackedScalars, SELECT_FIRST) == 12, "independent adjacent scalar layout");
_Static_assert(sizeof(Duo) == 16 && _Alignof(Duo) == 8 && offsetof(Duo, SECOND) == 8, "independent generic application layout");
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
#define STATUS(c) ((int32_t)UINT32_C(c))
static int retired;
int32_t record16_retired(int32_t calls) { CHECK(calls == 11); ++retired; return 0; }
static void *wrong_thread(void *argument) {
	MixedSample input = {1, 2.0, true, 9, 3.0f}, result = {99, 99, true, 99, 99};
	PackedScalars packed = {1, UINT32_MAX, 2.0f, true}; astra_foreign_error error = {99, 99};
	CHECK(record16_adjust(argument, input, 1.0, packed, &result, &error) == STATUS(0x8001010e));
	CHECK(result.COUNT == 0 && result.SCALE == 0 && !result.ENABLED && result.STAMP == 0 && result.WEIGHT == 0 && error.code == STATUS(0x8001010e));
	return NULL;
}
int main(void) {
	MixedSample seed = {3, 2.5, true, UINT64_MAX, 5.0f}; record16_handle *owner = NULL; astra_foreign_error error = {99, 99};
	CHECK(record16_create(seed, 7, &owner, &error) == 0 && owner != NULL);
	MixedSample input = {5, 4.0, false, UINT64_MAX, -0.0f}, result = {0};
	PackedScalars offsets = {2, UINT32_MAX, 1.25f, true};
	CHECK(record16_adjust(owner, input, 0.75, offsets, &result, &error) == 0);
	CHECK(result.COUNT == 17 && result.SCALE == 10.75 && result.ENABLED && result.STAMP == UINT64_MAX && result.WEIGHT == 1.25f);
	CHECK(input.COUNT == 5 && input.SCALE == 4.0 && !input.ENABLED && signbit(input.WEIGHT));
	Duo pair = {1.5, 8}, pair_result = {0};
	CHECK(record16_pair(owner, pair, -4, &pair_result, &error) == 0 && pair_result.FIRST == 4.0 && pair_result.SECOND == 4);
	Single one = {0}, one_result = {0}; CHECK(record16_one(owner, one, &one_result, &error) == 0 && one_result.VALUE == 2.5);
	CHECK(record16_adjust(owner, input, 0.75, offsets, NULL, &error) == STATUS(0x80004003));
	pthread_t worker; CHECK(pthread_create(&worker, NULL, wrong_thread, owner) == 0); CHECK(pthread_join(worker, NULL) == 0);
	int32_t calls = 0; CHECK(record16_get_processed(owner, &calls, &error) == 0 && calls == 11);
#ifdef EXPECT_SHARED
	(void)record16_release(owner);
#else
	CHECK(record16_destroy(&owner, &error) == 0 && owner == NULL);
#endif
	CHECK(retired == 1);
	puts("PASS declaration-derived mixed POD values, closed records and actual native algorithms");
	return 0;
}
