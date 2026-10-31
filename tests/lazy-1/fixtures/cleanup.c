// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void *receiver;
extern void *__real_calloc(size_t count, size_t bytes);
extern int32_t lazy_cleanup_bridge(void *object);
void *__wrap_calloc(size_t count, size_t bytes) {
	assert(!receiver && count == 1 && bytes >= 8);
	receiver = __real_calloc(count, bytes);
	assert(receiver);
	return receiver;
}
int32_t lazy_event(int32_t code, int32_t value) {
	assert(putchar(code) != EOF);
	assert(fflush(stdout) == 0);
	return value;
}
void *lazy_create(int32_t code) {
	int32_t *local = malloc(sizeof *local);
	assert(local);
	*local = code;
	return local;
}
void lazy_destroy(void *pointer) {
	int32_t *local = pointer;
	assert(receiver && local);
	lazy_event(*local, 0);
	free(local);
	lazy_cleanup_bridge(receiver);
	abort();
}
int32_t lazy_live(void) {
	return 0;
}
