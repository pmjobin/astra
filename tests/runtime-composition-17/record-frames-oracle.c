/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/runtime/context-17.h"
#include "../../lib/runtime/async/virtual.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
static _Atomic int entered[8], retired[8], pending, published[2];
static _Thread_local int returning_record;
static long home;
static _Atomic long worker;
static AstraContext17 *data_context[8], *state_context[8];
static _Atomic int anchor_closed[8], state_closed[8], bytes_released[8], item_released[8];
extern int run_record_frames(void);

int main(void) {
	home = syscall(SYS_gettid);
	return run_record_frames();
}

void record_frame_event(int kind, int identity) {
	assert(identity >= 17 && identity <= 24);
	int index = identity - 17;
	if (kind == 1) {
		atomic_fetch_add(&entered[index], 1);
		atomic_store(&worker, syscall(SYS_gettid));
	} else if (kind == 2) {
		assert(atomic_load(&anchor_closed[index]) && atomic_load(&state_closed[index]) && atomic_load(&bytes_released[index]) == 1);
		atomic_fetch_add(&retired[index], 1);
	} else if (kind == 3) {
		assert(identity == 21);
		atomic_store(&pending, 1);
	} else {
		assert(kind == 4 && (identity == 23 || identity == 24));
		assert(!returning_record);
		returning_record = identity;
	}
}

void record_frame_bind(AstraContext17 *context, int identity, int kind) {
	assert(identity >= 17 && identity <= 24 && context);
	int index = identity - 17;
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(context, &state) == 0);
	if (kind == 1) {
		assert(!data_context[index] && state.live == 2);
		data_context[index] = context;
	} else {
		assert(kind == 2 && !state_context[index] && state.live == 0);
		state_context[index] = context;
	}
}

void __real_astra_context17_destroy(AstraContext17 *);

void __wrap_astra_context17_destroy(AstraContext17 *context) {
	if (context) {
		for (int i = 0; i < 8; ++i) {
			if (context == data_context[i] && !atomic_load(&anchor_closed[i])) {
				atomic_store(&anchor_closed[i], 1);
				break;
			}
			if (context == state_context[i] && !atomic_load(&state_closed[i])) {
				assert(!atomic_load(&bytes_released[i]) && !atomic_load(&retired[i]));
				atomic_store(&state_closed[i], 1);
				break;
			}
		}
	}
	__real_astra_context17_destroy(context);
}

int __real_astra_context17_release_origin_checked(void *, uint64_t);

int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	if (pointer) {
		AstraContext17 *context = astra_context17_origin(pointer, tag);
		assert(context);
		for (int i = 7; i >= 0; --i) {
			if (context != data_context[i] || atomic_load(&item_released[i])) {
				continue;
			}
			assert(atomic_load(&anchor_closed[i]) && atomic_load(&state_closed[i]));
			if (atomic_load(&retired[i])) {
				assert(atomic_load(&bytes_released[i]) == 1);
				atomic_fetch_add(&item_released[i], 1);
			} else {
				assert(atomic_fetch_add(&bytes_released[i], 1) == 0);
			}
			break;
		}
	}
	return __real_astra_context17_release_origin_checked(pointer, tag);
}

void __real_astra_async_complete(AstraAsyncTask *, int, void *);

void __wrap_astra_async_complete(AstraAsyncTask *task, int phase, void *exception) {
	int identity = returning_record;
	returning_record = 0;
	if (identity) {
		assert((identity == 23 || identity == 24) && phase == ASTRA_ASYNC_SUCCESS && !exception);
	}
	__real_astra_async_complete(task, phase, exception);
	if (identity) {
		atomic_store(&published[identity - 23], 1);
	}
}

int record_frame_published(void) {
	return atomic_load(&published[1]);
}

int record_frame_pending(void) {
	if (!atomic_load(&pending)) {
		struct timespec delay = {0, 1000000};
		nanosleep(&delay, NULL);
	}
	return atomic_load(&pending);
}

int record_frame_finish(void) {
	int count = 6;
#ifdef M17_RECORD_RESULTS
	count = 8;
	assert(atomic_load(&published[0]) && atomic_load(&published[1]));
#endif
	for (int i = 0; i < count; ++i) {
		assert(atomic_load(&retired[i]) == 1 && atomic_load(&state_closed[i]) == 1 && atomic_load(&bytes_released[i]) == 1 && atomic_load(&item_released[i]) == 1);
		assert(atomic_load(&entered[i]) == (i == 0 || i == 3 ? 0 : 1));
	}
#ifdef M17_VIRTUAL
	assert(atomic_load(&worker) == home);
#else
	assert(atomic_load(&worker) != home);
#endif
	puts("owning record frames: cold capture, suspended locals, success/error/cancel and exact joined field retirement");
#ifdef M17_RECORD_RESULTS
	puts("owning record results: observed transfer and published discarded success, exact field retirement");
#endif
	return 0;
}
