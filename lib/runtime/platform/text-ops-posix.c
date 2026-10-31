/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <limits.h>
#include <stddef.h>
#if !defined(__linux__) || !defined(__x86_64__) || defined(__ILP32__)
#error "text-ops-posix is qualified only for GNU Linux x86-64 LP64"
#endif
_Static_assert(CHAR_BIT == 8 && sizeof(int32_t) == 4, "counted octet ABI");
/* Read-only, noescape; byte bounds use the authentic utf8-i32 descriptor. */
int32_t astra_host_text_byte(const unsigned char *data, int32_t length, int32_t index) {
	if (length < 0 || index < 0 || index >= length || data == NULL) {
		return -1;
	}
	return data[index];
}
