// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <float.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

_Static_assert(CHAR_BIT == 8 && sizeof(double) == 8 && sizeof(uint64_t) == 8, "64-bit double storage required");
_Static_assert(FLT_RADIX == 2 && DBL_MANT_DIG == 53, "binary64 radix and precision required");
_Static_assert(DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024, "binary64 exponent range required");
_Static_assert(DBL_HAS_SUBNORM == 1, "binary64 subnormals required");
_Static_assert(sizeof(float) == 4 && sizeof(uint32_t) == 4, "32-bit float storage required");
_Static_assert(FLT_MANT_DIG == 24 && FLT_MIN_EXP == -125 && FLT_MAX_EXP == 128 && FLT_HAS_SUBNORM == 1, "binary32 precision, exponent range and subnormals required");

// All bit oracles use byte transfer. No floating arithmetic in transport paths.
static const uint64_t patterns[] = {
    UINT64_C(0x0000000000000000), UINT64_C(0x8000000000000000),
    UINT64_C(0x0000000000000001), UINT64_C(0x000fffffffffffff),
    UINT64_C(0x0010000000000000), UINT64_C(0x3ff0000000000001),
    UINT64_C(0xc00921fb54442d18), UINT64_C(0x7fefffffffffffff),
    UINT64_C(0x7ff0000000000000), UINT64_C(0xfff0000000000000),
    UINT64_C(0x7ff8000000001234), UINT64_C(0xfff8000000005678)};

static uint64_t bits(double value) {
	uint64_t result;
	memcpy(&result, &value, sizeof(result));
	return result;
}

int32_t c_count(void) {
	return (int32_t)(sizeof(patterns) / sizeof(patterns[0]));
}

double c_pattern(int32_t index) {
	double value;
	memcpy(&value, &patterns[index], sizeof(value));
	return value;
}

int32_t c_check(int32_t index, double value) {
	return bits(value) == patterns[index] ? 0 : 1;
}

double c_echo(double value) {
	return value;
}

double c_produce(void) {
	return c_pattern(5);
}

static double consumed;

void c_consume(double value) {
	consumed = value;
}

int32_t c_consumed(int32_t index) {
	return c_check(index, consumed);
}

static int token;

void *c_token(void) {
	return &token;
}

int32_t c_mix(int32_t tag, float small, double precise, void *pointer, double second, int32_t tail) {
	return tag != 7 || small != 1.25f || bits(precise) != patterns[5] || pointer != &token || bits(second) != patterns[3] || tail != 9;
}

double c_many(double a, double b, double c, double d, double e, double f, double g, double h, double i, double j) {
	double values[] = {a, b, c, d, e, f, g, h, i, j};
	for (int n = 0; n < 10; n++) {
		if (bits(values[n]) != patterns[n]) {
			return c_pattern(0);
		}
	}
	return j;
}

static int32_t trace;

int32_t c_int_effect(int32_t step) {
	trace = trace * 10 + step;
	return 7;
}

double c_f64_effect(int32_t step) {
	trace = trace * 10 + step;
	return c_pattern(5);
}

void *c_ptr_effect(int32_t step) {
	trace = trace * 10 + step;
	return &token;
}

int32_t c_trace(void) {
	return trace;
}

int32_t c_order(int32_t tag, float small, double value, void *pointer, int32_t tail) {
	return tag != 7 || small != 0x1.000002p0f || bits(value) != patterns[5] || pointer != &token || tail != 7 || trace != 12345;
}

int32_t c_later(void) {
	puts("later argument executed");
	return 7;
}

double c_later_f64(void) {
	puts("later f64 argument executed");
	return c_pattern(5);
}

// Separate practical arithmetic example; never used as a transport oracle.
double c_half(double value) {
	return value / 2.0;
}

#ifdef ASTRA_TEST_REVERSE64
extern double astra_echo(double value);
extern double astra_bridge(double value);
extern void astra_consume(double value);
extern double astra_produce(void);

double c_chain(double value) {
	return astra_bridge(value);
}

int32_t c_reverse_matrix(void) {
	for (int32_t i = 0; i < c_count(); i++) {
		if (c_check(i, astra_echo(c_pattern(i))) || c_check(i, astra_bridge(c_pattern(i)))) {
			return 1;
		}
		astra_consume(c_pattern(i));
		if (c_consumed(i)) {
			return 2;
		}
	}
	return c_check(5, astra_produce());
}

#endif

static const uint32_t patterns32[] = {
    UINT32_C(0x00000000), UINT32_C(0x80000000), UINT32_C(0x00000001),
    UINT32_C(0x007fffff), UINT32_C(0x00800000), UINT32_C(0x3f800001),
    UINT32_C(0xc0490fdb), UINT32_C(0x7f7fffff), UINT32_C(0x7f800000),
    UINT32_C(0xff800000), UINT32_C(0x7fc01234), UINT32_C(0xffc05678)};

static uint32_t bits32(float value) {
	uint32_t result;
	memcpy(&result, &value, sizeof(result));
	return result;
}

int32_t c_count32(void) {
	return (int32_t)(sizeof(patterns32) / sizeof(patterns32[0]));
}

float c_pattern32(int32_t index) {
	float value;
	memcpy(&value, &patterns32[index], sizeof(value));
	return value;
}

int32_t c_check32(int32_t index, float value) {
	return bits32(value) == patterns32[index] ? 0 : 1;
}

float c_echo32(float value) {
	return value;
}

float c_produce32(void) {
	return c_pattern32(5);
}

float c_many32(float a, float b, float c, float d, float e, float f, float g, float h, float i, float j) {
	float values[] = {a, b, c, d, e, f, g, h, i, j};
	for (int n = 0; n < 10; n++) {
		if (bits32(values[n]) != patterns32[n]) {
			return c_pattern32(0);
		}
	}
	return j;
}

static float consumed32;

void c_consume32(float value) {
	consumed32 = value;
}

int32_t c_consumed32(int32_t index) {
	return c_check32(index, consumed32);
}

float c_f32_effect(int32_t step) {
	trace = trace * 10 + step;
	return c_pattern32(5);
}

#ifdef ASTRA_TEST_REVERSE32
extern float astra_echo32(float value);
extern float astra_bridge32(float value);
extern void astra_consume32(float value);
extern float astra_produce32(void);

float c_chain32(float value) {
	return astra_bridge32(value);
}

int32_t c_reverse_matrix32(void) {
	for (int32_t i = 0; i < c_count32(); i++) {
		if (c_check32(i, astra_echo32(c_pattern32(i))) || c_check32(i, astra_bridge32(c_pattern32(i)))) {
			return 1;
		}
		astra_consume32(c_pattern32(i));
		if (c_consumed32(i)) {
			return 2;
		}
	}
	return c_check32(5, astra_produce32());
}

#endif

int32_t c_finish(int32_t index, float small, double precise, void *pointer) {
	return c_check32(index, small) || c_check(index, precise) || pointer != &token;
}

#ifdef ASTRA_TEST_MIXED
extern int32_t astra_mixed(int32_t index, float small, double precise, void *pointer);

int32_t c_chain_mixed(int32_t index, float small, double precise, void *pointer) {
	return astra_mixed(index, small, precise, pointer);
}

#endif
