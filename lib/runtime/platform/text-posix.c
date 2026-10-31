/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "text-posix.h"
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <unistd.h>

#if !defined(__linux__) || !defined(__x86_64__)
#error "Astra text provider is qualified only for x86-64 Linux"
#endif
_Static_assert(CHAR_BIT == 8 && UCHAR_MAX == 255, "utf8-i32 requires octets");
_Static_assert(sizeof(int32_t) == 4 && INT32_MAX == 2147483647 && INT32_MIN == (-2147483647 - 1), "utf8-i32 requires exact signed I32");
_Static_assert(SIZE_MAX >= INT32_MAX && SSIZE_MAX >= INT32_MAX, "provider count must represent every nonnegative I32");

static int write_range(int descriptor, const unsigned char *data, size_t remaining) {
	while (remaining != 0) {
		ssize_t written = write(descriptor, data, remaining);
		if (written > 0) {
			data += (size_t)written;
			remaining -= (size_t)written;
		} else if (written == 0 || errno != EINTR) {
			return 1;
		}
	}
	return 0;
}

int32_t astra_host_text_write(int32_t stream, const unsigned char *data, int32_t byte_length, int32_t newline) {
	if ((stream != 1 && stream != 2) || (newline != 0 && newline != 1) || byte_length < 0 || (byte_length != 0 && data == NULL)) {
		return 1;
	}
	if (write_range((int)stream, data, (size_t)byte_length) != 0) {
		return 1;
	}
	if (newline != 0) {
		static const unsigned char lf = 10;
		return write_range((int)stream, &lf, 1);
	}
	return 0;
}
