// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Observation only: the application and object lifetimes execute in Astra.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long allocations;
static unsigned retired;
void *calloc(size_t count, size_t size) {
	if (size && count > SIZE_MAX / size) return NULL;
	void *memory = malloc(count * size);
	if (memory) memset(memory, 0, count * size);
	allocations++;
	return memory;
}
static void finish(void) {
	printf("allocations=%lu retired=%u\n", allocations, retired);
}
void storage18_begin(void) {
	if (atexit(finish)) abort();
	allocations = 0;
	retired = 0;
}
void storage18_retire(int value) {
	printf("retire=%d\n", value);
	retired++;
}
void storage18_caught(void) {
	puts("caught");
}
