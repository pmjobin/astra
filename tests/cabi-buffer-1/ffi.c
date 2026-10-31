/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
_Static_assert(sizeof(void *) == 8 && sizeof(int32_t) == 4 && sizeof(size_t) == 8, "qualified GNU LP64 ABI");
int32_t inspect_bytes(int32_t tag, unsigned char *bytes, int32_t length, int32_t expected) {
	assert(length == expected && length >= 0);
	if (tag == 0) {
		assert(length == 0);
		return 0;
	}
	/* Native empty slices may canonicalize a one-past address to NULL. The
	 * independent provider witness also supplies non-NULL empty views. */
	if (tag == 10) {
		assert(length == 0);
		return 10;
	}
	assert(bytes && length == 3 && bytes[0] == 0 && bytes[1] == 255 && bytes[2] == 128);
	bytes[1] = 42;
	return tag;
}
int32_t two_views(unsigned char *a, int32_t alen, int32_t middle, unsigned char *b, int32_t blen) {
	assert(a && b && alen == 2 && blen == 2 && middle == 77);
	assert(a[0] == 42 && b[0] == 42 && a[1] == 128 && b[1] == 128);
	a[0] = 91;
	assert(b[0] == 91);
	return 0;
}
uint64_t mixed_views(int64_t first, const unsigned char *text, int32_t text_length,
                     unsigned char *bytes, int32_t byte_length, uint64_t last) {
	assert(first == INT64_MIN && last == UINT64_MAX);
	assert(text && text_length == 3 && text[0] == 'a' && text[1] == 0 && text[2] == 'b');
	assert(bytes && byte_length == 3 && bytes[0] == 0 && bytes[1] == 255 && bytes[2] == 128);
	bytes[2] = 64;
	return UINT64_C(18446744073709551610);
}
