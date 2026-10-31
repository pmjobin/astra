/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "linux.h"
#include "provider.h"
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

typedef struct Frame {
	int turns;
	int result;
} Frame;
static unsigned destroyed;
static void destroy(AstraAsyncTask *task, int discard) {
	(void)task;
	(void)discard;
	destroyed++;
}
static void resume(AstraAsyncTask *task) {
	Frame *frame = astra_async_data(task);
	frame->turns++;
	if (astra_async_cancel_requested(task)) {
		if (astra_async_cancel_scope(task)) {
			astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
		}
		return;
	}
	if (astra_async_pc(task) == 0) {
		astra_async_set_pc(task, 1);
		frame->result = astra_async_linux_delay_ms(task, 100);
		if (!frame->result) {
			astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
		}
		return;
	}
	frame->result = astra_async_linux_delay_result(task, 1);
	astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
}
static AstraAsyncExecutor *executor(void) {
	AstraAsyncExecutor *ex = astra_async_linux_open(2);
	assert(ex != NULL);
	astra_async_linux_test_fake(ex);
	return ex;
}
static AstraAsyncTask *root(AstraAsyncExecutor *ex) {
	AstraAsyncTask *task = astra_async_new(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL);
	*(Frame *)astra_async_data(task) = (Frame){0};
	assert(astra_async_start(ex, task, NULL) == ASTRA_ASYNC_ADMITTED);
	return task;
}
static AstraAsyncLinuxSnapshot snapshot(AstraAsyncExecutor *ex) {
	AstraAsyncLinuxSnapshot out;
	assert(astra_async_linux_test_snapshot(ex, 0, &out));
	assert(out.target != out.cancel && out.generation == 1 && out.pc == 1);
	return out;
}
static void close_root(AstraAsyncExecutor *ex, AstraAsyncTask *task, int outcome) {
	assert(astra_async_phase(task) == outcome);
	astra_async_begin_shutdown(ex);
	assert(astra_async_shutdown_complete(ex));
	assert(!astra_async_finish_shutdown(ex));
	assert(astra_async_observe_root(ex, task, outcome == ASTRA_ASYNC_SUCCESS) == outcome);
	assert(astra_async_finish_shutdown(ex));
	astra_async_close(ex);
}
static void orders(void) {
	const int cancel_results[] = {0, -ENOENT, -EALREADY};
	const int target_results[] = {-ETIME, -ECANCELED};
	for (unsigned order = 0; order < 2; order++) {
		for (unsigned c = 0; c < 3; c++) {
			for (unsigned t = 0; t < 2; t++) {
				AstraAsyncExecutor *ex = executor();
				AstraAsyncTask *task = root(ex);
				astra_async_pump(ex, 1);
				AstraAsyncLinuxSnapshot before = snapshot(ex);
				assert(before.prepared && !before.cancel_prepared && !before.target_seen);
				assert(!astra_async_linux_test_decode(ex, before.cancel, 0, 0));
				assert(!astra_async_linux_test_decode(ex, before.target, 0, 0));
				assert(!astra_async_linux_test_decode(ex, before.target, -ETIME, 2));
				assert(!astra_async_linux_test_decode(ex, before.target, INT32_MIN, 0));
				assert(!astra_async_linux_test_decode(ex, before.cancel + 300, -ETIME, 0));
				AstraAsyncToken wrong = before.token;
				wrong.generation++;
				assert(!astra_async_provider_complete(ex, wrong, before.pc, 0));
				wrong = before.token;
				wrong.slot = 1;
				assert(!astra_async_provider_complete(ex, wrong, before.pc, 0));
				wrong = before.token;
				wrong.executor++;
				assert(!astra_async_provider_complete(ex, wrong, before.pc, 0));
				assert(!astra_async_provider_complete(ex, before.token, before.pc + 1, 0));
				astra_async_cancel(task);
				astra_async_cancel(task);
				astra_async_pump(ex, 1);
				before = snapshot(ex);
				assert(before.cancel_prepared);
				uint64_t first = order ? before.target : before.cancel, second = order ? before.cancel : before.target;
				int first_result = order ? target_results[t] : cancel_results[c], second_result = order ? cancel_results[c] : target_results[t];
				unsigned was_destroyed = destroyed;
				assert(astra_async_linux_test_decode(ex, first, first_result, 0));
				astra_async_pump(ex, 1);
				assert(destroyed == was_destroyed && astra_async_phase(task) == ASTRA_ASYNC_DRAINING && !astra_async_shutdown_complete(ex));
				assert(!astra_async_linux_test_decode(ex, first, first_result, 0));
				assert(astra_async_linux_test_decode(ex, second, second_result, 0));
				assert(!astra_async_linux_test_decode(ex, first, first_result, 0));
				astra_async_pump(ex, 1);
				close_root(ex, task, ASTRA_ASYNC_CANCELLED);
			}
		}
	}
}
static void identity_and_faults(void) {
	AstraAsyncExecutor *first = executor(), *second = executor();
	AstraAsyncTask *a = root(first), *b = root(second);
	/* EINTR after SQE acquisition preserves the exact original request identity. */
	astra_async_linux_test_submit(first, -EINTR);
	astra_async_pump(first, 1);
	AstraAsyncLinuxSnapshot sa = snapshot(first);
	astra_async_linux_test_submit(second, 0);
	astra_async_pump(second, 1);
	AstraAsyncLinuxSnapshot sb = snapshot(second);
	assert(sa.target != sb.target && sa.token.executor != sb.token.executor);
	assert(!astra_async_linux_test_decode(second, sa.target, -ETIME, 0));
	assert(!astra_async_linux_test_decode(first, sb.target, -ETIME, 0));
	for (unsigned n = 0; n < 4; n++) {
		astra_async_pump(first, 0);
		AstraAsyncLinuxSnapshot current = snapshot(first);
		assert(current.target == sa.target && current.cancel == sa.cancel && current.token.generation == sa.token.generation);
	}
	assert(astra_async_linux_test_decode(first, sa.target, -EIO, 0));
	astra_async_pump(first, 1);
	assert(((Frame *)astra_async_data(a))->result == EIO);
	close_root(first, a, ASTRA_ASYNC_SUCCESS);
	assert(astra_async_linux_test_decode(second, sb.target, -ETIME, 0));
	astra_async_pump(second, 1);
	assert(((Frame *)astra_async_data(b))->result == 0);
	close_root(second, b, ASTRA_ASYNC_SUCCESS);
	first = executor();
	a = root(first);
	astra_async_linux_test_ids(first, UINT64_MAX - 1);
	astra_async_pump(first, 1);
	assert(((Frame *)astra_async_data(a))->result == 0 && astra_async_linux_last_failure().operation == ASTRA_LINUX_IDS);
	close_root(first, a, ASTRA_ASYNC_SUCCESS);
}
static void partial_submission(void) {
	AstraAsyncExecutor *ex = executor();
	AstraAsyncTask *parent = root(ex);
	AstraAsyncTask *child = astra_async_new(sizeof(Frame), _Alignof(Frame), resume, destroy, parent);
	*(Frame *)astra_async_data(child) = (Frame){0};
	assert(astra_async_start(ex, child, parent) == ASTRA_ASYNC_ADMITTED);
	astra_async_linux_test_hold_submit(ex, 1);
	astra_async_pump(ex, 2);
	assert(astra_async_linux_test_pending(ex) == 2);
	AstraAsyncLinuxSnapshot first, second;
	assert(astra_async_linux_test_snapshot(ex, 0, &first) && astra_async_linux_test_snapshot(ex, 1, &second));
	assert(first.prepared && !first.exposed && !first.consumed && second.prepared && !second.exposed && !second.consumed);
	assert(!astra_async_linux_test_decode(ex, first.target, -ETIME, 0));
	astra_async_cancel(parent);
	astra_async_pump(ex, 2);
	assert(astra_async_linux_test_pending(ex) == 4);
	astra_async_linux_test_submit(ex, 1);
	astra_async_pump(ex, 0);
	assert(astra_async_linux_test_pending(ex) == 3);
	astra_async_linux_test_submit(ex, -EINTR);
	astra_async_pump(ex, 0);
	assert(astra_async_linux_test_pending(ex) == 3);
	astra_async_linux_test_submit(ex, -EAGAIN);
	astra_async_pump(ex, 0);
	assert(astra_async_linux_test_pending(ex) == 3);
	AstraAsyncLinuxSnapshot current;
	assert(astra_async_linux_test_snapshot(ex, 0, &current));
	assert(current.target == first.target && current.cancel == first.cancel && current.cancel_prepared);
	assert(current.exposed && current.consumed && current.cancel_exposed && !current.cancel_consumed);
	astra_async_linux_test_hold_submit(ex, 0);
	astra_async_pump(ex, 0);
	assert(astra_async_linux_test_pending(ex) == 0);
	assert(astra_async_linux_test_decode(ex, first.cancel, 0, 0));
	assert(astra_async_linux_test_decode(ex, second.target, -ECANCELED, 0));
	astra_async_pump(ex, 2);
	assert(astra_async_phase(parent) == ASTRA_ASYNC_DRAINING);
	assert(astra_async_linux_test_decode(ex, first.target, -ECANCELED, 0));
	assert(astra_async_linux_test_decode(ex, second.cancel, 0, 0));
	astra_async_pump(ex, 4);
	close_root(ex, parent, ASTRA_ASYNC_CANCELLED);
}
int main(void) {
	alarm(15);
	orders();
	partial_submission();
	identity_and_faults();
	assert(destroyed == 17);
	puts("INJECTED production decoder: both evidence orders, 0/ENOENT/EALREADY, independent target retirement, stale/role/wrong-ring rejection, partial SQ/short/EINTR/EAGAIN identity, deferred status and exhaustion");
	return 0;
}
