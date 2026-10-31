/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "args-posix.h"
#include <limits.h>
#include <stddef.h>
#include <stdlib.h>

#if !defined(__linux__) || !defined(__x86_64__) || defined(__ILP32__)
#error "args-posix-v0 is qualified only for x86-64 Linux LP64"
#endif

_Static_assert(CHAR_BIT == 8, "UTF-8 requires 8-bit bytes");
_Static_assert(sizeof(int) == 4 && INT_MAX == INT32_MAX && INT_MIN == INT32_MIN, "host main int must agree with signed I32");
_Static_assert(sizeof(void *) == 8 && sizeof(char *) == 8 && sizeof(unsigned char *) == 8, "qualified data pointer representations");
_Static_assert(_Alignof(void *) == 8 && _Alignof(char *) == 8 && _Alignof(unsigned char *) == 8, "qualified data pointer alignment");
_Static_assert(sizeof(int32_t) == 4 && _Alignof(int32_t) == 4, "qualified signed I32 storage");
_Static_assert(offsetof(struct AstraArgsTextV0, data) == 0 && offsetof(struct AstraArgsTextV0, byte_length) == 8, "native text descriptor component offsets");
_Static_assert(sizeof(struct AstraArgsTextV0) == 16 && _Alignof(struct AstraArgsTextV0) == 8, "native text descriptor stride and alignment");
_Static_assert(_Alignof(max_align_t) >= _Alignof(struct AstraArgsTextV0), "malloc alignment covers table");
_Static_assert(sizeof(size_t) == 8 && PTRDIFF_MAX == INT64_MAX, "qualified allocation and pointer arithmetic width");

/* PTRDIFF_MAX also bounds every offset formed inside the allocation. These
 * arithmetic seams are tested directly without huge allocations. */
static int args_add_size(size_t left, size_t right, size_t *result) {
	if (left > (size_t)PTRDIFF_MAX || right > (size_t)PTRDIFF_MAX - left) {
		return 0;
	}
	*result = left + right;
	return 1;
}

static int args_table_size(size_t count, size_t *result) {
	if (count > (size_t)PTRDIFF_MAX / sizeof(struct AstraArgsTextV0)) {
		return 0;
	}
	*result = count * sizeof(struct AstraArgsTextV0);
	return 1;
}

/* RFC 3629 / TEXT-1: shortest scalar encodings, with no normalization. */
static int args_valid_utf8(const unsigned char *data, size_t length) {
	size_t index = 0;
	while (index < length) {
		uint32_t first = data[index++];
		uint32_t scalar;
		uint32_t minimum;
		size_t continuation;
		if (first < 0x80) {
			continue;
		} else if (first >= 0xc2 && first <= 0xdf) {
			scalar = first & 0x1f;
			minimum = 0x80;
			continuation = 1;
		} else if (first >= 0xe0 && first <= 0xef) {
			scalar = first & 0x0f;
			minimum = 0x800;
			continuation = 2;
		} else if (first >= 0xf0 && first <= 0xf4) {
			scalar = first & 7;
			minimum = 0x10000;
			continuation = 3;
		} else {
			return 0;
		}
		if (continuation > length - index) {
			return 0;
		}
		while (continuation-- != 0) {
			uint32_t byte = data[index++];
			if ((byte & 0xc0) != 0x80) {
				return 0;
			}
			scalar = (scalar << 6) | (byte & 0x3f);
		}
		if (scalar < minimum || scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff)) {
			return 0;
		}
	}
	return 1;
}

int32_t astra_host_args_prepare_v0(int32_t argc, char *const *argv, const struct AstraArgsTextV0 **out_items) {
	size_t table_bytes;
	size_t total;
	if (out_items == NULL) {
		return 2;
	}
	*out_items = NULL;
	if (argc < 0) {
		return 2;
	}
	if (argc == 0) {
		return 0;
	}
	if (argv == NULL || argv[argc] != NULL || !args_table_size((size_t)argc, &table_bytes)) {
		return 2;
	}
	total = table_bytes;
	for (int32_t i = 0; i < argc; i++) {
		if (argv[i] == NULL) {
			return 2;
		}
		size_t length = 0;
		while (argv[i][length] != 0) {
			if (length == INT32_MAX) {
				return 2;
			}
			length++;
		}
		if (!args_add_size(total, length, &total)) {
			return 2;
		}
	}
	struct AstraArgsTextV0 *items = malloc(total);
	if (items == NULL) {
		return 3;
	}
	unsigned char *payload = (unsigned char *)items + table_bytes;
	size_t used = 0;
	size_t capacity = total - table_bytes;
	for (int32_t i = 0; i < argc; i++) {
		const unsigned char *input = (const unsigned char *)argv[i];
		if (input == NULL) {
			goto invalid;
		}
		size_t start = used;
		size_t length = 0;
		/* A changed source cannot overrun the first pass's planned capacity.
		 * The host contract still requires readable strings stable during capture. */
		while (input[length] != 0) {
			if (used == capacity || length == INT32_MAX) {
				goto invalid;
			}
			payload[used++] = input[length++];
		}
		items[i].data = length == 0 ? NULL : payload + start;
		items[i].byte_length = (int32_t)length;
	}
	for (int32_t i = 0; i < argc; i++) {
		if (!args_valid_utf8(items[i].data, (size_t)items[i].byte_length)) {
			goto invalid;
		}
	}
	*out_items = items;
	return 0;
invalid:
	free(items);
	return 2;
}

void astra_host_args_dispose_v0(const struct AstraArgsTextV0 *items) {
	if (items != NULL) {
		free((void *)items);
	}
}
