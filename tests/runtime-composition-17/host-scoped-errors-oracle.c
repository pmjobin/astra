/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "../../lib/runtime/async/virtual.h"
static unsigned retired[7], seen[6], runs[6], refused_delay;
static int current = -1, armed;
int __real_astra_async_run(AstraAsyncExecutor *, AstraAsyncTask *, void **);

int __wrap_astra_async_run(AstraAsyncExecutor *executor, AstraAsyncTask *task, void **error) {
	int phase = __real_astra_async_run(executor, task, error);
	if (current < 0 || current > 5 || runs[current]++) abort();
	int expected = current == 2 ? ASTRA_ASYNC_CANCELLED : current == 5 ? ASTRA_ASYNC_SUCCESS
	                                                                   : ASTRA_ASYNC_EXCEPTION;
	if (current == 4) {
		if (phase >= 0 || *error != NULL) abort();
	} else if (phase != expected || ((*error != NULL) != (phase == ASTRA_ASYNC_EXCEPTION)))
		abort();
	return phase;
}

int __real_astra_async_delay(AstraAsyncTask *, int64_t);

int __wrap_astra_async_delay(AstraAsyncTask *task, int64_t ticks) {
	if (armed) {
		armed = 0;
		if (refused_delay++ || current != 3) abort();
		return 0;
	}
	return __real_astra_async_delay(task, ticks);
}

void host_error_delay_arm(void) {
	if (armed || refused_delay || current != 3) abort();
	armed = 1;
}

void host_error_begin(int32_t mode) {
	if (mode != current + 1 || mode > 5) abort();
	current = mode;
}

void host_error_retired(int32_t identity) {
	if (identity < 1 || identity > 6 || retired[identity]++) abort();
}

void host_error_outcome(int32_t mode, int32_t value) {
	if (mode != current || seen[mode]++ || runs[mode] != 1) abort();
	if (mode < 2) {
		if (value != mode + 1 || retired[mode + 1]) abort();
	} else {
		if (value != ((mode == 3 || mode == 4) ? -1 : 0) || retired[mode + 1] != 1) abort();
	}
}

int32_t host_error_finish(void) {
	for (int mode = 0; mode < 6; ++mode)
		if (seen[mode] != 1 || runs[mode] != 1 || retired[mode + 1] != 1) abort();
	if (refused_delay != 1 || armed) abort();
	puts("host scoped errors: original and suspended payloads, empty errors, cancellation and success retire exactly once");
	return 0;
}

int32_t host_error_probe(void);

int main(void) {
	return host_error_probe();
}
