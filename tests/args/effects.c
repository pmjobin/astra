/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void *snapshot;
static int owner;
static int uses;
static void record(char event) {
	assert(write(2, &event, 1) == 1);
}
void *args_snapshot_alloc(size_t size) {
#ifdef FAIL_SNAPSHOT
	(void)size;
	record('F');
	return NULL;
#else
	assert(snapshot == NULL);
	snapshot = malloc(size);
	assert(snapshot != NULL);
	record('A');
	return snapshot;
#endif
}
void args_snapshot_free(void *pointer) {
	assert(pointer == snapshot && snapshot != NULL);
	record('D');
	snapshot = NULL;
	free(pointer);
}
void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);
void *__wrap_calloc(size_t count, size_t size) {
	assert(snapshot != NULL);
	record('B');
	return __real_calloc(count, size);
}
void __wrap_free(void *pointer) {
	if (pointer != NULL) {
		if (snapshot != NULL) {
			record('b');
		}
		__real_free(pointer);
	}
}
void *args_resource_acquire(void) {
	assert(snapshot != NULL);
	record('R');
	owner = 1;
	return &owner;
}
void args_resource_destroy(void *resource) {
	assert(resource == &owner && owner == 1 && snapshot != NULL);
	owner = 0;
	record('r');
}
int args_mark(int event) {
	assert(snapshot != NULL);
	if (event == 60) {
		return event;
	}
	record(event == 10 ? 'E' : event == 20 ? 'C'
	                       : event == 30   ? 'M'
	                       : event == 40   ? 'c'
	                       : event == 50   ? 'O'
	                                       : '?');
	return event;
}
int args_index(void) {
	record('I');
#ifdef TRAP_INDEX
	return -1;
#else
	return 1;
#endif
}
int args_observe(const unsigned char *text, int32_t length) {
	assert(snapshot != NULL && owner == 1 && uses++ == 0 && length == 3 && memcmp(text, "a\xc3\xa9", 3) == 0);
	record('U');
	return length;
}
