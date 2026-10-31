/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
static unsigned allocations;
static int measuring;
void *__real_calloc(size_t, size_t);
void *__real_malloc(size_t);
void *__wrap_calloc(size_t count, size_t size) {
	if (measuring) allocations++;
	return __real_calloc(count, size);
}
void *__wrap_malloc(size_t size) {
	if (measuring) allocations++;
	return __real_malloc(size);
}
void composition18_begin(void) {
	allocations = 0;
	measuring = 1;
}
void composition18_end(void) {
	measuring = 0;
	printf("allocations=%u\n", allocations);
}
void composition18_retire(int value) {
	printf("retire=%d\n", value);
}
void composition18_observe(int value) {
	printf("observe=%d\n", value);
}
