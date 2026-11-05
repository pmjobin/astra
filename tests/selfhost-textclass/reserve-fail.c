// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Refuse only the requested replacement slot backing; retain real app code.
#include <stddef.h>
#include <unistd.h>

void *__real_calloc(size_t count, size_t size);

void *__wrap_calloc(size_t count, size_t size) {
	if (count == 12 && size == 8) {
		static const char message[] = "TEXTCLASS_TEST: Bag reserve refused\n";
		if (write(2, message, sizeof message - 1) != (ssize_t)(sizeof message - 1)) _exit(98);
		return NULL;
	}
	return __real_calloc(count, size);
}
