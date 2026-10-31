/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/platform/args-posix.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

extern int args_consume(const struct AstraArgsTextV0 *a, int32_t an, const struct AstraArgsTextV0 *b, int32_t bn, int32_t index);
extern int args_count(const struct AstraArgsTextV0 *a, int32_t count);
extern int args_element(const struct AstraArgsTextV0 *a, int32_t count, int32_t index);
extern int args_short(const struct AstraArgsTextV0 *a, int32_t count, int32_t index, int32_t skip);

static unsigned char *guarded(size_t page) {
	unsigned char *memory = mmap(NULL, page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	assert(memory != MAP_FAILED && mprotect(memory + page, page, PROT_NONE) == 0);
	return memory;
}

int main(int argc, char **argv) {
	size_t page = (size_t)sysconf(_SC_PAGESIZE);
	unsigned char *table_memory = guarded(page);
	unsigned char *left = guarded(page);
	unsigned char *right = guarded(page);
	struct AstraArgsTextV0 *table = (void *)(table_memory + page - 3 * sizeof(*table));
	unsigned char content[] = {'a', 0, 0xc3, 0xa9, 0xf0, 0x9f, 0x98, 0x80};
	memcpy(left + page - sizeof(content), content, sizeof(content));
	memcpy(right + page - sizeof(content), content, sizeof(content));
	table[0] = (struct AstraArgsTextV0){NULL, 0};
	table[1] = (struct AstraArgsTextV0){left + page - sizeof(content), sizeof(content)};
	table[2] = (struct AstraArgsTextV0){right + page - sizeof(content), sizeof(content)};
	assert(args_count(NULL, 0) == 0 && args_count(table, 3) == 3);
	assert(args_short(table, 3, 99, 1) == 1 && args_short(table, 3, 0, 0) == 1);
	if (argc > 1) {
		int index = atoi(argv[1]);
		/* These executions deliberately trap; retained mappings are separate. */
		return index == 0 ? args_element(NULL, 0, index) : args_short(table, 3, index, 0);
	}
	struct AstraArgsTextV0 *copy = malloc(3 * sizeof(*copy));
	assert(copy != NULL);
	memcpy(copy, table, 3 * sizeof(*copy));
	copy[1].data = table[2].data;
	copy[2].data = table[1].data;
	for (int32_t i = 0; i < 3; i++) {
		assert(args_consume(table, 3, copy, 3, i) == table[i].byte_length);
	}
	for (int cycle = 0; cycle < 1024; cycle++) {
		char a[] = "\xc3\xa9";
		char b[] = "";
		char *original[] = {a, b, NULL};
		const struct AstraArgsTextV0 *snapshot = NULL;
		assert(astra_host_args_prepare_v0(2, original, &snapshot) == 0);
		original[0] = b;
		original[1] = a;
		a[0] = 'x';
		a[1] = 'y';
		unsigned char expected[] = {0xc3, 0xa9};
		struct AstraArgsTextV0 exact[] = {{expected, 2}, {NULL, 0}};
		assert(args_count(snapshot, 2) == 2 && args_consume(snapshot, 2, exact, 2, 0) == 2 && args_consume(snapshot, 2, exact, 2, 1) == 0);
		astra_host_args_dispose_v0(snapshot);
	}
	free(copy);
	assert(munmap(left, page * 2) == 0 && munmap(right, page * 2) == 0 && munmap(table_memory, page * 2) == 0);
	return 0;
}
