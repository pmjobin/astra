/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include "../../lib/runtime/async/virtual.h"
#include <stdio.h>
#include <stdlib.h>
static unsigned retired[5], seen[2], opened;
AstraAsyncExecutor *__real_astra_async_virtual_open(uint32_t capacity);

AstraAsyncExecutor *__wrap_astra_async_virtual_open(uint32_t capacity) {
	AstraAsyncExecutor *result = __real_astra_async_virtual_open(capacity);
	if (capacity != 0 || result != NULL || opened++) abort();
	return result;
}

void mixed_error_retired(int32_t identity) {
	if (identity < 1 || identity > 4 || retired[identity]++) abort();
}

void mixed_error_observed(int32_t mode, int32_t value) {
	if (mode < 0 || mode > 1 || seen[mode]++) abort();
	int selected = mode == 0 ? 1 : 4;
	int discarded = mode == 0 ? 2 : 3;
	if (mode == 0) {
		if (value != 17 || retired[selected] || retired[discarded] != 1) abort();
	} else if (value != -1 || retired[3] != 1 || retired[4] != 1 || opened != 1)
		abort();
}

int32_t mixed_error_finish(void) {
	if (seen[0] != 1 || seen[1] != 1 || opened != 1) abort();
	for (int i = 1; i <= 4; ++i)
		if (retired[i] != 1) abort();
	puts("mixed errors: original payload retained, real empty admission error, four exact destructions");
	return 0;
}

int32_t mixed_error_probe(void);

int main(void) {
	return mixed_error_probe();
}
