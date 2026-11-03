// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long allocations;
static int observed, failed, factories;
static FILE *output;
#ifndef ASTRA_SANITIZER_OBSERVER

void *calloc(size_t count, size_t size) {
	if (size && count > SIZE_MAX / size) return NULL;
	void *memory = malloc(count * size);
	if (memory) memset(memory, 0, count * size);
	allocations++;
	return memory;
}

#endif

static double sample(int sequence) {
	uint32_t bits = (uint32_t)sequence * UINT32_C(22695477) + UINT32_C(1);
	return (double)((int)(bits >> 17) - 16384) / 16384.0;
}

void metadata_factory_event(void) {
	factories++;
}

double metadata_sample(int sequence) {
	if (!sequence) {
		const char *path = getenv("ASTRA_NUMERICAL_OUTPUT");
		if (path) {
			output = fopen(path, "wb");
			if (!output) exit(72);
		}
		allocations = 0;
	}
	return sample(sequence);
}

int metadata_observe(int block, double value) {
	double energy = 0;
	for (int lane = 0; lane < 128; lane++) {
		double x = sample(block * 128 + lane);
		energy = energy + x * x;
	}
	double attenuation = 1.0 / (1.0 + energy * 0.125);
	double expected = (attenuation + attenuation) + (energy + (getenv("ASTRA_METADATA_MUTATED") ? 1.0 : 0.0)) / 256.0;
	if (block != observed || memcmp(&value, &expected, sizeof value)) failed = 1;
	if (output && fwrite(&value, sizeof value, 1, output) != 1) failed = 1;
	observed++;
	return failed;
}

int metadata_finish(int count) {
	if (output && fclose(output)) failed = 1;
	if (observed != count) failed = 1;
	if (factories != (getenv("ASTRA_EXPECT_FACTORIES") ? count : 0)) failed = 1;
	printf("numerical:A94:%d calloc=%lu factories=%d failed=%d\n", observed, allocations, factories, failed);
	return failed;
}
