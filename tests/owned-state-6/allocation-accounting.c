// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Selected GNU ELF --wrap boundary; no allocator implementation is replaced.
#include <stddef.h>
#include <stdio.h>
void *__real_calloc(size_t, size_t);
void __real_free(void *);
static struct {
	void *pointer;
	size_t bytes;
} allocations[1024];
static int calls, live;
static size_t bytes;
void *__wrap_calloc(size_t count, size_t width) {
	void *pointer = __real_calloc(count, width);
	if (!pointer) return pointer;
	for (int i = 0; i < 1024; ++i) {
		if (!allocations[i].pointer) {
			allocations[i].pointer = pointer;
			allocations[i].bytes = count * width;
			++calls;
			++live;
			bytes += count * width;
			return pointer;
		}
	}
	__builtin_trap();
}
void __wrap_free(void *pointer) {
	for (int i = 0; pointer && i < 1024; ++i) {
		if (allocations[i].pointer == pointer) {
			--live;
			bytes -= allocations[i].bytes;
			allocations[i].pointer = NULL;
			break;
		}
	}
	__real_free(pointer);
}
int arena_checkpoint(int phase, int expected_live, int expected_calls, int expected_bytes) {
	printf("arena phase=%d live=%d calls=%d bytes=%zu\n", phase, live, calls, bytes);
	return live != expected_live || (expected_calls >= 0 && calls != expected_calls) || bytes != (size_t)expected_bytes;
}
int arena_accounting(void);
int main(void) {
	return arena_accounting();
}
