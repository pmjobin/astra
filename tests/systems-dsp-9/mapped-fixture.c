/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Deliberate owned-buffer allocator fixture: each allocation is a real mapping. */
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>

struct mapping {
	void *base;
	size_t extent;
};
static struct mapping mappings[128];
static int count;
static int watching;

void *__wrap_calloc(size_t number, size_t size) {
	assert(size == 0 || number <= SIZE_MAX / size);
	size_t bytes = number * size;
	size_t page = (size_t)sysconf(_SC_PAGESIZE);
	assert(bytes <= SIZE_MAX - page);
	size_t extent = (bytes / page + 1) * page;
	void *base = mmap(NULL, extent, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	assert(base != MAP_FAILED && count < 128);
	for (int i = 0; i < 128; i++) {
		if (!mappings[i].base) {
			mappings[i] = (struct mapping){base, extent};
			count++;
			return base;
		}
	}
	assert(0);
	return NULL;
}

void __real_free(void *);

void __wrap_free(void *pointer) {
	for (int i = 0; i < 128; i++) {
		if (pointer && mappings[i].base == pointer) {
			assert(munmap(pointer, mappings[i].extent) == 0);
			mappings[i] = (struct mapping){0};
			count--;
			return;
		}
	}
	__real_free(pointer);
}

int mapped_count(void) {
	return count;
}

void mapping_watch(void) {
	const char *descriptor = getenv("ASTRA_WATCH_FD");
	if (descriptor) {
		uintptr_t addresses[4] = {(uintptr_t)mappings[0].base, (uintptr_t)mappings[0].base + 4,
		                          (uintptr_t)mappings[1].base, (uintptr_t)mappings[1].base + 8};
		assert(write(atoi(descriptor), addresses, sizeof addresses) == (ssize_t)sizeof addresses);
		watching = 1;
		raise(SIGSTOP);
	}
}

int mapping_audit(int expected) {
	if (watching) {
		raise(SIGSTOP);
		watching = 0;
	}
	assert(count == expected);
	if (expected == 2) {
		const uint32_t *words = mappings[0].base;
		const uint64_t *wide = mappings[1].base;
		assert(words[0] == 2 && words[1] == 7 && words[2] == 0 && words[3] == 0);
		assert(wide[0] == UINT64_C(4294967297) && wide[1] == UINT64_C(4294967299));
	}
	return 0;
}
