// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Independent GNU/Linux allocation observer. No private fastcc entry is called
// through a C calling convention; only the documented payload is inspected.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern void *__libc_calloc(size_t count, size_t size);
extern void __libc_free(void *pointer);

struct descriptor {
	const struct descriptor *parent;
	const void *destroy;
	const void *slots;
};

struct origin {
	const char *file;
	int32_t count;
	int32_t line;
	int32_t column;
};

struct error {
	const struct descriptor *descriptor;
	const struct origin *origin;
	unsigned char *data;
	int32_t count;
};

_Static_assert(sizeof(struct error) == 32 && _Alignof(struct error) == 8, "Error layout");
_Static_assert(offsetof(struct error, descriptor) == 0 && offsetof(struct error, origin) == 8, "header layout");
_Static_assert(offsetof(struct error, data) == 16 && offsetof(struct error, count) == 24, "counted snapshot layout");

static struct allocation {
	void *pointer;
	size_t bytes;
	int live;
} allocations[128];

static int used;
static int snapshots;
static int errors;
static int failed;
static void *observed_owner;

void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	if (pointer != NULL && used < 128 && (size == 0 || count <= SIZE_MAX / size)) allocations[used++] = (struct allocation){pointer, count * size, 1};
	return pointer;
}

void free(void *pointer) {
	if (pointer != NULL) {
		for (int i = 0; i < used; i++) {
			if (!allocations[i].live || allocations[i].bytes != sizeof(struct error)) continue;
			struct error *error = allocations[i].pointer;
			if (error->data == pointer) {
				const struct descriptor *derived = error->descriptor;
				static const char message[] = "invalid source span or offset";
				if (error->count != (int32_t)(sizeof(message) - 1) || memcmp(pointer, message, sizeof(message)) != 0 || error->origin == NULL || error->origin->file == NULL || error->origin->count <= 0 || error->origin->line <= 0 || error->origin->column <= 0 || derived == NULL || derived->parent == NULL || derived->parent->parent != NULL || derived->destroy == NULL || derived->destroy == derived->parent->destroy || derived->slots == NULL || derived->parent->slots == NULL) failed = 1;
				observed_owner = error;
				snapshots++;
			}
		}
		for (int i = 0; i < used; i++) {
			if (allocations[i].live && allocations[i].pointer == pointer) {
				if (allocations[i].bytes == sizeof(struct error)) {
					if (pointer != observed_owner || snapshots != 1) failed = 1;
					errors++;
				}
				allocations[i].live = 0;
			}
		}
	}
	__libc_free(pointer);
}

__attribute__((destructor)) static void finish(void) {
	int live = 0;
	for (int i = 0; i < used; i++)
		live += allocations[i].live;
	int valid = !failed && snapshots == 1 && errors == 1 && live == 0;
	fprintf(stderr, "R3_ERROR_OBSERVER valid=%d snapshots=%d errors=%d live=%d\n", valid, snapshots, errors, live);
	if (!valid) _exit(98);
}
