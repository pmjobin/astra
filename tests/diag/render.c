/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/platform/diagnostics-hosted.c"
#include <assert.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

struct view {
	void *mapping;
	size_t size;
	unsigned char *bytes;
	int32_t length;
};

static uint32_t word(void) {
	unsigned char bytes[4];
	assert(fread(bytes, 1, 4, stdin) == 4);
	return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 | (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}

static struct view read_view(void) {
	uint32_t length = word();
	assert(length <= 1024 * 1024);
	if (length == 0) {
		return (struct view){NULL, 0, NULL, 0};
	}
	size_t page = (size_t)sysconf(_SC_PAGESIZE);
	size_t capacity = (length + page - 1) / page * page;
	void *mapping = mmap(NULL, capacity + page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	assert(mapping != MAP_FAILED && mprotect((unsigned char *)mapping + capacity, page, PROT_NONE) == 0);
	unsigned char *bytes = (unsigned char *)mapping + capacity - length;
	assert(fread(bytes, 1, length, stdin) == length);
	return (struct view){mapping, capacity + page, bytes, (int32_t)length};
}

int main(int argc, char **argv) {
	if (argc == 3 && strcmp(argv[1], "shape") == 0) {
		int kind = atoi(argv[2]);
		const unsigned char *bad = (const unsigned char *)(uintptr_t)1;
		astra_diag_assert_fail_v0(kind == 3 ? NULL : bad, kind == 0 ? -1 : 1, INT32_MIN, kind == 4 ? NULL : bad, kind == 1 ? -1 : 1, kind == 5 ? NULL : bad, kind == 2 ? -1 : 1);
	}
	uint32_t bits = word();
	int32_t line;
	memcpy(&line, &bits, sizeof(line));
	struct view file = read_view(), expression = read_view(), message = read_view();
	if (argc == 2 && strcmp(argv[1], "fatal") == 0) {
		astra_diag_assert_fail_v0(file.bytes, file.length, line, expression.bytes, expression.length, message.bytes, message.length);
	}
	assert(astra_diag_render(stdout, file.bytes, file.length, line, expression.bytes, expression.length, message.bytes, message.length));
	assert(fflush(stdout) == 0);
	struct view views[] = {file, expression, message};
	for (size_t i = 0; i < sizeof(views) / sizeof(views[0]); i++) {
		if (views[i].mapping != NULL) {
			assert(munmap(views[i].mapping, views[i].size) == 0);
		}
	}
	return 0;
}
