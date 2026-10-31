// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include <stdlib.h>

static const uint64_t cases[] = {
    0, UINT64_C(0x8000000000000000), UINT64_C(0x3ff0000000000000),
    UINT64_C(0xbff0000000000000), 1, UINT64_C(0x0010000000000000),
    UINT64_C(0x7ff0000000000000), UINT64_C(0xfff0000000000000),
    UINT64_C(0x7ff8000000001234), UINT64_C(0x3ff0000002000000),
    UINT64_C(0x3feffffffc000000), UINT64_C(0x7fefffffffffffff),
    UINT64_C(0x3fd5555555555555), UINT64_C(0x4008000000000000),
    UINT64_C(0x3ff0000000000001), UINT64_C(0x7ff0000000000001)};
static double edge(int32_t i) {
	double x;
	uint64_t b = cases[(uint32_t)i % 16];
	memcpy(&x, &b, 8);
	return x;
}
double fp_input(int32_t i) {
	return edge(i);
}
float fp_input32(int32_t i) {
	if ((uint32_t)i % 16 == 9) return 1.0001220703125f;
	if ((uint32_t)i % 16 == 10) return 0.9998779296875f;
	return (float)edge(i);
}
static int fused_observations;
struct statistics {
	uint64_t count, nonfinite, max_ulp, zero_reference_differences;
	double max_absolute, max_relative;
};
static struct statistics statistics[2][5];
static uint64_t ordered64(double value) {
	uint64_t bits;
	memcpy(&bits, &value, 8);
	return bits >> 63 ? ~bits : bits | UINT64_C(0x8000000000000000);
}
static uint32_t ordered32(float value) {
	uint32_t bits;
	memcpy(&bits, &value, 4);
	return bits >> 31 ? ~bits : bits | UINT32_C(0x80000000);
}
static void record(int width, int mode, double expected, double value) {
	struct statistics *s = &statistics[width][mode];
	s->count++;
	if (!isfinite(expected) || !isfinite(value)) {
		s->nonfinite++;
		return;
	}
	uint64_t a = width ? ordered64(expected) : ordered32((float)expected), b = width ? ordered64(value) : ordered32((float)value);
	uint64_t ulp = a > b ? a - b : b - a;
	double absolute = fabs(value - expected);
	if (ulp > s->max_ulp) s->max_ulp = ulp;
	if (absolute > s->max_absolute) s->max_absolute = absolute;
	if (expected != 0) {
		double relative = absolute / fabs(expected);
		if (relative > s->max_relative) s->max_relative = relative;
	} else if (value != 0)
		s->zero_reference_differences++;
}
static int same(double a, double b) {
	uint64_t x, y;
	memcpy(&x, &a, 8);
	memcpy(&y, &b, 8);
	return (isnan(a) && isnan(b)) || x == y;
}
static int same32(float a, float b) {
	uint32_t x, y;
	memcpy(&x, &a, 4);
	memcpy(&y, &b, 4);
	return (isnan(a) && isnan(b)) || x == y;
}
int32_t fp_observe(int32_t mode, int32_t i, double a, double b, double c, double value) {
	volatile double product = a * b;
	volatile double sum = a + b;
	double reference = mode == 2 ? sum + c : mode == 3 ? a / b
	                                                   : product + c;
	int ok = same(value, reference);
	if (mode == 1) {
		ok |= same(value, fma(a, b, c));
		if (!same(value, reference) && same(value, fma(a, b, c))) fused_observations++;
	}
	if (mode == 2 && isfinite(reference) && isfinite(value)) ok |= fabsl((long double)reference - value) <= 8 * DBL_EPSILON * (fabsl((long double)a) + fabsl((long double)b) + fabsl((long double)c));
	if (mode == 3 && isfinite(reference) && isfinite(value)) ok |= fabs(reference - value) <= 4 * DBL_EPSILON * fabs(reference);
	if (mode == 4 && reference == 0 && value == 0) ok = 1;
	if (!ok) fprintf(stderr, "f64 mode=%d case=%d observed=%a expected=%a\n", mode, i, value, reference);
	if (ok) record(1, mode, reference, value);
	return ok ? 0 : 1;
}
int32_t fp_observe32(int32_t mode, int32_t i, float a, float b, float c, float value) {
	volatile float product = a * b;
	volatile float sum = a + b;
	float reference = mode == 2 ? sum + c : mode == 3 ? a / b
	                                                  : product + c;
	int ok = same32(value, reference);
	if (mode == 1) {
		ok |= same32(value, fmaf(a, b, c));
		if (!same32(value, reference) && same32(value, fmaf(a, b, c))) fused_observations++;
	}
	if (mode == 2 && isfinite(reference) && isfinite(value)) ok |= fabsl((long double)reference - value) <= 8 * FLT_EPSILON * (fabsl((long double)a) + fabsl((long double)b) + fabsl((long double)c));
	if (mode == 3 && isfinite(reference) && isfinite(value)) ok |= fabsf(reference - value) <= 4 * FLT_EPSILON * fabsf(reference);
	if (mode == 4 && reference == 0 && value == 0) ok = 1;
	if (!ok) fprintf(stderr, "f32 mode=%d case=%d observed=%a expected=%a\n", mode, i, (double)value, (double)reference);
	if (ok) record(0, mode, reference, value);
	return ok ? 0 : 1;
}
int32_t fp_finished(int32_t count) {
	const char *path = getenv("ASTRA_FP_METRICS");
	if (path) {
		FILE *file = fopen(path, "w");
		if (!file) abort();
		fprintf(file, "{\"fused_observations\":%d,\"modes\":[", fused_observations);
		for (int width = 0; width < 2; width++) {
			for (int mode = 0; mode < 5; mode++) {
				struct statistics *s = &statistics[width][mode];
				fprintf(file, "%s{\"width\":%d,\"mode\":%d,\"count\":%llu,\"nonfinite\":%llu,\"max_ulp_from_strict\":%llu,\"max_absolute\":%.17g,\"max_relative_nonzero_reference\":%.17g,\"zero_reference_differences\":%llu}",
				        width || mode ? "," : "", width ? 64 : 32, mode, (unsigned long long)s->count, (unsigned long long)s->nonfinite, (unsigned long long)s->max_ulp, s->max_absolute, s->max_relative, (unsigned long long)s->zero_reference_differences);
			}
		}
		fputs("]}\n", file);
		if (fclose(file) != 0) abort();
	}
	printf("floating-oracle:%d observations\n", count);
	return 0;
}
int32_t fp_require_fused(int32_t minimum) {
	if (fused_observations < minimum) {
		fprintf(stderr, "no fused numerical difference observed\n");
		return 1;
	}
	puts("fused-contraction-observed");
	return 0;
}
int32_t fp_copy_check(int32_t index, double value) {
	double expected = edge(index);
	uint64_t a, b;
	memcpy(&a, &expected, 8);
	memcpy(&b, &value, 8);
	return a == b ? 0 : 1;
}
int32_t fp_copy_check32(int32_t index, float value) {
	float expected = fp_input32(index);
	uint32_t a, b;
	memcpy(&a, &expected, 4);
	memcpy(&b, &value, 4);
	return a == b ? 0 : 1;
}
int32_t fp_dot_check(double a0, double a1, double b0, double b1, double value) {
	volatile double first = a0 * b0;
	volatile double second = a1 * b1;
	volatile double sum = 0.0 + first;
	double expected = sum + second;
	return same(value, expected) ? 0 : 1;
}
