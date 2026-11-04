// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only linker allocator wrapper. No Astra application body is here.
#include <stddef.h>
#include <unistd.h>

extern void *__real_calloc(size_t count, size_t stride);
static int failures;

void *__wrap_calloc(size_t count, size_t stride) {
	if (count == 4 && stride == 8 && failures == 0) {
		failures = 1;
		static const char message[] = "CLASS_STORAGE_TEST: calloc(4,8) refused\n";
		if (write(2, message, sizeof(message) - 1) != (ssize_t)(sizeof(message) - 1)) _exit(98);
		return NULL;
	}
	return __real_calloc(count, stride);
}

__attribute__((destructor)) static void check_injection(void) {
	if (failures != 1) _exit(98);
}
