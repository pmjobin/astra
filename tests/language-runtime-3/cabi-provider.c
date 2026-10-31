// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct CRecord {
	uint8_t tag;
	int64_t signed_value;
	uint16_t small;
	uint64_t wide;
	size_t count;
	ptrdiff_t delta;
	double measure;
	float ratio;
	int32_t total;
	uint32_t flags;
	int8_t negative;
	int16_t narrow;
};
struct Capture {
	int64_t total;
	int32_t invocations;
	int32_t bias;
};
#define OFFSET(type, field, value) _Static_assert(offsetof(struct type, field) == value, #type "." #field)
_Static_assert(sizeof(struct CRecord) == 72 && _Alignof(struct CRecord) == 8, "CRecord layout");
_Static_assert(sizeof(struct Capture) == 16 && _Alignof(struct Capture) == 8, "Capture layout");
OFFSET(CRecord, tag, 0);
OFFSET(CRecord, signed_value, 8);
OFFSET(CRecord, small, 16);
OFFSET(CRecord, wide, 24);
OFFSET(CRecord, count, 32);
OFFSET(CRecord, delta, 40);
OFFSET(CRecord, measure, 48);
OFFSET(CRecord, ratio, 56);
OFFSET(CRecord, total, 60);
OFFSET(CRecord, flags, 64);
OFFSET(CRecord, negative, 68);
OFFSET(CRecord, narrow, 70);
OFFSET(Capture, total, 0);
OFFSET(Capture, invocations, 8);
OFFSET(Capture, bias, 12);

static void expected_record(struct CRecord *p, int32_t seed) {
	memset(p, 0, sizeof *p); // Define every padding byte before whole-object comparison.
	p->tag = 201;
	p->signed_value = INT64_MIN + 1;
	p->small = 54321;
	p->wide = UINT64_MAX - 1;
	p->count = 987654;
	p->delta = -19;
	p->measure = 3.5;
	p->ratio = 1.5f;
	p->total = seed + 9;
	p->flags = UINT32_C(2147483649);
	p->negative = -127;
	p->narrow = -12345;
}
int32_t produce_record(struct CRecord *p, int32_t seed) {
	if (!p || p->tag != 7 || p->signed_value != INT64_MIN || p->small != UINT16_MAX ||
	    p->wide != UINT64_MAX || p->count != 123456 || p->delta != -17 || p->measure != 2.5 ||
	    p->ratio != 1.25f || p->total != seed || p->flags != UINT32_MAX || p->negative != INT8_MIN || p->narrow != INT16_MIN) return 11;
	expected_record(p, seed);
	return 0;
}
int32_t verify_record(struct CRecord *p, int32_t seed) {
	struct CRecord expected;
	expected_record(&expected, seed);
	return memcmp(p, &expected, sizeof expected) == 0 ? 0 : 12;
}
static int32_t calls;
void clear_callback_calls(void) {
	calls = 0;
}
int32_t callback_calls(void) {
	return calls;
}
int32_t invoke_sync(int32_t (*callback)(void *, int32_t), struct Capture *context, int32_t input) {
	if (!callback || !context) return -1;
	++calls;
	int32_t before = context->invocations;
	for (int32_t i = 0; i < 3; ++i) {
		if (callback(context, input + i) != before + i + 1) return -2;
	}
	return context->invocations;
}
int32_t invoke_noncapturing(int32_t (*callback)(void *, int32_t), struct Capture *context, int32_t input) {
	return callback(context, input) + callback(context, input + 1);
}
#ifdef CABI_LAYOUT_MAIN
int main(void) {
	printf("CRecord=72/8 offsets=0,8,16,24,32,40,48,56,60,64,68,70 Capture=16/8 offsets=0,8,12\n");
	return 0;
}
#endif
