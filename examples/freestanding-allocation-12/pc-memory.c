/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Explicit no-OS core primitives. No allocator, syscall or hosted provider. */
#include <stddef.h>
#include <stdint.h>
void *memset(void *destination, int byte, size_t count) {
	volatile unsigned char *out = destination;
	for (size_t i = 0; i < count; ++i) {
		out[i] = (unsigned char)byte;
	}
	return destination;
}
void *memcpy(void *destination, const void *source, size_t count) {
	volatile unsigned char *out = destination;
	const volatile unsigned char *in = source;
	for (size_t i = 0; i < count; ++i) {
		out[i] = in[i];
	}
	return destination;
}
void *memmove(void *destination, const void *source, size_t count) {
	volatile unsigned char *out = destination;
	const volatile unsigned char *in = source;
	if ((uintptr_t)destination > (uintptr_t)source) {
		for (size_t i = count; i > 0; --i) {
			out[i - 1] = in[i - 1];
		}
	} else {
		for (size_t i = 0; i < count; ++i) {
			out[i] = in[i];
		}
	}
	return destination;
}
