/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "../../lib/runtime/async/virtual.h"
#ifndef SCOPED_ERROR_WIDTH
#define SCOPED_ERROR_WIDTH 1
#endif
#ifndef SCOPED_ERROR_SUSPENDED
#define SCOPED_ERROR_SUSPENDED 0
#endif
#define SCOPED_ERROR_CASES (3 + SCOPED_ERROR_SUSPENDED)
static unsigned retired[9], published[9], checked, ready, refusals;
static int current_mode = -1;
#if SCOPED_ERROR_SUSPENDED
static int reject_delay;
int __real_astra_async_delay(AstraAsyncTask *, int64_t);

int __wrap_astra_async_delay(AstraAsyncTask *task, int64_t ticks) {
	if (reject_delay) {
		reject_delay = 0;
		++refusals;
		return 0;
	}
	return __real_astra_async_delay(task, ticks);
}

void scoped_error_delay_arm(int32_t mode) {
	if (mode == 3) {
		if (refusals || reject_delay) abort();
		reject_delay = 1;
	}
}

#endif

void scoped_error_begin(int32_t mode) {
	if (mode != (int32_t)checked || mode != current_mode + 1) abort();
	current_mode = mode;
	ready = 0;
}

void scoped_error_retired(int32_t identity) {
	if (identity < 1 || identity > SCOPED_ERROR_CASES * SCOPED_ERROR_WIDTH || retired[identity]++) abort();
	if (current_mode == 3 && identity == 3 * SCOPED_ERROR_WIDTH + 1) ready = 1;
}

void scoped_error_published(int32_t identity) {
	if (identity != SCOPED_ERROR_WIDTH + 1 || published[identity]++) abort();
	for (int f = 0; f < SCOPED_ERROR_WIDTH; ++f)
		if (retired[identity + f]) abort();
	ready = 1;
}

int32_t scoped_error_is_published(void) {
	return ready != 0;
}

void scoped_error_checked(int32_t identity, int32_t expected) {
	if (identity != (int32_t)(checked++ * SCOPED_ERROR_WIDTH + 1) || published[identity] != (unsigned)expected) abort();
	for (int f = 0; f < SCOPED_ERROR_WIDTH; ++f)
		if (retired[identity + f] != 1) abort();
}

int32_t scoped_error_finish(void) {
	if (checked != SCOPED_ERROR_CASES || published[SCOPED_ERROR_WIDTH + 1] != 1 || refusals != SCOPED_ERROR_SUSPENDED) abort();
	for (int f = 1; f <= SCOPED_ERROR_CASES * SCOPED_ERROR_WIDTH; ++f)
		if (retired[f] != 1) abort();
	puts("scoped error discard: cold, published and cancelled owners retire exactly once");
	return 0;
}

int32_t scoped_error_probe(void);

int main(void) {
	return scoped_error_probe();
}
