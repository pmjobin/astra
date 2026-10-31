/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern int32_t astra_allocation_probe(int32_t);
extern void *__real_calloc(size_t, size_t);
extern void __real_free(void *);
void *__wrap_calloc(size_t count, size_t bytes) {
	puts("allocate");
	fflush(stdout);
	if (getenv("CS_ALLOCATION_FAIL")) {
		return NULL;
	}
	return __real_calloc(count, bytes);
}
void __wrap_free(void *pointer) {
	puts("free");
	__real_free(pointer);
}
int main(void) {
	if (astra_allocation_probe(8) != 8) {
		return 1;
	}
	puts("returned");
	return 0;
}
