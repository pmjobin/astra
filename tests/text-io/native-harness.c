/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
const unsigned char *expected_a, *expected_b;
int32_t expected_an, expected_bn;
const unsigned char *expected_a_bytes, *expected_b_bytes;
void *expected_token;
extern int observer_calls;
/* Internal test entry. No Astra export(C) text acceptance is involved. */
extern int32_t text_io_entry(const unsigned char *, int32_t, const unsigned char *, int32_t, void *);

struct guarded {
	unsigned char *mapping;
	unsigned char *data;
	size_t size;
};

static struct guarded allocate(int32_t count) {
	if (count == 0) {
		return (struct guarded){NULL, NULL, 0};
	}
	size_t page = (size_t)sysconf(_SC_PAGESIZE);
	size_t size = (((size_t)count + page - 1) / page + 1) * page;
	unsigned char *mapping = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	assert(mapping != MAP_FAILED && mprotect(mapping + size - page, page, PROT_NONE) == 0);
	return (struct guarded){mapping, mapping + size - page - count, size};
}

static void release(struct guarded view) {
	if (view.size) {
		assert(munmap(view.mapping, view.size) == 0);
	}
}

static void call(const unsigned char *a, int32_t an, const unsigned char *b, int32_t bn) {
	int token = 19;
	expected_a = a;
	expected_an = an;
	expected_b = b;
	expected_bn = bn;
	expected_token = &token;
	unsigned char *acopy = an ? malloc((size_t)an) : NULL, *bcopy = bn ? malloc((size_t)bn) : NULL;
	if (an) {
		assert(acopy);
		memcpy(acopy, a, (size_t)an);
	}
	if (bn) {
		assert(bcopy);
		memcpy(bcopy, b, (size_t)bn);
	}
	expected_a_bytes = acopy;
	expected_b_bytes = bcopy;
	observer_calls = 0;
	assert(text_io_entry(a, an, b, bn, &token) == 0 && observer_calls == 5);
	free(acopy);
	free(bcopy);
	expected_a_bytes = NULL;
	expected_b_bytes = NULL;
	expected_a = NULL;
	expected_b = NULL;
	expected_token = NULL;
}

int main(void) {
	static const unsigned char unicode[] = {0xc3, 0xa9, 0x65, 0xcc, 0x81, 0, 0xf0, 0x9f, 0x98, 0x80};
	int32_t lengths[] = {0, 1, 10, 4096, 65536};
	for (size_t n = 0; n < sizeof lengths / sizeof lengths[0]; n++) {
		int32_t length = lengths[n];
		struct guarded a = allocate(length), b = allocate(length);
		for (int32_t i = 0; i < length; i++) {
			a.data[i] = b.data[i] = length == 10 ? unicode[i] : (unsigned char)('a' + i % 23);
		}
		call(a.data, length, b.data, length);
		call(a.data, length, a.data, length);
		if (length) {
			b.data[length == 10 ? 2 : length - 1] = 'z';
			call(a.data, length, b.data, length);
		}
		call(a.data, length, NULL, 0);
		release(a);
		release(b);
	}
	return 0;
}
