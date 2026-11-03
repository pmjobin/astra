/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
static uint32_t retirements[5];

int32_t byte16_retired(int32_t kind) {
	assert(kind > 0 && kind < 5);
	++retirements[kind];
	return 0;
}

uint32_t byte16_retired_count(int32_t kind) {
	assert(kind > 0 && kind < 5);
	return retirements[kind];
}
