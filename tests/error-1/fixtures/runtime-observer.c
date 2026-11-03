// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
extern void *__libc_calloc(size_t count, size_t size);
extern void __libc_free(void *pointer);
static int calls, releases, writes, observed, drops, failed;
static const unsigned char *input;
static int input_count, prior_calls, prior_releases, prior_writes;
#ifndef ERROR_MEMORY_ONLY

static struct {
	void *pointer;
	size_t bytes;
	int live;
} allocations[256];

static int used;
static const unsigned char *first_snapshot, *second_snapshot;

void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	if (pointer != NULL && used < 256 && (size == 0 || count <= SIZE_MAX / size)) {
		allocations[used].pointer = pointer;
		allocations[used].bytes = count * size;
		allocations[used].live = 1;
		used++;
	}
	calls++;
	return pointer;
}

void free(void *pointer) {
	for (int i = 0; i < used; i++) {
		if (allocations[i].pointer == pointer && allocations[i].live) {
			allocations[i].live = 0;
			releases++;
		}
	}
	__libc_free(pointer);
}

ssize_t write(int fd, const void *bytes, size_t count) {
	writes++;
	return syscall(SYS_write, fd, bytes, count);
}

static int live_backing(const void *pointer, int count) {
	for (int i = 0; i < used; i++) {
		if (allocations[i].live && allocations[i].pointer == pointer && allocations[i].bytes == (size_t)count) {
			return 1;
		}
	}
	return 0;
}

#endif

void runtime_input(const unsigned char *text, int32_t count) {
	input = text;
	input_count = count;
}

void runtime_drop(int32_t rank) {
	drops = drops * 10 + rank;
}

void runtime_snapshot(int32_t stage, const unsigned char *text, int32_t count) {
	if (stage != observed + 1 || count != input_count || memcmp(text, input, (size_t)count) != 0) {
		failed = 1;
	}
#ifndef ERROR_MEMORY_ONLY
	if (text == input || !live_backing(text, count)) {
		failed = 1;
	}
	if (stage == 1) {
		first_snapshot = text;
		int objects = 0;
		for (int i = 0; i < used; i++) {
			if (!allocations[i].live || allocations[i].bytes != 56) {
				continue;
			}
			const unsigned char *object = allocations[i].pointer;
			void *backing;
			int payload;
			memcpy(&backing, object + 32, sizeof backing);
			memcpy(&payload, object + 48, sizeof payload);
			if (backing == text && payload == 42) {
				objects++;
			}
		}
		if (objects != 1) {
			failed = 1;
		}
	}
	if (stage == 2 && (text != first_snapshot || calls != prior_calls || releases != prior_releases || writes != prior_writes)) {
		failed = 1;
	}
	if (stage == 3) {
		second_snapshot = text;
		if (text == first_snapshot || live_backing(first_snapshot, count) || drops != 321) {
			failed = 1;
		}
	}
#endif
	prior_calls = calls;
	prior_releases = releases;
	prior_writes = writes;
	observed = stage;
}

int32_t runtime_result(void) {
#ifdef ERROR_MEMORY_ONLY
	fprintf(stdout, "runtime-memory stages=%d drops=%d\n", observed, drops);
	return !failed && observed == 3 && drops == 3211;
#else
	int live = 0;
	for (int i = 0; i < used; i++) {
		live += allocations[i].live;
	}
	int valid = !failed && observed == 3 && drops == 3211 && live == 0 && first_snapshot != NULL && second_snapshot != NULL;
	fprintf(stdout, "runtime-observer input-distinct=%d snapshot-distinct=%d full-derived=%d getter-effects=%d drops=%d live=%d alloc=%d free=%d io=%d\n", !failed, first_snapshot != second_snapshot, !failed, !failed, drops, live, calls, releases, writes);
	return valid;
#endif
}
