/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static AstraAsyncTask *root, *child;
static void *root_frame, *child_frame;
static AstraAsyncToken token;
static unsigned mode, entries[5], observed_release, retained;
extern AstraAsyncTask *test_factory_1(AstraAsyncTask *parent);
extern int *test_loan_view(AstraAsyncTask *task);
extern AstraAsyncTask *__real_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent);
extern int __real_astra_async_delay(AstraAsyncTask *task, int64_t ticks);
extern void __real_free(void *pointer);
AstraAsyncTask *__wrap_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent) {
	AstraAsyncTask *task = __real_astra_async_new(size, alignment, resume, destroy, parent);
	if (!parent) {
		assert(!root);
		root = task;
		root_frame = astra_async_data(task);
	} else {
		assert(parent == root && !child);
		child = task;
		child_frame = astra_async_data(task);
	}
	return task;
}
int __wrap_astra_async_delay(AstraAsyncTask *task, int64_t ticks) {
	int result = __real_astra_async_delay(task, ticks);
	if (task == child && mode && !retained) {
		int *backing = test_loan_view(child);
		assert(backing && backing[0] == 20 && backing[1] == 2);
		assert(astra_async_retain(child, backing));
		token = astra_async_token(child);
		retained = 1;
	}
	return result;
}
void __wrap_free(void *pointer) {
	if (pointer && (pointer == root_frame || pointer == child_frame)) {
		assert(!retained || observed_release);
		if (pointer == root_frame) {
			root_frame = NULL;
		} else {
			child_frame = NULL;
		}
	}
	__real_free(pointer);
}
void loan_event(int stage, int value) {
	assert(stage > 0 && stage < 5 && value == (stage == 1 ? 23 : 42));
	entries[stage]++;
}
static void release(AstraAsyncExecutor *executor, int value) {
	assert(retained && !observed_release && astra_async_provider_read(executor, token) == value);
	observed_release = 1;
	assert(astra_async_observe_release(executor, token));
	assert(!astra_async_observe_release(executor, token) && astra_async_provider_read(executor, token) == -1);
}
static void drive(AstraAsyncExecutor *executor) {
	for (unsigned turn = 0; astra_async_phase(root) < ASTRA_ASYNC_SUCCESS; turn++) {
		assert(turn < 50);
		astra_async_pump(executor, 8);
		astra_async_advance_next(executor);
	}
}
static void run(unsigned selected) {
	mode = selected;
	observed_release = retained = 0;
	root = child = NULL;
	AstraAsyncExecutor *executor = astra_async_open(3);
	AstraAsyncTask *created = test_factory_1(NULL);
	assert(created == root);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_pump(executor, 2) == 2 && child);
	if (mode == 2) {
		release(executor, 20);
	}
	if (mode == 3) {
		astra_async_cancel(root);
		astra_async_pump(executor, 8);
		assert(astra_async_phase(root) < ASTRA_ASYNC_SUCCESS && root_frame && child_frame);
		release(executor, 20);
	} else if (mode == 1 || mode == 4) {
		for (unsigned turn = 0; astra_async_phase(child) != ASTRA_ASYNC_DRAINING; turn++) {
			assert(turn < 30);
			astra_async_advance_next(executor);
			astra_async_pump(executor, 8);
		}
		assert(astra_async_phase(root) == ASTRA_ASYNC_WAITING && astra_async_provider_read(executor, token) == 40);
		if (mode == 4) {
			astra_async_cancel(root);
			astra_async_pump(executor, 8);
			assert(astra_async_phase(root) < ASTRA_ASYNC_SUCCESS);
		}
		release(executor, 40);
	}
	drive(executor);
	int phase = mode >= 3 ? ASTRA_ASYNC_CANCELLED : ASTRA_ASYNC_SUCCESS;
	assert(astra_async_phase(root) == phase);
	astra_async_begin_shutdown(executor);
	assert(astra_async_observe_root(executor, root, phase == ASTRA_ASYNC_SUCCESS) == phase);
	assert(!root_frame && !child_frame && astra_async_finish_shutdown(executor));
	if (retained) {
		assert(!astra_async_wake(executor, token) && astra_async_provider_read(executor, token) == -1);
	}
	astra_async_close(executor);
}
int main(void) {
	for (unsigned cycle = 0; cycle < 16; cycle++) {
		for (unsigned selected = 0; selected < 5; selected++) {
			run(selected);
		}
	}
	assert(entries[1] == 80 && entries[2] == 64 && entries[3] == 48 && entries[4] == 48);
	puts("generated sealed parent-local loans passed: exact two views, stable backing, both release orders, pending success, parent cancellation and stale retirement");
	return 0;
}
