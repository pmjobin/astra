// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

#ifndef APP_ID
#error APP_ID is required
#endif
#define SAMPLES 48003
static double expected[SAMPLES];
static int initialized;
static FILE *output;
static int observations;
static double max_absolute;
static double max_relative;
static uint64_t digest = UINT64_C(14695981039346656037);

double numerical_sample(int32_t i) {
	if (i % 24000 == 0) return DBL_TRUE_MIN;
	if (i % 24000 == 1) return -DBL_TRUE_MIN;
	if (i % 24000 == 2) return DBL_MIN;
	return ((i * 17 + 13) % 257 - 128) / 128.0;
}

float numerical_sample32(int32_t i) {
	return (float)numerical_sample(i);
}

int16_t numerical_pcm(int32_t track, int32_t i) {
	static const int16_t extrema[2][8] = {{32767, -32768, 0, 32767, -32768, 1, -1, 123}, {1, -1, 0, 32767, -32768, -32768, 32767, -123}};
	if (i < 8) return extrema[track][i];
	uint32_t bits = ((uint32_t)i * (track == 0 ? UINT32_C(1664525) : UINT32_C(22695477)) + UINT32_C(1013904223)) >> 8;
	uint16_t low = (uint16_t)bits;
	int16_t value;
	memcpy(&value, &low, 2);
	return value;
}

int32_t numerical_pcm32(int32_t track, int32_t i) {
	return numerical_pcm(track, i);
}

float numerical_mask_sample(int32_t i) {
	static const uint32_t bits[] = {0, UINT32_C(0x80000000), UINT32_C(0x7fc01234), UINT32_C(0x7f800000), UINT32_C(0xff800000), 1, UINT32_C(0x80000001), UINT32_C(0x3f800000)};
	float value;
	uint32_t b = bits[(uint32_t)i % 8];
	memcpy(&value, &b, 4);
	return value;
}

double numerical_twiddle(int32_t part, int32_t index) {
	double angle = -2.0 * acos(-1.0) * (index % 64) / 64.0;
	return part == 0 ? cos(angle) : sin(angle);
}

int32_t numerical_mode(void) {
	const char *v = getenv("ASTRA_NUMERICAL_RELAXED");
	return v && strcmp(v, "1") == 0;
}

static void initialize(void) {
	if (initialized) return;
	initialized = 1;
	const char *path = getenv("ASTRA_NUMERICAL_OUTPUT");
	if (path) {
		output = fopen(path, "wb");
		if (!output) abort();
	}
	if (APP_ID == 88) {
		for (int i = 0; i < 48000; i++) {
			double sum = 0;
			for (int t = 0; t < 17; t++)
				if (t <= i % 24000) {
					volatile double product = ((t % 5) - 2) / 64.0 * numerical_sample(i - t);
					sum = sum + product;
				}
			expected[i] = sum;
		}
	}
	if (APP_ID == 89) {
		double z1[2] = {0, 0}, z2[2] = {0, 0};
		for (int i = 0; i < 48000; i++) {
			if (i == 24000) {
				z1[0] = 0;
				z1[1] = 0;
				z2[0] = 0;
				z2[1] = 0;
			}
			double sample = numerical_sample(i);
			for (int stage = 0; stage < 2; stage++) {
				double b0 = stage == 0 ? 0.125 : 0.25, b1 = stage == 0 ? 0.25 : 0.125, b2 = 0.125, a1 = -0.5, a2 = 0.25;
				volatile double product = b0 * sample;
				double value = product + z1[stage];
				volatile double first = b1 * sample;
				volatile double second = a1 * value;
				z1[stage] = (first - second) + z2[stage];
				first = b2 * sample;
				second = a2 * value;
				z2[stage] = first - second;
				sample = value;
			}
			expected[i] = sample;
		}
	}
	if (APP_ID == 90) {
		for (int block = 0; block < 32; block++)
			for (int k = 0; k < 64; k++) {
				long double real = 0, imag = 0;
				for (int n = 0; n < 64; n++) {
					long double angle = -2 * acosl(-1.0L) * ((k * n) % 64) / 64;
					long double sample = numerical_sample(block * 64 + n);
					real += sample * cosl(angle);
					imag += sample * sinl(angle);
				}
				expected[block * 128 + 2 * k] = (double)real;
				expected[block * 128 + 2 * k + 1] = (double)imag;
			}
	}
}

static double reference(int i) {
	if (APP_ID == 85) {
		int base = i / 4 * 4, other = base + (i % 4 + 1) % 4;
		if (base + 4 > SAMPLES) other = i;
		volatile float a = numerical_sample32(i + 1) * 0.25f;
		volatile float b = numerical_sample32(other + 1) * 0.5f;
		return (double)(a + b);
	}
	if (APP_ID == 86) {
		float a = numerical_mask_sample(i);
		return isnan(a) ? 0.0 : (double)(a > 0 ? a : -a);
	}
	if (APP_ID == 87) {
		int sum = (int)numerical_pcm(0, i) + (int)numerical_pcm(1, i);
		return sum > 32767 ? 32767 : sum < -32768 ? -32768
		                                          : sum;
	}
	if (APP_ID == 91) {
		double x = numerical_sample(i / 2), y = numerical_sample(i / 2 + 7);
		volatile double a = (i % 2 == 0 ? 0.75 : -0.5) * x;
		volatile double b = (i % 2 == 0 ? 0.25 : 1.25) * y;
		return a + b;
	}
	return expected[i];
}

int32_t numerical_observe(int32_t index, double value) {
	initialize();
	int count = APP_ID == 90 ? 4096 : APP_ID == 91 ? 48000
	                                               : SAMPLES;
	if (index < 0 || index >= count || index != observations) return 1;
	double wanted = reference(index);
	uint64_t a, b;
	memcpy(&a, &value, 8);
	memcpy(&b, &wanted, 8);
	double absolute = fabs(value - wanted);
	double relative = absolute / (fabs(wanted) + DBL_MIN);
	if (absolute > max_absolute) max_absolute = absolute;
	if (relative > max_relative) max_relative = relative;
	int ok = (isnan(value) && isnan(wanted)) || a == b;
	if (APP_ID == 90) ok = isfinite(value) && absolute <= 2e-10;
	if (!ok) {
		fprintf(stderr, "A%d sample=%d observed=%a expected=%a absolute=%.17g\n", APP_ID, index, value, wanted, absolute);
		return 1;
	}
	for (int i = 0; i < 8; i++) {
		digest ^= (a >> (i * 8)) & 255;
		digest *= UINT64_C(1099511628211);
	}
	if (output && fwrite(&value, 8, 1, output) != 1) abort();
	observations++;
	return 0;
}

int32_t numerical_finish(int32_t wanted) {
	if (output && fclose(output) != 0) abort();
	output = NULL;
	if (observations != wanted) return 1;
	printf("numerical:A%d:%d digest=%016llx max_absolute=%.17g max_relative=%.17g\n", APP_ID, observations, (unsigned long long)digest, max_absolute, max_relative);
	return 0;
}
