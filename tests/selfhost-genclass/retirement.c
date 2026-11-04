// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only linker observer. Application construction/retirement stays in Astra.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern void *__real_calloc(size_t count, size_t stride);
extern void __real_free(void *pointer);
static void *items[2];
static unsigned allocated, retired;

void *__wrap_calloc(size_t count, size_t stride) {
	void *pointer = __real_calloc(count, stride);
	if (count == 1 && stride == sizeof(int32_t)) {
		if (!pointer || allocated == 2) _exit(98);
		items[allocated++] = pointer;
	}
	return pointer;
}

void __wrap_free(void *pointer) {
	for (unsigned i = 0; i < allocated; ++i) {
		if (pointer != items[i]) continue;
		int32_t value;
		memcpy(&value, pointer, sizeof(value));
		if (retired != i || value != (i == 0 ? 4 : 9)) _exit(97);
		static const char old[] = "retire old 4\n", result[] = "retire result 9\n";
		const char *message = i == 0 ? old : result;
		size_t length = i == 0 ? sizeof(old) - 1 : sizeof(result) - 1;
		if (write(2, message, length) != (ssize_t)length) _exit(98);
		++retired;
	}
	__real_free(pointer);
}

__attribute__((destructor)) static void check_observation(void) {
	if (allocated != 2 || retired != 2) _exit(97);
}
