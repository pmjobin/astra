// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static unsigned long allocations;
static int retired, observed, failed;
static FILE *output;

// Host-only measurement adapter, linked explicitly by this recipe. It does
// not change Astra's allocator policy; the off/on executables use the same C.
#ifndef ASTRA_SANITIZER_OBSERVER
void *calloc(size_t count, size_t size) {
	if (size && count > SIZE_MAX / size) return NULL;
	void *memory = malloc(count * size);
	if (memory) memset(memory, 0, count * size);
	allocations++;
	return memory;
}
#endif

static double reference_sample(int sequence) {
	uint32_t bits = (uint32_t)sequence * UINT32_C(1664525) + UINT32_C(1013904223);
	return (double)((int)(bits >> 16) - 32768) / 32768.0;
}

double packet_sample(int sequence) {
	if (sequence == 0) {
		const char *path = getenv("ASTRA_NUMERICAL_OUTPUT");
		if (path) {
			output = fopen(path, "wb");
			if (!output) exit(72);
		}
		allocations = 0;
	}
	return reference_sample(sequence);
}

void packet_retire(int sequence) {
	if (sequence != retired) failed = 1;
	retired++;
}

int packet_observe(int sequence, double value) {
	double expected = reference_sample(sequence) * (sequence % 97 == 0 ? 0.5 : 0.75) + (double)(sequence % 7) / 16.0;
	if (sequence != observed || retired != sequence + 1 || memcmp(&value, &expected, sizeof value)) failed = 1;
	if (output && fwrite(&value, sizeof value, 1, output) != 1) failed = 1;
	observed++;
	return failed;
}

int packet_finish(int count) {
	if (output && fclose(output)) failed = 1;
	if (observed != count || retired != count) failed = 1;
	printf("numerical:A93:%d retired=%d calloc=%lu failed=%d\n", observed, retired, allocations, failed);
	return failed;
}
