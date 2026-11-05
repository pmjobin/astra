// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Observe only real text backing retirement; no application or Class ABI code.
#include <stddef.h>
#include <string.h>
#include <unistd.h>

void *__real_calloc(size_t count, size_t size);
void __real_free(void *pointer);
static void *backing[2];
static unsigned allocated, retired;

void *__wrap_calloc(size_t count, size_t size) {
	void *value = __real_calloc(count, size);
#ifdef TWO_FIELDS
	if ((count == 3 || count == 4) && size == 1) {
		if (count != (allocated == 0 ? 4U : 3U)) _exit(98);
#else
	if (count == 3 && size == 1) {
#endif
		if (!value || allocated == 2) _exit(98);
		backing[allocated++] = value;
	}
	return value;
}

void __wrap_free(void *pointer) {
	for (unsigned i = 0; i < allocated; ++i) {
		if (pointer != backing[i]) continue;
#ifdef TWO_FIELDS
		static const unsigned char expected[2][4] = {{'l', 'e', 'f', 't'}, {0xe5, 0x8f, 0xb3, 0}};
		if (retired != 1U - i || memcmp(pointer, expected[i], i == 0 ? 4 : 3)) _exit(97);
		static const char old[] = "retire field left\n", fresh[] = "retire field right\n";
#else
		static const unsigned char expected[2][3] = {{'o', 'l', 'd'}, {0xe6, 0x96, 0xb0}};
		if (retired != i || memcmp(pointer, expected[i], 3)) _exit(97);
		static const char old[] = "retire text old\n", fresh[] = "retire text new\n";
#endif
		const char *message = i == 0 ? old : fresh;
		size_t length = i == 0 ? sizeof old - 1 : sizeof fresh - 1;
		if (write(2, message, length) != (ssize_t)length) _exit(98);
		++retired;
	}
	__real_free(pointer);
}

__attribute__((destructor)) static void verify_retirement(void) {
	if (allocated != 2 || retired != 2) _exit(97);
}
