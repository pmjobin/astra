/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Resource {
	unsigned identity;
	int value;
} Resource;
static Resource *live[1024];
static unsigned opened, closed, entries[13];
static int close_values[1024];
Resource *open_resource(int value) {
	assert(opened < 1024);
	Resource *resource = calloc(1, sizeof(*resource));
	assert(resource);
	resource->identity = opened;
	resource->value = value;
	live[opened++] = resource;
	return resource;
}
int read_resource(Resource *resource) {
	assert(resource && resource->identity < opened && live[resource->identity] == resource);
	return resource->value;
}
void close_resource(Resource *resource) {
	assert(resource && resource->identity < opened && live[resource->identity] == resource);
	live[resource->identity] = NULL;
	close_values[closed++] = resource->value;
	free(resource);
}
void resource_event(int stage, int value) {
	assert(stage >= 1 && stage <= 12 && stage != 4);
	int expected = stage == 8 ? 92 : stage == 11            ? 10
	                             : stage == 7               ? 10
	                             : stage == 1 || stage == 5 ? 30
	                                                        : 42;
	if (value != expected) {
		fprintf(stderr, "resource stage=%d value=%d expected=%d\n", stage, value, expected);
	}
	assert(value == expected);
	entries[stage]++;
}
extern int resource_cold(void);
extern int resource_abort(void);
extern int resource_host(void);
extern int resource_admission(void);
extern int resource_fresh(void);
extern int resource_fresh_abort(void);
extern int mixed_host(void);
extern int resource_nested_abort(void);
extern int mixed_replace_host(void);
extern AstraAsyncTask *test_factory_13(AstraAsyncTask *parent);
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
static void cancel_composed(int handler) {
	AstraAsyncExecutor *executor = astra_async_open(3);
	AstraAsyncTask *root = test_factory_13(NULL);
	unsigned entered = entries[9];
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	if (!handler) {
		assert(astra_async_pump(executor, 2) == 2);
	} else {
		for (unsigned turns = 0; entries[9] == entered; turns++) {
			assert(turns < 40);
			astra_async_pump(executor, 1);
			astra_async_advance_next(executor);
		}
	}
	astra_async_cancel(root);
	for (unsigned turns = 0; astra_async_phase(root) < ASTRA_ASYNC_SUCCESS; turns++) {
		assert(turns < 40);
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
		assert(resource_cold() == 42);
		assert(resource_abort() == 42);
		assert(resource_host() == 42);
		assert(resource_admission() == 42);
		cancel_source();
		assert(resource_fresh() == 42);
		assert(resource_fresh_abort() == 42);
		assert(mixed_host() == 42);
		assert(mixed_replace_host() == 42);
		cancel_composed(1);
		cancel_composed(0);
		assert(resource_nested_abort() == 42);
		static const int expected[] = {20, 10, 20, 10, 20, 10, 32, 20, 10, 41, 40, 20, 10, 20, 10, 60, 61, 10, 70, 50, 60, 61, 10, 60, 61, 10, 50, 60, 61, 10, 50, 10, 50, 22, 21, 10};
		assert(opened == closed);
		for (unsigned i = 0; i < 36; i++) {
			assert(close_values[cycle * 36 + i] == expected[i]);
		}
		for (unsigned i = 0; i < opened; i++) {
			assert(!live[i]);
		}
	}
	assert(opened == 576);
	for (unsigned stage = 1; stage <= 12; stage++) {
		assert(entries[stage] == (stage == 4 ? 0 : stage == 9 ? 48
		                                       : stage == 10  ? 64
		                                       : stage == 11  ? 80
		                                                      : 16));
	}
	puts("generated Resource captures passed: exact live identities, cold disposal, abort, rearm, refusal and cancellation");
	return 0;
}
