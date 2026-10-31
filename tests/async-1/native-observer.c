/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

extern AstraAsyncTask *test_factory_0(int tag, uint32_t ticks, int seed, AstraAsyncTask *parent);
extern AstraAsyncTask *test_factory_1(AstraAsyncTask *parent);
extern int cold(void);
static int captures;
int capture(int ordinal) {
	assert(ordinal == ++captures);
	return ordinal;
}
static AstraAsyncTask *tasks[3];
static void *frames[3];
static int events[3];
static int steps[3];
static volatile int injected = 7;
static int starts[3] = {0, 10, 40};
void event(int tag, int value) {
	assert(tag == 1 || tag == 2);
	assert(astra_async_data(tasks[tag]) == frames[tag]);
	int expected = starts[tag];
	for (int n = 0; n < events[tag]; n++) {
		expected += tag * 10 + n + injected;
	}
	assert(value == expected);
	events[tag]++;
}
int step(int tag, int ordinal) {
	assert(tag == 1 || tag == 2);
	assert(ordinal == steps[tag]++);
	return tag * 10 + ordinal + injected;
}
static void finish(AstraAsyncExecutor *executor, AstraAsyncTask *root, int phase) {
	assert(astra_async_phase(root) == phase);
	astra_async_begin_shutdown(executor);
	assert(astra_async_shutdown_complete(executor));
	assert(!astra_async_finish_shutdown(executor));
	assert(astra_async_observe_root(executor, root, phase == ASTRA_ASYNC_SUCCESS) == phase);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}
static void source_progress(void) {
	AstraAsyncExecutor *executor = astra_async_open(3);
	AstraAsyncTask *root = test_factory_1(NULL);
	tasks[1] = test_factory_0(1, 5, starts[1], root);
	tasks[2] = test_factory_0(2, 1, starts[2], root);
	frames[1] = astra_async_data(tasks[1]);
	frames[2] = astra_async_data(tasks[2]);
	assert(frames[1] != frames[2] && events[1] == 0 && events[2] == 0);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(executor, tasks[1], root) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(executor, tasks[2], root) == ASTRA_ASYNC_ADMITTED);
	AstraAsyncToken stale = astra_async_token(tasks[2]);
	assert(astra_async_retain(tasks[2], frames[2]));
	assert(astra_async_pump(executor, 3) == 3 && events[1] == 1 && events[2] == 1);
	for (unsigned turn = 0; steps[2] != 3; turn++) {
		assert(turn < 16);
		assert(astra_async_advance_next(executor));
		assert(astra_async_pump(executor, 8) != 0);
	}
	assert(events[1] == 1 && steps[1] == 0 && events[2] == 3);
	assert(astra_async_phase(tasks[2]) == ASTRA_ASYNC_DRAINING && astra_async_provider_read(executor, stale) == ((starts[2] + 6 * 10 + 3 + 3 * injected) & 255));
	assert(astra_async_observe_release(executor, stale));
	assert(astra_async_phase(tasks[2]) == ASTRA_ASYNC_SUCCESS);
	assert(*(int *)frames[2] == starts[2] + 6 * 10 + 3 + 3 * injected);
	assert(astra_async_wait(root, tasks[2], 0) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_waited(root) == tasks[2]);
	assert(astra_async_release_wait(root, 1) == ASTRA_ASYNC_SUCCESS);
	assert(!astra_async_wake(executor, stale) && astra_async_provider_read(executor, stale) == -1);
	for (unsigned turn = 0; steps[1] != 3; turn++) {
		assert(turn < 16);
		assert(astra_async_pump(executor, 8) <= 8);
		assert(astra_async_advance_next(executor));
		assert(astra_async_pump(executor, 8) != 0);
	}
	assert(events[1] == 3 && *(int *)frames[1] == starts[1] + 3 * 10 + 3 + 3 * injected);
	assert(astra_async_wait(root, tasks[1], 0) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_release_wait(root, 1) == ASTRA_ASYNC_SUCCESS);
	assert(astra_async_pump(executor, 8) <= 8);
	assert(astra_async_advance_next(executor));
	assert(astra_async_pump(executor, 8) != 0);
	finish(executor, root, ASTRA_ASYNC_SUCCESS);
}
static void source_cancellation(void) {
	int before = events[1];
	AstraAsyncTask *cold = test_factory_0(1, 5, starts[1], NULL);
	astra_async_cancel(cold);
	astra_async_drop(cold);
	assert(events[1] == before);
	AstraAsyncExecutor *executor = astra_async_open(2);
	AstraAsyncTask *root = test_factory_1(NULL);
	AstraAsyncTask *child = test_factory_0(1, 5, starts[1], root);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(executor, child, root) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_retain(child, astra_async_data(child)));
	AstraAsyncToken token = astra_async_token(child);
	astra_async_cancel(root);
	assert(astra_async_pump(executor, 8) >= 2);
	assert(astra_async_phase(root) == ASTRA_ASYNC_DRAINING && events[1] == before);
	assert(astra_async_provider_read(executor, token) == 0);
	assert(astra_async_observe_release(executor, token));
	assert(astra_async_pump(executor, 8) != 0);
	finish(executor, root, ASTRA_ASYNC_CANCELLED);
}
int main(int argc, char **argv) {
	if (argc == 2) {
		injected = atoi(argv[1]);
	}
	assert(cold() == 42 && captures == 6 && events[1] == 0 && events[2] == 0);
	for (unsigned cycle = 0; cycle < 16; cycle++) {
		events[1] = events[2] = steps[1] = steps[2] = 0;
		source_progress();
		source_cancellation();
	}
	printf("compiled source frames passed: cycles=16 injected=%d slow=3 fast=3; retained release and cancellation observed\n", injected);
	return 0;
}
