// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

_Static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8, "selected Windows x64 pointer/allocator ABI");
_Static_assert(sizeof(int) == 4 && sizeof(int32_t) == 4, "selected C word ABI");
_Static_assert(_Alignof(max_align_t) >= 8, "native Shared natural allocator alignment");

extern int32_t astra_native_lifetime14(int32_t count);
extern void *astra_native_identity14(void *token);
static int destroyed;
static int invalid;

int32_t native_destroy14(int32_t value) {
	if (value != 42) {
		++invalid;
	}
	++destroyed;
	return 0;
}

int32_t native_increment14(int32_t value) {
	if (value != 40) {
		++invalid;
	}
	return value + 2;
}

void *native_identity14(void *value) {
	return value;
}

int main(void) {
	int token = 17;
	if (astra_native_identity14(&token) != &token || astra_native_identity14(NULL) != NULL) {
		return 10;
	}
	if (astra_native_lifetime14(128) != 0 || destroyed != 128 || invalid != 0) {
		printf("FAIL native lifetime destroyed=%d invalid=%d\n", destroyed, invalid);
		return 11;
	}
	printf("PASS Windows native O%d: C-word-pointer-roundtrip move explicit-clone weak-upgrade expiry 128-single-destructions\n", ASTRA_OPT);
	puts("ASTRA_COM_IMPORT_EXPORT=NOT_TESTED");
	return 0;
}
