/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "linux.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static unsigned events[10];
#ifndef ASTRA_LINUX_PLAIN_OBSERVER
#include <liburing.h>
static AstraAsyncTask *root_task, *slow_task;
static void *root_frame, *slow_frame, *allocation;
static int allocation_live, slow_joined, slow_retired, root_retired;
static unsigned waits;
static uint64_t first_started, second_started;
static AstraAsyncToken slow_token;
static uint64_t first_id;
static unsigned kernel_waits;
static uint64_t kernel_wait_ns;

static uint64_t clock_ns(void) {
	struct timespec ts;
	assert(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
	return (uint64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

extern void *__real_malloc(size_t bytes);
extern void *__real_calloc(size_t count, size_t bytes);
extern void __real_free(void *pointer);
extern AstraAsyncTask *__real_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent);
extern int __real_astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds);
extern int __real_astra_async_release_wait(AstraAsyncTask *parent, int transfer);
extern void __real_astra_async_complete(AstraAsyncTask *task, int phase, void *exception);
extern int __real_io_uring_submit_and_wait(struct io_uring *ring, unsigned wait_nr);

int __wrap_io_uring_submit_and_wait(struct io_uring *ring, unsigned wait_nr) {
	assert(wait_nr == 1);
	uint64_t started = clock_ns();
	int result = __real_io_uring_submit_and_wait(ring, wait_nr);
	kernel_wait_ns += clock_ns() - started;
	kernel_waits++;
	return result;
}

void *__wrap_malloc(size_t bytes) {
	return __real_malloc(bytes);
}

void *__wrap_calloc(size_t count, size_t bytes) {
	void *pointer = __real_calloc(count, bytes);
	if (count == 17 && bytes == sizeof(int)) {
		assert(!allocation);
		allocation = pointer;
		allocation_live = 1;
	}
	return pointer;
}

void __wrap_free(void *pointer) {
	if (pointer != NULL && pointer == slow_frame && !slow_retired) {
		assert(slow_joined && waits == 2);
		slow_retired = 1;
	}
	if (pointer != NULL && pointer == root_frame) {
		root_retired = 1;
	}
	if (pointer != NULL && pointer == allocation && allocation_live) {
		assert(events[5] == 1 && slow_retired);
		allocation_live = 0;
	}
	__real_free(pointer);
}

AstraAsyncTask *__wrap_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent) {
	AstraAsyncTask *task = __real_astra_async_new(size, alignment, resume, destroy, parent);
	if (parent == NULL) {
		assert(!root_task);
		root_task = task;
		root_frame = astra_async_data(task);
	} else if (slow_task == NULL) {
		assert(parent == root_task);
		slow_task = task;
		slow_frame = astra_async_data(task);
	}
	return task;
}

int __wrap_astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds) {
	uint64_t entered = clock_ns();
	int result = __real_astra_async_linux_delay_ms(task, milliseconds);
	if (task == slow_task && !slow_retired) {
		assert(result && allocation_live && waits < 2);
		AstraAsyncToken token = astra_async_token(task);
		AstraAsyncLinuxSnapshot snapshot;
		int found = 0;
		for (uint32_t slot = 0; slot < 3; slot++) {
			if (astra_async_linux_test_snapshot(astra_async_executor(task), slot, &snapshot) && snapshot.token.slot == token.slot && snapshot.token.generation == token.generation && snapshot.token.executor == token.executor) {
				found = 1;
				break;
			}
		}
		assert(found && snapshot.prepared && snapshot.exposed && snapshot.consumed && !snapshot.target_seen && snapshot.target != snapshot.cancel);
		if (waits == 0) {
			assert(milliseconds == 100);
			first_started = entered;
			first_id = snapshot.target;
			slow_token = token;
		} else {
			assert(milliseconds == 20 && snapshot.target != first_id && snapshot.generation == 2);
			assert(token.slot == slow_token.slot && token.generation == slow_token.generation && token.executor == slow_token.executor);
			assert(clock_ns() - first_started >= 100000000);
			second_started = entered;
		}
		waits++;
	}
	return result;
}

void __wrap_astra_async_complete(AstraAsyncTask *task, int phase, void *exception) {
	if (task == slow_task && !slow_retired) {
		typedef struct Buffer {
			int *base;
			int32_t count;
		} Buffer;

		Buffer *result = astra_async_data(task);
		assert(phase == ASTRA_ASYNC_SUCCESS && exception == NULL && waits == 2 && result->base == allocation && result->count == 17 && allocation_live && result->base[0] == 40 && result->base[1] == 2);
	}
	__real_astra_async_complete(task, phase, exception);
}

int __wrap_astra_async_release_wait(AstraAsyncTask *parent, int transfer) {
	if (astra_async_waited(parent) == slow_task && !slow_retired) {
		assert(transfer && events[3] == 1);
		slow_joined = 1;
	}
	return __real_astra_async_release_wait(parent, transfer);
}

#endif

void observed(int stage, int value) {
	assert(stage >= 1 && stage <= 9 && value == (stage == 1 ? 39 : 42));
	assert(events[stage]++ == 0);
#ifndef ASTRA_LINUX_PLAIN_OBSERVER
	if (stage == 2) {
		assert(waits == 1 && !slow_retired && allocation_live && astra_async_phase(slow_task) == ASTRA_ASYNC_WAITING);
		assert(!astra_async_linux_test_queued(astra_async_executor(slow_task), first_id));
		printf("REAL peer progress: target=%llu still pending, elapsed_ns=%llu\n", (unsigned long long)first_id, (unsigned long long)(clock_ns() - first_started));
	}
	if (stage == 3) {
		assert(waits == 2 && clock_ns() - second_started >= 20000000 && events[2] == 1 && allocation_live);
	}
	if (stage == 4 || stage == 5) {
		assert(slow_retired && allocation_live && ((int *)allocation)[0] == (stage == 4 ? 40 : 42));
	}
#endif
}

__attribute__((destructor)) static void verify(void) {
	for (unsigned i = 1; i <= 7; i++) {
		assert(events[i] == 1);
	}
#ifndef ASTRA_LINUX_PLAIN_OBSERVER
	assert(events[9] == 1 && waits == 2 && slow_retired && root_retired && !allocation_live);
	assert(kernel_waits != 0);
	printf("REAL liburing kernel wait: calls=%u elapsed_ns=%llu; no user body dispatch in wait\n", kernel_waits, (unsigned long long)kernel_wait_ns);
#else
	assert(events[9] == 1);
#endif
	puts("generated Linux tasks: real pending interleaving, two waits, same owned allocation after child retirement, aggregate results, message/rethrow and loan passed");
}
