// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// Internal compiler test seam: wrappers are appended to the emitted LLVM
// module. This deliberately does not expose an Astra C ABI string mapping.
extern int text_equal(const unsigned char *a, int32_t an, const unsigned char *b, int32_t bn);
extern int text_length(const unsigned char *a, int32_t an);

static int compare(const unsigned char *content, int32_t length) {
	unsigned char *a = malloc(length ? (size_t)length : 1);
	unsigned char *b = malloc(length ? (size_t)length : 1);
	if (!a || !b || a == b) {
		abort();
	}
	if (length) {
		memcpy(a, content, (size_t)length);
		memcpy(b, content, (size_t)length);
	}
	int ok = text_equal(a, length, b, length) && text_equal(a, length, a, length) && text_length(a, length) == length;
	if (length) {
		// Callers supply a final ASCII scalar, so changing that scalar
		// preserves the native well-formed-UTF-8 precondition.
		b[length - 1] = b[length - 1] == 'z' ? 'y' : 'z';
		ok = ok && !text_equal(a, length, b, length) && !text_equal(a, length, b, length - 1);
	}
	free(a);
	free(b);
	return ok;
}

int main(void) {
	if (!text_equal(NULL, 0, NULL, 0) || text_length(NULL, 0) != 0) {
		return 1;
	}
	unsigned char unicode[] = {0xc3, 0xa9, 0xce, 0xb1, 0xe4, 0xb8, 0xad, 0xf0, 0x9f, 0x98, 0x80, 0, 'b'};
	if (!compare(unicode, sizeof(unicode))) {
		return 8;
	}
	unsigned char nul[] = {'a', 0, 'b'};
	if (!compare(nul, 3) || !compare((const unsigned char *)"Astra", 5) || !compare(NULL, 0)) {
		return 2;
	}
	unsigned char *prefix = malloc(65536);
	if (!prefix) {
		abort();
	}
	memset(prefix, 'q', 65536);
	for (int32_t n = 1; n <= 65536; n *= 2) {
		if (!compare(prefix, n)) {
			return 3;
		}
	}
	free(prefix);
	long page = sysconf(_SC_PAGESIZE);
	unsigned char *a = mmap(NULL, (size_t)page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	unsigned char *b = mmap(NULL, (size_t)page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (a == MAP_FAILED || b == MAP_FAILED || mprotect(a + page, (size_t)page, PROT_NONE) || mprotect(b + page, (size_t)page, PROT_NONE)) {
		abort();
	}
	memset(a, 'p', (size_t)page);
	memset(b, 'p', (size_t)page);
	for (int32_t n = 1; n <= page; n *= 2) {
		if (!text_equal(a + page - n, n, b + page - n, n)) {
			return 4;
		}
	}
	a[page - 1] = 0;
	b[page - 1] = 0;
	if (!text_equal(a, (int32_t)page, b, (int32_t)page)) {
		return 5;
	}
	b[page - 1] = 'b';
	if (text_equal(a, (int32_t)page, b, (int32_t)page)) {
		return 6;
	}
	if (!text_equal(a + page, 0, b + page, 0)) {
		return 7;
	}
	munmap(a, (size_t)page * 2);
	munmap(b, (size_t)page * 2);
	return 0;
}
