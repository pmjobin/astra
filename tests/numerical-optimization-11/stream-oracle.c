// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <float.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double history[17], z1[2], z2[2], max_absolute;
static int position, observed, failed, relaxed;
static FILE *output;

double stream_sample(int index) {
	uint32_t bits = (uint32_t)index * UINT32_C(1664525) + UINT32_C(1013904223);
	if (index % 8191 == 0) return index % 2 ? -0.0 : 0.0;
	if (index % 4093 == 0) return DBL_TRUE_MIN;
	return (double)((int)(bits >> 16) - 32768) / 32768.0;
}

int stream_mode(void) {
	relaxed = getenv("ASTRA_NUMERICAL_RELAXED") && atoi(getenv("ASTRA_NUMERICAL_RELAXED"));
	const char *path = getenv("ASTRA_NUMERICAL_OUTPUT");
	if (path) {
		output = fopen(path, "wb");
		if (!output) exit(72);
	}
	return relaxed;
}

static double biquad(double x, int stage) {
	double b0 = stage == 0 ? 0.125 : 0.25;
	double b1 = stage == 0 ? 0.25 : 0.125;
	double value = b0 * x + z1[stage];
	z1[stage] = (b1 * x - -0.5 * value) + z2[stage];
	z2[stage] = 0.125 * x - 0.25 * value;
	return value;
}

int stream_observe(int index, double value) {
	if (index == 96000) {
		memset(history, 0, sizeof history);
		memset(z1, 0, sizeof z1);
		memset(z2, 0, sizeof z2);
		position = 0;
	}
	double x = stream_sample(index) * 0.75 + 0.00390625;
	history[position] = x;
	double sum = 0;
	int cursor = position;
	for (int tap = 0; tap < 17; tap++) {
		sum = sum + ((double)(tap % 5 - 2) / 64.0) * history[cursor];
		cursor--;
		if (cursor < 0) cursor = 16;
	}
	position++;
	if (position == 17) position = 0;
	double expected = biquad(biquad(sum, 0), 1);
	double absolute = fabs(value - expected);
	if (absolute > max_absolute) max_absolute = absolute;
	if (index != observed || !isfinite(value) || (relaxed ? absolute > 2e-12 : memcmp(&value, &expected, sizeof value) != 0)) failed = 1;
	if (output && fwrite(&value, sizeof value, 1, output) != 1) failed = 1;
	observed++;
	return failed;
}

int stream_finish(int count) {
	if (output && fclose(output)) failed = 1;
	if (count != observed) failed = 1;
	printf("numerical:A96:%d mode=%d max_absolute=%.17g failed=%d\n", observed, relaxed, max_absolute, failed);
	return failed;
}
