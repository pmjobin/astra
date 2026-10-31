// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern void *__libc_calloc(size_t count, size_t size);
extern void __libc_free(void *pointer);
struct allocation {
	void *pointer;
	size_t bytes;
	int live;
};
static struct allocation allocations[256];
static int used;
static int calls;
static int releases;
static void *exception;
static void *origin;
static void *text;
static int text_count;
static int observed;
static int drops;
static int failed;
static int prior_calls;
static int prior_releases;
#ifndef ERROR_MEMORY_ONLY
void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	if (pointer != NULL && used < 256 && (size == 0 || count <= SIZE_MAX / size)) {
		allocations[used++] = (struct allocation){pointer, count * size, 1};
	}
	calls++;
	return pointer;
}
void free(void *pointer) {
	if (pointer != NULL) {
		for (int i = 0; i < used; i++) {
			if (allocations[i].live && allocations[i].pointer == pointer) {
				allocations[i].live = 0;
				releases++;
			}
		}
	}
	__libc_free(pointer);
}
#endif
void error_record_drop(int value) {
	drops = drops * 10 + value;
}
void error_observe(int stage) {
#ifdef ERROR_MEMORY_ONLY
	if (stage != observed + 1) {
		failed = 1;
	}
	observed = stage;
	return;
#endif
	void *found = NULL;
	for (int i = 0; i < used; i++) {
		if (!allocations[i].live || allocations[i].bytes != 40) {
			continue;
		}
		void **header = allocations[i].pointer;
		if (header[0] != NULL && header[1] != NULL) {
			if (found != NULL) {
				failed = 1;
			}
			found = header;
		}
	}
	if (found == NULL || stage != observed + 1) {
		failed = 1;
		return;
	}
	void **header = found;
	void *backing;
	int count;
	int payload;
	memcpy(&backing, (char *)found + 16, sizeof backing);
	memcpy(&count, (char *)found + 24, sizeof count);
	memcpy(&payload, (char *)found + 32, sizeof payload);
	if (stage == 1) {
		exception = found;
		origin = header[1];
		text = backing;
		text_count = count;
	} else if (found != exception || header[1] != origin || backing != text || count != text_count) {
		failed = 1;
	}
	if (payload != 42 || count != 10 || memcmp(backing, "rethrow\0\xc3\xa9", 10) != 0) {
		failed = 1;
	}
	if (stage == 2 && (calls != prior_calls || releases != prior_releases)) {
		failed = 1;
	}
	prior_calls = calls;
	prior_releases = releases;
	observed = stage;
}
int error_observer_result(void) {
#ifdef ERROR_MEMORY_ONLY
	fprintf(stdout, "memory-control stages=%d drops=%d\n", observed, drops);
	return !failed && observed == 4 && drops == 4321;
#endif
	int live = 0;
	for (int i = 0; i < used; i++) {
		if (allocations[i].live) {
			live++;
		}
	}
	const unsigned char *record = origin;
	int path_count = 0;
	int line = 0;
	int column = 0;
	if (record != NULL) {
		memcpy(&path_count, record + 8, 4);
		memcpy(&line, record + 12, 4);
		memcpy(&column, record + 16, 4);
	}
	int valid = !failed && observed == 4 && drops == 4321 && live == 0 && path_count > 0 && line == 21 && column > 0;
	fprintf(stdout, "native-observer identity=%d origin=%d payload=%d getter-effects=%d drops=%d live=%d alloc=%d free=%d\n", !failed, line, !failed, !failed, drops, live, calls, releases);
	return valid;
}
