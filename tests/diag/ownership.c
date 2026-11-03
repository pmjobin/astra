/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/platform/diagnostics.h"
#include <assert.h>
#include <stdlib.h>
#include <unistd.h>

static void *snapshot;
static size_t snapshot_size;
static int resource;
static int state;

static void mark(char value) {
	assert(write(1, &value, 1) == 1);
}

void *diag_snapshot_alloc(size_t size) {
	assert(snapshot == NULL);
	snapshot = malloc(size);
	assert(snapshot != NULL);
	snapshot_size = size;
	mark('A');
	return snapshot;
}

void diag_snapshot_free(void *pointer) {
	assert(pointer == snapshot && snapshot != NULL && resource == 0 && state == 0);
	mark('D');
	snapshot = NULL;
	free(pointer);
}

void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);

void *__wrap_calloc(size_t count, size_t size) {
	assert(snapshot != NULL);
	mark('B');
	return __real_calloc(count, size);
}

void __wrap_free(void *pointer) {
	if (pointer != NULL) {
		if (snapshot != NULL) {
			mark('b');
		}
		__real_free(pointer);
	}
}

void *diag_acquire(void) {
	assert(snapshot != NULL && resource == 0);
	resource = 1;
	mark('R');
	return &resource;
}

void diag_release(void *pointer) {
	assert(snapshot != NULL && pointer == &resource && resource == 1);
	resource = 0;
	mark('r');
}

int32_t diag_mark(int32_t event) {
	assert(snapshot != NULL);
	if (event == 'C') {
		assert(state == 0);
		state = 1;
	}
	if (event == 'c') {
		assert(state == 1);
		state = 0;
	}
	mark((char)event);
	return event;
}

_Noreturn void __real_astra_diag_assert_fail_v0(const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length, const unsigned char *message, int32_t message_length);

_Noreturn void __wrap_astra_diag_assert_fail_v0(const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length, const unsigned char *message, int32_t message_length) {
	assert(snapshot != NULL && resource == 1 && state == 1 && message_length > 0);
	uintptr_t base = (uintptr_t)snapshot, start = (uintptr_t)message;
	assert(start >= base && start - base < snapshot_size && (size_t)message_length <= snapshot_size - (start - base));
	mark('F');
	__real_astra_diag_assert_fail_v0(file, file_length, line, expression, expression_length, message, message_length);
}
