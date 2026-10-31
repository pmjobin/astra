/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static unsigned entries[12];
static const uint32_t patterns[] = {UINT32_C(0x80000000), UINT32_C(0x00000001), UINT32_C(0x7fc01234)};
static unsigned selected;
float input_float(void) {
	float value;
	memcpy(&value, &patterns[selected], sizeof(value));
	return value;
}
int float_bits(float value) {
	uint32_t bits;
	memcpy(&bits, &value, sizeof(bits));
	return bits == patterns[selected] ? 42 : 81;
}
void result_event(int stage, int value) {
	static const int expected[] = {0, 42, 44, 42, 42, 5, 42, 42, 42, 42, 42, 42};
	assert(stage > 0 && stage < 12 && value == expected[stage]);
	entries[stage]++;
}
extern int result_host(void);
extern int owning_abort(void);
static AstraAsyncTask *root, *child;
static void *root_frame, *child_frame, *backing;
static unsigned held_mode, held_kind, retained, released;
static AstraAsyncToken token;
extern AstraAsyncTask *test_factory_5(AstraAsyncTask *parent);
extern AstraAsyncTask *test_factory_9(AstraAsyncTask *parent);
extern unsigned char *test_owning_backing(AstraAsyncTask *task);
extern unsigned char *test_record_backing(AstraAsyncTask *task);
extern AstraAsyncTask *__real_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent);
extern int __real_astra_async_delay(AstraAsyncTask *task, int64_t ticks);
extern void __real_free(void *pointer);
AstraAsyncTask *__wrap_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent) {
	AstraAsyncTask *task = __real_astra_async_new(size, alignment, resume, destroy, parent);
	if (held_mode) {
		if (!parent) {
			assert(!root);
			root = task;
			root_frame = astra_async_data(task);
		} else {
			assert(parent == root && !child);
			child = task;
			child_frame = astra_async_data(task);
		}
	}
	return task;
}
int __wrap_astra_async_delay(AstraAsyncTask *task, int64_t ticks) {
	int result = __real_astra_async_delay(task, ticks);
	if (held_mode && task == child && !retained) {
		unsigned char *data = held_kind ? test_record_backing(child) : test_owning_backing(child);
		assert(data);
		*data = 73;
		backing = data;
		assert(astra_async_retain(child, backing));
		token = astra_async_token(child);
		retained = 1;
	}
	return result;
}
void __wrap_free(void *pointer) {
	if (held_mode && pointer && (pointer == root_frame || pointer == child_frame || pointer == backing)) {
		assert(released);
		if (pointer == root_frame) {
			root_frame = NULL;
		} else if (pointer == child_frame) {
			child_frame = NULL;
		} else {
			backing = NULL;
		}
	}
	__real_free(pointer);
}
static void held_result(unsigned kind, unsigned mode) {
	held_kind = kind;
	held_mode = mode;
	root = child = NULL;
	root_frame = child_frame = backing = NULL;
	retained = released = 0;
	AstraAsyncExecutor *executor = astra_async_open(3);
	AstraAsyncTask *created = kind ? test_factory_9(NULL) : test_factory_5(NULL);
	assert(created == root);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	for (unsigned turns = 0; !child || astra_async_phase(child) != ASTRA_ASYNC_DRAINING; turns++) {
		assert(turns < 40);
		astra_async_pump(executor, 8);
		astra_async_advance_next(executor);
	}
	int expected_byte = kind ? 75 : 73;
	assert(root_frame && child_frame && backing && astra_async_provider_read(executor, token) == expected_byte);
	if (mode == 2) {
		for (unsigned turns = 0; astra_async_phase(root) != ASTRA_ASYNC_WAITING; turns++) {
			assert(turns < 40);
			astra_async_pump(executor, 8);
			astra_async_advance_next(executor);
		}
		astra_async_pump(executor, 8);
	}
	if (mode == 3) {
		astra_async_cancel(root);
		astra_async_pump(executor, 8);
	}
	assert(astra_async_phase(root) < ASTRA_ASYNC_SUCCESS && astra_async_provider_read(executor, token) == expected_byte);
	released = 1;
	assert(astra_async_observe_release(executor, token));
	assert(!astra_async_observe_release(executor, token));
	for (unsigned turns = 0; astra_async_phase(root) < ASTRA_ASYNC_SUCCESS; turns++) {
		assert(turns < 40);
		astra_async_pump(executor, 8);
		astra_async_advance_next(executor);
	}
	int phase = mode == 3 ? ASTRA_ASYNC_CANCELLED : ASTRA_ASYNC_SUCCESS;
	assert(astra_async_phase(root) == phase);
	astra_async_begin_shutdown(executor);
	assert(astra_async_observe_root(executor, root, 0) == phase);
	assert(!root_frame && !child_frame && !backing);
	assert(!astra_async_wake(executor, token) && astra_async_provider_read(executor, token) == -1);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
	held_mode = 0;
}
int main(void) {
	for (unsigned cycle = 0; cycle < 16; cycle++) {
		selected = cycle % 3;
		assert(result_host() == 42);
		assert(owning_abort() == 42);
	}
	for (unsigned stage = 1; stage < 10; stage++) {
		assert(entries[stage] == (stage == 5 ? 32 : 16));
	}
	for (unsigned cycle = 0; cycle < 16; cycle++) {
		for (unsigned kind = 0; kind < 2; kind++) {
			for (unsigned mode = 1; mode < 4; mode++) {
				held_result(kind, mode);
			}
		}
	}
	assert(entries[5] == 80 && entries[7] == 48 && entries[10] == 32 && entries[11] == 32);
	puts("generated record, enum, record-array and owning-enum results passed after child retirement; runtime-selected negative-zero, subnormal and quiet-NaN bits retained; held result payloads survive pending success, discard and parent cancellation until observed release");
	return 0;
}
