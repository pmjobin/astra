// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
#include <stdlib.h>
static int slot;
int mark(int value) {
	printf("E%d\n", value);
	fflush(stdout);
	return value;
}
void *test_acquire(int id) {
	slot = id;
	mark(id);
	return &slot;
}
void test_release(void *value) {
	if (value != &slot || slot != 7) {
		abort();
	}
	mark(-slot);
	slot = 0;
}
void *__real_calloc(size_t count, size_t width);
void __real_free(void *pointer);
void *__wrap_calloc(size_t count, size_t width) {
	mark(90);
	return __real_calloc(count, width);
}
void __wrap_free(void *pointer) {
	mark(-90);
	__real_free(pointer);
}
