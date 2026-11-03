/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Host-only count fault injection; never used by ordinary Astra binaries. */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
extern void *__libc_calloc(size_t, size_t);

struct buffer {
	unsigned char *base;
	int32_t capacity;
};

struct builder {
	struct buffer backing;
	int32_t used;
};

_Static_assert(sizeof(void *) == 8 && sizeof(struct builder) == 24 && offsetof(struct builder, used) == 16,
               "qualified x86-64 LP64 test layout");
static struct builder saved;
static size_t calls, before;
static int entered, restored, grow;

static void require(int yes) {
	if (!yes) {
		_Exit(98);
	}
}

void *calloc(size_t n, size_t size) {
	calls++;
	if (entered && n > 1024) {
		require(grow && n == INT32_MAX && size == 1);
		static const char trace[] = "limit-growth rejected allocation=2147483647\n";
		require(write(1, trace, sizeof(trace) - 1) == (ssize_t)(sizeof(trace) - 1));
		return NULL;
	}
	return __libc_calloc(n, size);
}

void builder_limit_enter(struct builder *object) {
	require(!entered && object && object->used == 0 && !object->backing.base && !object->backing.capacity);
	const char *mode = getenv("BUILDER_LIMIT_MODE");
	grow = mode && strcmp(mode, "growth") == 0;
	saved = *object;
	entered = 1;
	object->used = grow ? INT32_MAX - 1 : INT32_MAX;
	before = calls;
}

void builder_limit_leave(struct builder *object, int accepted) {
	require(entered && !restored && !grow && object->used == INT32_MAX && object->backing.base == saved.backing.base && object->backing.capacity == saved.backing.capacity && calls == before);
	require(accepted == 0 || accepted == 1);
	*object = saved;
	restored = 1;
	if (accepted) {
		static const char trace[] = "limit-empty accepted without allocation or mutation\n";
		require(write(1, trace, sizeof(trace) - 1) == (ssize_t)(sizeof(trace) - 1));
	} else {
		static const char trace[] = "limit-overflow rejected without allocation or mutation\n";
		require(write(1, trace, sizeof(trace) - 1) == (ssize_t)(sizeof(trace) - 1));
	}
}

__attribute__((destructor)) static void finish(void) {
	require(entered && restored);
}
