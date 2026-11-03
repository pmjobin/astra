/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern AstraAsyncTask *test_factory_2(AstraAsyncTask *parent);
extern AstraAsyncTask *test_factory_3(AstraAsyncTask *parent);
extern int host(void);
extern int host_cancel(void);
extern int host_invalid_capacity(void);
extern int host_original_error(void);
extern int host_invalid_delay(void);
extern int host_replacement(void);
extern int host_concurrent(void);
extern int host_refused_start(void);
extern int host_refused_await(void);
extern int host_child_cancel(void);
extern int host_sibling_error(void);
extern int host_discard_outcomes(void);
extern int host_parent_only(void);
static int counts[24];

void observed(int stage, int value) {
	assert(stage > 0 && stage < 24);
	assert(value == (stage == 1 ? 22 : 42));
	if (stage == 11) {
		assert(counts[10] == 1);
	}
	counts[stage]++;
}

static void drive(AstraAsyncExecutor *executor, AstraAsyncTask *root, int stop_at_catch) {
	for (unsigned turn = 0; astra_async_phase(root) < ASTRA_ASYNC_SUCCESS; turn++) {
		assert(turn < 80);
		astra_async_pump(executor, 1);
		if (stop_at_catch && counts[5] != 0) {
			return;
		}
		astra_async_advance_next(executor);
	}
}

static void finish(AstraAsyncExecutor *executor, AstraAsyncTask *root, int expected) {
	assert(astra_async_phase(root) == expected);
	astra_async_begin_shutdown(executor);
	assert(astra_async_shutdown_complete(executor));
	assert(astra_async_observe_root(executor, root, expected == ASTRA_ASYNC_SUCCESS) == expected);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}

int main(void) {
	for (unsigned cycle = 0; cycle < 16; cycle++) {
		for (unsigned n = 0; n < 24; n++) {
			counts[n] = 0;
		}
		AstraAsyncExecutor *executor = astra_async_open(3);
		AstraAsyncTask *root = test_factory_2(NULL);
		assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
		drive(executor, root, 0);
		assert(counts[1] == 1 && counts[2] == 1 && counts[3] == 1 && counts[5] == 1 && counts[9] == 1);
		finish(executor, root, ASTRA_ASYNC_SUCCESS);
		for (unsigned n = 0; n < 24; n++) {
			counts[n] = 0;
		}
		executor = astra_async_open(3);
		root = test_factory_2(NULL);
		assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
		drive(executor, root, 1);
		assert(counts[5] == 1 && counts[9] == 0);
		astra_async_cancel(root);
		drive(executor, root, 0);
		assert(counts[2] == 0 && counts[3] == 0 && counts[9] == 0);
		finish(executor, root, ASTRA_ASYNC_CANCELLED);
		assert(counts[9] == 1);
		for (unsigned n = 0; n < 24; n++) {
			counts[n] = 0;
		}
		executor = astra_async_open(1);
		root = test_factory_3(NULL);
		assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
		drive(executor, root, 0);
		assert(counts[4] == 1 && counts[9] == 0);
		finish(executor, root, ASTRA_ASYNC_SUCCESS);
	}
	for (unsigned n = 0; n < 24; n++) {
		counts[n] = 0;
	}
	assert(host() == 42 && counts[1] == 1 && counts[9] == 1);
	assert(host_cancel() == 42);
	assert(host_invalid_capacity() == 42);
	assert(host_invalid_delay() == 42 && counts[7] == 1);
	assert(host_original_error() == 42 && counts[6] == 1 && counts[9] == 2);
	assert(host_replacement() == 42 && counts[8] == 1 && counts[9] == 4);
	assert(host_concurrent() == 42 && counts[10] == 1 && counts[11] == 1 && counts[12] == 1);
	assert(host_refused_start() == 42 && counts[13] == 1);
	assert(host_refused_await() == 42 && counts[14] == 1);
	assert(host_child_cancel() == 42 && counts[15] == 0);
	assert(host_sibling_error() == 42 && counts[16] == 1 && counts[11] == 1 && counts[9] == 5);
	assert(host_discard_outcomes() == 42 && counts[17] == 1 && counts[18] == 1 && counts[9] == 6);
	assert(host_parent_only() == 42 && counts[19] == 0 && counts[20] == 2 && counts[21] == 2);
	puts("source await passed: value delivery; original derived exception, suspended message/rethrow; catch cancellation; cold cancel-and-join");
	return 0;
}
