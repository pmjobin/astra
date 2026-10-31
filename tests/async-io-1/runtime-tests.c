/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "linux.h"
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

typedef struct Frame {
	int turns;
	int error;
	int destroyed;
} Frame;
static int destroys;
static uint64_t clock_ns(void) {
	struct timespec ts;
	assert(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
	return (uint64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}
static void destroy(AstraAsyncTask *task, int discard) {
	(void)task;
	(void)discard;
	destroys++;
}
static void resume(AstraAsyncTask *task) {
	Frame *f = astra_async_data(task);
	f->turns++;
	if (astra_async_cancel_requested(task)) {
		if (astra_async_cancel_scope(task)) {
			astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
		}
		return;
	}
	if (astra_async_pc(task) == 0) {
		astra_async_set_pc(task, 1);
		assert(astra_async_linux_delay_ms(task, 20));
		return;
	}
	f->error = astra_async_linux_delay_result(task, 1);
	astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
}
static AstraAsyncTask *root(AstraAsyncExecutor *executor) {
	AstraAsyncTask *task = astra_async_new(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL);
	*(Frame *)astra_async_data(task) = (Frame){0};
	assert(astra_async_start(executor, task, NULL) == ASTRA_ASYNC_ADMITTED);
	return task;
}
int main(void) {
	alarm(15);
	assert(astra_async_linux_open(0) == NULL && astra_async_linux_last_failure().operation == ASTRA_LINUX_CAPACITY);
	assert(astra_async_linux_open(17) == NULL);
	for (int trial = 0; trial < 16; trial++) {
		AstraAsyncExecutor *executor = astra_async_linux_open(2);
		if (executor == NULL) {
			fprintf(stderr, "Linux startup blocked: operation=%d errno=%d\n", astra_async_linux_last_failure().operation, astra_async_linux_last_failure().error);
			return 77;
		}
		uint64_t start = clock_ns();
		astra_async_linux_wait(executor); /* No external work: no nonexistent wait. */
		AstraAsyncTask *task = root(executor);
		Frame *f = astra_async_data(task);
		astra_async_linux_wait(executor); /* Ready task: no user dispatch. */
		assert(f->turns == 0);
		assert(astra_async_pump(executor, 1) == 1 && f->turns == 1);
		assert(astra_async_phase(task) == ASTRA_ASYNC_WAITING);
		AstraAsyncToken token = astra_async_token(task);
		if (trial % 2) {
			astra_async_host_cancel(executor, task);
			astra_async_host_cancel(executor, task);
			astra_async_begin_shutdown(executor);
			assert(!astra_async_shutdown_complete(executor));
		}
		while (astra_async_phase(task) < ASTRA_ASYNC_SUCCESS) {
			astra_async_linux_wait(executor);
			assert(f->turns <= 2 || trial % 2);
			astra_async_pump(executor, 1);
		}
		int wanted = trial % 2 ? ASTRA_ASYNC_CANCELLED : ASTRA_ASYNC_SUCCESS;
		assert(astra_async_phase(task) == wanted && f->error == 0);
		if (!(trial % 2)) {
			assert(clock_ns() - start >= 20000000 && f->turns == 2);
		}
		astra_async_cancel(task); /* Published outcome is immutable. */
		assert(astra_async_phase(task) == wanted);
		astra_async_begin_shutdown(executor);
		assert(astra_async_shutdown_complete(executor));
		assert(!astra_async_finish_shutdown(executor));
		assert(astra_async_observe_root(executor, task, wanted == ASTRA_ASYNC_SUCCESS) == wanted);
		assert(!astra_async_wake(executor, token));
		assert(astra_async_finish_shutdown(executor));
		astra_async_close(executor);
	}
	assert(destroys == 16);
	AstraAsyncExecutor *pressure = astra_async_linux_open(16);
	assert(pressure != NULL);
	AstraAsyncTask *parent = root(pressure);
	for (unsigned i = 0; i < 15; i++) {
		AstraAsyncTask *child = astra_async_new(sizeof(Frame), _Alignof(Frame), resume, destroy, parent);
		*(Frame *)astra_async_data(child) = (Frame){0};
		assert(astra_async_start(pressure, child, parent) == ASTRA_ASYNC_ADMITTED);
	}
	assert(astra_async_pump(pressure, 16) == 16);
	astra_async_begin_shutdown(pressure);
	while (!astra_async_shutdown_complete(pressure)) {
		astra_async_pump(pressure, 16);
		astra_async_linux_wait(pressure);
	}
	assert(astra_async_observe_root(pressure, parent, 0) == ASTRA_ASYNC_CANCELLED);
	assert(astra_async_finish_shutdown(pressure));
	astra_async_close(pressure);
	assert(destroys == 32);
	puts("real native adapter: 8 expiry, 8 cancel, bounded pump, nondispatching wait, immutable publication, root observation and close");
	return 0;
}
