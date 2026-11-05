// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stddef.h>
#include <unistd.h>

void *__real_calloc(size_t count, size_t size);

void *__wrap_calloc(size_t count, size_t size) {
	if (count == 1 && size == 1) {
		static const char marker[] = "TEXTCLASS_TEST: one text byte refused\n";
		(void)write(2, marker, sizeof marker - 1);
		return NULL;
	}
	return __real_calloc(count, size);
}
