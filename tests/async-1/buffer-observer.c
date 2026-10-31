/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern AstraAsyncTask *test_factory_0(int seed, AstraAsyncTask *parent);
extern AstraAsyncTask *test_factory_1(AstraAsyncTask *parent);
extern AstraAsyncTask *test_factory_2(AstraAsyncTask *parent);
extern AstraAsyncTask *test_factory_3(AstraAsyncTask *parent);
typedef struct Buffer {
	int *base;
	int32_t length;
} Buffer;
extern AstraAsyncTask *test_factory_5(AstraAsyncTask *parent);
extern int cold_captures(void);
extern int capture_abort(void);
extern int fresh_captures(void);
extern int fresh_abort(void);
static unsigned counts[7];
void buffered(int stage, int value) {
	assert(stage >= 1 && stage <= 6);
	assert(value == (stage == 1 ? 123 : stage == 2 ? 41
	                                               : 42));
	counts[stage]++;
}
static void drive(AstraAsyncExecutor *executor, AstraAsyncTask *task) {
	for (unsigned turn = 0; astra_async_phase(task) < ASTRA_ASYNC_SUCCESS; turn++) {
		assert(turn < 40);
		astra_async_pump(executor, 8);
		astra_async_advance_next(executor);
	}
}
static void finish(AstraAsyncExecutor *executor, AstraAsyncTask *root, int phase) {
	assert(astra_async_phase(root) == phase);
	astra_async_begin_shutdown(executor);
	assert(astra_async_shutdown_complete(executor));
	assert(astra_async_observe_root(executor, root, phase == ASTRA_ASYNC_SUCCESS) == phase);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}
static void source_owned_await(void) {
	AstraAsyncExecutor *executor = astra_async_open(2);
	AstraAsyncTask *root = test_factory_1(NULL);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	drive(executor, root);
	finish(executor, root, ASTRA_ASYNC_SUCCESS);
	executor = astra_async_open(2);
	root = test_factory_1(NULL);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_pump(executor, 2) == 2);
	astra_async_cancel(root);
	drive(executor, root);
	finish(executor, root, ASTRA_ASYNC_CANCELLED);
	executor = astra_async_open(1);
	root = test_factory_2(NULL);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_pump(executor, 1) == 1);
	astra_async_cancel(root);
	drive(executor, root);
	finish(executor, root, ASTRA_ASYNC_CANCELLED);
	/* Discarding a published original exception frees both its message and the
	 * source buffer, whose scope cleanup ran before exceptional publication. */
	executor = astra_async_open(1);
	root = test_factory_2(NULL);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	drive(executor, root);
	assert(astra_async_phase(root) == ASTRA_ASYNC_EXCEPTION);
	astra_async_begin_shutdown(executor);
	assert(astra_async_observe_root(executor, root, 0) == ASTRA_ASYNC_EXCEPTION);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}
static void result_outlives_frame(void) {
	AstraAsyncExecutor *executor = astra_async_open(2);
	AstraAsyncTask *root = test_factory_3(NULL);
	AstraAsyncTask *child = test_factory_0(17, root);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(executor, child, root) == ASTRA_ASYNC_ADMITTED);
	drive(executor, child);
	assert(astra_async_phase(child) == ASTRA_ASYNC_SUCCESS);
	Buffer result = *(Buffer *)astra_async_data(child);
	assert(result.length == 3 && result.base[0] == 17 && result.base[2] == 19);
	AstraAsyncToken stale = astra_async_token(child);
	assert(astra_async_wait(root, child, 0) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_release_wait(root, 1) == ASTRA_ASYNC_SUCCESS);
	assert(!astra_async_wake(executor, stale));
	result.base[1] = 42;
	assert(result.base[0] + result.base[1] + result.base[2] == 78);
	free(result.base);
	drive(executor, root);
	finish(executor, root, ASTRA_ASYNC_SUCCESS);
}
int main(void) {
	for (unsigned cycle = 0; cycle < 16; cycle++) {
		source_owned_await();
		result_outlives_frame();
		assert(cold_captures() == 42);
		assert(capture_abort() == 42);
		assert(fresh_captures() == 42);
		assert(fresh_abort() == 42);
		AstraAsyncExecutor *executor = astra_async_open(3);
		AstraAsyncTask *root = test_factory_5(NULL);
		assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
		drive(executor, root);
		finish(executor, root, ASTRA_ASYNC_SUCCESS);
	}
	for (unsigned stage = 1; stage <= 6; stage++) {
		assert(counts[stage] == 16);
	}
	puts("owned source await passed: complete buffer transfer, frame retirement, cancellation and original exception cleanup");
	return 0;
}
