/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdio.h>
static unsigned entries[9];
void storage_event(int stage, int value) {
	static const int expected[] = {0, 40, 42, 39, 39, 5, 5, 3};
	assert(stage > 0 && stage < 8 && value == expected[stage]);
	entries[stage]++;
}
extern int storage_host(void);
extern int storage_cold(void);
extern AstraAsyncTask *test_factory_2(AstraAsyncTask *parent);
static void cancel_source(void) {
	AstraAsyncExecutor *executor = astra_async_open(1);
	AstraAsyncTask *root = test_factory_2(NULL);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_pump(executor, 1) == 1);
	astra_async_cancel(root);
	for (unsigned turn = 0; astra_async_phase(root) < ASTRA_ASYNC_SUCCESS; turn++) {
		assert(turn < 40);
		astra_async_pump(executor, 8);
		astra_async_advance_next(executor);
	}
	assert(astra_async_phase(root) == ASTRA_ASYNC_CANCELLED);
	astra_async_begin_shutdown(executor);
	assert(astra_async_observe_root(executor, root, 0) == ASTRA_ASYNC_CANCELLED);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}
int main(void) {
	for (unsigned cycle = 0; cycle < 16; cycle++) {
		assert(storage_host() == 42);
		assert(storage_cold() == 42);
		cancel_source();
	}
	for (unsigned stage = 1; stage < 8; stage++) {
		assert(entries[stage] == 16);
	}
	puts("generated persistent record/array/enum state and two owning enum captures passed");
	return 0;
}
