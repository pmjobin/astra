/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "../../lib/runtime/async/virtual.h"
static unsigned retired[7], seen[6], runs[6], cancelled;
static int current = -1;
static AstraAsyncTask *root;
void native_scope_begin(int32_t mode) {
	if (mode != current + 1 || mode > 5 || root) abort();
	current = mode;
}
void native_scope_leaf_retired(int32_t identity) {
	if (identity != current + 1 || retired[identity]++) abort();
}
int __real_astra_async_run(AstraAsyncExecutor *, AstraAsyncTask *, void **);
int __wrap_astra_async_run(AstraAsyncExecutor *executor, AstraAsyncTask *task, void **error) {
	if (current < 0 || current > 5 || current == 2 || runs[current]++ || root) abort();
	root = task;
	int phase = __real_astra_async_run(executor, task, error);
	root = NULL;
	if (current == 4) {
		if (phase >= 0 || *error) abort();
	} else {
		int expected = current == 1 || current == 5 ? ASTRA_ASYNC_CANCELLED : current == 3 ? ASTRA_ASYNC_EXCEPTION
		                                                                                   : ASTRA_ASYNC_SUCCESS;
		if (phase != expected || ((*error != NULL) != (phase == ASTRA_ASYNC_EXCEPTION))) abort();
	}
	return phase;
}
int __real_astra_async_delay(AstraAsyncTask *, int64_t);
int __wrap_astra_async_delay(AstraAsyncTask *task, int64_t ticks) {
	int admitted = __real_astra_async_delay(task, ticks);
	if (current == 5) {
		if (!admitted || !root || task == root || cancelled++) abort();
		astra_async_cancel(root);
	}
	return admitted;
}
void native_scope_outcome(int32_t mode) {
	if (mode != current || seen[mode]++ || retired[mode + 1] != 1 || runs[mode] != (mode != 2)) abort();
}
int32_t native_scope_finish(void) {
	for (int mode = 0; mode < 6; ++mode)
		if (seen[mode] != 1 || retired[mode + 1] != 1 || runs[mode] != (mode != 2)) abort();
	if (cancelled != 1 || root) abort();
	puts("opaque scoped task: success, cold drop, checked error and joined cancellation retire every input once");
	return 0;
}
int32_t native_scope_probe(void);
int main(void) {
	return native_scope_probe();
}
