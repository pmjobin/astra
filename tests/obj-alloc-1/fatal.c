// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

void *calloc(size_t count, size_t size) {
	(void)count;
	(void)size;
	(void)write(STDOUT_FILENO, "A", 1);
	return NULL;
}

int32_t alloc_fatal_event(int32_t code) {
	char byte = (char)code;
	(void)write(STDOUT_FILENO, &byte, 1);
	return 0;
}
