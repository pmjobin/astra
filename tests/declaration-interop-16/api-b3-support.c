/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
static uint32_t retired[5];

int32_t orbit16_retired(int32_t kind) {
	assert(kind > 0 && kind < 5);
	++retired[kind];
	return 0;
}

uint32_t orbit16_retired_count(int32_t kind) {
	assert(kind > 0 && kind < 5);
	return retired[kind];
}
